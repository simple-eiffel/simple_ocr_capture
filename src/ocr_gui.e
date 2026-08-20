note
	description: "[
		Assembles and runs the interface: settings window, progress strip,
		capture cycle, global hotkey, and the single timer that services them.

		Separate from OCR_APP so that every attribute here is set by one
		creation procedure. Holding them in the root class, whose `make'
		branches into a GUI-less worker mode, cannot satisfy void safety.
	]"

class
	OCR_GUI

create
	make

feature {NONE} -- Initialization

	make
			-- Build the interface and register the hotkey.
		local
			l_log: OCR_LOG_FILE
		do
			create application
			create settings
			settings.load

				-- Once per session, before anything writes to it. Bounds the log
				-- on disk without clearing it at startup - the previous session's
				-- account of itself is exactly what someone opening this file
				-- after a failed run needs to read.
				--
				-- Via a local, NOT `(create {OCR_LOG_FILE}).rotate_if_large' on
				-- the line after a call: a newline does not end a call in Eiffel,
				-- so that parses as an ARGUMENT to the preceding `settings.load'
				-- and fails with VUAR(1) blaming a routine that is not at fault.
			create l_log
			l_log.rotate_if_large

			create hotkey.make
			create preflight.make (settings)
			create runtime.make (settings)
				-- Before anything spawns a child: `prepare' is what puts the
				-- corrected OLLAMA_HOST and OLLAMA_ORIGINS into this process,
				-- and children inherit the environment as it stands when they
				-- are created.
			runtime.prepare
			create health.make (settings, runtime, preflight)
			create status_strip.make (settings)
			create cycle.make (settings, status_strip)
			create auto_run.make (settings, cycle, status_strip)
			create main_window.make (settings, cycle, status_strip)
			create ticker.make_with_interval (Tick_ms)
			create reported_error.make_empty

				-- Overlays out of the frame for the instant of each screenshot,
				-- and back immediately after, so an outline can be left up for a
				-- whole run without appearing in a single page image.
			cycle.set_shutter_actions (agent main_window.suspend_outlines,
				agent main_window.resume_outlines)

				-- Every finding the running application records also appears in
				-- the list, whatever noticed it.
			cycle.findings.set_notify (agent main_window.add_finding)

			main_window.set_hotkey_changed_action (agent register_hotkey)
			main_window.set_quit_action (agent shut_down)
			main_window.set_check_setup_action (agent run_setup_check)
			main_window.set_auto_start_action (agent start_auto_run)
			main_window.set_auto_pause_action (agent pause_auto_run)
			main_window.set_auto_stop_action (agent stop_auto_run)
			status_strip.set_transport_action (agent on_transport)
			ticker.actions.extend (agent on_tick)

			register_hotkey

			if settings.show_strip then
				status_strip.show
				status_strip.set_stage ({OCR_STATUS_STRIP}.Stage_ready, "READY")
			end
		end

feature -- Basic operations

	launch
			-- Show the window and enter the event loop.
		do
			main_window.show
				-- Checked after the window is up, so a missing runtime is
				-- reported in the interface rather than to nobody.
			run_preflight
			application.launch
		end

