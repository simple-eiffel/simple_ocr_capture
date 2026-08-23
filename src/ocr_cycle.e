note
	description: "[
		Drives one capture cycle and reports its five stages.

		The OCR call is the problem this class exists to solve. It takes ~11
		seconds warm and can exceed 45 on a cold model load. Doing it inline
		would freeze the Vision2 event loop, which means the progress strip
		would not repaint and the whole point of the strip - knowing when it is
		safe to turn the page - would be lost.

		So the image goes to disk, a detached worker process does the OCR, and
		`poll' checks on it from a timer tick. The GUI stays live throughout.
	]"

class
	OCR_CYCLE

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS; a_strip: OCR_SW_STRIP)
			-- Create a cycle driver.
		do
			settings := a_settings
			status_strip := a_strip
			create capture.make
			create run_log.make (a_settings)
			create findings.make (a_settings)
			create last_error.make_empty
			create last_text.make_empty
			create page_label.make_empty
			create current_image_path.make_empty
			create current_text_path.make_empty
			phase := Phase_ready
		end

feature -- Access

	last_error: STRING_32
			-- Reason the most recent cycle failed; empty when it succeeded.

	last_text: STRING_32
			-- Text produced by the most recent successful cycle.

	page_label: STRING_32
			-- Page indicator read for the current capture; empty when unknown.

	completed_count: INTEGER
			-- Number of cycles that finished successfully this session.

	findings: OCR_FINDINGS
			-- Problems worth a human's attention, beside the transcript.
			--
			-- Exposed for the same reason as `run_log': the auto-advance driver
			-- writes to the same file, so a book has one findings list whatever
			-- part of the program noticed the problem.

	run_log: OCR_RUN_LOG
			-- Machine-readable record of this session, beside the transcript.
			--
			-- Exposed so the auto-advance driver can add its own events to the
			-- same stream. One file per book, whatever produced the row.

feature -- Status report

	is_busy: BOOLEAN
			-- Is a cycle in progress?
		do
			Result := phase /= Phase_ready
		end

