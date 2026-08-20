note
	description: "[
		Problems worth a human's attention, recorded beside the transcript they
		concern as one JSON object per line.

		    <book>.txt  ->  <book>.findings.jsonl

		TWO writers, one file. The application appends what it OBSERVES while a
		run is going - an OCR failure, an indicator that stopped reading, a
		reader that jumped. The `--audit' mode appends what it DEDUCES from a
		finished corpus - coverage gaps, seams where the text does not join,
		near-duplicate blocks.

		The findings grid in the interface is only a view of this file.
	]"
	design: "[
		`source' distinguishes the two writers and is shown to the user, because
		a problem observed a second ago and one deduced an hour ago deserve
		different trust. A deduced finding can be stale - the gap it names may
		already have been filled.

		`certain' matters more than it looks. Two of the audit's checks cannot
		be sure: a page number with no covering capture may not be a real page
		(344 and 355-356 of one book simply did not exist), and a seam that
		looks broken may be a bibliography, where every entry begins capitalised
		and ends with a full stop. Reporting those as facts sends someone
		re-capturing pages that were never missing - a mistake made twice by
		hand before this class existed.

		`fix_file' is named for WHAT IS BEING FIXED, not for an error code.
		"-127-335" still means something in six months; "-ERR07" does not.

		Written with OCR_JSON_UTIL rather than SIMPLE_JSON_OBJECT for the same
		reason as OCR_RUN_LOG: the builder's `put_string' carries a precondition
		on value length, assertions are baked into the shipped binary, and a
		reporting class must never be able to abort the run it is reporting on.
	]"

class
	OCR_FINDINGS

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
			-- Record findings for the book described by `a_settings'.
		do
			settings := a_settings
		end

feature -- Access

	findings_path: STRING_32
			-- Where findings for this book are written.
		local
			l_stem: STRING_32
			l_dot: INTEGER
		do
			create l_stem.make_from_string (settings.text_file_name)
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
			Result.append_string_general (".findings.jsonl")
		ensure
			non_empty: not Result.is_empty
		end

feature -- Recording

	observed (a_severity, a_pages, a_problem, a_remedy: READABLE_STRING_GENERAL)
			-- Record something the running application noticed itself.
		do
			record ("run", a_severity, a_pages, a_problem, a_remedy, "", True)
		end

	deduced (a_severity, a_pages, a_problem, a_remedy, a_fix_file: READABLE_STRING_GENERAL;
			a_certain: BOOLEAN)
			-- Record something `--audit' worked out from a finished corpus.
		do
			record ("audit", a_severity, a_pages, a_problem, a_remedy, a_fix_file, a_certain)
		end

	set_notify (a_agent: PROCEDURE [STRING_32, STRING_32, STRING_32, STRING_32])
			-- Call `a_agent' with severity, pages, problem and remedy as each
			-- finding is recorded, so a display can show it as it happens.
			--
			-- One hook for both writers: whether the application noticed the
			-- problem itself or `--audit' worked it out, the grid gets the row.
		do
			on_finding := a_agent
		end

	record (a_source, a_severity, a_pages, a_problem, a_remedy, a_fix_file: READABLE_STRING_GENERAL;
			a_certain: BOOLEAN)
			-- Append one finding.
		local
			l_row: STRING_8
			l_util: OCR_JSON_UTIL
			l_sev: STRING_32
		do
			if attached on_finding as al_agent then
				create l_sev.make_from_string_general (a_severity)
				if not a_certain then
					l_sev.append_string_general ("?")
				end
				al_agent.call (l_sev,
					create {STRING_32}.make_from_string_general (a_pages),
					create {STRING_32}.make_from_string_general (a_problem),
					create {STRING_32}.make_from_string_general (a_remedy))
			end
			create l_util
			create l_row.make (256)
			l_row.append ("{%"t%":")
			l_row.append (l_util.quoted (stamp))
			add (l_row, "source", a_source)
			add (l_row, "severity", a_severity)
			add (l_row, "pages", a_pages)
			add (l_row, "problem", a_problem)
			add (l_row, "remedy", a_remedy)
			add (l_row, "fix_file", a_fix_file)
			l_row.append (",%"certain%":")
			if a_certain then
				l_row.append ("true")
			else
				l_row.append ("false")
			end
			l_row.append_character ('}')
			append_row (l_row)
		end

feature {NONE} -- Implementation

	add (a_row: STRING_8; a_key: READABLE_STRING_8; a_value: READABLE_STRING_GENERAL)
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

	append_row (a_row: STRING_8)
			-- Append `a_row' as one line, ignoring any failure.
			--
			-- Opened and closed per row, and every failure swallowed: this is a
			-- reporting class, and a locked file must cost a finding rather than
			-- the run it was reporting on.
		local
			l_file: RAW_FILE
			l_path: STRING_32
			l_retried: BOOLEAN
		do
			if not l_retried then
				l_path := findings_path
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

	stamp: STRING_8
			-- Now, as ISO-8601 local time. Sorts correctly as text, unlike
			-- `DATE_TIME.out', which is month-first and twelve-hour.
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
		end

	padded_2 (a_value: INTEGER): STRING_8
		do
			Result := a_value.out
			if Result.count < 2 then
				Result.prepend ("0")
			end
		ensure
			two_digits: Result.count >= 2
		end

	on_finding: detachable PROCEDURE [STRING_32, STRING_32, STRING_32, STRING_32]
			-- Told about each finding as it is recorded, for a live display.

	settings: OCR_SETTINGS

feature -- Constants

	Severity_error: STRING_8 = "error"
	Severity_warn: STRING_8 = "warn"
	Severity_info: STRING_8 = "info"

end