feature {NONE} -- Setup checks

	run_preflight
			-- Verify the runtime and model, starting the server when it is down
			-- and offering to install the model when it is missing.
		do
			if is_pulling then
				main_window.report ("Model download already in progress.")
			elseif is_awaiting_runtime then
				main_window.report ("Still starting the Ollama server...")
			else
				preflight.refresh
				if preflight.is_runtime_reachable then
					report_and_offer_model
				else
						-- Nothing is answering: bring the server up ourselves
						-- rather than telling the user to go and find a tray icon.
					start_runtime
				end
			end
		end

	start_runtime
			-- Spawn the Ollama server, then wait for it on the timer.
			--
			-- Waited for on the timer rather than here: the server takes several
			-- seconds to enumerate GPUs before it listens, and blocking the event
			-- loop for that long during startup would look like a hang.
		do
			if runtime.start then
				is_awaiting_runtime := True
				runtime_ticks := 0
				main_window.report ("Ollama is not running - starting it. This takes a few seconds.")
			else
				main_window.report (runtime.last_error)
			end
		end

	poll_runtime
			-- Watch for the spawned server to start answering.
		local
			l_seconds: INTEGER
			l_message: STRING_32
		do
			runtime_ticks := runtime_ticks + 1
				-- Once a second: `refresh' is a network round trip, and doing it
				-- twenty times a second would be a probe flood.
			if runtime_ticks \\ Ticks_per_second = 0 then
				l_seconds := runtime_ticks // Ticks_per_second
				preflight.refresh
				if preflight.is_runtime_reachable then
					is_awaiting_runtime := False
					report_and_offer_model
				elseif l_seconds >= Runtime_start_timeout_seconds then
					is_awaiting_runtime := False
					create l_message.make_from_string_general ("The Ollama server did not answer within ")
					l_message.append_string_general (Runtime_start_timeout_seconds.out)
					l_message.append_string_general (" seconds. See ")
					l_message.append (runtime.log_path)
					main_window.report (l_message)
				else
					create l_message.make_from_string_general ("Starting Ollama server... ")
					l_message.append_string_general (l_seconds.out)
					l_message.append_string_general ("s")
					main_window.report (l_message)
				end
			end
		end

	report_and_offer_model
			-- Report the diagnosis, and offer the download when the model is
			-- absent.
		do
			main_window.report (preflight.diagnosis)
			if preflight.is_runtime_reachable and then not preflight.is_model_present then
				offer_model_download
			end
		end

	offer_model_download
			-- Ask whether to pull the configured model now.
		local
			l_question: EV_CONFIRMATION_DIALOG
			l_prompt: STRING_32
		do
			create l_prompt.make_from_string_general ("The model ")
			l_prompt.append_string_general (settings.model)
			l_prompt.append_string_general (" is not installed.%N%NDownload it now? This is roughly 9.5 GB and will take a while. You can keep using the rest of the application, but captures will fail until it finishes.")

			create l_question.make_with_text (l_prompt)
			l_question.show_modal_to_window (main_window.window)
			if attached l_question.selected_button as al_button
				and then al_button.same_string_general ("OK")
			then
				start_pull
			end
		end

feature {NONE} -- Auto-advance

	start_auto_run
			-- Begin or resume an unattended run.
		do
			if auto_run.is_paused then
				auto_run.resume
				sync_auto_controls
			elseif not auto_run.is_ready_to_start then
				main_window.report (auto_run.blocking_reason)
			elseif not main_window.is_output_folder_ready then
					-- Already reported by the check itself; nothing to add.
			elseif not health_permits_auto_run then
					-- Refused rather than started: an unattended run against a
					-- dead model would click its way through the whole book
					-- writing failures, and the advance check cannot catch that
					-- because the pages really are turning.
				main_window.report ({STRING_32} "Not starting: " + health.failure_summary)
			else
				auto_run.start
				settings.set_auto_advance (True)
				sync_auto_controls
				main_window.report ("Auto-advance started. Press Stop, or the strip's square, to end it.")
			end
		end

	pause_auto_run
			-- Suspend the run after the step in flight.
		do
			auto_run.pause
			sync_auto_controls
			main_window.report (auto_run.last_message)
		end

	stop_auto_run
			-- End the run.
		do
			auto_run.stop
			settings.set_auto_advance (False)
			sync_auto_controls
			main_window.report (auto_run.last_message)
		end

	on_transport (a_command: INTEGER)
			-- Handle play/pause/stop pressed on the always-on-top strip.
		do
			inspect a_command
			when {OCR_STATUS_STRIP}.Transport_play then start_auto_run
			when {OCR_STATUS_STRIP}.Transport_pause then pause_auto_run
			else stop_auto_run
			end
		end

	poll_auto_run
			-- Drive the unattended run and report what it is doing.
		local
			l_was_running: BOOLEAN
		do
			l_was_running := auto_run.is_running
			auto_run.poll

			if not auto_run.last_message.same_string (reported_auto_message) then
				create reported_auto_message.make_from_string (auto_run.last_message)
					-- `status_line', not `last_message': it carries the rates on
					-- whatever the current step is saying, so they stay readable
					-- through the whole cycle instead of for the one instant the
					-- per-page summary is up.
				main_window.report (auto_run.status_line)
			end

				-- Stopped itself: the page failed to turn, or a capture failed.
			if l_was_running and not auto_run.is_running then
				sync_auto_controls
				if not auto_run.last_error.is_empty then
					settings.set_auto_advance (False)
					announce_auto_stop
				end
			end
		end

	announce_auto_stop
			-- Tell the user, loudly, that the unattended run ended early.
			--
			-- A modal rather than a status line: the whole point of the run is
			-- that nobody is watching the window, so a line of text at the
			-- bottom of a covered-up dialog would be found an hour later.
		local
			l_dialog: EV_INFORMATION_DIALOG
			l_text: STRING_32
		do
			create l_text.make_from_string_general ("Auto-advance stopped.%N%N")
			l_text.append (auto_run.last_error)
			l_text.append_string_general ("%N%NPages captured this run: ")
			l_text.append_string_general (auto_run.pages_done.out)

			status_strip.set_stage ({OCR_STATUS_STRIP}.Stage_ready, "AUTO STOPPED")
			create l_dialog.make_with_text (l_text)
			l_dialog.set_title ("Simple OCR Capture - Auto-advance")
			l_dialog.show_modal_to_window (main_window.window)
		end

	sync_auto_controls
			-- Keep both sets of transport controls showing the same state.
		do
			main_window.show_auto_state (auto_run.is_running, auto_run.is_paused)
			status_strip.set_transport_state (auto_run.is_running, auto_run.is_paused)
		end

	health_permits_auto_run: BOOLEAN
			-- Is the model up right now?
			--
			-- The cheap check only: the deep one loads the model, and making the
			-- user wait a minute at the press of Start would be worse than
			-- letting the first page pay that cost as it always has.
		do
			health.run_quick
			Result := health.is_healthy
		end

