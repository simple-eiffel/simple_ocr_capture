note
	description: "[
		Point at a YouTube channel and get every transcript it will give.

		The whole run is one state machine and `step' is one tick of it,
		because all of this happens on the window's thread: a 539-video
		channel is twenty listing pages, twenty-two calls to the local
		model and a thousand calls to YouTube, and a window that did
		that in one go would be a frozen rectangle for half an hour.
		Each phase does the smallest useful unit of work and returns.

		  resolving  the channel page, once, for its id and its name
		  sweeping   one listing page per tick
		  preparing  make the folder, read what is already there
		  proposing  ask the local model to name this channel's categories
		  placing    file twenty-five titles per tick
		  fetching   hand the queue a batch, let it work, take the next
		  done

		The fetching phase does not fetch. It feeds OCR_VIDEO_QUEUE,
		which already knows how to look a video up, read its caption
		track, write the file, fall back to the signed-in browser
		session for a members-only video, and do all of it one row per
		tick. A batch at a time, because YouTube and this machine both
		answer a handful of requests better than five hundred.

		Re-running a channel is the ordinary case, not the exception:
		what has already been written is listed in the folder's own
		manifest and skipped, so a second harvest a month later fetches
		only the new videos.

		A video YouTube refuses - members-only, no captions at all - is
		NOT written to the manifest. It is left to be tried again, since
		the answer can change: turning on the browser session makes the
		members-only ones fetchable without anything here having to know
		that it did.
	]"

class
	OCR_CHANNEL_HARVEST

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS; a_queue: OCR_VIDEO_QUEUE)
		do
			settings := a_settings
			queue := a_queue
			create sweep.make
			create categorizer.make (a_settings)
			create pending.make (256)
			create in_flight.make (8)
			create folder.make_empty
			create last_message.make_empty
			create last_error.make_empty
			create log
			phase := Phase_idle
		end

feature -- Phases

	Phase_idle: INTEGER = 0
	Phase_resolving: INTEGER = 1
	Phase_sweeping: INTEGER = 2
	Phase_preparing: INTEGER = 3
	Phase_proposing: INTEGER = 4
	Phase_placing: INTEGER = 5
	Phase_fetching: INTEGER = 6
	Phase_done: INTEGER = 7
	Phase_failed: INTEGER = 8

	phase: INTEGER

feature -- Access

	sweep: OCR_CHANNEL_SWEEP
			-- The listing.

	categorizer: OCR_TITLE_CATEGORIZER
			-- The local model that files the titles.

	folder: STRING_32
			-- The channel folder this run writes into.

	last_message: STRING_32
			-- What the last step has to say, for the status line.

	last_error: STRING_32
			-- Why the run stopped; empty when it did not.

	saved_count: INTEGER
			-- Transcripts written by this run.

	skipped_count: INTEGER
			-- Videos the manifest said were already here.

	refused_count: INTEGER
			-- Videos YouTube would not give captions for.

	channel_name: STRING_32
		do
			Result := sweep.channel_name
		end

feature -- Status report

	is_running: BOOLEAN
		do
			Result := phase >= Phase_resolving and phase <= Phase_fetching
		end

	is_done: BOOLEAN
		do
			Result := phase = Phase_done
		end

	is_failed: BOOLEAN
		do
			Result := phase = Phase_failed
		end

	remaining: INTEGER
			-- Videos still to fetch.
		do
			Result := pending.count + in_flight.count
		end

	progress_line: STRING_32
			-- Where the run stands, in one line.
		do
			create Result.make (120)
			inspect phase
			when Phase_idle then
				Result.append_string_general ("Paste a channel link and press Harvest Channel.")
			when Phase_resolving then
				Result.append_string_general ("Looking the channel up...")
			when Phase_sweeping then
				Result.append (sweep.summary_line)
			when Phase_preparing then
				Result.append_string_general ("Reading what is already in the folder...")
			when Phase_proposing then
				Result.append_string_general ("Asking the local model what this channel is about...")
			when Phase_placing then
				Result.append_string_general ("Filing titles: ")
				Result.append_string_general (place_index.out)
				Result.append_string_general (" of ")
				Result.append_string_general (pending.count.out)
			when Phase_fetching then
				Result.append (channel_name)
				Result.append_string_general (": ")
				Result.append_string_general (saved_count.out)
				Result.append_string_general (" written, ")
				Result.append_string_general (remaining.out)
				Result.append_string_general (" to go")
				if skipped_count > 0 then
					Result.append_string_general (", ")
					Result.append_string_general (skipped_count.out)
					Result.append_string_general (" already here")
				end
			when Phase_done then
				Result.append (done_line)
			else
				Result.append_string_general ("Harvest stopped: ")
				Result.append (last_error)
			end
		ensure
			never_empty: not Result.is_empty
		end

	done_line: STRING_32
			-- What the finished run wrote, and where.
		do
			create Result.make (140)
			Result.append_string_general ("Harvest done: ")
			Result.append_string_general (saved_count.out)
			Result.append_string_general (" transcript(s) written")
			if skipped_count > 0 then
				Result.append_string_general (", ")
				Result.append_string_general (skipped_count.out)
				Result.append_string_general (" already here")
			end
			if refused_count > 0 then
				Result.append_string_general (", ")
				Result.append_string_general (refused_count.out)
				Result.append_string_general (" refused by YouTube")
			end
			Result.append_string_general (" - ")
			Result.append (folder)
		end

feature -- Basic operations

	start (a_url: READABLE_STRING_GENERAL): BOOLEAN
			-- Begin a harvest of the channel `a_url' names.
		require
			url_given: not a_url.is_empty
		do
			if is_running then
				last_error := {STRING_32} "A harvest is already running."
			elseif queue.is_busy then
				last_error := {STRING_32} "The video queue is busy; let it finish first."
			else
				reset
				settings.set_last_channel_url (a_url)
				start_url := a_url.as_string_32
				phase := Phase_resolving
				last_message := {STRING_32} "Looking the channel up..."
				log.append ({STRING_32} "channel harvest: starting on " + start_url)
				Result := True
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			running_on_success: Result implies is_running
		end

	stop
			-- Give up on the run; whatever is written stays written.
		do
			if is_running then
				close_batch
				write_index
				phase := Phase_done
				last_message := done_line
				log.append ({STRING_32} "channel harvest: stopped by hand - " + done_line)
			end
		ensure
			not_running: not is_running
		end

	step
			-- One tick's share of the work.
		require
			running: is_running
		do
			inspect phase
			when Phase_resolving then step_resolving
			when Phase_sweeping then step_sweeping
			when Phase_preparing then step_preparing
			when Phase_proposing then step_proposing
			when Phase_placing then step_placing
			else step_fetching
			end
		end

