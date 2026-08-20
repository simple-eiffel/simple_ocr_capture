note
	description: "[
		Answers "is the OCR model up and operational?" and says which check
		failed when the answer is no.

		`run_quick' costs four cheap probes and is what the periodic monitor
		uses. `run_full' adds a real generate round trip - the only check that
		distinguishes a model that is merely listed from one that can answer -
		and is what the Check Setup button uses.

		The round trip can pay a cold model load, so it is deliberately kept off
		the timer: a monitor that stalled the event loop for a minute would be
		indistinguishable from the hang it exists to detect.
	]"

class
	OCR_HEALTH

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS; a_runtime: OCR_RUNTIME; a_preflight: OCR_PREFLIGHT)
			-- Check the runtime described by `a_settings', reusing `a_preflight'
			-- for the probes it already knows how to make.
		do
			settings := a_settings
			runtime := a_runtime
			preflight := a_preflight
			create report.make_empty
			create failure_summary.make_empty
			create probe_error.make_empty
		ensure
			settings_set: settings = a_settings
			runtime_set: runtime = a_runtime
			preflight_set: preflight = a_preflight
			nothing_run: report.is_empty
		end

feature -- Access

	report: STRING_32
			-- Every check and its outcome, one per line, from the last run.

	failure_summary: STRING_32
			-- The first check that failed, phrased for a status line;
			-- empty when nothing failed.

	report_headline: STRING_32
			-- One line fit for the status bar: what the last run concluded.
		do
			if report.is_empty then
				Result := {STRING_32} "Setup has not been checked yet."
			elseif is_healthy then
				Result := {STRING_32} "All checks passed - the OCR model is up and operational."
			else
				create Result.make_from_string_general ("Setup check FAILED: ")
				Result.append (failure_summary)
			end
		ensure
			non_empty: not Result.is_empty
		end