feature {NONE} -- Health

	run_setup_check
			-- Check everything, show the result, and offer the obvious repair.
		local
			l_dialog: EV_INFORMATION_DIALOG
		do
			if is_pulling then
				main_window.report ("Model download already in progress.")
			elseif is_awaiting_runtime then
				main_window.report ("Still starting the Ollama server...")
			else
					-- Painted before the round trip, not after: the test
					-- recognition blocks the event loop while a cold model
					-- loads, and a window that redraws nothing for a minute
					-- with no explanation reads as a crash.
				main_window.report ("Checking setup - a cold model load can take up to a minute...")
				health.run_full
				main_window.report (health.report_headline)

				create l_dialog.make_with_text (health.report)
				l_dialog.set_title ("Simple OCR Capture - Setup Check")
				l_dialog.show_modal_to_window (main_window.window)

					-- `was_healthy' is refreshed here so that a check run by hand
					-- re-arms the monitor's alert instead of leaving it primed to
					-- fire about a fault the user has just been shown.
				was_healthy := health.is_healthy
				if health.is_healthy then
					is_alert_suppressed := False
				elseif not health.is_server_reachable then
					offer_restart
				elseif not health.is_model_present then
					offer_model_download
				end
			end
		end

	poll_strip_health
			-- Put the progress strip back if it has gone missing.
			--
			-- It disappeared during a live run and could not be recovered from
			-- the interface: the checkbox still claimed it was on. Rather than
			-- guess at a cause that was never identified, this restates the
			-- invariant - if the user asked for the strip, the strip should be
			-- on screen - and repairs it a couple of times a second.
		do
			strip_ticks := strip_ticks + 1
			if strip_ticks >= Strip_check_ticks then
				strip_ticks := 0
				if settings.show_strip then
					status_strip.ensure_visible
				end
			end
		end

	poll_health
			-- Notice the runtime going away mid-session.
		do
			monitor_ticks := monitor_ticks + 1
			if monitor_ticks >= Monitor_period_ticks then
				monitor_ticks := 0
					-- Deferred while busy: a modal raised mid-capture would stop
					-- the tick that polls the worker, stalling the very capture
					-- the user is waiting on.
				if not cycle.is_busy and not is_pulling and not is_awaiting_runtime then
					health.run_quick
					if health.is_healthy then
						was_healthy := True
						is_alert_suppressed := False
					elseif was_healthy and not is_alert_suppressed then
							-- Only on the transition: a fault that was already
							-- reported must not reopen a dialog every 15 seconds.
						was_healthy := False
						main_window.report (health.failure_summary)
						offer_restart
					end
				end
			end
		end

	offer_restart
			-- Ask whether to bring the runtime back up; if not, whether to quit.
			--
			-- Two questions rather than one three-button dialog: Vision2's
			-- confirmation dialog offers OK and Cancel, and the second question
			-- only arises once the first is declined.
		local
			l_restart, l_quit: EV_CONFIRMATION_DIALOG
			l_prompt: STRING_32
		do
			create l_prompt.make_from_string_general ("The OCR model is not available.%N%N")
			l_prompt.append (health.failure_summary)
			l_prompt.append_string_general ("%N%NStart it back up now?")

			create l_restart.make_with_text (l_prompt)
			l_restart.set_title ("Simple OCR Capture")
			l_restart.show_modal_to_window (main_window.window)

			if attached l_restart.selected_button as al_restart
				and then al_restart.same_string_general ("OK")
			then
				start_runtime
			else
				create l_quit.make_with_text ({STRING_32} "Captures cannot work while the OCR model is down.%N%NClose Simple OCR Capture now?")
				l_quit.set_title ("Simple OCR Capture")
				l_quit.show_modal_to_window (main_window.window)

				if attached l_quit.selected_button as al_quit
					and then al_quit.same_string_general ("OK")
				then
					shut_down
				else
						-- Left running by choice: stop asking, or the question
						-- becomes a nag every fifteen seconds.
					is_alert_suppressed := True
					main_window.report ("Left running with the OCR model down. Use Check Setup when you want it back.")
				end
			end
		end

	start_pull
			-- Launch `ollama pull' detached.
			--
			-- Detached and polled rather than awaited: the download moves
			-- gigabytes, and blocking the event loop for that long would look
			-- exactly like a hang.
		local
			l_process: SIMPLE_ASYNC_PROCESS
		do
			create l_process.make
			l_process.set_show_window (False)
			l_process.start (runtime.pull_command (settings.model))
			if l_process.is_started then
				pull_process := l_process
				pull_ticks := 0
				main_window.report ("Downloading model... this window stays usable.")
			else
				main_window.report ("Could not start 'ollama pull'. Is Ollama on the PATH?")
			end
		end

	is_pulling: BOOLEAN
			-- Is a model download running?
		do
			Result := attached pull_process as al_process and then not al_process.has_finished
		end

	poll_pull
			-- Report download progress and completion.
		local
			l_seconds: INTEGER
		do
			if attached pull_process as al_process then
				if al_process.has_finished then
					al_process.close
					pull_process := Void
					preflight.refresh
					if preflight.is_model_present then
						main_window.report ("Model installed. Ready to capture.")
					else
						main_window.report ("Model download finished but the model is still not listed. Check the Ollama logs.")
					end
				else
					pull_ticks := pull_ticks + 1
						-- Once a second is plenty for a multi-minute download.
					if pull_ticks \\ Ticks_per_second = 0 then
						l_seconds := pull_ticks // Ticks_per_second
						main_window.report ("Downloading model... " + l_seconds.out + "s elapsed.")
					end
				end
			end
		end

