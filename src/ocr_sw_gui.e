note
	description: "[
		The composition root on the pure route: same assembly and the
		same agent seams as the Vision2 OCR_GUI it succeeds - window,
		strip, cycle, auto-run, hotkey, health - but the clock is
		simple_shell's app-settable FAST TIMER (event 25, every 50ms,
		armed on the first heartbeat once the window is up), and every
		modal is the toolkit's own drawn dialog, so each confirm flow
		is a continuation.

		The shell-event router: while the region selector is active,
		overlay events (31..35) go to it; the strip's (21..23) go to
		the strip; 25 is the fast tick.
	]"

class
	OCR_SW_GUI

create
	make

feature {NONE} -- Initialization

	make
		local
			l_log: OCR_LOG_FILE
		do
			create settings
			settings.load
			create l_log
			l_log.rotate_if_large

			create hotkey.make
			create preflight.make (settings)
			create runtime.make (settings)
			runtime.prepare
			create health.make (settings, runtime, preflight)
			create status_strip.make (settings)
			create cycle.make (settings, status_strip)
			create auto_run.make (settings, cycle, status_strip)
			create main_window.make (settings, cycle, status_strip)
			create reported_error.make_empty
			create reported_auto_message.make_empty

			cycle.set_shutter_actions (agent main_window.suspend_outlines,
				agent main_window.resume_outlines)
			cycle.findings.set_notify (agent main_window.add_finding)

			main_window.set_hotkey_changed_action (agent register_hotkey)
			main_window.set_quit_action (agent shut_down)
			main_window.set_check_setup_action (agent run_setup_check)
			main_window.set_auto_start_action (agent start_auto_run)
			main_window.set_auto_pause_action (agent pause_auto_run)
			main_window.set_auto_stop_action (agent stop_auto_run)
			status_strip.set_transport_action (agent on_transport)

			main_window.window.set_on_tick (agent on_heartbeat)
			main_window.window.set_on_shell_event (agent on_shell_event)

			register_hotkey
			if settings.show_strip then
				status_strip.show
				status_strip.set_stage ({OCR_SW_STRIP}.Stage_ready, "READY")
			end
		end

feature -- Basic operations

	launch
			-- Enter the pump; preflight runs from the first
			-- heartbeat, once the window exists to report into.
		do
			main_window.window.run
		end

feature {NONE} -- The clock

	on_heartbeat
			-- The 250ms heartbeat: arms the 50ms fast tick once the
			-- native window exists, then stays out of the way.
		do
			if not is_fast_timer_armed then
				is_fast_timer_armed := True
				main_window.window.set_fast_timer (Tick_ms)
				run_preflight
			end
		end

	on_shell_event (a_type, a_x, a_y: INTEGER)
			-- The router for app-owned windows and the fast tick.
		do
			if a_type = 25 then
				on_tick
			elseif a_type >= 31 and a_type <= 35 then
				if main_window.selector.is_active then
					main_window.selector.handle_event (a_type, a_x, a_y)
				end
			elseif a_type >= 21 and a_type <= 23 then
				status_strip.handle_event (a_type, a_x, a_y)
			end
		end

	on_tick
			-- Service the hotkey and any running cycle, 20x a second.
			-- Rescue-guarded: a failed cycle must cost one capture,
			-- not the program.
		local
			l_failed: BOOLEAN
		do
			if l_failed then
				cycle.log ("on_tick raised an exception; cycle reset")
				cycle.reset_to_ready
			else
				if hotkey.taken_presses > 0 then
						-- a burst collapses to one capture; ignored
						-- while a run is in flight
					if not cycle.is_busy and not auto_run.is_running
						and then main_window.is_output_folder_ready
					then
						cycle.trigger
					end
				end
				cycle.poll
				poll_pull
				poll_auto_run
				poll_strip_health
				if is_awaiting_runtime then
					poll_runtime
				elseif not auto_run.is_running then
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

