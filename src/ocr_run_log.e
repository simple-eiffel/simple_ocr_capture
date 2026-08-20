note
	description: "[
		Per-capture JSONL record of a reading session, written beside the
		transcript it describes.

		One JSON object per line, appended as each event happens. Never
		buffered: a run that dies unattended is exactly the run whose record
		matters, and anything held in memory would die with it.

		This is the machine-readable companion to ocr_capture.log. That log is
		prose, for a person reading it after a run stopped. This is columns,
		for a program - rate analysis, and the capture-index-to-filename
		mapping that lets an ingest step find an image without deriving its
		name from a counter.
	]"
	design: "[
		Rows are built with OCR_JSON_UTIL rather than SIMPLE_JSON_OBJECT, which
		is otherwise the house tool for JSON. Two reasons, both about running
		unattended:

		  * SIMPLE_JSON_OBJECT.put_string carries `value_reasonable_length' as
		    a PRECONDITION. Assertions are baked into the shipped binary -
		    `ec.sh test' finalizes with -keep - so an over-long value taken
		    from model output would abort a running scan on a contract
		    violation. A log writer must never be able to stop the thing it is
		    logging.

		  * A row here is flat. There is no nesting for a builder to earn.

		OCR_JSON_UTIL.escaped is fully general - UTF-8, control characters,
		quotes and backslashes - so untrusted model output is safe in a value.

		Every write is wrapped in a rescue and ignores failure, for the same
		reason: a locked file or a full disk must cost the log, not the run.
	]"

