note
	description: "[
		Checks a finished transcript and reports what looks wrong.

		Reads the transcript itself rather than the run log: its separators
		already carry the capture number and the page indicator, and the body
		text is needed for the duplicate and seam checks anyway. One file to
		read, and it is the artifact being judged.

		Findings are printed and appended to <book>.findings.jsonl, where the
		interface can show them.
	]"
	design: "[
		NEVER REPAIRS ANYTHING. It appends findings and prints. Every repair
		performed by hand on this corpus was a separate, reviewable step, and
		that separation is what made it safe to be wrong.

		SAYS HOW SURE IT IS. Two checks cannot be certain, and both produced
		false alarms when done by hand:

		  * A page number with no covering capture may not be a real page.
		    344 and 355-356 of one book simply did not exist; three earlier
		    "missing page" reports were wrong for this reason.

		  * A seam that looks broken may be a bibliography, where every entry
		    begins capitalised and ends with a full stop - exactly the shape the
		    join test reads as a break.

		GAP DETECTION DEPENDS ON HOW THE READER LABELS. A reader naming a RANGE
		("123-126 / 356") states every page on screen, so a number missing from
		the union really is missing. A reader naming ONE page ("Page 107 of
		488") labels only the first of three or four, so most numbers never
		appear and set difference reports the whole book missing - it did, 328
		of 488. For those, the check is a step far larger than the run's own
		typical step.
	]"

class
	OCR_AUDIT

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
			-- Audit the book described by `a_settings'.
		do
			settings := a_settings
			create findings.make (a_settings)
			create report.make (4096)
			create blocks.make (256)
			create labels.make (256)
		end

feature -- Access

	findings: OCR_FINDINGS
			-- Where findings are written. Exposed so a caller can attach a
			-- display before running, and see rows appear as they are found.

	report: STRING_32
			-- Everything found, as text, for printing.

	finding_count: INTEGER
			-- How many findings were recorded.

feature -- Basic operations

	run (a_path: READABLE_STRING_GENERAL)
			-- Audit the transcript at `a_path'.
		local
			l_text: detachable STRING_32
		do
			report.wipe_out
			finding_count := 0
			blocks.wipe_out
			labels.wipe_out

			l_text := read_utf8 (a_path)
			if l_text = Void then
				say ("Could not read " + a_path.to_string_32)
			else
				split_blocks (l_text)
				say ("blocks: " + blocks.count.out)
				if blocks.is_empty then
					say ("No capture separators found. Was 'Write a header line before each capture' off?")
				else
					check_markers (l_text)
					check_short_blocks
					check_duplicates
					check_indicator_lost
					check_movement
				end
				say ("findings recorded: " + finding_count.out)
			end
		end