feature {NONE} -- The phases

	step_resolving
		do
			if sweep.resolve (start_url) then
				phase := Phase_sweeping
				last_message := {STRING_32} "Listing the videos of " + sweep.channel_name + {STRING_32} "..."
			else
				fail (sweep.last_error)
			end
		end

	step_sweeping
		do
			if sweep.pages_read = 0 then
				if not sweep.sweep_first_page then
					fail (sweep.last_error)
				end
			elseif sweep.is_sweeping then
				if not sweep.sweep_next_page then
					fail (sweep.last_error)
				end
			end
			if phase = Phase_sweeping then
				last_message := sweep.summary_line
				if not sweep.is_sweeping then
					if sweep.count = 0 then
						fail ({STRING_32} "That channel lists no videos under Videos.")
					else
						phase := Phase_preparing
						log.append ({STRING_32} "channel harvest: listed " + sweep.count.out
							+ {STRING_32} " videos from " + sweep.channel_name)
					end
				end
			end
		end

	step_preparing
			-- Make the folder, read the manifest, drop what is already
			-- written, and decide whether the model is wanted.
		local
			l_manifest: OCR_CHANNEL_MANIFEST
		do
			folder := channel_folder
			if not made_folder (folder) then
				fail ({STRING_32} "Could not make the folder " + folder)
			else
				create l_manifest.make (folder)
				manifest := l_manifest
				pending.wipe_out
				across
					sweep.videos as ic
				loop
					if l_manifest.has (ic.video_id) then
						skipped_count := skipped_count + 1
					else
						pending.extend (ic)
					end
				end
				if pending.is_empty then
					write_index
					phase := Phase_done
					last_message := done_line
				elseif settings.categorize_channel then
					categorizer.seed (categories_in_use (l_manifest))
					phase := Phase_proposing
					if categorizer.has_categories then
						last_message := {STRING_32} "Filing under the categories this folder already uses."
					else
						last_message := {STRING_32} "Asking the local model what this channel is about..."
					end
				else
					across
						pending as ic
					loop
						ic.set_category (categorizer.Uncategorised)
					end
					phase := Phase_fetching
				end
			end
		end

	step_proposing
		do
			if categorizer.has_categories then
					-- Seeded from the folder's own manifest in
					-- `step_preparing'; there is nothing to ask.
				place_index := 0
				phase := Phase_placing
			elseif categorizer.propose (pending, sweep.channel_name) then
				place_index := 0
				phase := Phase_placing
				last_message := categorizer.last_message.twin
				log.append ({STRING_32} "channel harvest: categories - " + category_list)
			else
					-- The filing is a convenience, not the point of the run.
					-- A model that is not there, or will not answer, must not
					-- cost anyone their transcripts.
				across
					pending as ic
				loop
					ic.set_category (categorizer.Uncategorised)
				end
				phase := Phase_fetching
				last_message := {STRING_32} "Filing titles was skipped (" + categorizer.last_error
					+ {STRING_32} "); fetching anyway."
				log.append ({STRING_32} "channel harvest: categorising skipped - " + categorizer.last_error)
			end
		end

	step_placing
		local
			l_chunk: ARRAYED_LIST [OCR_CHANNEL_VIDEO]
			i, l_last: INTEGER
		do
			l_last := (place_index + categorizer.Assign_chunk).min (pending.count)
			create l_chunk.make (l_last - place_index)
			from
				i := place_index + 1
			until
				i > l_last
			loop
				l_chunk.extend (pending.i_th (i))
				i := i + 1
			end
			if l_chunk.is_empty then
				phase := Phase_fetching
			else
				if not categorizer.place (l_chunk) then
						-- Same rule as `step_proposing': file them all under
						-- the catch-all rather than stop the run.
					across
						l_chunk as ic
					loop
						if not ic.is_categorised then
							ic.set_category (categorizer.Uncategorised)
						end
					end
				end
				place_index := l_last
				last_message := progress_line
				if place_index >= pending.count then
					phase := Phase_fetching
					last_message := {STRING_32} "Titles filed. Fetching transcripts, "
						+ settings.channel_batch_size.out + {STRING_32} " at a time."
				end
			end
		end

	step_fetching
			-- Feed the queue a batch, let it work, then take the next.
		do
			if queue.is_busy then
					-- The window's own `poll_video' is advancing it; a
					-- second hand on the queue in the same tick is how a
					-- row gets looked up twice.
			elseif not in_flight.is_empty then
				if not batch_fetch_started and then queue.ready_count > 0 then
					queue.start_fetch_all (folder)
					batch_fetch_started := True
				else
					close_batch
				end
			elseif pending.is_empty then
				finish
			else
				start_batch
			end
		end

