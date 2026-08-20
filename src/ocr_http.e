note
	description: "[
		HTTP POST over WinHTTP. Deliberately minimal: one JSON POST to a
		localhost endpoint is all this application needs.

		Replaces simple_http, which resolves libcurl.dll at runtime from a
		directory that only exists inside an EiffelStudio installation. Using
		WinHTTP keeps the shipped binary free of redistributables.
	]"

class
	OCR_HTTP

create
	make

feature {NONE} -- Initialization

	make
			-- Create an HTTP client.
		do
			create last_error.make_empty
			create last_body.make_empty
		end

feature -- Access

	last_error: STRING_32
			-- Reason the most recent POST failed; empty when it succeeded.

	last_body: STRING_8
			-- Response body from the most recent successful POST.

	last_status: INTEGER
			-- HTTP status code of the most recent POST, 0 if none arrived.

feature -- Basic operations

	post_json (a_url: READABLE_STRING_8; a_body: READABLE_STRING_8; a_timeout_seconds: INTEGER): BOOLEAN
			-- POST `a_body' as application/json to `a_url'.
			-- On success `last_body' holds the reply.
		require
			url_not_empty: not a_url.is_empty
			positive_timeout: a_timeout_seconds > 0
		local
			l_host, l_path: STRING_8
			l_port: INTEGER
			l_c_host, l_c_path, l_c_body: C_STRING
			l_ptr: POINTER
			l_len: INTEGER
		do
			last_error.wipe_out
			last_body.wipe_out
			last_status := 0

			if not parse_url (a_url) then
				last_error := {STRING_32} "Endpoint is not a usable http:// URL: "
				last_error.append_string_general (a_url)
			else
				l_host := parsed_host
				l_port := parsed_port
				l_path := parsed_path

				create l_c_host.make (l_host)
				create l_c_path.make (l_path)
				create l_c_body.make (a_body)

				l_ptr := c_post_json (l_c_host.item, l_port, l_c_path.item,
					l_c_body.item, a_body.count, a_timeout_seconds * 1000, $l_len)

				last_status := c_status

				if l_ptr = default_pointer then
					last_error := {STRING_32} "WinHTTP POST failed (Win32 error "
					last_error.append_string_general (c_winerr.out)
					last_error.append_string_general (", host=")
					last_error.append_string_general (l_host)
					last_error.append_string_general (", port=")
					last_error.append_string_general (l_port.out)
					last_error.append_character (')')
				else
					create l_c_body.make_by_pointer (l_ptr)
					last_body := l_c_body.substring (1, l_len)
					c_free (l_ptr)

					if last_status >= 200 and last_status < 300 then
						Result := True
					else
						last_error := {STRING_32} "HTTP status "
						last_error.append_string_general (last_status.out)
					end
				end
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			body_on_success: Result implies last_error.is_empty
		end

	get (a_url: READABLE_STRING_8; a_timeout_seconds: INTEGER): BOOLEAN
			-- GET `a_url'. On success `last_body' holds the reply.
			-- Used for the Ollama preflight checks, which are queries, not
			-- submissions.
		require
			url_not_empty: not a_url.is_empty
			positive_timeout: a_timeout_seconds > 0
		local
			l_c_host, l_c_path: C_STRING
			l_result: C_STRING
			l_ptr: POINTER
			l_len: INTEGER
		do
			last_error.wipe_out
			last_body.wipe_out
			last_status := 0

			if not parse_url (a_url) then
				last_error := {STRING_32} "Not a usable http:// URL: "
				last_error.append_string_general (a_url)
			else
				create l_c_host.make (parsed_host)
				create l_c_path.make (parsed_path)

				l_ptr := c_get (l_c_host.item, parsed_port, l_c_path.item,
					a_timeout_seconds * 1000, $l_len)
				last_status := c_status

				if l_ptr = default_pointer then
					last_error := {STRING_32} "Could not reach "
					last_error.append_string_general (a_url)
					last_error.append_string_general (" (Win32 error ")
					last_error.append_string_general (c_winerr.out)
					last_error.append_character (')')
				else
					create l_result.make_by_pointer (l_ptr)
					last_body := l_result.substring (1, l_len)
					c_free (l_ptr)
					Result := last_status >= 200 and last_status < 300
					if not Result then
						last_error := {STRING_32} "HTTP status "
						last_error.append_string_general (last_status.out)
					end
				end
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
		end