feature {NONE} -- Setup checks

	run_preflight
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
					start_runtime
				end
			end
		end

	start_runtime
			-- Spawn the server; wait for it on the tick - it takes
			-- seconds to enumerate GPUs, and blocking would look
			-- like a hang.
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
		local
			l_seconds: INTEGER
			l_message: STRING_32
		do
			runtime_ticks := runtime_ticks + 1
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
					main_window.report ("Starting Ollama server... " + l_seconds.out + "s")
				end
			end
		end

	report_and_offer_model
		do
			main_window.report (preflight.diagnosis)
			if preflight.is_runtime_reachable and then not preflight.is_model_present then
				offer_model_download
			end
		end

	offer_model_download
		local
			d: SW_DIALOG
		do
			create d.make ({SW_DIALOG}.Kind_info, "Install model",
				{STRING_32} "The model " + settings.model
				+ {STRING_32} " is not installed.%N%NDownload it now? This is roughly 9.5 GB and will take a while. You can keep using the rest of the application, but captures will fail until it finishes.")
			d.add_button ("Not now", False, Void)
			d.add_button ("Download", True, agent start_pull)
			main_window.window.show_dialog (d)
		end

	start_pull
			-- Detached and polled: blocking the pump for gigabytes
			-- would look exactly like a hang.
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
				main_window.report ("Could not start the download. Is ollama on PATH?")
			end
		end

	poll_pull
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
					if pull_ticks \\ Ticks_per_second = 0 then
						l_seconds := pull_ticks // Ticks_per_second
						main_window.report ("Downloading model... " + l_seconds.out + "s elapsed.")
					end
				end
			end
		end

	is_pulling: BOOLEAN
		do
			Result := pull_process /= Void
		end

feature {NONE} -- Auto-advance

	start_auto_run
		do
			if auto_run.is_paused then
				auto_run.resume
				sync_auto_controls
			elseif not auto_run.is_ready_to_start then
				main_window.report (auto_run.blocking_reason)
			elseif not main_window.is_output_folder_ready then
					-- already reported by the check itself
			elseif not health_permits_auto_run then
				main_window.report ({STRING_32} "Not starting: " + health.failure_summary)
			else
				auto_run.start
				settings.set_auto_advance (True)
				sync_auto_controls
				main_window.report ("Auto-advance started. Press Stop, or the strip's square, to end it.")
			end
		end

	pause_auto_run
		do
			auto_run.pause
			sync_auto_controls
			main_window.report (auto_run.last_message)
		end

	stop_auto_run
		do
			auto_run.stop
			settings.set_auto_advance (False)
			sync_auto_controls
			main_window.report (auto_run.last_message)
		end

	on_transport (a_command: INTEGER)
		do
			inspect a_command
			when {OCR_SW_STRIP}.Transport_play then
				start_auto_run
			when {OCR_SW_STRIP}.Transport_pause then
				pause_auto_run
			else
				stop_auto_run
			end
		end

	poll_auto_run
		local
			l_was_running: BOOLEAN
		do
			l_was_running := auto_run.is_running
			auto_run.poll
			if not auto_run.last_message.same_string (reported_auto_message) then
				create reported_auto_message.make_from_string (auto_run.last_message)
				main_window.report (auto_run.status_line)
			end
			if l_was_running and not auto_run.is_running then
				sync_auto_controls
				if not auto_run.last_error.is_empty then
					settings.set_auto_advance (False)
					announce_auto_stop
				end
			end
		end

	announce_auto_stop
			-- A modal, loudly: nobody is watching the window during
			-- an unattended run, so a status line would be found an
			-- hour later.
		local
			d: SW_DIALOG
		do
			status_strip.set_stage ({OCR_SW_STRIP}.Stage_ready, "AUTO STOPPED")
			create d.make ({SW_DIALOG}.Kind_warning, "Auto-advance stopped",
				{STRING_32} "Auto-advance stopped.%N%N" + auto_run.last_error
				+ {STRING_32} "%N%NPages captured this run: " + auto_run.pages_done.out)
			d.add_button ("OK", True, Void)
			main_window.window.show_dialog (d)
		end

	sync_auto_controls
		do
			main_window.show_auto_state (auto_run.is_running, auto_run.is_paused)
			status_strip.set_transport_state (auto_run.is_running, auto_run.is_paused)
		end

	health_permits_auto_run: BOOLEAN
		do
			health.run_quick
			Result := health.is_healthy
		end

