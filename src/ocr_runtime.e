note
	description: "[
		Starts the local Ollama server this application talks to, so a fresh
		boot needs neither a tray icon nor a console window.

		Two environment variables are forced on the child rather than trusted
		from the machine:

		  OLLAMA_HOST     host:port taken from `settings.endpoint'. Ollama's own
		                  desktop app forces 0.0.0.0:11434 from its private
		                  settings database and ignores this variable, so the
		                  server it starts is not necessarily the one wanted
		                  here - and on a machine with a WSL Ollama, 11434 is
		                  already answered by a different install with a
		                  different model store.
		  OLLAMA_ORIGINS  a machine-wide value of "app://obsidian.md" (no '*',
		                  and no scheme gin-cors accepts) makes the server
		                  panic on startup before it ever listens. Inheriting
		                  that is indistinguishable, from here, from Ollama not
		                  being installed at all.

		simple_process creates the child with a null environment block, so
		setting the two on THIS process is what hands them over.
	]"
	design: "[
		The server's output is redirected to a log file through cmd rather than
		left on the pipe simple_process inherits to the child. Nothing in this
		application drains that pipe, and a long-running server that logged
		past the 64 KB buffer would block forever on a write - which would look
		like the model hanging mid-session.
	]"

class
	OCR_RUNTIME

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
			-- Prepare to start the runtime described by `a_settings'.
		do
			settings := a_settings
			create last_error.make_empty
			create executable_path.make_empty
		ensure
			settings_set: settings = a_settings
			no_error: last_error.is_empty
			nothing_located: not is_executable_found
		end

feature -- Access

	last_error: STRING_32
			-- Why the most recent `start' failed; empty when it succeeded.

	executable_path: STRING_32
			-- ollama.exe located by the most recent `start'; empty when none was.

	log_path: STRING_32
			-- File the started server's output is redirected to.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			create Result.make (72)
			if attached l_env.item ("LOCALAPPDATA") as al_local and then not al_local.is_empty then
				Result.append_string_general (al_local)
				Result.append_string_general ("\Ollama\simple_ocr_serve.log")
			else
				Result.append_string_general ("simple_ocr_serve.log")
			end
		ensure
			non_empty: not Result.is_empty
		end

feature -- Status report

	is_started: BOOLEAN
			-- Was a server spawned by `start' that has not exited?
		do
			Result := attached server_process as al_process and then al_process.is_running
		end

	is_executable_found: BOOLEAN
			-- Did the most recent `start' locate ollama.exe?
		do
			Result := not executable_path.is_empty
		end

feature -- Basic operations

	prepare
			-- Locate the executable and force the environment, without starting
			-- anything.
			--
			-- Called once at startup so that every later child - `ollama pull'
			-- included - inherits the corrected OLLAMA_HOST and reaches the same
			-- server this application talks to, whether or not `start' was the
			-- thing that brought it up.
		do
			executable_path := found_executable
			apply_environment
		end

	pull_command (a_model: READABLE_STRING_8): STRING_32
			-- Command line that installs `a_model', through the located
			-- executable rather than through PATH.
		require
			model_not_empty: not a_model.is_empty
		do
			create Result.make (96)
			if is_executable_found then
				Result.append_character ('%"')
				Result.append (executable_path)
				Result.append_character ('%"')
			else
				Result.append_string_general ("ollama")
			end
			Result.append_string_general (" pull ")
			Result.append_string_general (a_model)
		ensure
			non_empty: not Result.is_empty
		end

	start: BOOLEAN
			-- Locate ollama.exe and spawn `serve', forcing the environment the
			-- server needs. True when the child was created; the server still
			-- needs seconds after that before it accepts connections, so the
			-- caller must poll rather than assume readiness.
		local
			l_process: SIMPLE_ASYNC_PROCESS
		do
			last_error.wipe_out
			executable_path := found_executable

			if not is_executable_found then
				last_error := {STRING_32} "Could not find ollama.exe. Install Ollama from https://ollama.com, then use Check Setup again."
			else
				apply_environment
				ensure_log_directory
				create l_process.make
				l_process.set_show_window (False)
				l_process.start (serve_command)
				if l_process.is_started and then l_process.was_started_successfully then
					server_process := l_process
					Result := True
				elseif attached l_process.last_error as al_error and then not al_error.is_empty then
					last_error := al_error.twin
				else
					last_error := {STRING_32} "Could not start the Ollama server."
				end
			end
		ensure
			error_iff_failed: Result = last_error.is_empty
		end

	release
			-- Drop the handle to the spawned server, leaving it running.
			--
			-- Deliberately not killed: Ollama keeps the model resident for its
			-- keep-alive window, so a later session's first capture is warm
			-- instead of paying the cold load again.
		do
			if attached server_process as al_process then
				al_process.close
				server_process := Void
			end
		ensure
			handle_dropped: not is_started
		end