feature {NONE} -- Timer

	on_tick
			-- Service the hotkey and any running cycle. Runs 20x a second.
			--
			-- Guarded by a rescue: this agent runs from the Vision2 event loop,
			-- and an exception escaping it takes the whole application down
			-- silently, mid-reading-session, with no console to report why.
			-- A failed cycle must cost one capture, not the program.
		local
			l_failed: BOOLEAN
		do
			if l_failed then
				cycle.log ("on_tick raised an exception; cycle reset")
				cycle.reset_to_ready
			else
			if hotkey.taken_presses > 0 then
					-- A burst collapses to one capture: leaning on the key must
					-- not queue a dozen captures of the same page, and a press
					-- arriving mid-cycle is meaningless.
					-- Ignored while a run is in flight: a manual capture landing
					-- between the driver's steps would be attributed to the wrong
					-- page and would break the did-it-advance comparison.
				if not cycle.is_busy and not auto_run.is_running
					and then main_window.is_output_folder_ready
				then
					cycle.trigger
				end
			end

			cycle.poll
				poll_pull
				poll_auto_run
					-- Cheap when no outline is shown, which is almost always.
				main_window.animate_outlines
				poll_strip_health

				if is_awaiting_runtime then
					poll_runtime
				elseif not auto_run.is_running then
						-- Suspended during a run: `run_quick' is a blocking probe,
						-- and firing one between pages would add a stall to every
						-- page turn. A dead model shows up as the capture failing,
						-- which stops the run anyway.
					poll_health
				end

				if not cycle.last_error.is_empty and then not reported_error.same_string (cycle.last_error) then
				create reported_error.make_from_string (cycle.last_error)
				main_window.report (cycle.last_error)
			elseif cycle.last_error.is_empty and then not reported_error.is_empty then
					create reported_error.make_empty
				end
			end
		rescue
			l_failed := True
			retry
		end

feature {NONE} -- Hotkey

	register_hotkey
			-- Claim the configured combination, reporting refusal clearly.
		local
			l_message: STRING_32
		do
			if settings.hotkey_modifiers = 0 then
				create l_message.make_from_string_general (
					"Hotkey NOT registered: it needs at least one of Ctrl, Alt or Shift. A bare key would be taken from every application on the system.")
			elseif hotkey.register (settings.hotkey_modifiers, settings.hotkey_key) then
				create l_message.make_from_string_general ("Hotkey active: ")
				l_message.append (hotkey_description)
			else
				create l_message.make_from_string_general ("Could not claim ")
				l_message.append (hotkey_description)
				l_message.append_string_general (" - another application owns it. Choose a different combination.")
			end
			main_window.report (l_message)
		end

	hotkey_description: STRING_32
			-- Human-readable form of the configured hotkey.
		do
			create Result.make (24)
			if (settings.hotkey_modifiers & {OCR_HOTKEY}.Mod_control) /= 0 then
				Result.append_string_general ("Ctrl+")
			end
			if (settings.hotkey_modifiers & {OCR_HOTKEY}.Mod_alt) /= 0 then
				Result.append_string_general ("Alt+")
			end
			if (settings.hotkey_modifiers & {OCR_HOTKEY}.Mod_shift) /= 0 then
				Result.append_string_general ("Shift+")
			end
			if settings.hotkey_key >= 0x41 and settings.hotkey_key <= 0x5A then
				Result.append_string_general (settings.hotkey_key.to_integer_32.to_character_8.out)
			elseif settings.hotkey_key >= 0x70 and settings.hotkey_key <= 0x7B then
				Result.append_string_general ("F" + (settings.hotkey_key.to_integer_32 - 0x70 + 1).out)
			else
				Result.append_string_general ("?")
			end
		end

feature {NONE} -- Shutdown

	shut_down
			-- Release the system-wide hotkey and quit.
			--
			-- Releasing matters: a hotkey left registered stays claimed for the
			-- lifetime of the process, and an orphaned registration would block
			-- the combination for every other application.
		do
			hotkey.cleanup
			auto_run.stop
			settings.store
				-- Releases the handle without killing the server: the model stays
				-- resident for Ollama's keep-alive window, so the next session
				-- starts warm.
			runtime.release
			status_strip.hide
			application.destroy
		end

feature {NONE} -- Constants

	Tick_ms: INTEGER = 50
			-- Timer period. Below human perception for the strip, and the work
			-- per tick is an interlocked read plus a process-status check.

	Ticks_per_second: INTEGER = 20
			-- Derived from `Tick_ms'; keep the two in step.

	Strip_check_ticks: INTEGER = 40
			-- Two seconds. Frequent enough that a vanished strip comes back
			-- before the user goes looking for it, cheap enough to ignore.

	Monitor_period_ticks: INTEGER = 300
			-- Ticks between liveness checks: 15 seconds at `Tick_ms'.
			--
			-- Long enough that the probe is not traffic in its own right, short
			-- enough that a server that died is noticed before the user has
			-- flipped several pages into a lost session.

	Runtime_start_timeout_seconds: INTEGER = 60
			-- How long a spawned server gets to answer before giving up.
			--
			-- Generous: the server enumerates GPUs before it listens, and a
			-- first run after a driver update has been seen to take far longer
			-- than the few seconds it normally needs.

feature {NONE} -- State

	application: EV_APPLICATION
	settings: OCR_SETTINGS
	status_strip: OCR_STATUS_STRIP
	cycle: OCR_CYCLE
	main_window: OCR_MAIN_WINDOW
	ticker: EV_TIMEOUT
	hotkey: OCR_HOTKEY
	preflight: OCR_PREFLIGHT
	runtime: OCR_RUNTIME
	health: OCR_HEALTH
	auto_run: OCR_AUTO_RUN

	reported_auto_message: STRING_32
			-- Last auto-advance line shown, so it is not repainted every tick.
		attribute
			create Result.make_empty
		end

	is_awaiting_runtime: BOOLEAN
			-- Is a spawned server being waited on?

	runtime_ticks: INTEGER
			-- Timer ticks since the server was spawned.

	strip_ticks: INTEGER
			-- Timer ticks since the strip was last checked for existence.

	monitor_ticks: INTEGER
			-- Timer ticks since the last liveness check.

	was_healthy: BOOLEAN
			-- Did the previous liveness check pass? Gates the alert so it fires
			-- on the transition into trouble rather than on every check.

	is_alert_suppressed: BOOLEAN
			-- Has the user chosen to keep running with the model down?

	pull_process: detachable SIMPLE_ASYNC_PROCESS
			-- The `ollama pull' child, while one is running.

	pull_ticks: INTEGER
			-- Timer ticks since the download started.

	reported_error: STRING_32
			-- Last error shown, so it is not repainted twenty times a second.

end
