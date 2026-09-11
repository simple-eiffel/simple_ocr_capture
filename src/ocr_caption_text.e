note
	description: "[
		Turns a YouTube json3 caption track into readable paragraphs.

		The track is a list of events. A text event carries `segs', each
		with a `utf8' piece; timing-only events and the `aAppend' events
		whose only segment is a newline carry no words and are skipped.
		Measured 2026-09-11 on a 23:40 video: 1434 events, of which 717
		hold text - exactly the count yt-dlp reports.

		Paragraphs break at a speaker change (an event opening with the
		">>" mark YouTube writes), at a sentence end once a paragraph has
		run a minute, and unconditionally at two minutes - auto captions
		without punctuation would otherwise be one block.

		The events come through SIMPLE_JSON_STREAM one at a time: the
		track is never parsed whole. (The first build of this class
		carried a scanner of its own because simple_json's wrappers
		were quadratic under DBC - 158 s of CPU on one track. That was
		fixed in the library the same day; the scanner went with it.)

		Pure text: no network, no files. The fetch lives in
		OCR_CAPTION_TRACK; the file write in OCR_VIDEO_RUN.
	]"

class
	OCR_CAPTION_TEXT

create
	make

feature {NONE} -- Initialization

	make
		do
			create paragraphs.make (64)
			create last_error.make_empty
		end

feature -- Access

	paragraphs: ARRAYED_LIST [STRING_32]
			-- The transcript, one paragraph per item, in order.

	event_count: INTEGER
			-- Text-bearing events seen by the last `load_json3'.

	word_count: INTEGER
			-- Words across every paragraph.

	duration_ms: INTEGER
			-- Where the last event ends, in milliseconds.

	last_error: STRING_32
			-- Why the last `load_json3' refused; empty when it did not.

	is_loaded: BOOLEAN
			-- Did the last load produce any text?
		do
			Result := not paragraphs.is_empty
		end

	plain_text: STRING_32
			-- The paragraphs joined by a blank line.
		do
			create Result.make (word_count * 6 + 16)
			across
				paragraphs as ic
			loop
				if not Result.is_empty then
					Result.append_string_general ("%N%N")
				end
				Result.append (ic)
			end
		end

	duration_caption: STRING_32
			-- `duration_ms' as h:mm:ss or m:ss.
		do
			Result := clock_caption (duration_ms // 1000)
		end

feature -- Basic operations

	load_json3 (a_json: READABLE_STRING_32): BOOLEAN
			-- Stream the events of `a_json' (a json3 track, already
			-- decoded from UTF-8) into `paragraphs'. False, with
			-- `last_error', when it is not a track.
		local
			l_stream: SIMPLE_JSON_STREAM
			l_paragraph: STRING_32
			l_paragraph_start: INTEGER
		do
			reset
			if a_json.is_empty then
				last_error := {STRING_32} "The caption track is empty."
			else
				create l_stream.make_from_string_at (a_json.to_string_32, "events")
				create l_paragraph.make (400)
				across
					l_stream as ic
				loop
					if ic.value.is_object then
						read_event (ic.value.as_object)
						if not event_text.is_empty then
							event_count := event_count + 1
							if should_break (l_paragraph, event_text, event_start - l_paragraph_start) then
								flush (l_paragraph)
							end
							if l_paragraph.is_empty then
								l_paragraph_start := event_start
							else
								l_paragraph.append_character (' ')
							end
							l_paragraph.append (event_text)
							word_count := word_count + words_in (event_text)
						end
					end
				end
				if l_stream.has_errors then
					paragraphs.wipe_out
					last_error := {STRING_32} "The caption track could not be read: "
					last_error.append (l_stream.last_errors.first.message)
				else
					flush (l_paragraph)
					Result := True
				end
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			loaded_on_success: Result implies last_error.is_empty
		end

feature -- Measurement

	words_in (a_text: READABLE_STRING_32): INTEGER
			-- Whitespace-separated words in `a_text'.
		local
			i: INTEGER
			l_in_word: BOOLEAN
		do
			from
				i := 1
			until
				i > a_text.count
			loop
				if a_text.item (i).is_space then
					l_in_word := False
				elseif not l_in_word then
					l_in_word := True
					Result := Result + 1
				end
				i := i + 1
			end
		ensure
			non_negative: Result >= 0
		end

	clock_caption (a_seconds: INTEGER): STRING_32
			-- `a_seconds' as h:mm:ss, or m:ss under an hour.
		require
			non_negative: a_seconds >= 0
		local
			h, m, s: INTEGER
		do
			h := a_seconds // 3600
			m := (a_seconds \\ 3600) // 60
			s := a_seconds \\ 60
			create Result.make (8)
			if h > 0 then
				Result.append_string_general (h.out)
				Result.append_character (':')
				Result.append_string_general (two (m))
			else
				Result.append_string_general (m.out)
			end
			Result.append_character (':')
			Result.append_string_general (two (s))
		end