feature {NONE} -- Implementation

	serve_command: STRING_32
			-- `cmd /c' line running the located server with its output
			-- redirected, quoted so an install path containing spaces survives.
		require
			executable_found: is_executable_found
		do
			create Result.make (192)
			Result.append_string_general ("cmd.exe /c %"%"")
			Result.append (executable_path)
			Result.append_string_general ("%" serve >>%"")
			Result.append (log_path)
			Result.append_string_general ("%" 2>&1%"")
		ensure
			non_empty: not Result.is_empty
		end

	apply_environment
			-- Force the variables the child server must be started with.
		do
			put_variable ("OLLAMA_HOST", host_and_port)
			put_variable ("OLLAMA_ORIGINS", Safe_origins)
		end

	put_variable (a_name, a_value: READABLE_STRING_8)
			-- Set `a_name' to `a_value' in this process, for children to inherit.
			--
			-- A failure needs no branch of its own: it surfaces as the server
			-- not coming up, which the caller's poll already reports.
		require
			name_not_empty: not a_name.is_empty
		local
			l_name, l_value: C_STRING
		do
			create l_name.make (a_name)
			create l_value.make (a_value)
			c_put_environment (l_name.item, l_value.item)
		end

	host_and_port: STRING_8
			-- "host:port" from `settings.endpoint'.
		local
			l_http: OCR_HTTP
		do
			create l_http.make
			create Result.make (24)
			if l_http.parse_url (settings.endpoint) then
				Result.append (l_http.parsed_host)
				Result.append_character (':')
				Result.append (l_http.parsed_port.out)
			else
				Result.append (Fallback_host_and_port)
			end
		ensure
			non_empty: not Result.is_empty
		end

	found_executable: STRING_32
			-- First ollama.exe that exists among the known install locations,
			-- or empty when none does.
			--
			-- PATH is deliberately not consulted. The Ollama installer does not
			-- add itself to it, and a bare "ollama" resolves to the WSL shim on
			-- a machine that has one - which would start a server in another
			-- filesystem, against another model store, and report success.
		local
			l_candidates: ARRAYED_LIST [STRING_32]
			l_file: RAW_FILE
		do
			create Result.make_empty
			l_candidates := candidate_paths
			from
				l_candidates.start
			until
				l_candidates.after or not Result.is_empty
			loop
				create l_file.make_with_name (l_candidates.item)
				if l_file.exists and then not l_file.is_directory then
					Result := l_candidates.item.twin
				end
				l_candidates.forth
			end
		end

	candidate_paths: ARRAYED_LIST [STRING_32]
			-- Known Ollama install locations, most likely first.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create Result.make (4)
			create l_env
			if attached l_env.item ("LOCALAPPDATA") as al_local and then not al_local.is_empty then
				Result.extend (joined (al_local, "\Programs\Ollama\ollama.exe"))
			end
			if attached l_env.item ("ProgramFiles") as al_files and then not al_files.is_empty then
				Result.extend (joined (al_files, "\Ollama\ollama.exe"))
			end
			if attached l_env.item ("ProgramW6432") as al_wide and then not al_wide.is_empty then
				Result.extend (joined (al_wide, "\Ollama\ollama.exe"))
			end
		ensure
			attached_result: Result /= Void
		end

	joined (a_root: READABLE_STRING_GENERAL; a_tail: READABLE_STRING_8): STRING_32
			-- `a_root' followed by `a_tail'.
		do
			create Result.make (a_root.count + a_tail.count)
			Result.append_string_general (a_root)
			Result.append_string_general (a_tail)
		ensure
			non_empty: not Result.is_empty
		end

	ensure_log_directory
			-- Create the folder `log_path' lives in, if it is missing.
			--
			-- Without it the redirection fails, cmd exits at once, and the
			-- server never starts even though the child was created.
		local
			l_dir: DIRECTORY
			l_path: STRING_32
			l_cut: INTEGER
		do
			l_path := log_path
			l_cut := l_path.last_index_of ('\', l_path.count)
			if l_cut > 1 then
				create l_dir.make_with_name (l_path.substring (1, l_cut - 1))
				if not l_dir.exists then
					l_dir.recursive_create_dir
				end
			end
		end

	server_process: detachable SIMPLE_ASYNC_PROCESS
			-- The spawned `ollama serve' child, while a handle to it is held.

	settings: OCR_SETTINGS

feature {NONE} -- Constants

	Safe_origins: STRING_8 = "http://localhost,https://localhost,http://127.0.0.1,https://127.0.0.1,app://*,file://*,tauri://*"
			-- CORS origins forced on the child.
			--
			-- Every entry either contains '*' or starts with a scheme gin-cors
			-- accepts. One that does neither makes the server panic before it
			-- listens; "app://*" covers the Obsidian case that the offending
			-- machine-wide value was set for.

	Fallback_host_and_port: STRING_8 = "127.0.0.1:11435"
			-- Used when `settings.endpoint' cannot be parsed.

feature {NONE} -- Externals

	c_put_environment (a_name, a_value: POINTER)
			-- SetEnvironmentVariable on this process, so children inherit it.
		external
			"C inline use %"windows.h%""
		alias
			"SetEnvironmentVariableA ((LPCSTR) $a_name, (LPCSTR) $a_value);"
		end

invariant
	error_attached: last_error /= Void
	path_attached: executable_path /= Void
	found_definition: is_executable_found = not executable_path.is_empty

end
