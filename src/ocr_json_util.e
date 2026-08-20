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
