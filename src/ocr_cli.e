note
	description: "[
		Headless entry point. Two jobs:

		  --worker <image> <out-text>   OCR one image, write the text. This is
		                                what the GUI spawns per capture, so the
		                                event loop never blocks on a ~11s call.

		  --shot <x> <y> <w> <h>        Capture a region, OCR it, print the
		                                text. Used to verify the pipeline with
		                                no GUI involved.

		  --health                      Run every setup check and print the
		                                report. Exit 0 when all pass, 1 when any
		                                fails, so it can gate a script.
	]"

class
	OCR_CLI

create
	make

feature {NONE} -- Initialization

	make
			-- Dispatch on the command line.
		local
			l_args: ARGUMENTS_32
		do
			create l_args
			if l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--worker") then
				run_worker (l_args)
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--shot") then
				run_shot (l_args)
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--label-worker") then
				run_label_worker (l_args)
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--rescan") then
				run_rescan (l_args)
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--image-name") then
				run_image_name (l_args)
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--compare") then
				run_compare (l_args)
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--health") then
				run_health
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--runlog") then
				run_runlog
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--metrics") then
				run_metrics
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--outline") then
				run_outline (l_args)
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--postclick") then
				run_postclick (l_args)
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string_general ("--audit") then
				run_audit (l_args)
			else
				print_usage
			end
		end