feature -- Access: parsed URL

	parsed_host: STRING_8
			-- Host from the most recent `parse_url'.
		attribute
			create Result.make_empty
		end

	parsed_path: STRING_8
			-- Path (with leading slash) from the most recent `parse_url'.
		attribute
			create Result.make_from_string ("/")
		end

	parsed_port: INTEGER
			-- Port from the most recent `parse_url'; 80 when unspecified.

feature -- Basic operations

	parse_url (a_url: READABLE_STRING_8): BOOLEAN
			-- Split `a_url' into `parsed_host', `parsed_port', `parsed_path'.
			-- Only http:// is accepted; this talks to localhost, and adding TLS
			-- would mean certificate handling for no benefit.
		local
			l_url, l_rest: STRING_8
			l_slash, l_colon: INTEGER
			l_authority: STRING_8
		do
				-- Copy once into a STRING_8 so every substring below is already
				-- a STRING_8; slicing the READABLE_STRING_8 argument directly
				-- would force an obsolete as_string_8 conversion per call.
			create l_url.make_from_string (a_url)
			if l_url.count > 7 and then l_url.substring (1, 7).is_case_insensitive_equal ("http://") then
				l_rest := l_url.substring (8, l_url.count)

				l_slash := l_rest.index_of ('/', 1)
				if l_slash = 0 then
					l_authority := l_rest
					create parsed_path.make_from_string ("/")
				else
					l_authority := l_rest.substring (1, l_slash - 1)
					parsed_path := l_rest.substring (l_slash, l_rest.count)
				end

				l_colon := l_authority.index_of (':', 1)
				if l_colon = 0 then
					parsed_host := l_authority
					parsed_port := 80
				else
					parsed_host := l_authority.substring (1, l_colon - 1)
					if l_authority.substring (l_colon + 1, l_authority.count).is_integer then
						parsed_port := l_authority.substring (l_colon + 1, l_authority.count).to_integer
					else
						parsed_port := 80
					end
				end

				Result := not parsed_host.is_empty and parsed_port > 0
			end
		ensure
			host_on_success: Result implies not parsed_host.is_empty
			port_on_success: Result implies parsed_port > 0
			path_rooted: Result implies parsed_path.starts_with ("/")
		end

feature {NONE} -- Externals

	c_post_json (a_host: POINTER; a_port: INTEGER; a_path, a_body: POINTER;
			a_body_len, a_timeout_ms: INTEGER; a_out_len: TYPED_POINTER [INTEGER]): POINTER
		external
			"C inline use %"ocr_http.h%""
		alias
			"return ohttp_post_json ((const char *) $a_host, (int) $a_port, (const char *) $a_path, (const char *) $a_body, (int) $a_body_len, (int) $a_timeout_ms, (int *) $a_out_len);"
		end

	c_get (a_host: POINTER; a_port: INTEGER; a_path: POINTER;
			a_timeout_ms: INTEGER; a_out_len: TYPED_POINTER [INTEGER]): POINTER
		external
			"C inline use %"ocr_http.h%""
		alias
			"return ohttp_get ((const char *) $a_host, (int) $a_port, (const char *) $a_path, (int) $a_timeout_ms, (int *) $a_out_len);"
		end

	c_status: INTEGER
		external
			"C inline use %"ocr_http.h%""
		alias
			"return ohttp_status ();"
		end

	c_winerr: INTEGER
		external
			"C inline use %"ocr_http.h%""
		alias
			"return ohttp_winerr ();"
		end

	c_free (a_ptr: POINTER)
		external
			"C inline use %"ocr_http.h%""
		alias
			"ohttp_free ((char *) $a_ptr);"
		end

invariant
	error_attached: last_error /= Void
	body_attached: last_body /= Void

end