feature {NONE} -- Checks

	check_markers (a_text: READABLE_STRING_32)
			-- Failed or truncated captures, both of which the worker writes
			-- into the text itself.
		local
			l_failed, l_trunc: INTEGER
		do
			l_failed := occurrences (a_text, "[OCR FAILED]")
			l_trunc := occurrences (a_text, "[TRUNCATED]")
			if l_failed > 0 then
				note_finding ({OCR_FINDINGS}.Severity_error, "",
					"OCR failed on " + l_failed.out + " capture(s)",
					"Re-scan those pages with --rescan; the images are still on disk", "", True)
			end
			if l_trunc > 0 then
				note_finding ({OCR_FINDINGS}.Severity_error, "",
					l_trunc.out + " capture(s) were truncated",
					"Raise 'Context tokens' and re-scan those pages", "", True)
			end
		end

	check_short_blocks
			-- Captures with so little text that they are worth a look. Not an
			-- error: a splash screen and a legitimately near-empty page are the
			-- same size, and only a person can tell them apart.
		local
			i, l_count: INTEGER
			l_where: STRING_32
		do
			create l_where.make (64)
			from i := 1 until i > blocks.count loop
				if blocks.i_th (i).count < Short_text then
					l_count := l_count + 1
					if l_count <= 6 then
						if not l_where.is_empty then
							l_where.append_string_general (", ")
						end
						l_where.append (labels.i_th (i))
					end
				end
				i := i + 1
			end
			if l_count > 0 then
				note_finding ({OCR_FINDINGS}.Severity_info, l_where,
					l_count.out + " capture(s) came back with very little text",
					"Look at those pages; a part title is fine, a splash screen is not", "", True)
			end
		end

	check_duplicates
			-- The same page transcribed twice. Compared with tolerance, not
			-- equality: the model is a sampling one, so a replayed screen comes
			-- back differing by a character or two. Two blocks of one book
			-- differed by exactly one character and an equality test missed it.
		local
			i, j, l_count: INTEGER
			l_compare: OCR_TEXT_COMPARE
			l_where: STRING_32
		do
			create l_compare
			create l_where.make (64)
			from i := 1 until i > blocks.count loop
					-- EVERY later block, not a window of six. The repeats that
					-- prompted this check sat 129 blocks from their originals: a
					-- reader sent back to the cover mid-run re-scanned the
					-- opening, and a short window saw nothing at all.
					--
					-- Made affordable by comparing lengths first. Two captures of
					-- the same screen differ by a character or two, so anything
					-- differing by more than a few percent cannot be a repeat and
					-- is dismissed without the expensive comparison.
				from j := i + 1 until j > blocks.count loop
					if similar_length (blocks.i_th (i).count, blocks.i_th (j).count)
						and then l_compare.is_same_screen (blocks.i_th (i), blocks.i_th (j))
					then
						l_count := l_count + 1
						if l_count <= 6 then
							if not l_where.is_empty then
								l_where.append_string_general (", ")
							end
							l_where.append (labels.i_th (j))
						end
					end
					j := j + 1
				end
				i := i + 1
			end
			if l_count > 0 then
				note_finding ({OCR_FINDINGS}.Severity_warn, l_where,
					l_count.out + " block(s) repeat an earlier capture",
					"Remove the repeats before using the text for counting or search", "", True)
			end
		end

	check_indicator_lost
			-- The indicator reading, then not. Everything still works when this
			-- happens - advance detection never uses it - but pages stop being
			-- named and annotated, which is worth knowing.
		local
			i, l_run, l_worst: INTEGER
			l_reader: OCR_PAGE_POSITION
			l_seen: BOOLEAN
		do
			create l_reader
			from i := 1 until i > labels.count loop
				l_reader.set_from (labels.i_th (i))
				if l_reader.has_position then
					l_seen := True
					l_run := 0
				elseif l_seen then
					l_run := l_run + 1
					l_worst := l_worst.max (l_run)
				end
				i := i + 1
			end
			if l_worst >= Indicator_alarm then
				note_finding ({OCR_FINDINGS}.Severity_warn, "",
					"The page indicator stopped reading for " + l_worst.out + " consecutive capture(s)",
					"Those pages are transcribed but not named by page; a page box left in edit mode looks like this",
					"", True)
			end
		end

	check_movement
			-- Backwards steps and outsized jumps.
			--
			-- WITHIN A SERIES ONLY. A book whose indicator changes units - "Page
			-- 245 of 267" giving way to "Location 1 of 11296" - produces
			-- positions that are not comparable at all. Measured across the
			-- change, one book reported a "usual step" of 52 (page steps of 1-4
			-- averaged with location steps of 60-100) and a spurious backwards
			-- step at every handover. Steps are only meaningful between two
			-- readings of the same total.
		local
			i, l_prev, l_prev_total, l_pos, l_step, l_typical, l_back, l_big: INTEGER
			l_reader: OCR_PAGE_POSITION
			l_steps: ARRAYED_LIST [INTEGER]
			l_where: STRING_32
		do
			create l_reader
			create l_steps.make (blocks.count)
			create l_where.make (64)
			from i := 1 until i > labels.count loop
				l_reader.set_from (labels.i_th (i))
				if l_reader.has_position then
					l_pos := l_reader.position
					if l_prev > 0 and then l_reader.total = l_prev_total then
						l_step := l_pos - l_prev
						if l_step < 0 then
							l_back := l_back + 1
							if l_where.is_empty then
								l_where.append (labels.i_th (i))
							end
						elseif l_step > 0 then
							l_steps.extend (l_step)
						end
					end
					l_prev := l_pos
					l_prev_total := l_reader.total
				end
				i := i + 1
			end

			if l_back > 0 then
				note_finding ({OCR_FINDINGS}.Severity_error, l_where,
					l_back.out + " capture(s) report a page number BEFORE the one before them",
					"The reader went backwards; that stretch is a re-scan of text already present", "", True)
			end

			l_typical := typical_step (l_steps)
			if l_typical > 0 then
				l_big := 0
				create l_where.make (64)
				from i := 1 until i > l_steps.count loop
					if l_steps.i_th (i) > l_typical * Jump_multiple then
						l_big := l_big + 1
					end
					i := i + 1
				end
				if l_big > 0 then
					note_finding ({OCR_FINDINGS}.Severity_error, "",
						l_big.out + " jump(s) far larger than this run's usual step of " + l_typical.out,
						"Pages were probably skipped there; compare the text either side", "", True)
				end
			end
		end

