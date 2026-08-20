note
	description: "[
		Best-effort reading of "where are we" out of a reader's page indicator.

		Finds every "<number> of <number>" or "<number> / <number>" pair and
		takes the one with the LARGEST total:

		    "Page 224 of 416"                      -> 224 of 416
		    "90-92 / 139"                          ->  92 of 139
		    "Location 3120 of 8890"                -> 3120 of 8890
		    "Page 12 of 170  Location 890 of 8890" -> 890 of 8890
		    "Page iii of 214"                      -> nothing
		    "10"                                   -> nothing

		That covers every format seen in the field without knowing any of them.
	]"
	design: "[
		PAIRS, NOT FIRST-AND-LAST. The original took the first integer as the
		position and the last as the total. That is right for two numbers and
		silently wrong for four: a reader showing "Page 12 of 170  Location 890
		of 8890" paired a PAGE position with a LOCATION total, giving 12 of
		8890 - a percentage near zero and a meaningless ETA, on every capture,
		for any book whose reader shows both counters.

		LARGEST TOTAL. Where several pairs are present, the one with the biggest
		total is the location counter, and it is the most stable thing on the
		indicator: monotonic across the whole book, its total never changing and
		its position never resetting. Anchoring to it means front matter, roman
		numerals and the arrival of page numbers are all non-events - there is
		no handover, because the series is never interrupted.

		Chosen by ARITHMETIC, never by looking for the word "Location". Its
		ancestor OCR_PAGE_LABEL required the indicator to match one reader's
		wording, and the next book - "Page iii of 214" - was rejected on every
		page until the run gave up. Nothing here may depend on a word.

		STILL AN EXTRACTOR, NOT A VALIDATOR. It never refuses a label; it
		answers `has_position' with False and says nothing more. Nothing here
		may gate a capture, a page turn or a stop. The page indicator has been
		tried twice as a control input and failed twice; it is an annotation.
	]"

class
	OCR_PAGE_POSITION

feature -- Access

	position: INTEGER
			-- Where the reader says it is; meaningless unless `has_position'.

	total: INTEGER
			-- What the reader says the end is; meaningless unless `has_total'.

	pair_count: INTEGER
			-- How many usable pairs the last label held. For diagnostics: two
			-- means a reader showing both a page and a location counter.

feature -- Status report

	has_position: BOOLEAN
			-- Was a position recovered?

	has_total: BOOLEAN
			-- Was a total recovered?

feature -- Element change

	set_from (a_label: READABLE_STRING_GENERAL)
			-- Read what can be read out of `a_label'.
		local
			l_text: STRING_32
			l_starts, l_ends, l_values: ARRAYED_LIST [INTEGER]
			l_digits: STRING_8
			i, k, l_run_start: INTEGER
		do
			has_position := False
			has_total := False
			position := 0
			total := 0
			pair_count := 0

			create l_text.make_from_string_general (a_label)
			create l_starts.make (6)
			create l_ends.make (6)
			create l_values.make (6)
			create l_digits.make (12)

				-- Every run of digits, with where it began and ended. The three
				-- lists are only ever appended together, so they stay in step.
			from
				i := 1
			until
				i > l_text.count + 1
			loop
				if i <= l_text.count and then is_digit (l_text.item (i)) then
					if l_digits.is_empty then
						l_run_start := i
					end
					l_digits.extend (l_text.item (i).to_character_8)
				elseif not l_digits.is_empty then
						-- Capped at nine digits: `to_integer' overflows beyond
						-- that, and no page or location counter is that large.
					if l_digits.count <= Maximum_digits and then l_digits.is_integer then
						l_starts.extend (l_run_start)
						l_ends.extend (i - 1)
						l_values.extend (l_digits.to_integer)
					end
					l_digits.wipe_out
				end
				i := i + 1
			end

				-- Adjacent numbers separated by "of" or "/" form a pair. Keep
				-- the pair with the largest total.
			from
				k := 1
			until
				k > l_values.count - 1
			loop
				if l_values.i_th (k) > 0
					and then l_values.i_th (k + 1) > l_values.i_th (k)
					and then is_separator (l_text.substring (l_ends.i_th (k) + 1,
						l_starts.i_th (k + 1) - 1))
				then
					pair_count := pair_count + 1
					if not has_total or else l_values.i_th (k + 1) > total then
						position := l_values.i_th (k)
						total := l_values.i_th (k + 1)
						has_position := True
						has_total := True
					end
				end
				k := k + 1
			end
		ensure
			total_implies_position: has_total implies has_position
			ordered: has_total implies total > position
			counted: pair_count >= 0
		end

feature {NONE} -- Implementation

	is_digit (a_char: CHARACTER_32): BOOLEAN
		do
			Result := a_char >= '0' and a_char <= '9'
		end

	is_separator (a_gap: READABLE_STRING_32): BOOLEAN
			-- Does `a_gap' join two numbers into a "<position> of <total>" pair?
			--
			-- "of" and "/" only. An EMPTY gap is deliberately not a separator:
			-- two numbers merely sitting next to each other are not a ratio, and
			-- treating them as one would invent pairs out of dates, chapter
			-- numbers and anything else the indicator happens to carry.
		local
			l_trim: STRING_32
		do
			create l_trim.make_from_string (a_gap)
			l_trim.left_adjust
			l_trim.right_adjust
			l_trim.to_lower
			Result := l_trim.same_string ({STRING_32} "of")
				or l_trim.same_string ({STRING_32} "/")
		end

	Maximum_digits: INTEGER = 9

end
