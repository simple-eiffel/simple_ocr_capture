note
	description: "[
		Sends a captured image to a local Ollama vision model and returns the
		transcribed text.

		This runs in the WORKER process, not the GUI process. A single OCR call
		takes roughly 11 seconds warm and can exceed 45 seconds on a cold model
		load, which would freeze a Vision2 event loop solid. The GUI launches
		this work as a detached process and polls it.
	]"

class
	OCR_ENGINE

create
	make

feature {NONE} -- Initialization

	make
			-- Create an OCR client.
		do
			create last_error.make_empty
			create last_text.make_empty
		end

feature -- Access

	last_error: STRING_32
			-- Reason the most recent call failed; empty when it succeeded.

	last_text: STRING_32
			-- Text returned by the most recent successful call.

	last_truncated: BOOLEAN
			-- Did the most recent reply stop because it ran out of context
			-- rather than because it finished?

feature -- Basic operations

	recognize (a_image_path: READABLE_STRING_GENERAL; a_settings: OCR_SETTINGS): BOOLEAN
			-- Transcribe the image at `a_image_path'. On success `last_text'
			-- holds the transcription.
		require
			path_not_empty: not a_image_path.is_empty
		local
			l_http: OCR_HTTP
			l_bytes: detachable STRING_8
			l_body: STRING_8
			l_quick: SIMPLE_JSON_QUICK
			l_retried: BOOLEAN
		do
			if not l_retried then
				last_error.wipe_out
				last_text.wipe_out

				l_bytes := read_binary (a_image_path)
				if l_bytes = Void then
					last_error := {STRING_32} "Could not read image: "
					last_error.append_string_general (a_image_path)
				else
					l_body := request_body (l_bytes, a_settings)

					create l_http.make
					if not l_http.post_json (a_settings.endpoint, l_body, a_settings.ocr_timeout_seconds) then
						last_error := l_http.last_error.twin
					elseif l_http.last_body.is_empty then
						last_error := {STRING_32} "Endpoint returned an empty body."
					else
						create l_quick.make
						if attached l_quick.parse_object (l_http.last_body) as al_obj then
							if attached al_obj.string_item ({STRING_32} "response") as al_text then
								last_text := utf8_repaired (al_text)

									-- Ollama reports done_reason "length" when it
									-- ran out of context rather than finishing.
									-- The reply still looks like clean prose - it
									-- just stops mid-sentence - so without this
									-- check a half-transcribed page is
									-- indistinguishable from a short one. Mark it
									-- in the output where it cannot be missed.
								if attached al_obj.string_item ({STRING_32} "done_reason") as al_reason
									and then al_reason.same_string_general ("length")
								then
									last_truncated := True
									last_text.append ({STRING_32} "%N%N[TRUNCATED: hit the token limit. Raise num_ctx in settings.json - the image and the transcription share one context window.]%N")
								else
									last_truncated := False
								end

								Result := True
							elseif attached al_obj.string_item ({STRING_32} "error") as al_err then
								last_error := {STRING_32} "Model error: "
								last_error.append (al_err)
							else
								last_error := {STRING_32} "Reply had no %"response%" field."
							end
						else
							last_error := {STRING_32} "Reply was not valid JSON: "
							last_error.append_string_general (l_http.last_body.substring (1, (200).min (l_http.last_body.count)))
						end
					end
				end
			else
				last_error := {STRING_32} "OCR request raised an exception."
			end
		ensure
			text_on_success: Result implies last_error.is_empty
			error_on_failure: not Result implies not last_error.is_empty
		rescue
			l_retried := True
			retry
		end

feature {NONE} -- Implementation

	request_body (a_image_bytes: STRING_8; a_settings: OCR_SETTINGS): STRING_8
			-- Ollama /api/generate payload carrying the base64 image.
		local
			l_b64: SIMPLE_BASE64
			u: OCR_JSON_UTIL
		do
			create l_b64.make
			create u
			create Result.make (a_image_bytes.count * 2 + 512)
			Result.append ("{%"model%":")
			Result.append (u.quoted (a_settings.model))
			Result.append (",%"prompt%":")
			Result.append (u.quoted (a_settings.ocr_prompt))
			Result.append (",%"stream%":false")
				-- temperature 0 keeps the transcription deterministic. It does
				-- NOT stop the model normalizing visually ambiguous characters
				-- (lowercase l read as digit 1 in hashes and serials); that is
				-- inherent to a language model reading, not a sampling setting.
				--
				-- num_ctx is the important one. Image and answer share the
				-- context, and Ollama's 4096 default is smaller than a
				-- screenshot: see the note on OCR_SETTINGS.num_ctx.
			Result.append (",%"options%":{%"temperature%":0,%"num_ctx%":")
			Result.append (a_settings.num_ctx.out)
			Result.append (",%"num_predict%":")
			Result.append (a_settings.num_predict.out)
			Result.append ("}")
			Result.append (",%"images%":[%"")
			Result.append (l_b64.encode (a_image_bytes))
			Result.append ("%"]}")
		ensure
			non_empty: not Result.is_empty
		end

	utf8_repaired (a_text: READABLE_STRING_32): STRING_32
			-- `a_text' with UTF-8 byte sequences decoded to real characters.
			--
			-- SIMPLE_JSON_QUICK parses a STRING_8, so each raw UTF-8 byte in the
			-- reply arrives as one STRING_32 character: an em dash comes back as
			-- three characters rather than one. Reassembling the bytes and
			-- decoding them properly undoes that. Characters above U+00FF cannot
			-- have come from this path, so text that was already correct (or that
			-- arrived via \u escapes) is returned untouched.
		local
			l_bytes: STRING_8
			i: INTEGER
			l_code: NATURAL_32
			l_all_latin1: BOOLEAN
		do
			from
				i := 1
				l_all_latin1 := True
			until
				i > a_text.count or not l_all_latin1
			loop
				if a_text.code (i) > 0xFF then
					l_all_latin1 := False
				end
				i := i + 1
			end

			if not l_all_latin1 then
				Result := a_text.to_string_32
			else
				create l_bytes.make (a_text.count)
				from i := 1 until i > a_text.count loop
					l_code := a_text.code (i)
					l_bytes.extend (l_code.to_integer_32.to_character_8)
					i := i + 1
				end
				if {UTF_CONVERTER}.is_valid_utf_8_string_8 (l_bytes) then
					Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (l_bytes)
				else
						-- Not UTF-8 after all; keep exactly what arrived.
					Result := a_text.to_string_32
				end
			end
		ensure
			attached_result: Result /= Void
		end

	read_binary (a_path: READABLE_STRING_GENERAL): detachable STRING_8
			-- Whole contents of `a_path', or Void when unreadable.
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (a_path)
				if l_file.exists and then l_file.is_readable and then l_file.count > 0 then
					l_file.open_read
					l_file.read_stream (l_file.count)
					Result := l_file.last_string.twin
					l_file.close
				end
			end
		rescue
			l_retried := True
			retry
		end

invariant
	error_attached: last_error /= Void
	text_attached: last_text /= Void

end
