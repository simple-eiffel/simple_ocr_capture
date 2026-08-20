note
	description: "[
		The diagnostic log: where it lives, and what can be done to it -
		append a line, empty it, open it for reading, keep it from growing
		without limit.

		The path was previously built inline inside OCR_CYCLE.log, which was
		fine while writing was the only thing anyone did to it. Buttons that
		open and clear the file need the same path, and two copies of a path
		is one copy too many.
	]"
	design: "[
		Every operation swallows its own failure. A log is a diagnostic aid; a
		locked file or a full disk must cost the log and nothing else. Nothing
		here may ever propagate an exception into a running capture.
	]"

class
	OCR_LOG_FILE

feature -- Access

	path: STRING_32
			-- Full path of the diagnostic log; empty when APPDATA is unset.
			--
			-- Beside settings.json rather than in the output folder, because
			-- "could not create the output folder" is one of the failures most
			-- worth recording.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			create Result.make (64)
			if attached l_env.item ("APPDATA") as al_appdata and then not al_appdata.is_empty then
				Result.append_string_general (al_appdata)
				Result.append_string_general ("\simple_ocr_capture\ocr_capture.log")
			end
		end

	byte_count: INTEGER
			-- Size of the log in bytes; zero when it is absent or unreadable.
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried and then not path.is_empty then
				create l_file.make_with_name (path)
				if l_file.exists then
					Result := l_file.count
				end
			end
		rescue
			l_retried := True
			retry
		end

feature -- Status report

	exists: BOOLEAN
			-- Is there a log file to read?
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried and then not path.is_empty then
				create l_file.make_with_name (path)
				Result := l_file.exists
			end
		rescue
			l_retried := True
			retry
		end

feature -- Basic operations

	append (a_message: READABLE_STRING_GENERAL)
			-- Add `a_message' as one timestamped line.
			--
			-- The shipped application is a GUI subsystem binary with no console,
			-- so a failure that is not written somewhere is simply invisible.
		local
			l_file: RAW_FILE
			l_time: DATE_TIME
			l_retried: BOOLEAN
		do
			if not l_retried and then not path.is_empty then
				create l_file.make_with_name (path)
				if l_file.exists then
					l_file.open_append
				else
					l_file.create_read_write
				end
				create l_time.make_now
				l_file.put_string (utf8 (l_time.out))
				l_file.put_string ("  ")
				l_file.put_string (utf8 (a_message))
				l_file.put_string ("%N")
				l_file.close
			end
		rescue
			l_retried := True
			retry
		end

	clear
			-- Empty the log, leaving one line saying so.
			--
			-- Not deleted: a file that vanishes looks like a bug to the next
			-- person who opens the folder, and the surviving line dates the
			-- gap so an empty log is never mistaken for a silent one.
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried and then not path.is_empty then
				create l_file.make_with_name (path)
				l_file.create_read_write
				l_file.close
				append ("log cleared")
			end
		rescue
			l_retried := True
			retry
		end

	open_externally: BOOLEAN
			-- Show the log in whatever reads .txt on this machine. True when
			-- the viewer was launched.
			--
			-- `start' rather than a named editor: the user's own file
			-- association is a better guess than Notepad, and naming an editor
			-- that is not installed fails silently.
		local
			l_process: SIMPLE_ASYNC_PROCESS
			l_command: STRING_32
			l_retried: BOOLEAN
		do
			if not l_retried and then exists then
				create l_command.make (160)
				l_command.append_string_general ("cmd.exe /c start %"%" %"")
				l_command.append (path)
				l_command.append_character ('%"')

				create l_process.make
				l_process.set_show_window (False)
				l_process.start (l_command)
				Result := l_process.is_started
			end
		rescue
			l_retried := True
			retry
		end

	rotate_if_large
			-- Start a fresh log when the current one has grown past
			-- `Maximum_bytes', keeping exactly ONE previous generation.
			--
			-- Called once per session rather than per write. Clearing the log
			-- at startup was considered and rejected: the moment anyone opens
			-- this file is the moment after something went wrong, and starting
			-- every session by destroying the previous session's account of
			-- itself optimises for tidiness at the cost of the log's only
			-- purpose. Rotation bounds the disk cost without losing the recent
			-- past, and needs no decision from the user.
		local
			l_file, l_previous: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried and then not path.is_empty and then byte_count > Maximum_bytes then
				create l_previous.make_with_name (previous_path)
				if l_previous.exists then
					l_previous.delete
				end
					-- `rename_file', not `change_name': the latter is obsolete and
					-- takes a STRING_8, which forces an implicit narrowing of the
					-- STRING_32 path.
				create l_file.make_with_name (path)
				if l_file.exists then
					l_file.rename_file (previous_path)
				end
				append ("log rotated; previous generation is ocr_capture.log.1")
			end
		rescue
			l_retried := True
			retry
		end

feature {NONE} -- Implementation

	previous_path: STRING_32
			-- Where the outgoing generation is kept.
		do
			create Result.make_from_string (path)
			Result.append_string_general (".1")
		end

	utf8 (a_text: READABLE_STRING_GENERAL): STRING_8
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
		end

feature -- Constants

	Maximum_bytes: INTEGER = 4194304
			-- Four megabytes. A full unattended book run writes on the order of
			-- a hundred kilobytes, so this holds dozens of runs before the
			-- oldest is retired.

end