feature -- Basic operations

	trigger
			-- Begin a cycle, unless one is already running.
			-- Re-triggering mid-cycle is ignored rather than queued: a second
			-- capture of the same page is never what was wanted.
		local
			l_ok: BOOLEAN
		do
			if not is_busy then
				last_error.wipe_out
				last_text.wipe_out

				announce (1, "capturing...")

				if not settings.is_region_valid then
					fail ("No capture region set.")
				elseif not ensured_output_folder then
					fail ({STRING_32} "The output folder does not exist: " + settings.output_folder)
				else
					settings.bump_capture_index
					current_image_path := image_path_for (settings.capture_index)
					current_text_path := sidecar_path_for (settings.capture_index)

						-- Around the shutter only. Anything the application itself
						-- draws over the capture rectangle - the region outlines -
						-- must be off the screen for these few milliseconds, or it
						-- is photographed into the page image and sent to the OCR
						-- model as if it were part of the book.
					if attached on_shutter_open as al_open then
						al_open.call
					end
					l_ok := capture.capture_to_file (settings.region_x, settings.region_y,
						settings.region_width, settings.region_height,
						current_image_path, settings.image_format)
					if attached on_shutter_close as al_close then
						al_close.call
					end

					if not l_ok then
						fail (capture.last_error)
					else
							-- Shown at stage 2, while the OCR is still running,
							-- so a wrong region is obvious immediately rather
							-- than 40 seconds later.
						status_strip.set_thumbnail (capture.last_thumbnail)
						announce (2, "captured, running OCR...")
						start_worker
							-- Fired once the screenshot is safely on disk and the
							-- OCR is under way. The auto-advance driver turns the
							-- page here rather than at the end of the cycle: the
							-- page is already captured, so the reader is free to
							-- repaint during the OCR instead of after it.
						if attached on_captured_agent as al_agent then
							al_agent.call
						end
					end
				end
			end
		end

	poll
			-- Advance the cycle. Call from a timer tick.
		do
			if phase = Phase_ocr and then attached worker as al_worker then
				if al_worker.has_finished then
					harvest (al_worker)
				end
			end
		end

	set_shutter_actions (a_open, a_close: PROCEDURE)
			-- Call `a_open' immediately before the screenshot and `a_close'
			-- immediately after, so overlays can get out of the frame.
		do
			on_shutter_open := a_open
			on_shutter_close := a_close
		end

	set_captured_action (a_agent: PROCEDURE)
			-- Call `a_agent' as soon as the screenshot has been taken and the
			-- OCR started, while the cycle is still running.
		do
			on_captured_agent := a_agent
		end

	set_page_label (a_label: READABLE_STRING_GENERAL)
			-- Record which page(s) the next capture covers, for its header.
			--
			-- Set by the auto-advance driver, which reads the reader's page
			-- indicator BEFORE triggering the capture, so the label written
			-- above the text is the one that was on screen when it was taken.
		do
			create page_label.make_from_string_general (a_label)
		ensure
			set: page_label.same_string_general (a_label)
		end

	reset_to_ready
			-- Force the cycle back to its resting state.
		do
			discard_worker
			phase := Phase_ready
			announce (5, "READY")
		ensure
			ready: not is_busy
		end

feature {NONE} -- Stages

	start_worker
			-- Launch the detached OCR worker for the current image.
		local
			l_cmd: STRING_32
		do
			discard_worker

			create l_cmd.make (256)
			l_cmd.append_character ('%"')
			l_cmd.append (executable_path)
			l_cmd.append_string_general ("%" --worker %"")
			l_cmd.append (current_image_path)
			l_cmd.append_string_general ("%" %"")
			l_cmd.append (current_text_path)
			l_cmd.append_character ('%"')

			create worker.make
			if attached worker as al_worker then
					-- Default is already hidden; being explicit because a console
					-- window flashing up on every page turn would be intolerable.
				al_worker.set_show_window (False)
				al_worker.start (l_cmd)
				if al_worker.is_started then
					phase := Phase_ocr
					announce (3, "OCR running...")
				else
					fail ("Could not start the OCR worker process.")
				end
			end
		end

	harvest (a_worker: SIMPLE_ASYNC_PROCESS)
			-- Collect the worker's output and finish the cycle.
		local
			l_text: detachable STRING_32
			l_reason: STRING_32
		do
			l_text := read_utf8 (current_text_path)
			discard_worker

			if l_text = Void then
				fail ("OCR worker produced no output file.")
			elseif l_text.starts_with ({STRING_32} "[OCR FAILED]") then
				fail (l_text)
			else
				last_text := l_text
				announce (4, "writing results...")

					-- A capture identical to the one just written is not a page;
					-- it is the same page photographed again. That happens by
					-- design at the end of a book: the run captures, sees no
					-- advance, clicks twice more and captures each time before
					-- concluding the book has ended. Those retries are worth
					-- keeping - they rescue a genuinely missed click - but their
					-- TEXT is not, and it left three copies of the last page in
					-- every transcript to be trimmed by hand afterwards.
					--
					-- Byte-identical only. Two different pages are never
					-- identical, so this cannot drop real content; the worst it
					-- can cost is one of two consecutive blank pages.
				if settings.save_text and then l_text.same_string (last_appended_text) then
					log ("identical to the previous block - not appended (retry capture)")
				elseif settings.save_text then
					if append_to_master (l_text) then
						last_appended_text := l_text.twin
					else
						l_reason := {STRING_32} "Could not write to "
						l_reason.append (settings.text_file_path)
						fail (l_reason)
					end
				end

				if not last_error.is_empty then
						-- append_to_master already reported
				else
						-- Recorded before the image is disposed of, and named only
						-- when one was actually kept: a row pointing at a file
						-- that was deleted a line later would be worse than a row
						-- with no file name at all.
					if settings.save_image then
						run_log.record_capture (settings.capture_index,
							current_image_path, page_label, "", l_text.count)
					else
						run_log.record_capture (settings.capture_index,
							"", page_label, "", l_text.count)
						delete_file (current_image_path)
					end
					delete_file (current_text_path)

					completed_count := completed_count + 1
					settings.store
					phase := Phase_ready
					announce (5, "READY")
				end
			end
		end

	fail (a_reason: READABLE_STRING_GENERAL)
			-- Abort the cycle, reporting `a_reason'.
		do
			create last_error.make_from_string_general (a_reason)
			log (last_error)
				-- A failed capture earns a row too. A gap in the record is
				-- indistinguishable from a capture that never happened, and the
				-- failures are the rows most worth having afterwards.
			run_log.record_capture (settings.capture_index,
				current_image_path, page_label, last_error, 0)
			discard_worker
			phase := Phase_ready
			status_strip.set_stage ({OCR_SW_STRIP}.Stage_ready, truncated (a_reason))
		ensure
			ready: not is_busy
			reported: not last_error.is_empty
		end

	announce (a_stage: INTEGER; a_message: READABLE_STRING_GENERAL)
			-- Report progress to the strip.
		do
			status_strip.set_stage (a_stage, a_message)
		end

