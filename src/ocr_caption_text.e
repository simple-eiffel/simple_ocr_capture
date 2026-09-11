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

		The track is read by a small scanner of its own rather than
		through simple_json: a 391 KB track holds 1434 events, and
		SIMPLE_JSON_ARRAY's invariants walk the whole array on every
		element access, which made the first build spend 158 s of CPU
		on one video under DBC. The scanner reads the three keys this
		class needs (tStartMs, dDurationMs, segs[].utf8) and skips
		everything else by structure, so an unknown key can never
		derail it.

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
			create source.make_empty
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
			-- Parse `a_json' (a json3 track, already decoded from UTF-8)
			-- into `paragraphs'. False, with `last_error', when it is not
			-- a track.
		local
			l_paragraph: STRING_32
			l_paragraph_start: INTEGER
		do
			reset
			create source.make_from_string (a_json)
			if source.is_empty then
				last_error := {STRING_32} "The caption track is empty."
			else
				pos := source.substring_index ({STRING_32} "%"events%"", 1)
				if pos = 0 then
					if is_json_object then
						last_error := {STRING_32} "The caption track has no events list."
					else
						last_error := {STRING_32} "The caption track is not JSON."
					end
				else
					pos := pos + 8
					skip_blanks
					if pos <= source.count and then source.item (pos) = ':' then
						pos := pos + 1
					end
					skip_blanks
					if pos > source.count or else source.item (pos) /= '[' then
						last_error := {STRING_32} "The caption track's events are not a list."
					else
						pos := pos + 1
						create l_paragraph.make (400)
						from
							skip_blanks
						until
							pos > source.count or else source.item (pos) = ']'
						loop
							if source.item (pos) = '{' then
								read_event
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
							elseif source.item (pos) = ',' then
								pos := pos + 1
							else
									-- anything else here is malformed; step past it
								pos := pos + 1
							end
							skip_blanks
						end
						flush (l_paragraph)
						Result := True
					end
				end
			end
			source.wipe_out
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
			pos := 0
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

feature {NONE} -- Scanner state

	source: STRING_32
			-- The track being read; emptied when the read is done.

	pos: INTEGER
			-- The scanner's cursor into `source'.

	event_start: INTEGER
			-- tStartMs of the event `read_event' just read.

	event_text: STRING_32
			-- The collapsed words of the event `read_event' just read.
		attribute
			create Result.make_empty
		end

