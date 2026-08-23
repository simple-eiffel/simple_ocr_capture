note
	description: "[
		Drives an unattended reading session: read the page indicator, capture
		the page, click the reader's next-page control, wait for it to settle,
		and go round again.

		Stops by itself the moment a page fails to turn. That check is the whole
		reason this class can be trusted to run for a hundred pages unattended -
		without it, a reader that stopped responding would quietly append the
		same page to the transcript until the book "finished".
	]"
	design: "[
		The indicator is read BEFORE the capture, not after, so the label
		recorded above a page's text is the one that was on screen when the
		screenshot was taken.

		Advancement is judged on ONE thing: the captured text differs from the
		previous capture's. Nothing else. The reader has moved on, or it has not.

		The page indicator plays no part in that decision. Deriving progress
		from it was tried twice and failed twice - first by demanding the label
		change (wrong the moment a printed page spans several screenfuls), then
		by measuring the page numbers for skips (wrong the moment a reader
		legitimately shows two to four pages at a time). The indicator's real
		job is annotation: it records what the reader displayed, and that is
		all it is trusted with.

		Every wait is counted in timer ticks rather than slept through. This
		runs on the same 50 ms tick as everything else, so the strip keeps
		animating and the user can still press Stop while a page settles.
	]"

class
	OCR_AUTO_RUN

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS; a_cycle: OCR_CYCLE; a_strip: OCR_SW_STRIP)
			-- Prepare to drive `a_cycle'.
		do
			settings := a_settings
			cycle := a_cycle
			status_strip := a_strip
			create clicker.make
			create capture.make
			create metrics.make
			create last_error.make_empty
			create last_message.make_empty
			create previous_text.make_empty
			create previous_label.make_empty
			create current_label.make_empty
			create label_image_path.make_empty
			create label_text_path.make_empty
			state := State_stopped
			step := Step_idle
		ensure
			stopped: is_stopped
		end

feature -- Access

	last_error: STRING_32
			-- Why the run stopped early; empty when it was stopped by hand or
			-- is still going.

	last_message: STRING_32
			-- Most recent progress line, for the status bar.

	pages_done: INTEGER
			-- Captures completed since `start'.

	current_label: STRING_32
			-- Page indicator read for the capture in progress.

feature -- Status report

	is_running: BOOLEAN
		do
			Result := state = State_running
		end

	is_paused: BOOLEAN
		do
			Result := state = State_paused
		end

	is_stopped: BOOLEAN
		do
			Result := state = State_stopped
		end

	is_ready_to_start: BOOLEAN
			-- Is everything auto-advance needs configured?
		do
			Result := settings.is_region_valid and settings.is_advance_region_valid
		end

	blocking_reason: STRING_32
			-- Why `start' would refuse; empty when it would not.
		do
			create Result.make_empty
			if not settings.is_region_valid then
				Result := {STRING_32} "Set the capture region first."
			elseif not settings.is_advance_region_valid then
				Result := {STRING_32} "Set the advance button region first - nothing will be clicked until you do."
			end
		end

feature -- Basic operations

	start
			-- Begin an unattended run.
		require
			configured: is_ready_to_start
		do
			last_error.wipe_out
			previous_text.wipe_out
			previous_label.wipe_out
			current_label.wipe_out
			pages_done := 0
			stall_retries := 0
			has_clicked_this_page := False
			ticks_since_click := 0
			label_retries := 0
			state := State_running
			metrics.note_start
			cycle.set_captured_action (agent on_page_captured)
			log_configuration
			record_run_start
			begin_page
		ensure
			running: is_running
		end

	pause
			-- Suspend after the step in flight, keeping the run's history so
			-- `resume' can still tell whether the next page turned.
		do
			if is_running then
				state := State_paused
				metrics.note_pause
				note_progress ("Auto-advance paused.")
			end
		end

	resume
			-- Continue a paused run.
		do
			if is_paused then
				state := State_running
				metrics.note_resume
				note_progress ("Auto-advance resumed.")
					-- Mid-page when paused, so pick the sequence back up rather
					-- than re-capturing a page already written.
				if step = Step_idle then
					begin_page
				end
			end
		end

	stop
			-- End the run, by hand.
		do
			if not is_stopped then
				state := State_stopped
				step := Step_idle
				has_clicked_this_page := False
				discard_label_worker
				status_strip.set_page_caption ("")
				status_strip.set_metrics_caption ("")
				cycle.run_log.record_stop ("stopped by hand", pages_done)
				note_progress ("Auto-advance stopped.")
			end
		ensure
			stopped: is_stopped
		end

	poll
			-- Advance the state machine. Call from a timer tick.
		do
			if is_running then
				if has_clicked_this_page then
					ticks_since_click := ticks_since_click + 1
				end
				inspect step
				when Step_reading_label then
					poll_label
				when Step_capturing then
					poll_capture
				when Step_settling then
					poll_settle
				when Step_waiting_for_page then
					poll_waiting_for_page
				else
					-- Step_idle: nothing in flight.
				end
			end
		end