feature {NONE} -- Paragraphs

	Sentence_break_ms: INTEGER = 60_000
			-- After this long, a sentence end starts a new paragraph.

	Hard_break_ms: INTEGER = 120_000
			-- After this long, anything does.

	reset
		do
			paragraphs.wipe_out
			last_error.wipe_out
			event_count := 0
			word_count := 0
			duration_ms := 0
			event_start := 0
			create event_text.make_empty
		end

	flush (a_paragraph: STRING_32)
			-- Keep `a_paragraph' (when it holds anything) and empty it.
		do
			if not a_paragraph.is_empty then
				paragraphs.extend (a_paragraph.twin)
				a_paragraph.wipe_out
			end
		ensure
			emptied: a_paragraph.is_empty
		end

	should_break (a_paragraph: STRING_32; a_next: STRING_32; a_elapsed_ms: INTEGER): BOOLEAN
			-- Does `a_next' start a new paragraph rather than extend
			-- `a_paragraph', which began `a_elapsed_ms' ago?
		do
			if a_paragraph.is_empty then
				Result := False
			elseif a_next.starts_with ({STRING_32} ">>") then
				Result := True
			elseif a_elapsed_ms >= Hard_break_ms then
				Result := True
			elseif a_elapsed_ms >= Sentence_break_ms then
				Result := ends_sentence (a_paragraph)
			end
		end

	ends_sentence (a_text: STRING_32): BOOLEAN
		local
			c: CHARACTER_32
		do
			if not a_text.is_empty then
				c := a_text.item (a_text.count)
				Result := c = '.' or c = '?' or c = '!'
			end
		end

feature {NONE} -- Events

	event_start: INTEGER
			-- tStartMs of the event `read_event' just read.

	event_text: STRING_32
			-- The collapsed words of the event `read_event' just read.
		attribute
			create Result.make_empty
		end

	read_event (a_event: SIMPLE_JSON_OBJECT)
			-- Read one event's tStartMs, dDurationMs and segs into
			-- `event_start', `duration_ms' and `event_text'.
		local
			i: INTEGER
			l_raw: STRING_32
		do
			event_start := a_event.integer_item ({STRING_32} "tStartMs").to_integer_32
			duration_ms := duration_ms.max (event_start + a_event.integer_item ({STRING_32} "dDurationMs").to_integer_32)
			create l_raw.make (80)
			if attached a_event.array_item ({STRING_32} "segs") as al_segs then
				from
					i := 1
				until
					i > al_segs.count
				loop
					if attached al_segs.object_item (i) as al_seg
						and then attached al_seg.string_item ({STRING_32} "utf8") as al_piece
					then
						l_raw.append (al_piece)
					end
					i := i + 1
				end
			end
			event_text := collapsed (l_raw)
		end

feature {NONE} -- Text

	collapsed (a_text: STRING_32): STRING_32
			-- `a_text' with runs of whitespace (newlines included) as
			-- one space and none at either end.
		local
			i: INTEGER
			l_pending: BOOLEAN
		do
			create Result.make (a_text.count)
			from
				i := 1
			until
				i > a_text.count
			loop
				if a_text.item (i).is_space then
					l_pending := not Result.is_empty
				else
					if l_pending then
						Result.append_character (' ')
						l_pending := False
					end
					Result.append_character (a_text.item (i))
				end
				i := i + 1
			end
		ensure
			no_leading_space: Result.is_empty or else not Result.item (1).is_space
			no_trailing_space: Result.is_empty or else not Result.item (Result.count).is_space
		end

	two (a_value: INTEGER): STRING_8
		do
			if a_value < 10 then
				Result := "0" + a_value.out
			else
				Result := a_value.out
			end
		end

invariant
	paragraphs_attached: paragraphs /= Void
	counts_non_negative: event_count >= 0 and word_count >= 0 and duration_ms >= 0

end
