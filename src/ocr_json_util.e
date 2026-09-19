note
	description: "[
		Minimal JSON string escaping, shared by settings persistence and the
		Ollama request body.

		Writing is hand-rolled rather than routed through SIMPLE_JSON_BUILDER
		because the only untrusted value in either payload is a single
		user-editable prompt; everything else is an identifier, a number, or
		base64. Reading always goes through SIMPLE_JSON_QUICK.
	]"

class
	OCR_JSON_UTIL

feature -- Conversion

	escaped (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' as a JSON string body (no surrounding quotes),
			-- UTF-8 encoded with the mandatory escapes applied.
		local
			l_utf8: STRING_8
			i: INTEGER
			c: CHARACTER_8
		do
			l_utf8 := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
			create Result.make (l_utf8.count + 8)
			from
				i := 1
			until
				i > l_utf8.count
			loop
				c := l_utf8.item (i)
				inspect c
				when '%"' then Result.append ("\%"")
				when '\' then Result.append ("\\")
				when '%N' then Result.append ("\n")
				when '%R' then Result.append ("\r")
				when '%T' then Result.append ("\t")
				when '%B' then Result.append ("\b")
				when '%F' then Result.append ("\f")
				else
					if c.code < 0x20 then
							-- Remaining control characters need \u00XX form.
						Result.append ("\u00")
						Result.append (hex_digit (c.code // 16))
						Result.append (hex_digit (c.code \\ 16))
					else
						Result.extend (c)
					end
				end
				i := i + 1
			end
		ensure
			no_raw_quote: not Result.has ('%"') or else Result.has ('\')
		end

	quoted (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' as a complete JSON string literal, quotes included.
		do
			Result := "%""
			Result.append (escaped (a_text))
			Result.append_character ('%"')
		ensure
			has_both_quotes: Result.count >= 2
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

feature {NONE} -- Implementation

	hex_digit (a_value: INTEGER): STRING_8
			-- Lowercase hexadecimal digit for `a_value'.
		require
			in_range: a_value >= 0 and a_value <= 15
		do
			if a_value < 10 then
				Result := a_value.out
			else
				Result := (('a').code + a_value - 10).to_character_8.out
			end
		ensure
			single_digit: Result.count = 1
		end

end
