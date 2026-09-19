note
	description: "[
		One video, start to finish: look the link up, read its caption
		track, assemble the paragraphs, write the transcript file. The
		Video tab and the --captions CLI mode both drive this and read
		their messages from it.

		Synchronous by design. A probe is one round trip and a track is
		one more - two seconds on a 23-minute video today - so the
		window pauses for less time than a page capture takes; a worker
		process here would be machinery for nothing.

		Output follows the page reader's rule: the transcript is
		APPENDED to the named file behind a header naming the video,
		never written over anything.
	]"

class
	OCR_VIDEO_RUN

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
		do
			settings := a_settings
			create track.make
			create text.make
			create url.make_empty
			create last_message.make_empty
			create last_error.make_empty
			create saved_path.make_empty
			create log
		end

feature -- Access

	track: OCR_CAPTION_TRACK
			-- The look-up and the fetch.

	text: OCR_CAPTION_TEXT
			-- The assembled paragraphs of the last fetch.

	url: STRING_32
			-- The link the last `probe' was given.

	last_message: STRING_32
			-- What the last operation has to say, for the status line.

	last_error: STRING_32
			-- Why the last operation failed; empty when it did not.

	saved_path: STRING_32
			-- Where the last `fetch_and_save' wrote; empty until it has.

	front_matter: STRING_32
			-- YAML to open a Markdown transcript with, its --- fences
			-- included; empty, and then nothing is written.
			--
			-- The channel harvest sets this so a vault can sort a
			-- transcript by its channel and its category without the
			-- file having to live in a folder named after either. It
			-- stays empty for a video fetched on its own, so those files
			-- keep the shape they have always had.
		attribute
			create Result.make_empty
		end

feature -- Status report

	is_probed: BOOLEAN
		do
			Result := track.is_probed
		end

	is_saved: BOOLEAN
		do
			Result := not saved_path.is_empty
		end

	can_fetch: BOOLEAN
			-- Would `fetch_and_save' proceed?
		do
			Result := blocking_reason.is_empty
		end

	blocking_reason: STRING_32
			-- Why a fetch cannot happen now; empty when it can.
		do
			create Result.make_empty
			if not track.is_probed then
				Result := {STRING_32} "Look the video up first."
			elseif track.is_members_only then
				Result := {STRING_32} "This video is members-only. YouTube will not hand its captions to an anonymous request; the signed-in route is not built yet."
			elseif track.needs_login then
				Result := {STRING_32} "YouTube wants a signed-in viewer for this video (age-restricted or private)."
			elseif not track.is_playable then
				Result := {STRING_32} "YouTube reports this video as unavailable: "
				Result.append (track.status_reason)
			elseif not track.has_captions then
				Result := {STRING_32} "This video has no caption track - no CC button, nothing to fetch. Screen capture of burned-in captions or audio transcription would be needed."
			end
		end

	summary_line: STRING_32
			-- The probe's findings in one line for the tab.
		local
			i: INTEGER
		do
			create Result.make (120)
			if not track.is_probed then
				Result.append_string_general ("Paste a YouTube link and press Look Up.")
			else
				if track.title.is_empty then
					Result.append_string_general ("(no title)")
				else
					Result.append (track.title)
				end
				if not track.channel.is_empty then
					Result.append_string_general (" - ")
					Result.append (track.channel)
				end
				if track.length_seconds > 0 then
					Result.append_string_general (" - ")
					Result.append (text.clock_caption (track.length_seconds))
				end
				Result.append_string_general (" - ")
				if track.is_members_only then
					Result.append_string_general ("members only")
				elseif track.needs_login then
					Result.append_string_general ("sign-in required")
				elseif not track.is_playable then
					Result.append_string_general ("unavailable: ")
					Result.append (track.status_reason)
				elseif not track.has_captions then
					Result.append_string_general ("open, NO captions")
				else
					i := track.preferred_track
					Result.append_string_general ("open, captions: ")
					Result.append (track.track_caption (i))
					if track.tracks.count > 1 then
						Result.append_string_general (" (+")
						Result.append_string_general ((track.tracks.count - 1).out)
						Result.append_string_general (" more)")
					end
				end
			end
		ensure
			never_empty: not Result.is_empty
		end

	suggested_file_name: STRING_32
			-- A file name from the title: "<title>.md". Markdown is the
			-- default for a video: the header becomes a heading and a
			-- table, and the paragraphs are paragraphs.
		do
			Result := safe_file_stem (track.title)
			Result.append_string_general (".md")
		ensure
			named: Result.count > 3
			markdown: Result.ends_with ({STRING_32} ".md")
		end

	is_markdown_path (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_path' name a Markdown file?
		do
			Result := a_path.as_lower.ends_with (".md")
		end

feature -- Element change

	set_front_matter (a_yaml: READABLE_STRING_GENERAL)
			-- Open the next Markdown transcript with `a_yaml'.
		do
			create front_matter.make_from_string_general (a_yaml)
		ensure
			set: front_matter.same_string_general (a_yaml)
		end