feature {NONE} -- Steps

	begin_page
			-- Start the next page: read its indicator, or go straight to the
			-- capture when there is no indicator to read.
		do
			if settings.is_page_label_region_valid and then start_label_worker then
				step := Step_reading_label
				ticks_waited := 0
				note_progress ("Reading page indicator...")
			else
				current_label.wipe_out
				begin_capture
			end
		end

	poll_label
			-- Collect the page indicator, then capture.
			--
			-- Whatever the indicator says is taken at face value. An earlier
			-- version required it to parse as "<page> / <total>" and refused to
			-- capture until it did; that is a rule about ONE reader's formatting,
			-- and the next book presented "Page iii of 214" and was rejected on
			-- every page until the run gave up. Readers vary in prefix, numeral
			-- system and separator, so the text is recorded, not judged.
		do
			ticks_waited := ticks_waited + 1
			if attached label_worker as al_worker and then al_worker.has_finished then
				harvest_label
				if current_label.is_empty then
					retry_label
				else
					begin_capture
				end
			elseif ticks_waited > Label_timeout_ticks then
				log ("indicator worker timed out")
				discard_label_worker
				current_label.wipe_out
				retry_label
			end
		end

	retry_label
			-- Nothing came back at all. Look again, then give up on the
			-- indicator for this page and carry on without it.
			--
			-- Never fatal. An empty read means the OCR failed or the reader was
			-- mid-repaint, and the page text can still witness the turn; halting
			-- a hundred-page run over a page number would be the worse failure.
		do
			label_retries := label_retries + 1
			if label_retries > Maximum_label_retries then
				log ("indicator unreadable after " + Maximum_label_retries.out
					+ " tries; continuing without it")
				begin_capture
			else
				note_progress (waiting_line)
				step := Step_waiting_for_page
				ticks_waited := 0
			end
		end

	poll_waiting_for_page
			-- Give the reader a moment, then read the indicator again.
		do
			ticks_waited := ticks_waited + 1
			if ticks_waited >= Page_retry_ticks then
				begin_page
			end
		end

	begin_capture
			-- Capture the screen as it now stands.
			--
			-- No advance check here. An earlier version refused to capture when
			-- the indicator still read the same page, which is wrong whenever a
			-- printed page spans more than one screenful: shrink the reader and
			-- "Page 23 of 384" stays put for several screens while the text
			-- moves on every time. Whether anything advanced can only be settled
			-- once the text is in hand, so it is settled in `poll_capture'.
		do
			label_retries := 0
			check_indicator_health
			cycle.set_page_label (current_label)
			status_strip.set_page_caption (page_caption_text)
			cycle.trigger
			step := Step_capturing
			ticks_waited := 0
		end

	on_page_captured
			-- Turn the page the moment the screenshot is on disk.
			--
			-- This is the whole speed-up: the click lands at the START of the
			-- OCR rather than after it, so the reader repaints during the ten to
			-- forty seconds the model is busy. By the time the strip says READY
			-- the next page has long since arrived, and no waiting is left to do.
		do
			if is_running and then not has_clicked_this_page then
				if clicker.click_centre_of (settings.advance_x, settings.advance_y,
					settings.advance_width, settings.advance_height)
				then
					has_clicked_this_page := True
					ticks_since_click := 0
					log ("clicked advance at (" + (settings.advance_x + settings.advance_width // 2).out
						+ "," + (settings.advance_y + settings.advance_height // 2).out
						+ ") while OCR runs")
				else
					halt (clicker.last_error)
				end
			end
		end

	poll_capture
			-- Wait for the OCR to finish, then judge and move on.
		do
			if not cycle.is_busy then
				log_capture
				if not cycle.last_error.is_empty then
					halt ({STRING_32} "Capture failed: " + cycle.last_error)
				elseif not has_advanced then
					retry_advance
				else
					metrics.note_capture (current_label)
					report_jump_if_any
						-- Logged as its own line. `progress_line' is display text
						-- that gets overwritten; this is the durable record of how
						-- the run was performing at each page.
					if metrics.captures >= 2 then
						log ({STRING_32} "rate " + metrics.summary_line)
					end
						-- Straight to the strip: during an unattended run the
						-- settings window is behind the reader, so its status line
						-- cannot be read. The strip is the only surface visible.
					status_strip.set_metrics_caption (metrics.strip_line)
						-- Recorded before `stall_retries' is cleared, so the row
						-- carries how many extra clicks this page cost.
					cycle.run_log.record_advance (settings.capture_index,
						"text", stall_retries)
					stall_retries := 0
					log_advance
					previous_text := cycle.last_text.twin
					previous_label := current_label.twin
					pages_done := pages_done + 1
					note_progress (progress_line)
					step := Step_settling
				end
			end
		end

	retry_advance
			-- Nothing moved. Click again before concluding the reader has stopped.
			--
			-- One missed click used to end the run. A click can fail to land for
			-- reasons that pass on their own - the reader busy laying out, focus
			-- momentarily elsewhere, a control not yet enabled after a section
			-- break - and ending a hundred-page run over one of those is far
			-- more expensive than clicking twice more.
			--
			-- Each attempt costs one duplicate block in the transcript, since
			-- the capture is written before it can be judged. That is the cheap
			-- side of the trade, and the log names them.
		do
			if stall_retries >= Maximum_stall_retries then
				halt (stall_reason)
			else
				stall_retries := stall_retries + 1
				log ("nothing advanced - clicking again, attempt "
					+ stall_retries.out + " of " + Maximum_stall_retries.out)
				note_progress (retry_line)
				if clicker.click_centre_of (settings.advance_x, settings.advance_y,
					settings.advance_width, settings.advance_height)
				then
					has_clicked_this_page := True
					ticks_since_click := 0
					step := Step_settling
				else
					halt (clicker.last_error)
				end
			end
		end

	retry_line: STRING_32
			-- What to say while re-clicking a page that would not turn.
		do
			create Result.make_from_string_general ("Page did not turn - clicking again (")
			Result.append_string_general (stall_retries.out)
			Result.append_character ('/')
			Result.append_string_general (Maximum_stall_retries.out)
			Result.append_string_general (")...")
		end

	poll_settle
			-- Hold only if the OCR came back faster than the reader can repaint.
			--
			-- Normally already satisfied - the OCR outlasts the settle time
			-- several times over - so this costs nothing and simply guarantees a
			-- floor between the click and the next screenshot.
		do
			if ticks_since_click >= settle_ticks then
				has_clicked_this_page := False
				begin_page
			end
		end

feature {NONE} -- Judgement

	waiting_line: STRING_32
			-- What to say while the indicator is being re-read.
		do
			create Result.make_from_string_general ("Page indicator did not read (")
			Result.append_string_general (label_retries.out)
			Result.append_character ('/')
			Result.append_string_general (Maximum_label_retries.out)
			Result.append_string_general ("); looking again...")
		end

	has_advanced: BOOLEAN
			-- Did anything move on since the previous capture?
			--
			-- Either witness is enough, and that is the point. A printed page
			-- larger than the window advances the TEXT while the indicator holds
			-- still; a page turn in a full-window reader advances the INDICATOR
			-- and the text together. Requiring both would stop the first case on
			-- its second screenful, and requiring only the indicator did exactly
			-- that. Only when NEITHER has moved has the reader genuinely stopped.
		do
			Result := pages_done = 0 or else text_changed
		end

	label_changed: BOOLEAN
			-- Does the indicator differ from the previous capture's?
			--
			-- False when either is missing: an absent indicator is not evidence
			-- of standing still, it is an absence of evidence, and the text is
			-- then the only witness.
		do
			Result := not current_label.is_empty and then not previous_label.is_empty
				and then not current_label.same_string (previous_label)
		end

	text_changed: BOOLEAN
			-- Does the captured text differ from the previous capture's?
			--
			-- Compared with a tolerance rather than exactly. The OCR is a
			-- sampling model, so re-reading one unchanged screen can return
			-- wording that differs in a character or two; demanding exact
			-- equality would read that jitter as progress and click on for ever
			-- at the end of a book.
		local
			l_compare: OCR_TEXT_COMPARE
		do
			create l_compare
			Result := not l_compare.is_same_screen (cycle.last_text, previous_text)
		end

	stall_reason: STRING_32
			-- What to report when the page did not turn.
		do
			create Result.make_from_string_general ("Stopped after ")
			Result.append_string_general (pages_done.out)
			Result.append_string_general (" capture(s): nothing advanced - the text is the same as the previous capture")
			if not current_label.is_empty then
				Result.append_string_general (" and the indicator still reads ")
				Result.append (current_label)
			end
			Result.append_string_general (". The click may have missed the button, or the book may have ended.")
		ensure
			non_empty: not Result.is_empty
		end

	halt (a_reason: READABLE_STRING_GENERAL)
			-- Stop the run because something went wrong.
		do
			create last_error.make_from_string_general (a_reason)
			state := State_stopped
			step := Step_idle
			discard_label_worker
			cycle.run_log.record_stop (last_error, pages_done)
			note_progress (last_error)
		ensure
			stopped: is_stopped
			reported: not last_error.is_empty
		end

feature {NONE} -- Page indicator

	start_label_worker: BOOLEAN
			-- Capture the indicator region and spawn its OCR. True when started.
		local
			l_process: SIMPLE_ASYNC_PROCESS
			l_command: STRING_32
		do
			discard_label_worker
			label_image_path := scratch_path ("ocr_page_label.png")
			label_text_path := scratch_path ("ocr_page_label.txt")
			delete_file (label_text_path)

			if capture.capture_to_file (settings.page_label_x, settings.page_label_y,
				settings.page_label_width, settings.page_label_height,
				label_image_path, "png")
			then
				create l_command.make (256)
				l_command.append_character ('%"')
				l_command.append (executable_path)
				l_command.append_string_general ("%" --label-worker %"")
				l_command.append (label_image_path)
				l_command.append_string_general ("%" %"")
				l_command.append (label_text_path)
				l_command.append_character ('%"')

				create l_process.make
				l_process.set_show_window (False)
				l_process.start (l_command)
				if l_process.is_started then
					label_worker := l_process
					Result := True
				end
			end
		end

	harvest_label
			-- Read what the indicator worker produced.
		local
			l_text: detachable STRING_32
		do
			l_text := read_utf8 (label_text_path)
			discard_label_worker

			if l_text = Void then
				current_label.wipe_out
				log ("indicator produced no output file")
			elseif l_text.starts_with ({STRING_32} "[OCR FAILED]") then
				current_label.wipe_out
				log ({STRING_32} "indicator OCR failed: " + excerpt (l_text))
			else
				current_label := condensed (l_text)
				log_label (excerpt (l_text), current_label)
			end
			delete_file (label_image_path)
			delete_file (label_text_path)
		end

	condensed (a_text: READABLE_STRING_32): STRING_32
			-- `a_text' as one trimmed line.
			--
			-- The model occasionally answers with a trailing newline or wraps
			-- the number in a sentence; only the first line is ever the answer,
			-- and comparing untrimmed strings would call two identical pages
			-- different over a stray space.
		local
			l_break: INTEGER
		do
			create Result.make_from_string (a_text)
			l_break := Result.index_of ('%N', 1)
			if l_break > 0 then
				Result := Result.substring (1, l_break - 1)
			end
			Result.left_adjust
			Result.right_adjust
			if Result.count > Label_maximum_length then
				Result := Result.substring (1, Label_maximum_length)
			end
		end

	discard_label_worker
			-- Release the indicator worker, killing it if it is still going.
		do
			if attached label_worker as al_worker then
				if al_worker.is_started and then al_worker.is_running then
					if al_worker.kill then
						-- terminated
					end
				end
				al_worker.close
			end
			label_worker := Void
		end