feature -- Diagnostics

	log (a_message: READABLE_STRING_GENERAL)
			-- Append `a_message' to the diagnostic log.
			--
			-- Delegated to OCR_LOG_FILE, which owns the path. Writing used to
			-- build it inline here, which was fine while writing was the only
			-- thing done to the file; the Open Log and Clear Log buttons need
			-- the same path, and two copies of a path is one too many.
		do
			log_file.append (a_message)
		end

	log_file: OCR_LOG_FILE
			-- The diagnostic log this cycle writes to.
		once
			create Result
		end

feature {NONE} -- Files

	ensured_output_folder: BOOLEAN
			-- Make sure the output folder exists. True when it does afterwards.
			--
			-- Must run BEFORE the capture, not before the text append: the image
			-- and the worker's sidecar are both written into this folder, so
			-- creating it only at append time left the very first capture of a
			-- fresh install writing into a directory that did not exist.
		local
			l_dir: DIRECTORY
			l_retried: BOOLEAN
		do
				-- Checked, NEVER created. Creating it here meant a mistyped path
				-- silently produced a new folder and scanned a whole book into
				-- it. Consent belongs with the user, in the interface, before a
				-- run starts - not in the capture path where the only options
				-- are to guess or to fail.
			if not l_retried then
				create l_dir.make_with_name (settings.output_folder)
				Result := l_dir.exists
			end
		rescue
			l_retried := True
			retry
		end

	append_to_master (a_text: READABLE_STRING_32): BOOLEAN
			-- Append `a_text' to the single output file, creating it and its
			-- directory if needed.
		local
			l_file: RAW_FILE
			l_dir: DIRECTORY
			l_path: PATH
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_dir.make_with_name (settings.output_folder)
				if not l_dir.exists then
					l_dir.recursive_create_dir
				end

				create l_path.make_from_string (settings.text_file_path)
				create l_file.make_with_path (l_path)
				if l_file.exists then
					l_file.open_append
				else
					l_file.create_read_write
				end

				if settings.add_separators then
					l_file.put_string (utf8 (separator_for (settings.capture_index)))
				end
				l_file.put_string (utf8 (a_text))
				if not a_text.is_empty and then a_text.item (a_text.count) /= '%N' then
					l_file.put_string ("%N")
				end
				l_file.put_string ("%N")
				l_file.close
				Result := True
			end
		rescue
			l_retried := True
			retry
		end

	separator_for (a_index: INTEGER): STRING_32
			-- Header written before each capture's text.
		local
			l_time: DATE_TIME
		do
			create l_time.make_now
			create Result.make (80)
			Result.append_string_general ("----- capture ")
			Result.append_string_general (a_index.out)
			if not page_label.is_empty then
				Result.append_string_general ("  [page ")
				Result.append (page_label)
				Result.append_character (']')
			end
			Result.append_string_general ("  ")
			Result.append_string_general (l_time.out)
			Result.append_string_general (" -----%N")
		end

	image_path_for (a_index: INTEGER): STRING_32
			-- Where capture `a_index' is written.
			--
			-- Named after what the reader was showing rather than after a
			-- counter, so a folder of screenshots can be navigated against the
			-- book. The counter remains the fallback when there is no indicator.
			--
			-- One indicator can name several files: a printed page larger than
			-- the reader's window is captured in portions, all of them showing
			-- the same page number. Later portions therefore take a "-2", "-3"
			-- suffix. Nothing is ever overwritten - a screenshot is the only
			-- record of what was on screen, and a second one that quietly
			-- replaced the first would destroy evidence, not tidy it.
		local
			l_namer: OCR_IMAGE_NAME
			l_stem: STRING_32
			l_suffix: INTEGER
		do
			create l_namer
			l_stem := l_namer.stem (page_label, a_index)
			from
				l_suffix := 1
				Result := image_path_of (l_stem, l_suffix)
			until
				not file_exists (Result)
			loop
				l_suffix := l_suffix + 1
				Result := image_path_of (l_stem, l_suffix)
			end
		ensure
			non_empty: not Result.is_empty
		end

	image_path_of (a_stem: READABLE_STRING_32; a_suffix: INTEGER): STRING_32
			-- Path for `a_stem', with a disambiguating suffix when `a_suffix'
			-- is above one.
		require
			stem_not_empty: not a_stem.is_empty
			positive: a_suffix >= 1
		do
			create Result.make_from_string (folder_prefix)
			Result.append_string_general ("ocr_")
			Result.append (a_stem)
			if a_suffix > 1 then
				Result.append_character ('-')
				Result.append_string_general (a_suffix.out)
			end
			Result.append_character ('.')
			Result.append_string_general (settings.image_format)
		ensure
			non_empty: not Result.is_empty
		end

	file_exists (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Is there already a file at `a_path'?
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (a_path)
				Result := l_file.exists
			end
		rescue
			l_retried := True
			retry
		end

	sidecar_path_for (a_index: INTEGER): STRING_32
			-- Where the worker writes this capture's text.
		do
			create Result.make_from_string (folder_prefix)
			Result.append_string_general ("ocr_")
			Result.append_string_general (padded (a_index))
			Result.append_string_general (".sidecar.txt")
		end

	folder_prefix: STRING_32
			-- Output folder with a trailing separator.
		do
			create Result.make_from_string (settings.output_folder)
			if not Result.is_empty and then Result.item (Result.count) /= '\' then
				Result.append_character ('\')
			end
		end

	padded (a_index: INTEGER): STRING_8
			-- `a_index' as at least four digits, so files sort in capture order.
		do
			Result := a_index.out
			from until Result.count >= 4 loop
				Result.prepend ("0")
			end
		ensure
			wide_enough: Result.count >= 4
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

feature {NONE} -- Implementation

	discard_worker
			-- Release the worker process handle, if any.
		do
			if attached worker as al_worker then
				if al_worker.is_started and then al_worker.is_running then
					if al_worker.kill then
						-- terminated
					end
				end
				al_worker.close
			end
			worker := Void
		end

	executable_path: STRING_32
			-- Full path of this program, used to spawn worker mode.
		local
			l_args: ARGUMENTS_32
		do
			create l_args
			create Result.make_from_string (l_args.command_name)
		end

	utf8 (a_text: READABLE_STRING_GENERAL): STRING_8
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
		end

	truncated (a_text: READABLE_STRING_GENERAL): STRING_32
			-- `a_text' shortened to fit the strip caption.
		do
			create Result.make_from_string_general (a_text)
			if Result.count > 34 then
				Result := Result.substring (1, 31) + {STRING_32} "..."
			end
		end

	settings: OCR_SETTINGS

	status_strip: OCR_SW_STRIP
			-- Not named `strip': that is a reserved word in Eiffel (the obsolete
			-- strip expression) and assigning to it is a syntax error.

	capture: OCR_GRAB

	worker: detachable SIMPLE_ASYNC_PROCESS
			-- The detached OCR process, while one is running.

	on_captured_agent: detachable PROCEDURE
			-- Called mid-cycle, once the screenshot exists.

	on_shutter_open: detachable PROCEDURE
	on_shutter_close: detachable PROCEDURE
			-- Called either side of the screenshot itself, for overlays that
			-- must not appear in it.

	last_appended_text: STRING_32
			-- Text of the block most recently written to the transcript, so an
			-- identical retry capture can be recognised and skipped.
		attribute
			create Result.make_empty
		end

	current_image_path: STRING_32
	current_text_path: STRING_32

	phase: INTEGER
			-- `Phase_ready' or `Phase_ocr'.

	Phase_ready: INTEGER = 0
	Phase_ocr: INTEGER = 2

invariant
	error_attached: last_error /= Void
	text_attached: last_text /= Void
	counted: completed_count >= 0

end