feature {NONE} -- Modes

	run_outline (a_args: ARGUMENTS_32)
			-- Draw a dashed outline around a given rectangle for a few seconds.
			--
			-- The geometry spike for the region-outline feature, and the gate on
			-- building the rest of it. If popup `set_position' and `set_size' do
			-- not land in physical screen pixels on a scaled display, every
			-- outline would be drawn somewhere other than where the region
			-- actually is - confidently wrong, which is worse than absent. This
			-- puts one outline at known coordinates so the result can be checked
			-- against a screenshot rather than trusted.
		local
			l_app: EV_APPLICATION
			l_outline: OCR_REGION_OUTLINE
			l_timer: EV_TIMEOUT
			l_colour: EV_COLOR
			x, y, w, h, ms: INTEGER
		do
			if a_args.argument_count < 5 then
				io.error.put_string ("usage: --outline <x> <y> <w> <h> [<milliseconds>]%N")
				set_exit_code (1)
			else
				x := a_args.argument (2).to_integer
				y := a_args.argument (3).to_integer
				w := a_args.argument (4).to_integer
				h := a_args.argument (5).to_integer
				if a_args.argument_count >= 6 and then a_args.argument (6).is_integer then
					ms := a_args.argument (6).to_integer
				else
					ms := 4000
				end

				if w <= 0 or h <= 0 then
					io.error.put_string ("width and height must be positive%N")
					set_exit_code (1)
				else
					create l_app
						-- Magenta: no reader chrome and no page is this colour, so
						-- a pixel test cannot mistake the outline for content.
					create l_colour.make_with_8_bit_rgb (255, 0, 255)
					create l_outline.make (l_colour, {OCR_REGION_OUTLINE}.Pattern_dash)
					l_outline.set_rectangle (x, y, w, h)
					l_outline.show

					print ("outline shown at (" + x.out + "," + y.out + ") "
						+ w.out + "x" + h.out + " for " + ms.out + "ms%N")

					create l_timer.make_with_interval (ms)
					l_timer.actions.extend (agent l_app.destroy)
					l_app.launch
					print ("outline closed%N")
				end
			end
		end

	run_audit (a_args: ARGUMENTS_32)
			-- Check a finished transcript and report what looks wrong.
			--
			-- Takes the TRANSCRIPT, not a folder: one book, one audit, and the
			-- settings supply the output folder so findings land beside it.
		local
			l_audit: OCR_AUDIT
			l_settings: OCR_SETTINGS
			l_path: STRING_32
			l_dir: INTEGER
		do
			if a_args.argument_count < 2 then
				io.error.put_string ("usage: --audit <transcript.txt>%N")
				set_exit_code (1)
			else
				create l_path.make_from_string (a_args.argument (2))
				create l_settings
				l_settings.load
					-- Findings belong beside the file being audited, whatever the
					-- saved settings currently point at - an audit is usually run
					-- on a book finished days ago.
				l_dir := l_path.last_index_of ('\', l_path.count)
				if l_dir > 1 then
					l_settings.set_output_folder (l_path.substring (1, l_dir - 1))
					l_settings.set_text_file_name (l_path.substring (l_dir + 1, l_path.count))
				end

				create l_audit.make (l_settings)
				print ("auditing " + utf8 (l_path) + "%N")
				l_audit.run (l_path)
				print (utf8 (l_audit.report))
			end
		end

	run_postclick (a_args: ARGUMENTS_32)
			-- Spike: click a point by POSTING mouse messages, and report whether
			-- focus moved.
			--
			-- Two questions, and they are separate. Did it steal focus? - which
			-- is what the whole exercise is about. And did the target actually
			-- act on it? - which only the user can see, by watching whether the
			-- page turned. A click that steals no focus and does nothing is no
			-- use, so both answers are needed before this replaces SendInput.
		local
			l_clicker: OCR_CLICKER
			x, y: INTEGER
		do
			if a_args.argument_count < 3 then
				io.error.put_string ("usage: --postclick <x> <y>%N")
				set_exit_code (1)
			else
				x := a_args.argument (2).to_integer
				y := a_args.argument (3).to_integer
				create l_clicker.make
				print ("posting a click at (" + x.out + "," + y.out + ")...%N")
				if l_clicker.post_click_at (x, y) then
					print ("FOCUS UNCHANGED - nothing was activated.%N")
				else
					print ("FOCUS MOVED - the target was activated anyway.%N")
				end
				print ("Now look at the reader: did the page actually turn?%N")
			end
		end

	run_metrics
			-- Exercise the indicator reader and the rate arithmetic against
			-- known inputs, including the awkward ones seen in real runs.
		local
			l_reader: OCR_PAGE_POSITION
			l_metrics: OCR_RUN_METRICS
			i: INTEGER
		do
			print ("--- indicator reader ---%N")
			create l_reader
			show_position (l_reader, "Page 224 of 416")
			show_position (l_reader, "90-92 / 139")
			show_position (l_reader, "Location 3120 of 8890")
			show_position (l_reader, "Page iii of 214")
			show_position (l_reader, "Page 10 of 379")
			show_position (l_reader, "")
			show_position (l_reader, "no numbers at all")

			print ("%N--- rate arithmetic ---%N")
				-- A run shaped like the measured Hardin session: a capture every
				-- 22 seconds, three pages each, starting at page 100 of 485.
			create l_metrics.make
			l_metrics.note_start
			from i := 0 until i > 10 loop
				l_metrics.note_capture_at ("Page " + (100 + 3 * i).out + " of 485", 22 * i)
				i := i + 1
			end
			print ("captures         : " + l_metrics.captures.out + "%N")
			print ("scans/min        : " + l_metrics.scans_per_minute.out + "   (expect ~2.73)%N")
			print ("pages/scan       : " + l_metrics.pages_per_scan.out + "   (expect 3.0)%N")
			print ("pages/min        : " + l_metrics.pages_per_minute.out + "   (expect ~8.18)%N")
			print ("position         : " + l_metrics.position.out + " of " + l_metrics.total.out + "%N")
			print ("ETA minutes      : " + l_metrics.eta_minutes.out + "   (expect 43 = (485-130)/8.18)%N")
			print ("summary          : " + utf8 (l_metrics.summary_line) + "%N")
			print ("percent complete : " + l_metrics.percent_complete.out + "%%   (expect 26 = 130/485)%N")
			print ("finish clock     : " + utf8 (l_metrics.finish_clock) + "   (now + 43 min)%N")
			print ("--- strip lines (as drawn, one per row) ---%N")
			print (utf8 (l_metrics.strip_line) + "%N")

			print ("%N--- garbled indicator is ignored, not obeyed ---%N")
				-- The matched -90/+92 pair from a real run. A single misread page
				-- number must not move `position' or throw the rate.
			create l_metrics.make
			l_metrics.note_start
			l_metrics.note_capture_at ("Page 260 of 485", 0)
			l_metrics.note_capture_at ("Page 263 of 485", 22)
			l_metrics.note_capture_at ("Page 352 of 485", 44)
			l_metrics.note_capture_at ("Page 266 of 485", 66)
			print ("position after garble: " + l_metrics.position.out
				+ "   (expect 266, NOT 352)%N")
			print ("pages/min            : " + l_metrics.pages_per_minute.out
				+ "   (expect 5.45 = 6 pages over 66s; the garbled capture contributed time but no readable pages)%N")

			print ("%N--- combined page+location indicator ---%N")
			show_position (l_reader, "Page 12 of 170  Location 890 of 8890")
			show_position (l_reader, "Page iii of 214  Location 120 of 8890")
			show_position (l_reader, "Location 45 of 8890")
			show_position (l_reader, "Page 12/170")
				-- The real label from the VanderKam reader, screenshotted at the
				-- end of the run. Note the leading "100%%": a bare number with no
				-- separator after it, which must NOT be mistaken for a position.
			show_position (l_reader, "100%% Page 168 of 170 . Location 3101 of 3116")

			print ("%N--- ProQuest online reader (no location counter at all) ---%N")
			show_position (l_reader, "Page i of 330")
			show_position (l_reader, "Page ii of 330")
			show_position (l_reader, "Page 1 of 330")
			show_position (l_reader, "Page 47 of 330")

			print ("%N--- roman front matter misread as digits, then real page 1 ---%N")
				-- "ii" can come back as "11". The total never changes, so only the
				-- pending rule can rescue this.
			create l_metrics.make
			l_metrics.note_start
			l_metrics.note_capture_at ("Page 11 of 330", 0)
			l_metrics.note_capture_at ("Page 13 of 330", 22)
			l_metrics.note_capture_at ("Page 1 of 330", 44)
			print ("  after 1 odd : " + l_metrics.position.out + "   (expect 13 - held)%N")
			l_metrics.note_capture_at ("Page 3 of 330", 66)
			print ("  after 2 odd : " + l_metrics.position.out + "   (expect 3 - adopted)%N")

			print ("%N--- units handover: locations give way to pages ---%N")
				-- The 1 Enoch shape. With the largest total preferred, the
				-- location series simply continues and there is no handover.
			create l_metrics.make
			l_metrics.note_start
			l_metrics.note_capture_at ("Location 45 of 8890", 0)
			l_metrics.note_capture_at ("Location 120 of 8890", 22)
			l_metrics.note_capture_at ("Page 1 of 170  Location 200 of 8890", 44)
			l_metrics.note_capture_at ("Page 3 of 170  Location 275 of 8890", 66)
			print ("position after handover: " + l_metrics.position.out + " of "
				+ l_metrics.total.out + "   (expect 275 of 8890 - stays on locations)%N")
			print ("percent                : " + l_metrics.percent_complete.out
				+ "%%   (expect 3)%N")

			print ("%N--- roman front matter, total NEVER changes ---%N")
				-- "iii" misread as 111 gives a plausible 111 of 214; page 1 then
				-- arrives as a -110 step against an UNCHANGED total. One reading
				-- must not move it; two consistent readings must.
			create l_metrics.make
			l_metrics.note_start
			l_metrics.note_capture_at ("Page 111 of 214", 0)
			l_metrics.note_capture_at ("Page 113 of 214", 22)
			print ("  before reset : " + l_metrics.position.out + " of " + l_metrics.total.out + "%N")
			l_metrics.note_capture_at ("Page 1 of 214", 44)
			print ("  after 1 odd  : " + l_metrics.position.out
				+ "   (expect 113 - one reading is not enough)%N")
			l_metrics.note_capture_at ("Page 3 of 214", 66)
			print ("  after 2 odd  : " + l_metrics.position.out
				+ "   (expect 3 - reality repeated itself, so it wins)%N")

			print ("%N--- a lone garble must NOT trigger a reset ---%N")
			create l_metrics.make
			l_metrics.note_start
			l_metrics.note_capture_at ("Page 260 of 485", 0)
			l_metrics.note_capture_at ("Page 263 of 485", 22)
			l_metrics.note_capture_at ("Page 991 of 485", 44)
			l_metrics.note_capture_at ("Page 266 of 485", 66)
			print ("position: " + l_metrics.position.out + "   (expect 266, NOT 991)%N")

			print ("%N--- no position yet: strip must say so, not go blank ---%N")
			create l_metrics.make
			l_metrics.note_start
			l_metrics.note_capture_at ("Page i of 330", 0)
			l_metrics.note_capture_at ("Page ii of 330", 22)
			print ("strip lines with no parseable position:%N")
			print (utf8 (l_metrics.strip_line) + "%N")

			print ("%N--- standby GIVES WAY to real figures, unattended ---%N")
				-- A ProQuest run started at the cover: roman front matter yields
				-- no position at all, then the body begins.
			create l_metrics.make
			l_metrics.note_start
			l_metrics.note_capture_at ("Page i of 330", 0)
			print ("after roman i   :%N" + utf8 (l_metrics.strip_line) + "%N%N")
			l_metrics.note_capture_at ("Page iii of 330", 22)
			print ("after roman iii :%N" + utf8 (l_metrics.strip_line) + "%N%N")
			l_metrics.note_capture_at ("Page 1 of 330", 44)
			print ("first real page :%N" + utf8 (l_metrics.strip_line) + "%N%N")
			l_metrics.note_capture_at ("Page 3 of 330", 66)
			print ("second real page:%N" + utf8 (l_metrics.strip_line) + "%N%N")
			l_metrics.note_capture_at ("Page 6 of 330", 88)
			print ("third real page :%N" + utf8 (l_metrics.strip_line) + "%N")

			print ("%N--- reader jumps, detected by percent ---%N")
				-- Jehu's Tribute: 123-126 of 356 to 336-337 of 356.
			create l_metrics.make
			l_metrics.note_start
			l_metrics.note_capture_at ("121-123 / 356", 0)
			l_metrics.note_capture_at ("123-126 / 356", 22)
			l_metrics.note_capture_at ("336-337 / 356", 44)
			l_metrics.note_capture_at ("338-341 / 356", 66)
			print ("  FORWARD  jumped=" + l_metrics.has_jumped.out
				+ " backwards=" + l_metrics.jumped_backwards.out
				+ "  " + l_metrics.jumped_from.out + "%% -> " + l_metrics.jumped_to.out
				+ "%%   (expect True/False, 34 -> 94)%N")

				-- Heiser Demons: Page 245 of 267 back to Location 1 of 11296.
			create l_metrics.make
			l_metrics.note_start
			l_metrics.note_capture_at ("Page 243 of 267", 0)
			l_metrics.note_capture_at ("Page 245 of 267", 22)
			l_metrics.note_capture_at ("0%%    Location 1 of 11296", 44)
			l_metrics.note_capture_at ("1%%    Location 5 of 11296", 66)
			print ("  BACKWARD jumped=" + l_metrics.has_jumped.out
				+ " backwards=" + l_metrics.jumped_backwards.out
				+ "  " + l_metrics.jumped_from.out + "%% -> " + l_metrics.jumped_to.out
				+ "%%   (expect True/True, 91 -> 0)%N")

				-- The ordinary units handover at the front of a book must NOT
				-- look like a jump: locations give way to pages while both are
				-- near zero percent.
			create l_metrics.make
			l_metrics.note_start
			l_metrics.note_capture_at ("Location 1 of 12724", 0)
			l_metrics.note_capture_at ("Page 1 of 488", 22)
			l_metrics.note_capture_at ("Page 2 of 488", 44)
			print ("  HANDOVER jumped=" + l_metrics.has_jumped.out
				+ "   (expect False - benign, both ends near 0%%)%N")

			print ("%N--- pause stops the clock ---%N")
			create l_metrics.make
			l_metrics.note_start
			l_metrics.note_pause
			l_metrics.note_resume
			print ("elapsed after immediate pause/resume: " + l_metrics.elapsed_seconds.out
				+ "   (expect 0)%N")
		end

	show_position (a_reader: OCR_PAGE_POSITION; a_label: STRING)
			-- Print what `a_reader' makes of `a_label'.
		do
			a_reader.set_from (a_label)
			print ("  [" + a_label + "] -> ")
			if a_reader.has_position then
				print (a_reader.position.out + " of " + a_reader.total.out + "%N")
			else
				print ("nothing (correct - not enough numbers)%N")
			end
		end

	run_runlog
			-- Report where the run log for the CURRENT settings would go, then
			-- prove the writer works by putting sample rows in the temporary
			-- folder.
			--
			-- Two halves, answering two different questions. The path is derived
			-- from the real settings, so a run log aimed at the wrong folder
			-- shows up here. The write goes to TEMP, so exercising it can never
			-- pollute a book's folder with test rows.
		local
			l_settings, l_probe: OCR_SETTINGS
			l_log: OCR_RUN_LOG
			l_env: EXECUTION_ENVIRONMENT
			l_temp, l_nasty: STRING_32
		do
			create l_settings
			l_settings.load
			create l_log.make (l_settings)
			io.put_string ("run log path for current settings:%N  ")
			io.put_string (utf8_out (l_log.run_log_path))
			io.put_new_line

			create l_env
			create l_temp.make_from_string_general (".")
			if attached l_env.item ("TEMP") as al_temp and then not al_temp.is_empty then
				create l_temp.make_from_string_general (al_temp)
			end

			create l_probe
			l_probe.set_output_folder (l_temp)
			l_probe.set_text_file_name ("runlog_selftest.txt")
			create l_log.make (l_probe)

				-- Every character that must be escaped, plus one non-ASCII, so a
				-- broken escape shows up as invalid JSON rather than as a subtly
				-- wrong value nobody notices.
			l_nasty := {STRING_32} "Page %"3%" of 5 \ tab%There%Nnewline %/233/"

			l_log.record_run_start ("100x200 at (10,20)", "30x40 at (50,60)", "")
			l_log.record_capture (7, "C:\books\ocr_Page_7_of_9.png", l_nasty, "", 4192)
			l_log.record_capture (8, "", "Page 8 of 9", "OCR worker produced no output file.", 0)
			l_log.record_advance (8, "text", 1)
			l_log.record_stop ("the page did not advance", 2)

			io.put_string ("%Nself-test rows written to:%N  ")
			io.put_string (utf8_out (l_log.run_log_path))
			io.put_new_line
		end

	utf8_out (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' encoded for the console.
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
		end

	run_label_worker (a_args: ARGUMENTS_32)
			-- OCR argument 2 as a page indicator into the file named by
			-- argument 3.
			--
			-- A separate mode rather than a flag on `--worker': the indicator is
			-- a handful of characters, so it wants its own prompt and a tiny
			-- prediction budget. Reusing the page prompt made the model narrate
			-- the toolbar around the number.
		local
			l_settings: OCR_SETTINGS
			l_engine: OCR_ENGINE
		do
			if a_args.argument_count < 3 then
				io.error.put_string ("usage: --label-worker <image> <out-text>%N")
				set_exit_code (1)
			else
				create l_settings
				l_settings.load
				l_settings.set_ocr_prompt ({OCR_SETTINGS}.Page_label_prompt)
				l_settings.set_num_predict (Label_prediction_tokens)
				create l_engine.make

				if l_engine.recognize (a_args.argument (2), l_settings) then
					if write_text (a_args.argument (3), l_engine.last_text) then
							-- written
					else
						set_exit_code (1)
					end
				else
					if not write_text (a_args.argument (3), {STRING_32} "[OCR FAILED] " + l_engine.last_error) then
						set_exit_code (1)
					end
					set_exit_code (1)
				end
			end
		end

	run_rescan (a_args: ARGUMENTS_32)
			-- Re-OCR each image named on the command line, writing the text
			-- beside it as "<image>.rescan.txt".
			--
			-- The point of re-running a page is to get ANOTHER sample, not to
			-- repair the first: the engine is non-deterministic, and a second
			-- pass routinely recovers a marginal column or a footnote block the
			-- first dropped. So the original transcript is never touched and the
			-- result lands in its own file for comparison.
		local
			l_settings: OCR_SETTINGS
			l_engine: OCR_ENGINE
			i, l_first, l_done, l_failed: INTEGER
			l_out: STRING_32
		do
			if a_args.argument_count < 2 then
				io.error.put_string ("usage: --rescan [--prompt %"<text>%"] <image.png> [<image.png> ...]%N")
				set_exit_code (1)
			else
				create l_settings
				l_settings.load

					-- An optional prompt for this run only, never written back to
					-- settings. Re-running a page with the SAME prompt tends to
					-- reproduce the same omission; what recovers a dropped
					-- marginal column or footnote block is asking differently.
				l_first := 2
				if a_args.argument_count >= 3 and then a_args.argument (2).same_string_general ("--prompt") then
					l_settings.set_ocr_prompt (a_args.argument (3))
					l_first := 4
					print ("prompt: " + utf8 (a_args.argument (3)) + "%N")
				end

				create l_engine.make

				from
					i := l_first
				until
					i > a_args.argument_count
				loop
					l_out := rescan_path_for (a_args.argument (i))
					print (utf8 (a_args.argument (i)) + " ... ")
					if l_engine.recognize (a_args.argument (i), l_settings) then
						if write_text (l_out, l_engine.last_text) then
							l_done := l_done + 1
							print (l_engine.last_text.count.out + " chars -> " + utf8 (l_out) + "%N")
						else
							l_failed := l_failed + 1
							print ("could not write " + utf8 (l_out) + "%N")
						end
					else
						l_failed := l_failed + 1
						print ("FAILED: " + utf8 (l_engine.last_error) + "%N")
					end
					i := i + 1
				end

				print ("rescanned " + l_done.out + ", failed " + l_failed.out + "%N")
				if l_failed > 0 then
					set_exit_code (1)
				end
			end
		end

	rescan_path_for (a_image: READABLE_STRING_GENERAL): STRING_32
			-- Where the re-scan of `a_image' is written.
		do
			create Result.make_from_string_general (a_image)
			Result.append_string_general (".rescan.txt")
		ensure
			non_empty: not Result.is_empty
		end

	run_image_name (a_args: ARGUMENTS_32)
			-- Show the file name a capture showing the given indicator would get.
		local
			l_namer: OCR_IMAGE_NAME
		do
			if a_args.argument_count < 2 then
				io.error.put_string ("usage: --image-name %"<page indicator>%"%N")
				set_exit_code (1)
			else
				create l_namer
				print ("ocr_" + utf8 (l_namer.stem (a_args.argument (2), 7)) + ".png%N")
			end
		end

	run_compare (a_args: ARGUMENTS_32)
			-- Report whether two text files would count as the same screen.
			--
			-- This is the judgement auto-advance makes after every capture, so
			-- it is worth being able to try it on real page text rather than
			-- discovering its behaviour halfway through a book.
		local
			l_compare: OCR_TEXT_COMPARE
			l_first, l_second: detachable STRING_32
		do
			if a_args.argument_count < 3 then
				io.error.put_string ("usage: --compare <file-a> <file-b>%N")
				set_exit_code (1)
			else
				l_first := read_utf8 (a_args.argument (2))
				l_second := read_utf8 (a_args.argument (3))
				if l_first = Void or l_second = Void then
					io.error.put_string ("could not read both files%N")
					set_exit_code (1)
				elseif attached l_first as al_first and then attached l_second as al_second then
					create l_compare
					print ("agreement: " + l_compare.agreement_percent (al_first, al_second).out + "%%%N")
					if l_compare.is_same_screen (al_first, al_second) then
						print ("SAME SCREEN (auto-advance would call this a stall)%N")
					else
						print ("ADVANCED (auto-advance would carry on)%N")
					end
				end
			end
		end

	read_utf8 (a_path: READABLE_STRING_GENERAL): detachable STRING_32
			-- Contents of `a_path' decoded from UTF-8, or Void if unreadable.
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

	run_health
			-- Print the full setup report and exit non-zero if anything failed.
			--
			-- Starts nothing: this reports the machine as it stands, which is
			-- what makes it useful for deciding whether the GUI should have to.
		local
			l_settings: OCR_SETTINGS
			l_runtime: OCR_RUNTIME
			l_preflight: OCR_PREFLIGHT
			l_health: OCR_HEALTH
		do
			create l_settings
			l_settings.load
			create l_runtime.make (l_settings)
			l_runtime.prepare
			create l_preflight.make (l_settings)
			create l_health.make (l_settings, l_runtime, l_preflight)

			l_health.run_full
			io.put_string_32 (l_health.report)
			io.put_new_line

			if not l_health.is_healthy then
				set_exit_code (1)
			end
		end

	run_worker (a_args: ARGUMENTS_32)
			-- OCR the image named by argument 2 into the file named by
			-- argument 3. Exit code 0 on success, 1 on failure; the text file
			-- is the real channel back to the GUI.
		local
			l_settings: OCR_SETTINGS
			l_engine: OCR_ENGINE
		do
			if a_args.argument_count < 3 then
				io.error.put_string ("usage: --worker <image> <out-text>%N")
				set_exit_code (1)
			else
				create l_settings
				l_settings.load
				create l_engine.make

				if l_engine.recognize (a_args.argument (2), l_settings) then
					if write_text (a_args.argument (3), l_engine.last_text) then
						set_exit_code (0)
					else
						io.error.put_string ("could not write output file%N")
						set_exit_code (1)
					end
				else
						-- Record the reason where the GUI can surface it.
					if write_text (a_args.argument (3), {STRING_32} "[OCR FAILED] " + l_engine.last_error) then
						-- reported through the file
					end
					io.error.put_string (utf8 (l_engine.last_error) + "%N")
					set_exit_code (1)
				end
			end
		end

	run_shot (a_args: ARGUMENTS_32)
			-- Capture, OCR, print. End-to-end pipeline check.
		local
			l_app: EV_APPLICATION
			l_capture: OCR_CAPTURE
			l_engine: OCR_ENGINE
			l_settings: OCR_SETTINGS
			l_png: STRING_32
			l_env: EXECUTION_ENVIRONMENT
			x, y, w, h: INTEGER
		do
			if a_args.argument_count < 5 then
				io.error.put_string ("usage: --shot <x> <y> <w> <h>%N")
				set_exit_code (1)
			else
				x := a_args.argument (2).to_integer
				y := a_args.argument (3).to_integer
				w := a_args.argument (4).to_integer
				h := a_args.argument (5).to_integer

				if w <= 0 or h <= 0 then
					io.error.put_string ("width and height must be positive%N")
					set_exit_code (1)
				else
						-- Vision2 objects require an application instance; no
						-- event loop is launched, so this stays a console run.
					create l_app
					create l_capture.make
					create l_settings
					l_settings.load

					create l_env
					create l_png.make (64)
					if attached l_env.item ("TEMP") as al_temp and then not al_temp.is_empty then
						l_png.append_string_general (al_temp)
					else
						l_png.append_string_general (".")
					end
					l_png.append_string_general ("\ocr_shot.png")

					print ("screen: " + l_capture.screen_width.out + "x" + l_capture.screen_height.out + "%N")

					if l_capture.capture_to_file (x, y, w, h, l_png, "png") then
						print ("captured " + l_capture.last_width.out + "x" + l_capture.last_height.out
							+ " -> " + utf8 (l_png) + "%N")
						create l_engine.make
						if l_engine.recognize (l_png, l_settings) then
							print ("--- OCR TEXT ---%N")
							print (utf8 (l_engine.last_text) + "%N")
							print ("--- RESULT: PASS ---%N")
							set_exit_code (0)
						else
							print ("OCR failed: " + utf8 (l_engine.last_error) + "%N")
							print ("--- RESULT: FAIL ---%N")
							set_exit_code (1)
						end
					else
						print ("capture failed: " + utf8 (l_capture.last_error) + "%N")
						print ("--- RESULT: FAIL ---%N")
						set_exit_code (1)
					end
				end
			end
		end

	print_usage
		do
			print ("simple_ocr_capture (headless modes)%N")
			print ("  --worker <image> <out-text>   OCR one image to a text file%N")
			print ("  --shot <x> <y> <w> <h>        capture + OCR + print%N")
			print ("  --label-worker <image> <out>  OCR a page indicator to a text file%N")
			print ("  --rescan [--prompt %"..%"] <image>...  re-OCR to <image>.rescan.txt%N")
			print ("  --image-name %"<label>%"        file name a capture would get%N")
			print ("  --compare <file-a> <file-b>   same screen, or advanced?%N")
			print ("  --health                      check the whole setup; exit 1 if not ready%N")
		end

feature {NONE} -- Constants

	Label_prediction_tokens: INTEGER = 32
			-- Enough for "90-92 / 139" and nothing like enough to ramble.

feature {NONE} -- Implementation

	write_text (a_path: READABLE_STRING_GENERAL; a_text: READABLE_STRING_32): BOOLEAN
			-- Write `a_text' to `a_path' as UTF-8. True on success.
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (a_path)
				l_file.create_read_write
				l_file.put_string (utf8 (a_text))
				l_file.close
				Result := True
			end
		rescue
			l_retried := True
			retry
		end

	utf8 (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' as UTF-8 bytes.
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
		end

	set_exit_code (a_code: INTEGER)
			-- Terminate with `a_code'.
		external
			"C inline use <stdlib.h>"
		alias
			"exit ((int) $a_code);"
		end

end
