note
	description: "[
		Weaves extracted figure links into the model's Markdown. The
		model marks figures IN READING ORDER (a line whose trimmed
		form starts "!["); the detector finds crops top-to-bottom.
		Pairing the Nth marker with the Nth link places each figure
		where it occurred; extra links append at the end (degraded
		placement, never lost images); leftover markers are dropped
		(a marker with no crop would render as a broken link). Pure -
		the assault drives it with bare strings.
	]"

class
	OCR_MD_WEAVER

feature -- Basic operations

	woven (a_markdown: READABLE_STRING_32; a_links: LIST [READABLE_STRING_32]): STRING_32
			-- `a_markdown' with its figure markers replaced by image
			-- lines "![Figure](link)" in order, extras appended,
			-- leftovers dropped.
		local
			l_used: INTEGER
		do
			create Result.make (a_markdown.count + a_links.count * 48)
			across
				a_markdown.split ('%N') as ic_line
			loop
				if is_marker_line (ic_line) then
					l_used := l_used + 1
					if l_used <= a_links.count then
						Result.append (image_line (a_links.i_th (l_used)))
						Result.append_character ('%N')
					end
						-- beyond the links: the marker is dropped whole
				else
					Result.append (ic_line)
					Result.append_character ('%N')
				end
			end
			from
			until
				l_used >= a_links.count
			loop
				l_used := l_used + 1
				Result.append_character ('%N')
				Result.append (image_line (a_links.i_th (l_used)))
				Result.append_character ('%N')
			end
			if not Result.is_empty and then Result.item (Result.count) = '%N' then
				Result.remove_tail (1)
			end
		end

	is_marker_line (a_line: READABLE_STRING_32): BOOLEAN
			-- Does `a_line' hold a Markdown image marker - its first
			-- non-blank characters being "!["?
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > a_line.count or else (a_line.item (i) /= ' ' and a_line.item (i) /= '%T')
			loop
				i := i + 1
			end
			Result := i < a_line.count and then a_line.item (i) = '!' and then a_line.item (i + 1) = '['
		end

	image_line (a_link: READABLE_STRING_GENERAL): STRING_32
			-- The Markdown image line for `a_link'.
		do
			create Result.make (a_link.count + 12)
			Result.append_string_general ("![Figure](")
			Result.append_string_general (a_link)
			Result.append_character (')')
		ensure
			formed: Result.starts_with ({STRING_32} "![Figure](")
		end

end
