note
	description: "[
		First-run checks: is the model runtime there, and is the model pulled?

		The installer deliberately does not ship the 9.5 GB model, so a fresh
		install has to answer both questions and offer to fix the second. Doing
		it here rather than in the installer means it also self-heals later - if
		Ollama is stopped, or the model is removed, the app says which of the two
		is wrong instead of failing at the first capture with a network error.
	]"

class
	OCR_PREFLIGHT

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
			-- Prepare checks against `a_settings'.
		do
			settings := a_settings
			create last_error.make_empty
			create installed_models.make (8)
		end

feature -- Access

	last_error: STRING_32
			-- Why the most recent check failed; empty when it succeeded.

	installed_models: ARRAYED_LIST [STRING_32]
			-- Model tags reported by the runtime at the last `refresh'.

feature -- Status report

	is_runtime_reachable: BOOLEAN
			-- Did the last `refresh' reach the Ollama endpoint?

	is_model_present: BOOLEAN
			-- Was the configured model among `installed_models'?

	is_ready: BOOLEAN
			-- Can a capture succeed right now?
		do
			Result := is_runtime_reachable and is_model_present
		end

	diagnosis: STRING_32
			-- One sentence describing what is wrong, or that all is well.
		do
			if is_ready then
				create Result.make_from_string_general ("Ready.")
			elseif not is_runtime_reachable then
				create Result.make_from_string_general ("Cannot reach Ollama at ")
				Result.append_string_general (settings.endpoint)
				Result.append_string_general (" - is it running?")
			else
				create Result.make_from_string_general ("Ollama is running but the model ")
				Result.append_string_general (settings.model)
				Result.append_string_general (" is not installed.")
			end
		ensure
			non_empty: not Result.is_empty
		end

feature -- Basic operations

	refresh
			-- Ask the runtime what it has. Sets `is_runtime_reachable',
			-- `is_model_present' and `installed_models'.
		local
			l_http: OCR_HTTP
			l_quick: SIMPLE_JSON_QUICK
			l_url: STRING_8
		do
			last_error.wipe_out
			is_runtime_reachable := False
			is_model_present := False
			installed_models.wipe_out

			l_url := tags_url
			create l_http.make
				-- Short timeout: this is a liveness probe, and a stalled one
				-- would freeze the GUI it is called from.
			if not l_http.get (l_url, Probe_timeout_seconds) then
				last_error := l_http.last_error.twin
			else
				is_runtime_reachable := True
				create l_quick.make
				if attached l_quick.parse_object (l_http.last_body) as al_obj then
					collect_models (al_obj)
					is_model_present := has_model (settings.model)
				else
					last_error := {STRING_32} "Runtime replied with something that is not JSON."
				end
			end
		end

	pull_command: STRING_32
			-- Command line that installs the configured model.
			-- Run detached and polled; the pull moves gigabytes.
		do
			create Result.make_from_string_general ("ollama pull ")
			Result.append_string_general (settings.model)
		ensure
			non_empty: not Result.is_empty
		end

feature {NONE} -- Implementation

	tags_url: STRING_8
			-- The runtime's model-list endpoint, derived from `endpoint'.
			--
			-- Built by trimming the configured generate path rather than by
			-- asking for a second setting: the two always live on the same
			-- server, and one of them getting edited to point elsewhere would
			-- be a confusing way to fail.
		local
			l_http: OCR_HTTP
		do
			create l_http.make
			create Result.make (48)
			if l_http.parse_url (settings.endpoint) then
				Result.append ("http://")
				Result.append (l_http.parsed_host)
				Result.append_character (':')
				Result.append (l_http.parsed_port.out)
				Result.append ("/api/tags")
			else
				Result.append ("http://127.0.0.1:11435/api/tags")
			end
		ensure
			non_empty: not Result.is_empty
		end

	collect_models (a_obj: SIMPLE_JSON_OBJECT)
			-- Read the "models" array of `a_obj' into `installed_models'.
		local
			l_array: SIMPLE_JSON_ARRAY
			i: INTEGER
		do
			if attached a_obj.item ({STRING_32} "models") as al_value and then al_value.is_array then
					-- Indexed rather than `across': SIMPLE_JSON_ARRAY does not
					-- conform to ITERABLE.
				l_array := al_value.array_value
				from
					i := 1
				until
					i > l_array.count
				loop
					if attached l_array.item (i) as al_entry and then al_entry.is_object then
						if attached al_entry.object_value.string_item ({STRING_32} "name") as al_name then
							installed_models.extend (al_name.twin)
						end
					end
					i := i + 1
				end
			end
		end

	has_model (a_tag: READABLE_STRING_8): BOOLEAN
			-- Is `a_tag' installed?
			--
			-- Matches a bare name against "name:latest" too, because that is
			-- how Ollama reports a model pulled without an explicit tag and
			-- users routinely type the short form.
		local
			l_wanted: STRING_32
		do
			create l_wanted.make_from_string_general (a_tag)
			from
				installed_models.start
			until
				installed_models.after or Result
			loop
				Result := installed_models.item.same_string (l_wanted)
					or installed_models.item.same_string (l_wanted + {STRING_32} ":latest")
				installed_models.forth
			end
		end

	settings: OCR_SETTINGS

	Probe_timeout_seconds: INTEGER = 5

invariant
	error_attached: last_error /= Void
	models_attached: installed_models /= Void

end