feature {NONE} -- Batches

	start_batch
			-- Hand the queue the next `channel_batch_size' videos.
		require
			something_pending: not pending.is_empty
			nothing_in_flight: in_flight.is_empty
		local
			l_links: STRING_32
			i, l_count, l_added: INTEGER
		do
			create l_links.make (200)
			from
				i := 1
			until
				i > settings.channel_batch_size or pending.is_empty
			loop
				in_flight.extend (pending.first)
				l_links.append (pending.first.watch_url)
				l_links.append_character ('%N')
				pending.start
				pending.remove
				i := i + 1
			end
			l_added := queue.add_links (l_links)
				-- The rows are found again by id, because `add_links' folds
				-- a duplicate and gives back only a count.
			across
				in_flight as ic
			loop
				if attached queue.item_of_id (ic.video_id) as al_item then
					al_item.set_front_matter (front_matter_for (ic))
				end
			end
			batch_fetch_started := False
			l_count := in_flight.count
			last_message := {STRING_32} "Looking up " + l_count.out + {STRING_32} " video(s) ("
				+ remaining.out + {STRING_32} " to go)"
		ensure
			in_flight_loaded: not in_flight.is_empty
		end

	close_batch
			-- Record what the batch wrote and clear it away.
		local
			l_saved: BOOLEAN
		do
			across
				in_flight as ic
			loop
				if attached queue.item_of_id (ic.video_id) as al_item then
					if al_item.is_saved then
						saved_count := saved_count + 1
						if attached manifest as al_manifest then
							al_manifest.record (ic.video_id, al_item.file_name, ic.category)
							l_saved := True
						end
					elseif al_item.is_refused or al_item.is_failed then
							-- Deliberately NOT recorded: see the class note.
						refused_count := refused_count + 1
						log.append ({STRING_32} "channel harvest: refused " + ic.watch_url
							+ {STRING_32} " - " + al_item.detail)
					end
				end
			end
			in_flight.wipe_out
			batch_fetch_started := False
			queue.clear_finished
			if l_saved and then attached manifest as al_manifest and then not al_manifest.save then
				log.append ({STRING_32} "channel harvest: could not write the manifest - " + al_manifest.last_error)
			end
		ensure
			emptied: in_flight.is_empty
		end

	finish
		do
			write_index
			phase := Phase_done
			last_message := done_line
			log.append ({STRING_32} "channel harvest: " + done_line)
		end

	fail (a_reason: READABLE_STRING_32)
		do
			last_error := a_reason.to_string_32
			last_message := last_error.twin
			phase := Phase_failed
			log.append ({STRING_32} "channel harvest FAILED: " + last_error)
		ensure
			failed: is_failed
		end