class
	OCR_RUN_LOG

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
			-- Record events for the session described by `a_settings'.
		do
			settings := a_settings
		end

feature -- Recording

	record_run_start (a_capture_region, a_advance_region, a_label_region: READABLE_STRING_GENERAL)
			-- Note that an unattended run began, with the rectangles it started
			-- from. Most trouble turns out to be a box aimed at the wrong place,
			-- and the coordinates cannot be reconstructed afterwards.
		local
			l_row: STRING_8
		do
			l_row := opened ("run_start")
			with_text (l_row, "capture_region", a_capture_region)
			with_text (l_row, "advance_region", a_advance_region)
			with_text (l_row, "label_region", a_label_region)
			with_text (l_row, "output", settings.text_file_path)
			closed (l_row)
		end

	record_capture (a_index: INTEGER; a_image_path, a_label, a_error: READABLE_STRING_GENERAL; a_chars: INTEGER)
			-- Note one completed capture.
			--
			-- `a_image_path' is reduced to its file name: the folder is already
			-- known to anything reading this file, since the log lives in it.
			--
			-- The label is recorded exactly as the model produced it, with no
			-- attempt to parse a page number out of it. Deriving a position is
			-- an analysis-time concern, and a reader that presents pages in an
			-- unforeseen format must still get a usable record.
		local
			l_row: STRING_8
		do
			l_row := opened ("capture")
			with_number (l_row, "capture", a_index)
			with_text (l_row, "image", base_name (a_image_path))
			with_text (l_row, "label", a_label)
			with_number (l_row, "chars", a_chars)
			with_text (l_row, "error", a_error)
			closed (l_row)
		end

	record_advance (a_index: INTEGER; a_reason: READABLE_STRING_GENERAL; a_retries: INTEGER)
			-- Note that the reader moved on after capture `a_index'.
		local
			l_row: STRING_8
		do
			l_row := opened ("advance")
			with_number (l_row, "capture", a_index)
			with_text (l_row, "reason", a_reason)
			with_number (l_row, "retries", a_retries)
			closed (l_row)
		end

	record_stop (a_reason: READABLE_STRING_GENERAL; a_captures: INTEGER)
			-- Note that a run ended, and why.
		local
			l_row: STRING_8
		do
			l_row := opened ("stop")
			with_text (l_row, "reason", a_reason)
			with_number (l_row, "captures", a_captures)
			closed (l_row)
		end

feature -- Access

	run_log_path: STRING_32
			-- The run log, beside the transcript: same stem, ".runlog.jsonl".
			--
			-- Beside the transcript rather than in %APPDATA%, because this is
			-- per-BOOK evidence and should travel with the book. ocr_capture.log
			-- is per-install and stays where it is.
		local
			l_stem: STRING_32
			l_dot: INTEGER
		do
			create l_stem.make_from_string (settings.text_file_name)
				-- Guarded for the same reason as `base_name': `last_index_of'
				-- rejects a start index of zero, and a settings file that failed
				-- to parse can leave this empty.
			if l_stem.is_empty then
				l_stem := {STRING_32} "ocr_capture"
			else
				l_dot := l_stem.last_index_of ('.', l_stem.count)
				if l_dot > 1 then
					l_stem := l_stem.substring (1, l_dot - 1)
				end
			end

			create Result.make_from_string (settings.output_folder)
			if not Result.is_empty and then Result.item (Result.count) /= '\' then
				Result.append_character ('\')
			end
			Result.append (l_stem)
			Result.append_string_general (".runlog.jsonl")
		ensure
			non_empty: not Result.is_empty
		end

feature {NONE} -- Row building

	opened (a_event: READABLE_STRING_8): STRING_8
			-- A row's opening: timestamp and event name.
		local
			l_util: OCR_JSON_UTIL
		do
			create l_util
			create Result.make (192)
			Result.append ("{%"t%":")
			Result.append (l_util.quoted (stamp))
			Result.append (",%"event%":")
			Result.append (l_util.quoted (a_event))
		ensure
			started: not Result.is_empty
		end

	with_text (a_row: STRING_8; a_key: READABLE_STRING_8; a_value: READABLE_STRING_GENERAL)
			-- Append `a_key': `a_value' as a JSON string member.
		local
			l_util: OCR_JSON_UTIL
		do
			create l_util
			a_row.append_character (',')
			a_row.append (l_util.quoted (a_key))
			a_row.append_character (':')
			a_row.append (l_util.quoted (a_value))
		end

	with_number (a_row: STRING_8; a_key: READABLE_STRING_8; a_value: INTEGER)
			-- Append `a_key': `a_value' as a JSON number member.
		local
			l_util: OCR_JSON_UTIL
		do
			create l_util
			a_row.append_character (',')
			a_row.append (l_util.quoted (a_key))
			a_row.append_character (':')
			a_row.append (a_value.out)
		end

	closed (a_row: STRING_8)
			-- Finish `a_row' and write it.
		do
			a_row.append_character ('}')
			append_row (a_row)
		end

feature {NONE} -- Writing

	append_row (a_row: STRING_8)
			-- Append `a_row' as one line, ignoring any failure.
			--
			-- Opened and closed per row rather than held open for the session.
			-- A handle kept across an hour-long run is a handle that survives
			-- the crash it was supposed to describe with its last rows still
			-- unflushed.
		local
			l_file: RAW_FILE
			l_path: STRING_32
			l_retried: BOOLEAN
		do
			if not l_retried then
				l_path := run_log_path
				if not l_path.is_empty then
					create l_file.make_with_name (l_path)
					if l_file.exists then
						l_file.open_append
					else
						l_file.create_read_write
					end
					l_file.put_string (a_row)
					l_file.put_string ("%N")
					l_file.close
				end
			end
		rescue
			l_retried := True
			retry
		end

feature {NONE} -- Implementation

	stamp: STRING_8
			-- Now, as ISO-8601 local time.
			--
			-- Not `DATE_TIME.out', which produces "08/17/2026 6:35:25.005 PM" -
			-- month-first, twelve-hour, and locale-shaped. Sorting that as text
			-- is wrong and parsing it is a guess. ISO sorts correctly as a
			-- string and every analysis tool reads it without being told how.
		local
			l_now: DATE_TIME
		do
			create l_now.make_now
			create Result.make (20)
			Result.append (l_now.year.out)
			Result.append_character ('-')
			Result.append (padded_2 (l_now.month))
			Result.append_character ('-')
			Result.append (padded_2 (l_now.day))
			Result.append_character ('T')
			Result.append (padded_2 (l_now.hour))
			Result.append_character (':')
			Result.append (padded_2 (l_now.minute))
			Result.append_character (':')
			Result.append (padded_2 (l_now.second))
		ensure
			iso_length: Result.count >= 19
		end

	padded_2 (a_value: INTEGER): STRING_8
			-- `a_value' as at least two digits.
		do
			Result := a_value.out
			if Result.count < 2 then
				Result.prepend ("0")
			end
		ensure
			two_digits: Result.count >= 2
		end

	base_name (a_path: READABLE_STRING_GENERAL): STRING_32
			-- The file name part of `a_path'.
			--
			-- An empty path is normal here, not exceptional: a capture taken
			-- with image saving switched off has no file to name, and a failure
			-- before the screenshot has no path yet. `last_index_of' requires a
			-- start index of at least one, so the empty case must be taken
			-- BEFORE calling it - passing zero violates its precondition and
			-- brings the whole program down from inside a log writer.
		local
			l_slash: INTEGER
		do
			create Result.make_from_string_general (a_path)
			if not Result.is_empty then
				l_slash := Result.last_index_of ('\', Result.count)
				if l_slash > 0 and then l_slash < Result.count then
					Result := Result.substring (l_slash + 1, Result.count)
				end
			end
		end

	settings: OCR_SETTINGS

end