feature -- Basic operations

	probe (a_url: READABLE_STRING_GENERAL): BOOLEAN
			-- Look `a_url' up; `summary_line' then describes it.
		do
			create url.make_from_string_general (a_url)
			last_error.wipe_out
			saved_path.wipe_out
			settings.set_last_video_url (url)
			Result := track.probe (url)
			if Result then
				last_message := summary_line
				log.append ({STRING_32} "video probe: " + url + {STRING_32} " -> " + summary_line)
			else
				last_error := track.last_error.twin
				last_message := last_error.twin
				log.append ({STRING_32} "video probe FAILED: " + url + {STRING_32} " -> " + last_error)
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
		end

	fetch_and_save (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Read the preferred track and append its transcript to
			-- `a_path'. `last_message' says what was written.
		require
			fetchable: can_fetch
			path_given: not a_path.is_empty
		local
			l_index: INTEGER
		do
			last_error.wipe_out
			saved_path.wipe_out
			l_index := track.preferred_track
			if not track.fetch_json3 (l_index) then
				last_error := track.last_error.twin
			elseif not text.load_json3 (track.last_json3) then
				last_error := text.last_error.twin
			elseif not text.is_loaded then
				last_error := {STRING_32} "The caption track came back but holds no words."
			elseif not write_transcript (a_path, l_index) then
				last_error := {STRING_32} "Could not write "
				last_error.append_string_general (a_path)
			else
				create saved_path.make_from_string_general (a_path)
				Result := True
			end
			if Result then
				create last_message.make (160)
				last_message.append_string_general ("Saved ")
				last_message.append_string_general (text.word_count.out)
				last_message.append_string_general (" words in ")
				last_message.append_string_general (text.paragraphs.count.out)
				last_message.append_string_general (" paragraphs (")
				last_message.append (text.duration_caption)
				last_message.append_string_general (" of captions) to ")
				last_message.append (saved_path)
				log.append ({STRING_32} "video transcript: " + last_message)
			else
				last_message := last_error.twin
				log.append ({STRING_32} "video transcript FAILED: " + url + {STRING_32} " -> " + last_error)
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			saved_on_success: Result implies is_saved
		end

	save_session_track (a_json3: READABLE_STRING_32; a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Assemble a transcript from `a_json3' (a track the sign-in
			-- helper fetched for a members-only video) and append it to
			-- `a_path'. The probe already holds the title, channel and
			-- length, which are served even for gated videos.
		require
			probed: is_probed
			json3_given: not a_json3.is_empty
			path_given: not a_path.is_empty
		do
			last_error.wipe_out
			saved_path.wipe_out
			if not text.load_json3 (a_json3) then
				last_error := text.last_error.twin
			elseif not text.is_loaded then
				last_error := {STRING_32} "The caption track came back but holds no words."
			elseif not write_session_transcript (a_path) then
				last_error := {STRING_32} "Could not write "
				last_error.append_string_general (a_path)
			else
				create saved_path.make_from_string_general (a_path)
				Result := True
			end
			if Result then
				create last_message.make (160)
				last_message.append_string_general ("Saved ")
				last_message.append_string_general (text.word_count.out)
				last_message.append_string_general (" words in ")
				last_message.append_string_general (text.paragraphs.count.out)
				last_message.append_string_general (" paragraphs (members-only, via your browser session) to ")
				last_message.append (saved_path)
				log.append ({STRING_32} "members transcript: " + last_message)
			else
				last_message := last_error.twin
				log.append ({STRING_32} "members transcript FAILED: " + url + {STRING_32} " -> " + last_error)
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			saved_on_success: Result implies is_saved
		end

feature -- Conversion

	safe_file_stem (a_title: READABLE_STRING_32): STRING_32
			-- `a_title' fit for a Windows file name: reserved
			-- characters and controls dropped, whitespace collapsed,
			-- capped at `Stem_cap' characters, never empty.
		local
			i: INTEGER
			c: CHARACTER_32
			l_pending: BOOLEAN
		do
				-- The whole title is cleaned first and cut to length after,
				-- rather than stopping the loop at `Stem_cap'. One pass of
				-- that loop can append TWO characters - a held-over space
				-- and then the character after it - so a cap tested only at
				-- the top can be overshot by one, and the postcondition
				-- below then fails. It takes a title longer than the cap
				-- with a space at exactly the wrong offset, which is why
				-- the single-video path never met it and the first channel
				-- harvest did, 125 titles in.
			create Result.make (a_title.count.min (Stem_cap))
			from
				i := 1
			until
				i > a_title.count
			loop
				c := a_title.item (i)
				if c.is_space then
					l_pending := not Result.is_empty
				elseif c.natural_32_code < 32 or else Reserved_characters.has (c) then
						-- dropped
				else
					if l_pending then
						Result.append_character (' ')
						l_pending := False
					end
					Result.append_character (c)
				end
				i := i + 1
			end
			if Result.count > Stem_cap then
				Result.keep_head (Stem_cap)
			end
			Result.right_adjust
			if Result.is_empty then
				Result.append_string_general ("video")
			end
		ensure
			never_empty: not Result.is_empty
			capped: Result.count <= Stem_cap
			clean: across Reserved_characters as ic all not Result.has (ic) end
		end

	Stem_cap: INTEGER = 80

	Reserved_characters: STRING_32 = "\/:*?%"<>|"

feature {NONE} -- Implementation

	settings: OCR_SETTINGS

	log: OCR_LOG_FILE

	write_transcript (a_path: READABLE_STRING_GENERAL; a_track: INTEGER): BOOLEAN
			-- Append the header and the paragraphs to `a_path',
			-- creating it when absent. False when the write fails.
		local
			l_file: RAW_FILE
			l_retried, l_existed: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (a_path)
				l_existed := l_file.exists
				if l_existed then
					l_file.open_append
					l_file.put_string ("%N%N")
				else
					l_file.create_read_write
				end
				if is_markdown_path (a_path) then
						-- Front matter has to be the very first thing in the
						-- file or a vault will not read it, so it goes in only
						-- when this transcript is starting the file. Asked
						-- before the open, because by now the file is there
						-- either way.
					if not front_matter.is_empty and then not l_existed then
						l_file.put_string (utf8 (front_matter))
					end
					l_file.put_string (utf8 (markdown_header (a_track)))
				else
					l_file.put_string (utf8 (header (a_track)))
				end
				l_file.put_string (utf8 (text.plain_text))
				l_file.put_string ("%N")
				l_file.close
				Result := True
			end
		rescue
			l_retried := True
			retry
		end

	write_session_transcript (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Append the members-only header and paragraphs to `a_path'.
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (a_path)
				if l_file.exists then
					l_file.open_append
					l_file.put_string ("%N%N")
				else
					l_file.create_read_write
				end
				l_file.put_string (utf8 (session_header (is_markdown_path (a_path))))
				l_file.put_string (utf8 (text.plain_text))
				l_file.put_string ("%N")
				l_file.close
				Result := True
			end
		rescue
			l_retried := True
			retry
		end

	session_header (a_markdown: BOOLEAN): STRING_32
			-- The header for a members-only transcript; no track index is
			-- needed because the gated probe still yields title and length.
		local
			l_now: DATE_TIME
			l_src: STRING_32
		do
			create l_now.make_now
			l_src := {STRING_32} "YouTube caption track (members-only, via your browser session)"
			create Result.make (320)
			if a_markdown then
				Result.append_string_general ("# ")
				Result.append (track.title)
				Result.append_string_general ("%N%N| | |%N|---|---|%N| URL | https://www.youtube.com/watch?v=")
				Result.append_string_general (track.video_id)
				Result.append_string_general (" |%N| Channel | ")
				Result.append (track.channel)
				Result.append_string_general (" |%N| Length | ")
				Result.append (text.clock_caption (track.length_seconds))
				Result.append_string_general (" |%N| Source | ")
				Result.append (l_src)
				Result.append_string_general (" |%N| Fetched | ")
				Result.append_string_general (l_now.out)
				Result.append_string_general (" |%N%N")
			else
				Result.append_string_general ("===== ")
				Result.append (track.title)
				Result.append_string_general (" =====%NURL: https://www.youtube.com/watch?v=")
				Result.append_string_general (track.video_id)
				Result.append_string_general ("%NChannel: ")
				Result.append (track.channel)
				Result.append_string_general ("%NLength: ")
				Result.append (text.clock_caption (track.length_seconds))
				Result.append_string_general ("%NSource: ")
				Result.append (l_src)
				Result.append_string_general ("%NFetched: ")
				Result.append_string_general (l_now.out)
				Result.append_string_general ("%N%N")
			end
		end

	header (a_track: INTEGER): STRING_32
			-- The lines above a plain-text transcript naming what it is.
		require
			in_range: a_track >= 1 and a_track <= track.tracks.count
		local
			l_now: DATE_TIME
		do
			create l_now.make_now
			create Result.make (300)
			Result.append_string_general ("===== ")
			Result.append (track.title)
			Result.append_string_general (" =====%N")
			Result.append_string_general ("URL: https://www.youtube.com/watch?v=")
			Result.append_string_general (track.video_id)
			Result.append_string_general ("%NChannel: ")
			Result.append (track.channel)
			Result.append_string_general ("%NLength: ")
			Result.append (text.clock_caption (track.length_seconds))
			Result.append_string_general ("%NSource: YouTube caption track, ")
			Result.append (track.track_caption (a_track))
			Result.append_string_general ("%NFetched: ")
			Result.append_string_general (l_now.out)
			Result.append_string_general ("%N%N")
		end

	markdown_header (a_track: INTEGER): STRING_32
			-- The same facts as a heading and a two-column table.
		require
			in_range: a_track >= 1 and a_track <= track.tracks.count
		local
			l_now: DATE_TIME
		do
			create l_now.make_now
			create Result.make (400)
			Result.append_string_general ("# ")
			Result.append (track.title)
			Result.append_string_general ("%N%N| | |%N|---|---|%N| URL | https://www.youtube.com/watch?v=")
			Result.append_string_general (track.video_id)
			Result.append_string_general (" |%N| Channel | ")
			Result.append (track.channel)
			Result.append_string_general (" |%N| Length | ")
			Result.append (text.clock_caption (track.length_seconds))
			Result.append_string_general (" |%N| Source | YouTube caption track, ")
			Result.append (track.track_caption (a_track))
			Result.append_string_general (" |%N| Fetched | ")
			Result.append_string_general (l_now.out)
			Result.append_string_general (" |%N%N")
		end

	utf8 (a_text: READABLE_STRING_GENERAL): STRING_8
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
		end

invariant
	parts_attached: track /= Void and text /= Void and url /= Void
		and last_message /= Void and last_error /= Void and saved_path /= Void

end