feature -- Status report

	is_healthy: BOOLEAN
			-- Did every check in the last run pass?

	is_server_reachable: BOOLEAN
			-- Did the endpoint answer?

	is_model_present: BOOLEAN
			-- Was the configured model listed?

	is_model_answering: BOOLEAN
			-- Did a real generate request come back with text?
			-- Always False after `run_quick', which does not ask.

	is_output_folder_ready: BOOLEAN
			-- Does the output folder exist and accept writes?

	is_executable_found: BOOLEAN
			-- Was ollama.exe located on this machine?
		do
			Result := runtime.is_executable_found
		end

feature -- Basic operations

	run_quick
			-- Check everything that costs no inference.
		do
			examine (False)
		ensure
			reported: not report.is_empty
			shallow: not is_model_answering
		end

	run_full
			-- Check everything, including that the model answers.
		do
			examine (True)
		ensure
			reported: not report.is_empty
		end

feature {NONE} -- Implementation

	examine (a_deep: BOOLEAN)
			-- Run the checks, building `report' as it goes.
		do
			report.wipe_out
			failure_summary.wipe_out
			probe_error.wipe_out

			preflight.refresh
			is_server_reachable := preflight.is_runtime_reachable
			is_model_present := preflight.is_model_present
			is_output_folder_ready := output_folder_usable
			is_model_answering := False

			append_check ("Ollama installed", is_executable_found, executable_detail)
			append_check ("Server responding", is_server_reachable, server_detail)
			append_check ("Model installed", is_model_present, settings.model)
			append_check ("Output folder", is_output_folder_ready, settings.output_folder)

			if a_deep then
					-- Skipped rather than attempted when the ground beneath it is
					-- missing: a request to a dead server would just repeat the
					-- failure already reported, after a long timeout.
				if is_server_reachable and is_model_present then
					is_model_answering := model_answers
					append_check ("Test recognition", is_model_answering, probe_error)
				else
					append_check ("Test recognition", False, {STRING_32} "not attempted - fix the checks above first")
				end
			end

			is_healthy := is_executable_found and is_server_reachable
				and is_model_present and is_output_folder_ready
				and (is_model_answering or not a_deep)

			append_verdict (a_deep)
		end

	append_check (a_label: READABLE_STRING_8; a_passed: BOOLEAN; a_detail: READABLE_STRING_GENERAL)
			-- Add one "label .... OK" line, with `a_detail' indented beneath it.
		require
			label_not_empty: not a_label.is_empty
		local
			i: INTEGER
		do
			report.append_string_general (a_label)
			from
				i := a_label.count
			until
				i >= Label_width
			loop
				report.append_character (' ')
				i := i + 1
			end

			if a_passed then
				report.append_string_general ("OK")
			else
				report.append_string_general ("FAILED")
				if failure_summary.is_empty then
					failure_summary.append_string_general (a_label)
					failure_summary.append_string_general (" - ")
					failure_summary.append_string_general (a_detail)
				end
			end
			report.append_character ('%N')

			if not a_detail.is_empty then
				report.append_string_general ("      ")
				report.append_string_general (a_detail)
				report.append_character ('%N')
			end
		ensure
			grew: report.count > old report.count
		end

	append_verdict (a_deep: BOOLEAN)
			-- Add the closing summary line.
		do
			report.append_character ('%N')
			if is_healthy and a_deep then
				report.append_string_general ("Everything is up and operational - ready to capture.")
			elseif is_healthy then
				report.append_string_general ("Everything needed to capture is up.")
			else
				report.append_string_general ("NOT ready: ")
				report.append (failure_summary)
			end
		end

	model_answers: BOOLEAN
			-- Does a generate request come back with text?
			--
			-- A corrupt blob, or a GPU the runtime cannot initialise, both leave
			-- the model tag listed and fail only here.
		local
			l_http: OCR_HTTP
			l_quick: SIMPLE_JSON_QUICK
		do
			create l_http.make
			if not l_http.post_json (settings.endpoint, probe_body, Probe_timeout_seconds) then
				probe_error := l_http.last_error.twin
			else
				create l_quick.make
				if attached l_quick.parse_object (l_http.last_body) as al_obj then
					if attached al_obj.string_item ({STRING_32} "response") then
						Result := True
					elseif attached al_obj.string_item ({STRING_32} "error") as al_error then
						probe_error := al_error.twin
					else
						probe_error := {STRING_32} "the server replied without any text"
					end
				else
					probe_error := {STRING_32} "the server replied with something that is not JSON"
				end
			end
		end

	probe_body: STRING_8
			-- Smallest generate request that still proves the model runs.
			--
			-- No image and a tiny `num_predict': this asks whether the model
			-- loads and emits tokens, not whether it can read a page.
		local
			l_util: OCR_JSON_UTIL
		do
			create l_util
			create Result.make (160)
			Result.append ("{%"model%":")
			Result.append (l_util.quoted (settings.model))
			Result.append (",%"prompt%":")
			Result.append (l_util.quoted ({STRING_32} "Reply with the single word: ready"))
			Result.append (",%"stream%":false,%"options%":{%"num_predict%":8}}")
		ensure
			non_empty: not Result.is_empty
		end

	output_folder_usable: BOOLEAN
			-- Does the output folder exist, or can it be made, and take writes?
			--
			-- Guarded: a folder on a disconnected network drive raises rather
			-- than returning False, and a health check must report that, not
			-- become the failure it was called to diagnose.
		local
			l_dir: DIRECTORY
			l_failed: BOOLEAN
		do
			if not l_failed then
				create l_dir.make_with_name (settings.output_folder)
				if not l_dir.exists then
					l_dir.recursive_create_dir
				end
				Result := l_dir.exists and then l_dir.is_writable
			end
		rescue
			l_failed := True
			retry
		end

	executable_detail: STRING_32
			-- Where ollama.exe was found, or how to get it.
		do
			if runtime.is_executable_found then
				Result := runtime.executable_path.twin
			else
				Result := {STRING_32} "not found - install Ollama from https://ollama.com"
			end
		ensure
			non_empty: not Result.is_empty
		end

	server_detail: STRING_32
			-- The endpoint, plus why it is not answering when it is not.
		do
			create Result.make_from_string_general (settings.endpoint)
			if not is_server_reachable and then not preflight.last_error.is_empty then
				Result.append_string_general (" - ")
				Result.append (preflight.last_error)
			end
		ensure
			non_empty: not Result.is_empty
		end

	probe_error: STRING_32
			-- Why `model_answers' came back False.

	settings: OCR_SETTINGS
	runtime: OCR_RUNTIME
	preflight: OCR_PREFLIGHT

feature {NONE} -- Constants

	Label_width: INTEGER = 20
			-- Column the OK/FAILED verdict starts in.

	Probe_timeout_seconds: INTEGER = 90
			-- Long enough for a cold model load, short enough that a hung
			-- server does not freeze the interface for the full capture timeout.

invariant
	report_attached: report /= Void
	summary_attached: failure_summary /= Void
	probe_error_attached: probe_error /= Void
	healthy_implies_no_failure: is_healthy implies failure_summary.is_empty

end
