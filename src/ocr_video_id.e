note
	description: "[
		Finds the 11-character YouTube video id inside whatever the user
		pasted: a watch URL, a youtu.be short link, a /live/, /shorts/ or
		/embed/ path, or the bare id itself. Pure text; no network.

		The id alphabet is [A-Za-z0-9_-] and the length is always 11, which
		is enough to tell an id from the parameters that trail it.
	]"

class
	OCR_VIDEO_ID

feature -- Access

	video_id_of (a_url: READABLE_STRING_GENERAL): STRING_8
			-- The video id named by `a_url'; empty when none is found.
		local
			l_url: STRING_8
		do
			l_url := ascii_only (a_url)
			l_url.left_adjust
			l_url.right_adjust
			Result := after_query_key (l_url, "v=")
			if Result.is_empty then
				Result := after_marker (l_url, "youtu.be/")
			end
			if Result.is_empty then
				Result := after_marker (l_url, "/live/")
			end
			if Result.is_empty then
				Result := after_marker (l_url, "/shorts/")
			end
			if Result.is_empty then
				Result := after_marker (l_url, "/embed/")
			end
			if Result.is_empty and then l_url.count = Id_length and then id_at (l_url, 1).count = Id_length then
				Result := l_url.twin
			end
		ensure
			empty_or_exact: Result.is_empty or Result.count = Id_length
		end

	is_id_character (a_char: CHARACTER_8): BOOLEAN
			-- May `a_char' appear in a video id?
		do
			Result := (a_char >= 'A' and a_char <= 'Z')
				or (a_char >= 'a' and a_char <= 'z')
				or (a_char >= '0' and a_char <= '9')
				or a_char = '_' or a_char = '-'
		end

	Id_length: INTEGER = 11

feature {NONE} -- Implementation

	after_query_key (a_url: STRING_8; a_key: STRING_8): STRING_8
			-- The id following `a_key' when the key starts a query
			-- parameter (preceded by '?' or '&'); empty otherwise.
			-- A bare "v=" search would also hit "&pv=" and the like.
		local
			i: INTEGER
		do
			create Result.make_empty
			from
				i := a_url.substring_index (a_key, 1)
			until
				i = 0 or not Result.is_empty
			loop
				if i > 1 and then (a_url.item (i - 1) = '?' or a_url.item (i - 1) = '&') then
					Result := id_at (a_url, i + a_key.count)
				end
				if Result.is_empty and then i + a_key.count <= a_url.count then
					i := a_url.substring_index (a_key, i + 1)
				else
					i := 0
				end
			end
		end

	after_marker (a_url: STRING_8; a_marker: STRING_8): STRING_8
			-- The id following `a_marker'; empty when the marker is
			-- absent or not followed by a complete id.
		local
			i: INTEGER
		do
			create Result.make_empty
			i := a_url.substring_index (a_marker, 1)
			if i > 0 then
				Result := id_at (a_url, i + a_marker.count)
			end
		end

	id_at (a_url: STRING_8; a_start: INTEGER): STRING_8
			-- The run of id characters beginning at `a_start' when it is
			-- exactly `Id_length' long and ends the text or meets a
			-- non-id character; empty otherwise.
		local
			i: INTEGER
		do
			create Result.make (Id_length)
			from
				i := a_start
			until
				i > a_url.count or else not is_id_character (a_url.item (i))
			loop
				Result.extend (a_url.item (i))
				i := i + 1
			end
			if Result.count /= Id_length then
				Result.wipe_out
			end
		ensure
			empty_or_exact: Result.is_empty or Result.count = Id_length
		end

	ascii_only (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' with every non-ASCII character dropped: a URL is
			-- ASCII, and to_string_8 on a wide character would not be.
		local
			i: INTEGER
			c: NATURAL_32
		do
			create Result.make (a_text.count)
			from
				i := 1
			until
				i > a_text.count
			loop
				c := a_text.item (i).natural_32_code
				if c < 128 then
					Result.extend (c.to_character_8)
				end
				i := i + 1
			end
		end

end