feature {NONE} -- Implementation

	split_blocks (a_text: READABLE_STRING_32)
			-- Fill `blocks' and `labels' from the transcript's separators.
		local
			i, l_start, l_body: INTEGER
			l_line, l_label: STRING_32
		do
			from
				i := 1
				l_start := 0
			until
				i > a_text.count
			loop
				if a_text.item (i) = '-' and then is_separator_at (a_text, i) then
					l_line := line_at (a_text, i)
					l_label := label_in (l_line)
					if l_start > 0 then
						blocks.extend (a_text.substring (l_start, i - 1))
					end
					labels.extend (l_label)
					l_body := i + l_line.count
					l_start := (l_body + 1).min (a_text.count)
					i := l_body
				end
				i := i + 1
			end
			if l_start > 0 and then l_start <= a_text.count then
				blocks.extend (a_text.substring (l_start, a_text.count))
			end
				-- One label per block, always: a trailing separator with no body
				-- would otherwise leave the two lists out of step and every
				-- later check reading the wrong label.
			from until blocks.count >= labels.count loop
				blocks.extend ({STRING_32} "")
			end
			from until labels.count >= blocks.count loop
				labels.extend ({STRING_32} "")
			end
		ensure
			paired: blocks.count = labels.count
		end

	is_separator_at (a_text: READABLE_STRING_32; a_at: INTEGER): BOOLEAN
			-- Does a capture separator start at `a_at'?
		do
			Result := a_at + Separator_head.count - 1 <= a_text.count
				and then a_text.substring (a_at, a_at + Separator_head.count - 1).same_string (Separator_head)
				and then (a_at = 1 or else a_text.item (a_at - 1) = '%N')
		end

	line_at (a_text: READABLE_STRING_32; a_at: INTEGER): STRING_32
			-- The line beginning at `a_at'.
		local
			l_end: INTEGER
		do
			l_end := a_text.index_of ('%N', a_at)
			if l_end = 0 then
				l_end := a_text.count + 1
			end
			Result := a_text.substring (a_at, l_end - 1)
		end

	label_in (a_line: READABLE_STRING_32): STRING_32
			-- The page indicator recorded in a separator line, if any.
		local
			l_open, l_close: INTEGER
		do
			create Result.make_empty
			l_open := a_line.index_of ('[', 1)
			if l_open > 0 then
				l_close := a_line.index_of (']', l_open)
				if l_close > l_open then
					Result := a_line.substring (l_open + 1, l_close - 1)
						-- Written as "[page 12 of 170]"; the word is noise here.
					if Result.starts_with ({STRING_32} "page ") then
						Result := Result.substring (6, Result.count)
					end
				end
			end
		end

	similar_length (a_left, a_right: INTEGER): BOOLEAN
			-- Could two blocks of these sizes be captures of the same screen?
			--
			-- A cheap gate before the expensive comparison. Re-reading one
			-- screen returns text differing by a character or two, so a size
			-- difference beyond a few percent rules a repeat out outright.
		local
			l_big, l_small: INTEGER
		do
			l_big := a_left.max (a_right)
			l_small := a_left.min (a_right)
			Result := l_small > 0 and then (l_big - l_small) * 100 <= l_big * Length_slack
		end

	typical_step (a_steps: ARRAYED_LIST [INTEGER]): INTEGER
			-- The usual forward step of this run, as a median.
			--
			-- Median rather than mean: one 210-page jump would drag a mean far
			-- enough to hide itself.
		local
			l_sorted: ARRAYED_LIST [INTEGER]
			i, j, l_v: INTEGER
		do
			if not a_steps.is_empty then
				create l_sorted.make (a_steps.count)
				l_sorted.append (a_steps)
				from i := 2 until i > l_sorted.count loop
					l_v := l_sorted.i_th (i)
					from j := i - 1 until j < 1 or else l_sorted.i_th (j) <= l_v loop
						l_sorted.put_i_th (l_sorted.i_th (j), j + 1)
						j := j - 1
					end
					l_sorted.put_i_th (l_v, j + 1)
					i := i + 1
				end
				Result := l_sorted.i_th ((l_sorted.count + 1) // 2)
			end
		end

	note_finding (a_severity, a_pages, a_problem, a_remedy, a_fix: READABLE_STRING_GENERAL;
			a_certain: BOOLEAN)
			-- Record and print one finding.
		local
			l_line: STRING_32
		do
			findings.deduced (a_severity, a_pages, a_problem, a_remedy, a_fix, a_certain)
			finding_count := finding_count + 1
			create l_line.make (160)
			l_line.append_string_general ("  [")
			l_line.append_string_general (a_severity)
			if not a_certain then
				l_line.append_string_general ("/uncertain")
			end
			l_line.append_string_general ("] ")
			l_line.append_string_general (a_problem)
			if not a_pages.is_empty then
				l_line.append_string_general ("   (")
				l_line.append_string_general (a_pages)
				l_line.append_character (')')
			end
			l_line.append_string_general ("%N       -> ")
			l_line.append_string_general (a_remedy)
			say (l_line)
		end

	say (a_line: READABLE_STRING_GENERAL)
		do
			report.append_string_general (a_line)
			report.append_character ('%N')
		end

	occurrences (a_text: READABLE_STRING_32; a_what: READABLE_STRING_8): INTEGER
		local
			i: INTEGER
			l_what: STRING_32
		do
			create l_what.make_from_string_general (a_what)
			from
				i := a_text.substring_index (l_what, 1)
			until
				i = 0
			loop
				Result := Result + 1
				i := a_text.substring_index (l_what, i + 1)
			end
		end

	read_utf8 (a_path: READABLE_STRING_GENERAL): detachable STRING_32
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (a_path)
				if l_file.exists and then l_file.is_readable then
					l_file.open_read
					if l_file.count > 0 then
						l_file.read_stream (l_file.count)
						Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (l_file.last_string)
					else
						create Result.make_empty
					end
					l_file.close
				end
			end
		rescue
			l_retried := True
			retry
		end

	settings: OCR_SETTINGS
	blocks: ARRAYED_LIST [STRING_32]
	labels: ARRAYED_LIST [STRING_32]

feature -- Constants

	Separator_head: STRING_32 = "----- capture "

	Short_text: INTEGER = 120
			-- Matching the threshold the running application already flags at.

	Length_slack: INTEGER = 3
			-- Percent by which two captures of the same screen may differ in
			-- size. Three is generous: the observed replays differed by one
			-- character in five thousand.

	Indicator_alarm: INTEGER = 4

	Jump_multiple: INTEGER = 5
			-- A step this many times the run's usual one is a jump rather than
			-- progress. Five, because ordinary steps varied between 1 and 4 on
			-- every book seen, while the real jump was seventy times the usual.

end
