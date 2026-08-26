note
	description: "[
		Decides whether two captures show the same screen.

		Used by the auto-advance driver to answer "did anything move on?" when
		the page indicator cannot answer it - which is whenever a printed page
		is larger than the reader's window, so the indicator holds still across
		several screenfuls while the text advances every time.
	]"
	design: "[
		Compared with a tolerance rather than exactly, because the OCR is a
		sampling model: re-reading one unchanged screen can come back differing
		by a character or two. Exact comparison would read that jitter as
		progress and go on clicking for ever at the end of a book.

		The tolerance is safe because the two cases are nowhere near each other.
		A genuine next screenful shares almost nothing with its predecessor,
		while a re-read of the same screen shares nearly all of it. Anything
		above `Similarity_percent` is the second case.
	]"

class
	OCR_TEXT_COMPARE

feature -- Status report

	is_same_screen (a_first, a_second: READABLE_STRING_32): BOOLEAN
			-- Are `a_first' and `a_second' the same text but for jitter?
		local
			l_first, l_second: STRING_32
			l_shorter, l_head, l_tail: INTEGER
		do
			l_first := flattened (a_first)
			l_second := flattened (a_second)

			if l_first.same_string (l_second) then
				Result := True
			elseif not l_first.is_empty and not l_second.is_empty then
				l_shorter := l_first.count.min (l_second.count)
				l_head := common_head (l_first, l_second)
					-- Capped so a head match and a tail match cannot both count
					-- the same character.
				l_tail := common_tail (l_first, l_second, l_shorter - l_head)
				Result := (l_head + l_tail) * 100 >= Similarity_percent * l_shorter
			end
		end

feature -- Measurement

	agreement_percent (a_first, a_second: READABLE_STRING_32): INTEGER
			-- How much of the shorter text the two share, at the ends.
			-- Reported for diagnostics; `is_same_screen' is the decision.
		local
			l_first, l_second: STRING_32
			l_shorter, l_head: INTEGER
		do
			l_first := flattened (a_first)
			l_second := flattened (a_second)
			if l_first.is_empty or l_second.is_empty then
				if l_first.is_empty and l_second.is_empty then
					Result := 100
				end
			else
				l_shorter := l_first.count.min (l_second.count)
				l_head := common_head (l_first, l_second)
				Result := ((l_head + common_tail (l_first, l_second, l_shorter - l_head)) * 100) // l_shorter
			end
		ensure
			in_range: Result >= 0 and Result <= 100
		end

feature -- Conversion

	flattened (a_text: READABLE_STRING_32): STRING_32
			-- `a_text' with every run of whitespace reduced to one space, so a
			-- line rewrapped between two reads is not mistaken for new content.
			-- Markdown IMAGE lines (first non-blank characters "![") are
			-- dropped whole first: their link targets carry per-capture file
			-- names, which would read as fresh content on every re-read of
			-- the same screen.
		local
			l_space: BOOLEAN
			l_kept: STRING_32
		do
			create l_kept.make (a_text.count)
			across a_text.split ('%N') as ic_line loop
				if not is_image_line (ic_line) then
					l_kept.append (ic_line)
					l_kept.append_character ('%N')
				end
			end
			create Result.make (l_kept.count)
			across l_kept as ic_char loop
				if is_blank (ic_char.item) then
					if not l_space and then not Result.is_empty then
						Result.append_character (' ')
					end
					l_space := True
				else
					Result.append_character (ic_char.item)
					l_space := False
				end
			end
			Result.right_adjust
		end

	is_image_line (a_line: READABLE_STRING_32): BOOLEAN
			-- Does `a_line' hold a Markdown image link - its first
			-- non-blank characters being "!["?
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > a_line.count or else (a_line.item (i) /= ' ' and a_line.item (i) /= '%T')
			loop
				i := i + 1
			end
			Result := i < a_line.count and then a_line.item (i) = '!' and then a_line.item (i + 1) = '['
		end

feature {NONE} -- Implementation

	common_head (a_first, a_second: READABLE_STRING_32): INTEGER
			-- How many characters `a_first' and `a_second' share from the front?
		local
			l_limit: INTEGER
		do
			l_limit := a_first.count.min (a_second.count)
			from
			until
				Result >= l_limit or else a_first.item (Result + 1) /= a_second.item (Result + 1)
			loop
				Result := Result + 1
			end
		ensure
			bounded: Result <= a_first.count and Result <= a_second.count
		end

	common_tail (a_first, a_second: READABLE_STRING_32; a_limit: INTEGER): INTEGER
			-- How many characters they share from the back, at most `a_limit'.
			--
			-- The guard is checked before the indexing, so a limit of zero or
			-- less simply yields zero rather than reading past the front.
		do
			from
			until
				Result >= a_limit
					or else a_first.item (a_first.count - Result) /= a_second.item (a_second.count - Result)
			loop
				Result := Result + 1
			end
		ensure
			not_negative: Result >= 0
			within_limit: Result <= a_limit.max (0)
		end

	is_blank (a_char: CHARACTER_32): BOOLEAN
			-- Is `a_char' whitespace?
		do
			Result := a_char = ' ' or a_char = '%N' or a_char = '%R' or a_char = '%T'
		end

feature -- Constants

	Similarity_percent: INTEGER = 97
			-- How alike two captures must be to count as the same screen.

end
