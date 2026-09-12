note
	description: "[
		Runs the members-only session helper from the GUI without pulling
		WebView2 into the main binary: it writes the watch URLs to a file,
		spawns ocr_yt_session.exe (which shows its own signed-in browser
		window), and watches the output directory for the results it
		writes - one <id>.json3 per fetched track, <id>.refused per gated
		video, and session.done when the run ends.

		The helper exe ships beside the application; in a dev tree it is
		under EIFGENs/ocr_yt_session/F_code. Both locations are tried.
	]"

class
	OCR_YT_SESSION_LAUNCHER

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
		do
			settings := a_settings
			create work_dir.make_empty
			create last_error.make_empty
		end

feature -- Access

	is_available: BOOLEAN
			-- Was the helper exe found?
		do
			Result := not helper_path.is_empty
		end

	is_running: BOOLEAN
			-- Is a session in progress?
		do
			Result := attached process as p and then not is_finished
		end

	is_finished: BOOLEAN
			-- Has the current (or last) session written session.done?
		do
			Result := not work_dir.is_empty and then (create {RAW_FILE}.make_with_name (done_path)).exists
		end

	last_error: STRING_32

	work_dir: STRING_32
			-- Where this run's urls file and result files live.

feature -- Basic operations

	start (a_ids: ARRAYED_LIST [STRING_8])
			-- Spawn the helper for `a_ids' (video ids); results land in
			-- `work_dir'. False progress is reported through `last_error'.
		require
			available: is_available
			has_ids: not a_ids.is_empty
		local
			l_proc: SIMPLE_ASYNC_PROCESS
			l_dir: DIRECTORY
			l_urls: RAW_FILE
			l_cmd: STRING_32
		do
			last_error.wipe_out
			work_dir := run_folder
			create l_dir.make (work_dir)
			if not l_dir.exists then
				l_dir.recursive_create_dir
			end
			clear_dir
			create l_urls.make_open_write (urls_path)
			across a_ids as ic loop
				l_urls.put_string (utf8 ("https://www.youtube.com/watch?v=" + ic + "%N"))
			end
			l_urls.close
			create l_cmd.make (256)
			l_cmd.append_character ('%"')
			l_cmd.append (helper_path)
			l_cmd.append_string_general ("%" %"")
			l_cmd.append (urls_path)
			l_cmd.append_string_general ("%" %"")
			l_cmd.append (work_dir)
			l_cmd.append_character ('%"')
			create l_proc.make
			l_proc.set_show_window (True)
			l_proc.start (l_cmd)
			if l_proc.is_started then
				process := l_proc
			else
				last_error := {STRING_32} "Could not start the sign-in helper."
			end
		end

	poll
			-- Reap the process once the session is done.
		do
			if attached process as p and then is_finished then
				p.close
				process := Void
			end
		end

	result_of (a_id: STRING_8): TUPLE [kind: INTEGER; content: STRING_32]
			-- After a run: `Kind_track' with the json3 text, `Kind_refused'
			-- with the reason, or `Kind_missing' when neither file exists.
		local
			l_json3, l_refused: RAW_FILE
		do
			create l_json3.make_with_name (result_path (a_id, ".json3"))
			create l_refused.make_with_name (result_path (a_id, ".refused"))
			if l_json3.exists then
				Result := [Kind_track, file_text_utf8 (l_json3)]
			elseif l_refused.exists then
				Result := [Kind_refused, file_text_utf8 (l_refused)]
			else
				Result := [Kind_missing, {STRING_32} ""]
			end
		end

	Kind_track: INTEGER = 1
	Kind_refused: INTEGER = 2
	Kind_missing: INTEGER = 3

feature {NONE} -- Implementation

	settings: OCR_SETTINGS

	process: detachable SIMPLE_ASYNC_PROCESS

	helper_path: STRING_32
			-- Full path of ocr_yt_session.exe, or empty when not found.
		local
			l_dir, l_cand: STRING_32
		once
			create Result.make_empty
			l_dir := exe_dir
			l_cand := joined (l_dir, "ocr_yt_session.exe")
			if (create {RAW_FILE}.make_with_name (l_cand)).exists then
				Result := l_cand
			else
				l_cand := joined (l_dir, "EIFGENs\ocr_yt_session\F_code\simple_ocr_capture.exe")
				if (create {RAW_FILE}.make_with_name (l_cand)).exists then
					Result := l_cand
				end
			end
		end

	exe_dir: STRING_32
			-- Directory of the running application.
		local
			l_args: ARGUMENTS_32
			l_cmd: STRING_32
			i: INTEGER
		do
			create l_args
			create l_cmd.make_from_string_general (l_args.command_name)
			i := l_cmd.last_index_of ('\', l_cmd.count)
			if i > 0 then
				Result := l_cmd.substring (1, i - 1)
			else
				create Result.make_from_string_general (".")
			end
		end

	run_folder: STRING_32
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			create Result.make (64)
			if attached l_env.item ("APPDATA") as al and then not al.is_empty then
				Result.append_string_general (al)
			else
				Result.append_character ('.')
			end
			Result.append_string_general ("\simple_ocr_capture\yt_session_run")
		end

	urls_path: STRING_32
		do
			Result := joined (work_dir, "urls.txt")
		end

	done_path: STRING_32
		do
			Result := joined (work_dir, "session.done")
		end

	result_path (a_id: STRING_8; a_ext: STRING_8): STRING_32
		do
			Result := joined (work_dir, a_id + a_ext)
		end

	joined (a_dir: READABLE_STRING_GENERAL; a_leaf: READABLE_STRING_GENERAL): STRING_32
		do
			create Result.make_from_string_general (a_dir)
			if not Result.is_empty and then Result.item (Result.count) /= '\' then
				Result.append_character ('\')
			end
			Result.append_string_general (a_leaf)
		end

	clear_dir
			-- Remove stale result files from a previous run.
		local
			l_dir: DIRECTORY
			l_f: RAW_FILE
			l_path: STRING_32
		do
			create l_dir.make (work_dir)
			if l_dir.exists then
				across l_dir.entries as e loop
					if not e.name.same_string_general (".") and then not e.name.same_string_general ("..") then
						l_path := joined (work_dir, e.name)
						create l_f.make_with_name (l_path)
						if l_f.exists and then l_f.is_writable then
							l_f.delete
						end
					end
				end
			end
		end

	file_text_utf8 (a_file: RAW_FILE): STRING_32
			-- Contents of `a_file' decoded from UTF-8.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_file.open_read
				a_file.read_stream (a_file.count)
				Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_file.last_string)
				a_file.close
			else
				create Result.make_empty
			end
		rescue
			l_retried := True
			retry
		end

	utf8 (a_text: READABLE_STRING_GENERAL): STRING_8
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
		end

invariant
	dirs_attached: work_dir /= Void and last_error /= Void

end