feature {NONE} -- Scanner

	is_json_object: BOOLEAN
			-- Does `source' open with a brace, after any whitespace?
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > source.count or else not source.item (i).is_space
			loop
				i := i + 1
			end
			Result := i <= source.count and then source.item (i) = '{'
		end

	skip_blanks
		do
			from
			until
				pos > source.count or else not source.item (pos).is_space
			loop
				pos := pos + 1
			end
		end

	read_event
			-- At '{': read one event's tStartMs, dDurationMs and segs
			-- into `event_start', `duration_ms' and `event_text';
			-- leave `pos' after its closing brace.
		require
			at_brace: pos <= source.count and then source.item (pos) = '{'
		local
			l_key, l_raw: STRING_32
			l_start, l_duration: INTEGER
		do
			create l_raw.make (80)
			pos := pos + 1
			from
				skip_blanks
			until
				pos > source.count or else source.item (pos) = '}'
			loop
				if source.item (pos) = '%"' then
					l_key := read_string
					skip_blanks
					if pos <= source.count and then source.item (pos) = ':' then
						pos := pos + 1
					end
					skip_blanks
					if l_key.same_string_general ("tStartMs") then
						l_start := read_number
					elseif l_key.same_string_general ("dDurationMs") then
						l_duration := read_number
					elseif l_key.same_string_general ("segs") then
						read_segs (l_raw)
					else
						skip_value
					end
				else
						-- a comma between members, or something malformed
					pos := pos + 1
				end
				skip_blanks
			end
			if pos <= source.count then
				pos := pos + 1
			end
			event_start := l_start
			duration_ms := duration_ms.max (l_start + l_duration)
			event_text := collapsed (l_raw)
		end

	read_segs (a_raw: STRING_32)
			-- At '[': append every segment's utf8 to `a_raw'; leave
			-- `pos' after the closing bracket.
		local
			l_key: STRING_32
		do
			if pos <= source.count and then source.item (pos) = '[' then
				pos := pos + 1
				from
					skip_blanks
				until
					pos > source.count or else source.item (pos) = ']'
				loop
					if source.item (pos) = '{' then
						pos := pos + 1
						from
							skip_blanks
						until
							pos > source.count or else source.item (pos) = '}'
						loop
							if source.item (pos) = '%"' then
								l_key := read_string
								skip_blanks
								if pos <= source.count and then source.item (pos) = ':' then
									pos := pos + 1
								end
								skip_blanks
								if l_key.same_string_general ("utf8") and then pos <= source.count and then source.item (pos) = '%"' then
									a_raw.append (read_string)
								else
									skip_value
								end
							else
								pos := pos + 1
							end
							skip_blanks
						end
						if pos <= source.count then
							pos := pos + 1
						end
					else
						pos := pos + 1
					end
					skip_blanks
				end
				if pos <= source.count then
					pos := pos + 1
				end
			else
				skip_value
			end
		end

	read_string: STRING_32
			-- At '"': the string's characters with JSON escapes
			-- decoded (surrogate pairs joined); leave `pos' after
			-- the closing quote. An unterminated string reads to
			-- the end.
		require
			at_quote: pos <= source.count and then source.item (pos) = '%"'
		local
			c: CHARACTER_32
			l_code, l_low: NATURAL_32
			l_done: BOOLEAN
		do
			create Result.make (32)
			pos := pos + 1
			from
			until
				l_done or pos > source.count
			loop
				c := source.item (pos)
				if c = '%"' then
					l_done := True
					pos := pos + 1
				elseif c = '\' and then pos < source.count then
					pos := pos + 1
					c := source.item (pos)
					inspect c
					when 'n' then Result.append_character ('%N')
					when 't' then Result.append_character ('%T')
					when 'r' then Result.append_character ('%R')
					when 'b' then Result.append_character ('%B')
					when 'f' then Result.append_character ('%F')
					when 'u' then
						l_code := hex_at (pos + 1)
						pos := pos + 4
						if l_code >= 0xD800 and l_code <= 0xDBFF and then pos + 6 <= source.count
							and then source.item (pos + 1) = '\' and then source.item (pos + 2) = 'u'
						then
							l_low := hex_at (pos + 3)
							if l_low >= 0xDC00 and l_low <= 0xDFFF then
								l_code := 0x10000 + ((l_code - 0xD800) |<< 10) + (l_low - 0xDC00)
								pos := pos + 6
							end
						end
						Result.append_code (l_code)
					else
						Result.append_character (c)
					end
					pos := pos + 1
				else
					Result.append_character (c)
					pos := pos + 1
				end
			end
		end

	hex_at (a_index: INTEGER): NATURAL_32
			-- The four hex digits at `a_index'; digits past the end
			-- or not hex count as zero.
		local
			i: INTEGER
			c: CHARACTER_32
			d: NATURAL_32
		do
			from
				i := a_index
			until
				i >= a_index + 4
			loop
				d := 0
				if i <= source.count then
					c := source.item (i)
					if c >= '0' and c <= '9' then
						d := c.natural_32_code - ('0').natural_32_code
					elseif c >= 'a' and c <= 'f' then
						d := c.natural_32_code - ('a').natural_32_code + 10
					elseif c >= 'A' and c <= 'F' then
						d := c.natural_32_code - ('A').natural_32_code + 10
					end
				end
				Result := Result * 16 + d
				i := i + 1
			end
		end

	read_number: INTEGER
			-- The integer at `pos' (a fractional part is dropped);
			-- leave `pos' after it.
		local
			l_negative, l_in_fraction: BOOLEAN
			c: CHARACTER_32
		do
			if pos <= source.count and then source.item (pos) = '-' then
				l_negative := True
				pos := pos + 1
			end
			from
			until
				pos > source.count or else not (source.item (pos).is_digit or source.item (pos) = '.')
			loop
				c := source.item (pos)
				if c = '.' then
					l_in_fraction := True
				elseif not l_in_fraction and then Result < 100_000_000 then
					Result := Result * 10 + (c.natural_32_code - ('0').natural_32_code).to_integer_32
				end
				pos := pos + 1
			end
			if l_negative then
				Result := -Result
			end
		end

	skip_value
			-- Step over whatever JSON value starts at `pos': a string,
			-- a number, a literal, or a nested object or array with
			-- every string inside it honoured.
		local
			l_depth: INTEGER
			c: CHARACTER_32
			l_discard: STRING_32
			l_done: BOOLEAN
		do
			if pos <= source.count then
				c := source.item (pos)
				if c = '%"' then
					l_discard := read_string
				elseif c = '{' or c = '[' then
					from
					until
						l_done or pos > source.count
					loop
						c := source.item (pos)
						if c = '%"' then
							l_discard := read_string
						else
							if c = '{' or c = '[' then
								l_depth := l_depth + 1
							elseif c = '}' or c = ']' then
								l_depth := l_depth - 1
								l_done := l_depth = 0
							end
							pos := pos + 1
						end
					end
				else
					from
					until
						pos > source.count or else source.item (pos) = ',' or else source.item (pos) = '}' or else source.item (pos) = ']' or else source.item (pos).is_space
					loop
						pos := pos + 1
					end
				end
			end
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