feature {NONE} -- Reporting

	note_progress (a_message: READABLE_STRING_GENERAL)
			-- Record a line for the status bar, and log it.
		do
			create last_message.make_from_string_general (a_message)
			log (a_message)
		end

	log (a_message: READABLE_STRING_GENERAL)
			-- Append `a_message' to the diagnostic log, tagged as auto-advance.
			--
			-- Everything this class decides is logged, not just its failures.
			-- An unattended run is by definition unwatched, so when it stops
			-- after an hour the log is the only account of what it saw. The
			-- first version logged nothing, and diagnosing a stalled run meant
			-- reproducing it by hand.
		local
			l_line: STRING_32
		do
			create l_line.make_from_string_general ("[auto] ")
			l_line.append_string_general (a_message)
			cycle.log (l_line)
		end

	log_label (a_raw, a_condensed: READABLE_STRING_GENERAL)
			-- Record what the page indicator read.
			--
			-- Both forms, because they differ when the model adds a newline or
			-- a stray word: the raw text says what the model produced, the
			-- condensed one says what the run actually compared against.
			-- Indicators are one short line, so both are logged whole.
		local
			l_line: STRING_32
		do
			create l_line.make_from_string_general ("indicator raw=[")
			l_line.append_string_general (a_raw)
			l_line.append_string_general ("] used=[")
			l_line.append_string_general (a_condensed)
			l_line.append_character (']')
			log (l_line)
		end

	log_configuration
			-- Record what the run was set up with.
			--
			-- First line of every run, because most failures turn out to be a
			-- box aimed at the wrong place, and the coordinates are the one
			-- thing nobody can reconstruct after the fact.
		local
			l_line: STRING_32
		do
			log ("=== auto-advance run starting ===")
			create l_line.make_from_string_general ("capture region ")
			l_line.append (rectangle_out (settings.region_x, settings.region_y,
				settings.region_width, settings.region_height))
			l_line.append_string_general ("  advance button ")
			l_line.append (rectangle_out (settings.advance_x, settings.advance_y,
				settings.advance_width, settings.advance_height))
			l_line.append_string_general ("  page indicator ")
			if settings.is_page_label_region_valid then
				l_line.append (rectangle_out (settings.page_label_x, settings.page_label_y,
					settings.page_label_width, settings.page_label_height))
			else
				l_line.append_string_general ("(not set - page text will witness the turn)")
			end
			log (l_line)

				-- The last gate before an unattended hour. A page indicator
				-- sitting on the advance button reads a number off a control and
				-- annotates every page with it, and nothing in the output says
				-- so - the run looks entirely healthy.
			if settings.is_label_over_advance then
				log ("WARNING: page indicator and advance button rectangles OVERLAP -"
					+ " the indicator is probably aimed at the button")
			end

			create l_line.make_from_string_general ("min settle ")
			l_line.append_string_general (settings.advance_delay_ms.out)
			l_line.append_string_general ("ms  output ")
			l_line.append_string_general (settings.text_file_path)
			log (l_line)
		end

	report_jump_if_any
			-- Say so, loudly, when the reader has moved somewhere unexpected.
			--
			-- The two costliest failures so far were both this, and both went
			-- unnoticed while the run carried happily on:
			--
			--   35% -> 94%  the reader skipped ahead; 209 pages never captured
			--   92% ->  0%  the reader returned to the cover and re-scanned
			--
			-- The program already knew: `rebaseline' fires at exactly that
			-- moment. All that was missing was saying it out loud.
			--
			-- Reported, never fatal. Halting on a misjudged jump is the mistake
			-- the removed `max_page_step' feature made, and advance detection is
			-- still doing its job - the text really did change.
		local
			l_what, l_do: STRING_32
		do
			if metrics.has_jumped then
				if metrics.jumped_backwards then
					create l_what.make_from_string_general ("The reader jumped BACKWARDS, from ")
					l_do := {STRING_32} "Everything from here is being scanned again. Stop, put the reader back where it was, and restart."
				else
					create l_what.make_from_string_general ("The reader jumped FORWARDS, from ")
					l_do := {STRING_32} "Pages are being skipped. Stop, return to where it was, and restart from there."
				end
				l_what.append_string_general (metrics.jumped_from.out)
				l_what.append_string_general ("%% to ")
				l_what.append_string_general (metrics.jumped_to.out)
				l_what.append_character ('%%')

				cycle.findings.observed ({OCR_FINDINGS}.Severity_error,
					current_label, l_what, l_do)
				note_progress ({STRING_32} "WARNING: " + l_what + ". " + l_do)
				metrics.clear_jump
			end
		end

	check_indicator_health
			-- Notice an indicator that WAS readable and has stopped being so.
			--
			-- Live case: a stray keypress put the reader's page box into edit
			-- mode, so the label came back as "of 330" - one number, no pair, no
			-- position - for eleven captures. Everything behaved correctly: the
			-- reading was refused, the tracked position held rather than
			-- corrupting, and text-based advance detection carried on. But
			-- NOTHING SAID SO, and eleven images were named ocr_of_330-N.png
			-- before anyone noticed.
			--
			-- No reader knowledge is needed to spot this, and none is used. The
			-- test is only "this was working and now it is not", which holds for
			-- every reader and every language.
			--
			-- Reported, never fatal. The run is still capturing correctly.
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from (current_label)
			if l_reader.has_position then
				indicator_was_parsing := True
				unreadable_labels := 0
				has_warned_indicator := False
			elseif indicator_was_parsing then
				unreadable_labels := unreadable_labels + 1
				if unreadable_labels >= Indicator_alarm and then not has_warned_indicator then
					has_warned_indicator := True
					note_progress ({STRING_32} "WARNING: the page indicator has stopped reading ("
						+ unreadable_labels.out
						+ " captures). Pages are still being captured, but they are no longer named or annotated by page. Check the reader - a page box left in edit mode looks like this.")
				end
			end
		end

	page_caption_text: STRING_32
			-- The indicator, with how far through the book it is.
			--
			-- Derived from `current_label' itself rather than from `metrics',
			-- and deliberately so. The caption names the page ABOUT to be
			-- captured; the metrics hold the last page COMPLETED. Taking the
			-- percentage from the metrics would print a figure one capture
			-- behind the number sitting right beside it, which reads as an
			-- arithmetic bug rather than as a lag.
		local
			l_reader: OCR_PAGE_POSITION
		do
			create Result.make_from_string (current_label)
			if not current_label.is_empty then
				create l_reader
				l_reader.set_from (current_label)
				if l_reader.has_total and then l_reader.total > 0 then
					Result.append_string_general ("   ")
					Result.append_string_general (
						((l_reader.position * 100) // l_reader.total).out)
					Result.append_character ('%%')
				end
			end
		end

	record_run_start
			-- Open the machine-readable record with the rectangles this run
			-- started from, mirroring what `log_configuration' writes in prose.
		local
			l_label: STRING_32
		do
			if settings.is_page_label_region_valid then
				l_label := rectangle_out (settings.page_label_x, settings.page_label_y,
					settings.page_label_width, settings.page_label_height)
			else
				create l_label.make_empty
			end
			cycle.run_log.record_run_start (
				rectangle_out (settings.region_x, settings.region_y,
					settings.region_width, settings.region_height),
				rectangle_out (settings.advance_x, settings.advance_y,
					settings.advance_width, settings.advance_height),
				l_label)
		end

	rectangle_out (a_x, a_y, a_width, a_height: INTEGER): STRING_32
			-- "WxH at (X,Y)".
		do
			create Result.make (32)
			Result.append_string_general (a_width.out)
			Result.append_character ('x')
			Result.append_string_general (a_height.out)
			Result.append_string_general (" at (")
			Result.append_string_general (a_x.out)
			Result.append_character (',')
			Result.append_string_general (a_y.out)
			Result.append_character (')')
		end

	log_advance
			-- Record that the reader moved on, and note the indicator alongside.
			--
			-- The indicator is logged for the record, never for the decision:
			-- seeing it hold still across several captures is how a page bigger
			-- than the window shows up in the log, and seeing it jump is how a
			-- reader showing several pages at once shows up. Neither changes
			-- what the run does.
		local
			l_line: STRING_32
		do
			create l_line.make_from_string_general ("advanced: text changed")
			if not current_label.is_empty then
				if label_changed then
					l_line.append_string_general ("; indicator moved to ")
					l_line.append (current_label)
				else
					l_line.append_string_general ("; indicator still reads ")
					l_line.append (current_label)
					l_line.append_string_general (" (same page, next portion)")
				end
			end
			log (l_line)
		end

	log_capture
			-- Record how the page came back: size, and enough of the text to
			-- identify it. A suspiciously short page is flagged rather than
			-- rejected - a reader's splash screen looks like this, and so does a
			-- legitimately near-empty page, and only a human can tell them apart
			-- afterwards from the transcript.
		local
			l_line: STRING_32
		do
			create l_line.make_from_string_general ("capture done chars=")
			l_line.append_string_general (cycle.last_text.count.out)
			if not cycle.last_error.is_empty then
				l_line.append_string_general (" ERROR=[")
				l_line.append (cycle.last_error)
				l_line.append_character (']')
			else
				if cycle.last_text.count < Suspicious_text_length then
					l_line.append_string_general (" WARNING: very little text - check this page")
				end
				l_line.append_string_general (" text=[")
				l_line.append (excerpt (cycle.last_text))
				l_line.append_character (']')
			end
			log (l_line)
		end

	excerpt (a_text: READABLE_STRING_32): STRING_32
			-- The opening and closing of `a_text', for the log.
			--
			-- Not the whole page: a hundred pages of transcript in the log would
			-- bury the decisions it exists to record, and duplicate a file that
			-- already holds the text. The head and tail are what identify WHICH
			-- page this was, and reveal a capture that came back near-empty.
		local
			l_flat: STRING_32
		do
			create l_flat.make (a_text.count)
			across a_text as ic_char loop
				if ic_char.item = '%N' or ic_char.item = '%R' or ic_char.item = '%T' then
					l_flat.append_character (' ')
				else
					l_flat.append_character (ic_char.item)
				end
			end
			l_flat.left_adjust
			l_flat.right_adjust

			if l_flat.count <= 2 * Excerpt_edge then
				Result := l_flat
			else
				Result := l_flat.substring (1, Excerpt_edge)
				Result.append_string_general (" ... ")
				Result.append (l_flat.substring (l_flat.count - Excerpt_edge + 1, l_flat.count))
			end
		end

	progress_line: STRING_32
			-- What to say after a page has been written and the click issued.
		do
			create Result.make_from_string_general ("Auto-advance: ")
			Result.append_string_general (pages_done.out)
			Result.append_string_general (" page(s) written")
			if not current_label.is_empty then
				Result.append_string_general (", last was ")
				Result.append (current_label)
			end
			Result.append_string_general (". Page ready.")
		end

feature -- Access

	status_line: STRING_32
			-- `last_message' with the run's rates appended, for the settings
			-- window.
			--
			-- Appended HERE rather than inside `progress_line'. That line is
			-- replaced within a second by "Reading page indicator...", so
			-- anything carried on it is on screen for a fraction of each cycle
			-- and absent for the rest - which reads exactly like a feature that
			-- does not work. The rates belong on whatever the status line
			-- currently says, not on one message of five.
		do
			create Result.make_from_string (last_message)
			if metrics.captures >= 2 then
				Result.append_string_general ("   |   ")
				Result.append (metrics.summary_line)
			end
		ensure
			non_empty: not Result.is_empty
		end

feature {NONE} -- Files

	scratch_path (a_name: READABLE_STRING_8): STRING_32
			-- `a_name' in the temporary folder.
			--
			-- Not the output folder: these two files are machinery, and a reader
			-- opening their transcript folder should find pages, not a page
			-- number that keeps being overwritten.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			create Result.make (64)
			if attached l_env.item ("TEMP") as al_temp and then not al_temp.is_empty then
				Result.append_string_general (al_temp)
				Result.append_character ('\')
			end
			Result.append_string_general (a_name)
		ensure
			non_empty: not Result.is_empty
		end

	read_utf8 (a_path: READABLE_STRING_GENERAL): detachable STRING_32
			-- Contents of `a_path' decoded from UTF-8, or Void if absent.
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

	delete_file (a_path: READABLE_STRING_GENERAL)
			-- Remove `a_path' if present, ignoring failure.
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried and then not a_path.is_empty then
				create l_file.make_with_name (a_path)
				if l_file.exists then
					l_file.delete
				end
			end
		rescue
			l_retried := True
			retry
		end

	executable_path: STRING_32
			-- Full path of this program, used to spawn worker mode.
		local
			l_args: ARGUMENTS_32
		do
			create l_args
			create Result.make_from_string (l_args.command_name)
		end

feature {NONE} -- Implementation

	settle_ticks: INTEGER
			-- Ticks to wait after a click, from the configured delay.
		do
			Result := (settings.advance_delay_ms // Tick_ms).max (1)
		ensure
			at_least_one: Result >= 1
		end

	settings: OCR_SETTINGS
	cycle: OCR_CYCLE
	clicker: OCR_CLICKER
	capture: OCR_GRAB

	previous_text: STRING_32
			-- Page text of the capture before this one.

	previous_label: STRING_32
			-- Page indicator of the capture before this one.

	label_image_path: STRING_32
	label_text_path: STRING_32

	label_worker: detachable SIMPLE_ASYNC_PROCESS
			-- The indicator OCR process, while one is running.

	status_strip: OCR_SW_STRIP

	metrics: OCR_RUN_METRICS
			-- Rate and ETA for this run. Display only - nothing here may gate a
			-- capture, a page turn or a stop.

	state: INTEGER
	step: INTEGER
	ticks_waited: INTEGER

	ticks_since_click: INTEGER
			-- Ticks since the page was turned, counted so the settle floor is
			-- measured from the click and not from the end of the OCR.

	has_clicked_this_page: BOOLEAN
			-- Has the advance click already been issued for the page in flight?
			-- Guards against the cycle's captured hook firing twice.

	indicator_was_parsing: BOOLEAN
			-- Has the page indicator ever yielded a position this run? Until it
			-- has, an unreadable label is normal - roman front matter, or a
			-- reader that shows nothing useful yet.

	unreadable_labels: INTEGER
			-- Consecutive captures whose indicator yielded no position, after it
			-- had been working.

	has_warned_indicator: BOOLEAN
			-- Said once per outage, not once per capture.

	label_retries: INTEGER
			-- Consecutive re-reads spent waiting for the reader to show a page.
			-- Cleared once a page is actually captured.

	stall_retries: INTEGER
			-- Extra clicks spent on a page that would not turn.
			-- Cleared the moment anything advances.

feature {NONE} -- Constants

	State_stopped: INTEGER = 0
	State_running: INTEGER = 1
	State_paused: INTEGER = 2

	Step_idle: INTEGER = 0
	Step_reading_label: INTEGER = 1
	Step_capturing: INTEGER = 2
	Step_settling: INTEGER = 3
	Step_waiting_for_page: INTEGER = 4

	Excerpt_edge: INTEGER = 70
			-- Characters of head and of tail kept when logging page text.

	Suspicious_text_length: INTEGER = 120
			-- Below this a capture is flagged in the log as worth a look. Chosen
			-- from a real run: a reader's splash screen produced 16 characters,
			-- while the sparsest genuine page - one bibliography line - produced
			-- 55, so this cannot separate them and does not try. It marks the
			-- page for a human instead of discarding it.

	Maximum_stall_retries: INTEGER = 2
			-- Extra clicks allowed on a page that will not turn.
			--
			-- Two, because the failures worth surviving are transient - a stray
			-- keystroke stealing the click, a control not yet enabled after a
			-- section break - and a reader that has genuinely ended will not be
			-- talked round by a fourth attempt.

	Indicator_alarm: INTEGER = 4
			-- Unreadable labels before saying so. Four rather than one: a single
			-- bad read is ordinary sampling noise and self-corrects, while four
			-- in a row is something that has actually changed on screen.

	Maximum_label_retries: INTEGER = 10
			-- Re-reads allowed before giving up on the reader showing a page.
			-- Ten at `Page_retry_ticks' apart covers a slow cache load without
			-- letting a genuinely stuck reader spin for ever.

	Page_retry_ticks: INTEGER = 40
			-- Two seconds between re-reads of the indicator.

	Tick_ms: INTEGER = 50
			-- Timer period this is polled on; keep in step with OCR_GUI.

	Label_timeout_ticks: INTEGER = 1200
			-- One minute. The indicator is a few characters, but the very first
			-- one of a session can still pay a cold model load.

	Label_maximum_length: INTEGER = 40
			-- Indicators are short; anything longer is the model editorialising.

invariant
	error_attached: last_error /= Void
	message_attached: last_message /= Void
	label_attached: current_label /= Void
	counted: pages_done >= 0
	one_state: is_running xor is_paused xor is_stopped

end