feature {NONE} -- Health

	run_setup_check
		local
			d: SW_DIALOG
		do
			if is_pulling then
				main_window.report ("Model download already in progress.")
			elseif is_awaiting_runtime then
				main_window.report ("Still starting the Ollama server...")
			else
				main_window.report ("Checking setup - a cold model load can take up to a minute...")
				health.run_full
				main_window.report (health.report_headline)
				create d.make ({SW_DIALOG}.Kind_info, "Setup Check", health.report)
				d.add_button ("OK", True, Void)
				main_window.window.show_dialog (d)
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
		do
			monitor_ticks := monitor_ticks + 1
			if monitor_ticks >= Monitor_period_ticks then
				monitor_ticks := 0
				if not cycle.is_busy and not is_pulling and not is_awaiting_runtime then
					health.run_quick
					if health.is_healthy then
						was_healthy := True
						is_alert_suppressed := False
					elseif was_healthy and not is_alert_suppressed then
						was_healthy := False
						main_window.report (health.failure_summary)
						offer_restart
					end
				end
			end
		end

	offer_restart
			-- Two questions as continuations: restart? and only when
			-- declined, quit?
		local
			d: SW_DIALOG
		do
			create d.make ({SW_DIALOG}.Kind_warning, "OCR model down",
				{STRING_32} "The OCR server is not answering.%N%N" + health.failure_summary
				+ {STRING_32} "%N%NRestart it now?")
			d.add_button ("No", False, agent offer_quit_instead)
			d.add_button ("Restart", True, agent start_runtime)
			main_window.window.show_dialog (d)
		end

	offer_quit_instead
		local
			d: SW_DIALOG
		do
			create d.make ({SW_DIALOG}.Kind_warning, "Keep running?",
				"Keep the application running without the model?%N%NCaptures will fail until it is back.")
			d.add_button ("Quit", False, agent shut_down)
			d.add_button ("Keep running", True, agent suppress_alerts)
			main_window.window.show_dialog (d)
		end

	suppress_alerts
		do
			is_alert_suppressed := True
			main_window.report ("Left running with the OCR model down. Use Check Setup when you want it back.")
		end

feature {NONE} -- Hotkey

	register_hotkey
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
			-- Release the hotkey (an orphaned registration would
			-- block the combo system-wide), stop the run, store,
			-- release the server handle, and close the window - the
			-- pump sees WM_QUIT and `launch' returns.
		do
			hotkey.cleanup
			auto_run.stop
			settings.store
			runtime.release
			status_strip.hide
			main_window.outlines.hide (main_window.outlines.Kind_all)
			main_window.window.close
		end

feature {NONE} -- State

	settings: OCR_SETTINGS
	hotkey: OCR_HOTKEY
	preflight: OCR_PREFLIGHT
	runtime: OCR_RUNTIME
	health: OCR_HEALTH
	status_strip: OCR_SW_STRIP
	cycle: OCR_CYCLE
	auto_run: OCR_AUTO_RUN
	main_window: OCR_SW_MAIN_WINDOW

	is_fast_timer_armed: BOOLEAN
	is_awaiting_runtime: BOOLEAN
	is_alert_suppressed: BOOLEAN
	was_healthy: BOOLEAN
	runtime_ticks: INTEGER
	pull_ticks: INTEGER
	strip_ticks: INTEGER
	monitor_ticks: INTEGER
	pull_process: detachable SIMPLE_ASYNC_PROCESS
	reported_error: STRING_32
	reported_auto_message: STRING_32

	Tick_ms: INTEGER = 50
	Ticks_per_second: INTEGER = 20
	Strip_check_ticks: INTEGER = 40
	Monitor_period_ticks: INTEGER = 300
	Runtime_start_timeout_seconds: INTEGER = 60

end