feature {NONE} -- What goes in the files

	front_matter_for (a_video: OCR_CHANNEL_VIDEO): STRING_32
			-- The YAML a harvested transcript opens with, so a vault can
			-- find it by channel or by category without the file having
			-- to sit in a folder named after either.
		local
			l_now: DATE
		do
			create l_now.make_now
			create Result.make (400)
			Result.append_string_general ("---%Ntitle: ")
			Result.append (yaml_text (a_video.title))
			Result.append_string_general ("%Nchannel: ")
			Result.append (yaml_text (sweep.channel_name))
			Result.append_string_general ("%Ncategory: ")
			Result.append (yaml_text (a_video.category))
			Result.append_string_general ("%Nurl: ")
			Result.append (a_video.watch_url)
			Result.append_string_general ("%Nvideo_id: ")
			Result.append_string_general (a_video.video_id)
			Result.append_string_general ("%Nharvested: ")
			Result.append_string_general (l_now.formatted_out ("yyyy-[0]mm-[0]dd"))
			Result.append_string_general ("%Ntags:%N  - youtube-transcript%N  - ")
			Result.append (slug (sweep.channel_name))
			Result.append_string_general ("%N  - ")
			Result.append (slug (a_video.category))
			Result.append_string_general ("%N---%N%N")
		ensure
			fenced: Result.starts_with ({STRING_32} "---%N")
		end

