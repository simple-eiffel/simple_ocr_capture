note
	description: "[
		What a channel folder already holds, so a second harvest of the
		same channel fetches only what is new.

		One line per transcript, tab separated: the video id, the file
		it was written to, the category it was filed under, the title
		and length it had then, and the channel listing it was found
		under ("videos" or "streams"; empty in a row written before
		that column existed, until a later harvest fills it in). The id
		is what is matched on, never the title or the file name - a
		channel can rename a video, and the transcript on disk is still
		that video's.

		The file lives in the channel folder and is named with a leading
		dot so it sorts away from the transcripts. It is rewritten in
		full rather than appended to, so a harvest interrupted halfway
		leaves a file that still parses.

		Unreadable lines are skipped, not refused: a manifest that has
		been hand-edited should cost the harvest the lines that were
		broken, not the whole record.
	]"

class
	OCR_CHANNEL_MANIFEST

create
	make

feature {NONE} -- Initialization

	make (a_folder: READABLE_STRING_GENERAL)
			-- The manifest of the channel folder `a_folder', read now if
			-- it is there.
		require
			folder_given: not a_folder.is_empty
		do
			create folder.make_from_string_general (a_folder)
			create entries.make (128)
			create last_error.make_empty
			load
		ensure
			folder_kept: folder.same_string_general (a_folder)
		end

feature -- Access

	folder: STRING_32
			-- The channel folder this manifest belongs to.

	entries: ARRAYED_LIST [TUPLE [video_id: STRING_8; file_name, category, title: STRING_32; length_seconds: INTEGER; tab: STRING_8]]
			-- One per transcript already written.
			--
			-- `title' and `length_seconds' are carried so a later harvest
			-- can tell, for nothing, that a video has been RENAMED or
			-- re-cut upstream: the channel listing hands both back
			-- without an extra request. A file written before these
			-- columns existed reads back with an empty title and zero
			-- length, which is treated as "unknown", never as "changed".

	last_error: STRING_32
			-- Why the last `save' failed; empty when it did not.

	path: STRING_32
			-- Where the manifest is kept.
		do
			create Result.make (folder.count + 20)
			Result.append (folder)
			if not folder.is_empty and then folder.item (folder.count) /= '\' then
				Result.append_character ('\')
			end
			Result.append_string_general (File_name)
		ensure
			named: Result.ends_with_general (File_name)
		end

	File_name: STRING_8 = ".harvested.tsv"

feature -- Measurement

	count: INTEGER
		do
			Result := entries.count
		end

feature -- Status report

	has (a_id: READABLE_STRING_8): BOOLEAN
			-- Is video `a_id' already recorded as written?
		do
			across
				entries as ic
			until
				Result
			loop
				Result := ic.video_id.same_string (a_id)
			end
		end

	entry_of (a_id: READABLE_STRING_8): detachable TUPLE [video_id: STRING_8; file_name, category, title: STRING_32; length_seconds: INTEGER; tab: STRING_8]
			-- What is recorded for video `a_id', if anything.
		do
			across
				entries as ic
			until
				attached Result
			loop
				if ic.video_id.same_string (a_id) then
					Result := ic
				end
			end
		ensure
			found_implies_recorded: attached Result implies has (a_id)
		end

	file_of (a_id: READABLE_STRING_8): STRING_32
			-- The full path of the transcript recorded for `a_id';
			-- empty when nothing is recorded for it.
		do
			create Result.make_empty
			if attached entry_of (a_id) as al and then not al.file_name.is_empty then
				Result.append (folder)
				if not folder.is_empty and then folder.item (folder.count) /= '\' then
					Result.append_character ('\')
				end
				Result.append (al.file_name)
			end
		end

	is_file_present (a_id: READABLE_STRING_8): BOOLEAN
			-- Is the transcript recorded for `a_id' still on disk?
			--
			-- The manifest is a record of intent; the disk is the fact.
			-- A transcript deleted by hand must be fetched again, and
			-- without this check the id alone would keep it skipped for
			-- ever.
		local
			l_file: RAW_FILE
			l_path: STRING_32
			l_retried: BOOLEAN
		do
			if not l_retried then
				l_path := file_of (a_id)
				if not l_path.is_empty then
					create l_file.make_with_name (l_path)
					Result := l_file.exists
				end
			end
		rescue
			l_retried := True
			retry
		end

	exists: BOOLEAN
			-- Is there a manifest on disk?
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (path)
				Result := l_file.exists
			end
		rescue
			l_retried := True
			retry
		end

feature -- Element change

	record (a_id: READABLE_STRING_8; a_file_name, a_category, a_title: READABLE_STRING_32; a_length: INTEGER; a_tab: READABLE_STRING_8)
			-- Note that video `a_id', found under listing `a_tab'
			-- ("videos", "streams", or empty when not known), has been
			-- written to `a_file_name'.
		require
			id_given: not a_id.is_empty
			tab_known: a_tab.is_empty or else {OCR_CHANNEL_VIDEO}.is_tab_key (a_tab)
		do
			if not has (a_id) then
				entries.extend ([create {STRING_8}.make_from_string (a_id),
					create {STRING_32}.make_from_string (a_file_name),
					create {STRING_32}.make_from_string (a_category),
					create {STRING_32}.make_from_string (a_title),
					a_length,
					create {STRING_8}.make_from_string (a_tab)])
			end
		ensure
			recorded: has (a_id)
		end

	set_tab (a_id: READABLE_STRING_8; a_tab: READABLE_STRING_8)
			-- Note the listing an already-recorded video was found under:
			-- how a row written before the column existed gets one, from
			-- a later harvest that has the listing in hand anyway.
		require
			recorded: has (a_id)
			tab_known: {OCR_CHANNEL_VIDEO}.is_tab_key (a_tab)
		do
			if attached entry_of (a_id) as al then
				al.tab := create {STRING_8}.make_from_string (a_tab)
			end
		ensure
			set: attached entry_of (a_id) as al and then al.tab.same_string (a_tab)
		end

	forget (a_id: READABLE_STRING_8)
			-- Drop the record of video `a_id', so a later pass fetches
			-- it again. Used when the transcript it names is no longer
			-- on disk, or when its content is being refreshed.
		require
			id_given: not a_id.is_empty
		do
			from
				entries.start
			until
				entries.after
			loop
				if entries.item.video_id.same_string (a_id) then
					entries.remove
				else
					entries.forth
				end
			end
		ensure
			forgotten: not has (a_id)
		end

feature -- Basic operations

	save: BOOLEAN
			-- Write the manifest out. False, with `last_error', when it
			-- could not be written.
		local
			l_file: RAW_FILE
			l_line: STRING_32
			l_retried: BOOLEAN
		do
			last_error.wipe_out
			if not l_retried then
				create l_file.make_with_name (path)
				l_file.create_read_write
				l_file.put_string (utf8 (Header_line))
				across
					entries as ic
				loop
					create l_line.make (120)
					l_line.append_string_general (ic.video_id)
					l_line.append_character ('%T')
					l_line.append (ic.file_name)
					l_line.append_character ('%T')
					l_line.append (ic.category)
					l_line.append_character ('%T')
						-- A tab or newline inside a title would break the
						-- row; the title is written flattened.
					l_line.append (flattened (ic.title))
					l_line.append_character ('%T')
					l_line.append_string_general (ic.length_seconds.out)
					l_line.append_character ('%T')
					l_line.append_string_general (ic.tab)
					l_line.append_character ('%N')
					l_file.put_string (utf8 (l_line))
				end
				l_file.close
				Result := True
			else
				last_error := {STRING_32} "Could not write "
				last_error.append (path)
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
		end

feature {NONE} -- Implementation

	Header_line: STRING_8 = "# simple_ocr_capture channel harvest - video id, file, category, title, length, tab%N"

	load
			-- Read the manifest, if there is one. A line that does not
			-- parse is skipped.
		local
			l_file: PLAIN_TEXT_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (path)
				if l_file.exists and then l_file.is_readable then
					l_file.open_read
					from
						l_file.read_line
					until
						l_file.exhausted
					loop
						read_line (l_file.last_string)
						l_file.read_line
					end
					read_line (l_file.last_string)
					l_file.close
				end
			end
		rescue
			l_retried := True
			retry
		end

	read_line (a_raw: READABLE_STRING_8)
			-- Add the entry `a_raw' holds, if it holds one.
		local
			l_text: STRING_32
			l_parts: LIST [STRING_32]
		do
			l_text := decoded (a_raw)
			l_text.right_adjust
			if not l_text.is_empty and then l_text.item (1) /= '#' then
				l_parts := l_text.split ('%T')
				if l_parts.count >= 1 and then not l_parts.i_th (1).is_empty then
						-- Columns 4 to 6 arrived later; a manifest written
						-- before them reads back with an empty title, a
						-- zero length and no tab, which mean "not known".
					entries.extend ([ascii_of (l_parts.i_th (1)),
						part (l_parts, 2),
						part (l_parts, 3),
						part (l_parts, 4),
						integer_part (l_parts, 5),
						tab_part (l_parts, 6)])
				end
			end
		end

	part (a_parts: LIST [STRING_32]; a_index: INTEGER): STRING_32
			-- Field `a_index', or empty when the line is short.
		do
			if a_index <= a_parts.count then
				Result := a_parts.i_th (a_index).twin
			else
				create Result.make_empty
			end
		end

	integer_part (a_parts: LIST [STRING_32]; a_index: INTEGER): INTEGER
			-- Field `a_index' as a number; 0 when absent or not one.
		local
			l_text: STRING_32
		do
			l_text := part (a_parts, a_index)
			if l_text.is_integer then
				Result := l_text.to_integer
			end
		ensure
			not_negative: Result >= 0 or a_parts.count >= a_index
		end

	tab_part (a_parts: LIST [STRING_32]; a_index: INTEGER): STRING_8
			-- Field `a_index' as a tab key; empty when absent, or when it
			-- is not one of the two keys.
		local
			l_text: STRING_8
		do
			l_text := ascii_of (part (a_parts, a_index))
			if {OCR_CHANNEL_VIDEO}.is_tab_key (l_text) then
				Result := l_text
			else
				create Result.make_empty
			end
		ensure
			known_or_empty: Result.is_empty or else {OCR_CHANNEL_VIDEO}.is_tab_key (Result)
		end

feature -- Conversion

	flattened (a_text: READABLE_STRING_32): STRING_32
			-- `a_text' with tabs and line breaks turned into spaces, so
			-- it cannot break the row it is written into.
		local
			i: INTEGER
			c: CHARACTER_32
		do
			create Result.make (a_text.count)
			from
				i := 1
			until
				i > a_text.count
			loop
				c := a_text.item (i)
				if c = '%T' or c = '%N' or c = '%R' then
					Result.append_character (' ')
				else
					Result.append_character (c)
				end
				i := i + 1
			end
		ensure
			same_length: Result.count = a_text.count
			single_row: not Result.has ('%T') and not Result.has ('%N')
		end

	utf8 (a_text: READABLE_STRING_GENERAL): STRING_8
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
		end

feature {NONE} -- Implementation, continued

	decoded (a_utf8: READABLE_STRING_8): STRING_32
		do
			Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (create {STRING_8}.make_from_string (a_utf8))
		end

	ascii_of (a_text: READABLE_STRING_32): STRING_8
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text)
		end

invariant
	parts_attached: folder /= Void and entries /= Void and last_error /= Void
	folder_named: not folder.is_empty

end