feature -- Conversion

	yaml_text (a_text: READABLE_STRING_32): STRING_32
			-- `a_text' as a double-quoted YAML scalar, safe for a title
			-- holding a colon, a quote or a backslash.
		local
			i: INTEGER
			c: CHARACTER_32
		do
			create Result.make (a_text.count + 4)
			Result.append_character ('%"')
			from
				i := 1
			until
				i > a_text.count
			loop
				c := a_text.item (i)
				if c = '%"' or c = '\' then
					Result.append_character ('\')
					Result.append_character (c)
				elseif c.natural_32_code >= 32 then
					Result.append_character (c)
				end
				i := i + 1
			end
			Result.append_character ('%"')
		ensure
			quoted: Result.count >= 2
		end

	slug (a_text: READABLE_STRING_32): STRING_32
			-- `a_text' as a tag: lower case, words joined by hyphens,
			-- nothing else. Never empty, since a tag list with a blank
			-- entry is not valid YAML.
		local
			i: INTEGER
			c: CHARACTER_32
			l_pending: BOOLEAN
		do
			create Result.make (a_text.count)
			from
				i := 1
			until
				i > a_text.count
			loop
				c := a_text.item (i).as_lower
				if c.is_alpha_numeric then
					if l_pending and then not Result.is_empty then
						Result.append_character ('-')
					end
					l_pending := False
					Result.append_character (c)
				else
					l_pending := True
				end
				i := i + 1
			end
			if Result.is_empty then
				Result.append_string_general ("untitled")
			end
		ensure
			never_empty: not Result.is_empty
		end

feature {NONE} -- What goes in the files, continued

	write_index
			-- Write the folder's index: every video of this channel that
			-- has a transcript here, grouped under its category.
		local
			l_file: RAW_FILE
			l_text: STRING_32
			l_retried: BOOLEAN
		do
			if not l_retried and then attached manifest as al_manifest and then not folder.is_empty then
				create l_file.make_with_name (index_path)
				l_file.create_read_write
				l_text := index_text (al_manifest)
				l_file.put_string ({UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (l_text))
				l_file.close
			end
		rescue
			l_retried := True
			retry
		end

	index_text (a_manifest: OCR_CHANNEL_MANIFEST): STRING_32
			-- The index, categories in the order the model named them
			-- and the catch-all last.
		local
			l_now: DATE_TIME
		do
			create l_now.make_now
			create Result.make (4000)
			Result.append_string_general ("# ")
			Result.append (sweep.channel_name)
			Result.append_string_general (" - transcripts%N%N")
			Result.append_string_general ("| | |%N|---|---|%N| Channel | ")
			Result.append (sweep.channel_name)
			Result.append_string_general (" |%N| Videos listed | ")
			Result.append_string_general (sweep.count.out)
			Result.append_string_general (" |%N| Transcripts here | ")
			Result.append_string_general (a_manifest.count.out)
			Result.append_string_general (" |%N| Last harvest | ")
			Result.append_string_general (l_now.out)
			Result.append_string_general (" |%N%N")
			across
				categorizer.categories as ic
			loop
				append_category (Result, a_manifest, ic)
			end
			append_category (Result, a_manifest, categorizer.Uncategorised)
			Result.append_string_general ("%N")
		end

	append_category (a_text: STRING_32; a_manifest: OCR_CHANNEL_MANIFEST; a_category: READABLE_STRING_32)
			-- The heading for `a_category' and a link per transcript
			-- filed under it, if any are.
		local
			l_any: BOOLEAN
		do
			across
				a_manifest.entries as ic
			loop
				if ic.category.is_case_insensitive_equal (a_category.to_string_32) then
					if not l_any then
						a_text.append_string_general ("## ")
						a_text.append (a_category)
						a_text.append_string_general ("%N%N")
						l_any := True
					end
					a_text.append_string_general ("- [[")
					a_text.append (stem_of (ic.file_name))
					a_text.append_string_general ("]]%N")
				end
			end
			if l_any then
				a_text.append_string_general ("%N")
			end
		end

	stem_of (a_file_name: READABLE_STRING_32): STRING_32
			-- `a_file_name' without its extension, which is how a vault
			-- link names a note.
		local
			i: INTEGER
		do
			Result := a_file_name.to_string_32
			i := Result.last_index_of ('.', Result.count)
			if i > 1 then
				Result := Result.substring (1, i - 1)
			end
		end

	index_path: STRING_32
		require
			folder_known: not folder.is_empty
		do
			create Result.make (folder.count + 32)
			Result.append (folder)
			Result.append_character ('\')
			Result.append (sweep.folder_name_of (sweep.channel_name))
			Result.append_string_general (" - Index.md")
		end

	categories_in_use (a_manifest: OCR_CHANNEL_MANIFEST): ARRAYED_LIST [STRING_32]
			-- The distinct categories the folder's transcripts already
			-- carry, in the order they first appear.
		local
			l_seen: BOOLEAN
		do
			create Result.make (12)
			across
				a_manifest.entries as ic
			loop
				if not ic.category.is_empty then
					l_seen := False
					across
						Result as ic_known
					until
						l_seen
					loop
						l_seen := ic_known.is_case_insensitive_equal (ic.category)
					end
					if not l_seen then
						Result.extend (ic.category.twin)
					end
				end
			end
		end

	category_list: STRING_32
			-- The proposed categories on one line, for the log.
		do
			create Result.make (200)
			across
				categorizer.categories as ic
			loop
				if not Result.is_empty then
					Result.append_string_general (", ")
				end
				Result.append (ic)
			end
		end

feature {NONE} -- The folder

	channel_folder: STRING_32
			-- Where this channel's transcripts go.
		require
			resolved: sweep.is_resolved
		do
			create Result.make (120)
			Result.append (settings.channel_root_or_default)
			if not Result.is_empty and then Result.item (Result.count) /= '\' then
				Result.append_character ('\')
			end
			if settings.channel_folder_name.is_empty then
				Result.append (sweep.folder_name)
			else
					-- Cleaned the same way a channel name is: what the user
					-- typed still has to be a folder Windows will accept.
				Result.append (sweep.folder_name_of (settings.channel_folder_name))
			end
		ensure
			never_empty: not Result.is_empty
		end

	made_folder (a_path: READABLE_STRING_32): BOOLEAN
			-- Make `a_path' and every folder above it; True when it is
			-- there afterwards.
		local
			l_dir: DIRECTORY
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_dir.make_with_name (a_path)
				if not l_dir.exists then
					l_dir.recursive_create_dir
				end
				Result := l_dir.exists
			end
		rescue
			l_retried := True
			retry
		end

feature {NONE} -- Implementation

	settings: OCR_SETTINGS

	queue: OCR_VIDEO_QUEUE
			-- The Video tab's own queue, which does the fetching.

	log: OCR_LOG_FILE

	manifest: detachable OCR_CHANNEL_MANIFEST
			-- What the folder already holds; Void before `step_preparing'.

	pending: ARRAYED_LIST [OCR_CHANNEL_VIDEO]
			-- Videos still to hand to the queue.

	in_flight: ARRAYED_LIST [OCR_CHANNEL_VIDEO]
			-- The batch the queue is working on.

	start_url: STRING_32
			-- The link `start' was given.
		attribute
			create Result.make_empty
		end

	place_index: INTEGER
			-- Titles filed so far.

	batch_fetch_started: BOOLEAN
			-- Has the current batch been handed to `start_fetch_all'?

	reset
		do
			pending.wipe_out
			in_flight.wipe_out
			folder.wipe_out
			last_error.wipe_out
			last_message.wipe_out
			manifest := Void
			saved_count := 0
			skipped_count := 0
			refused_count := 0
			place_index := 0
			batch_fetch_started := False
		end

invariant
	parts_attached: settings /= Void and queue /= Void and sweep /= Void
		and categorizer /= Void and pending /= Void and in_flight /= Void
		and folder /= Void and last_message /= Void and last_error /= Void
	counts_not_negative: saved_count >= 0 and skipped_count >= 0 and refused_count >= 0
	phase_known: phase >= Phase_idle and phase <= Phase_failed

end
