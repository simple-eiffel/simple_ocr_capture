note
	description: "[
		What a channel folder already holds, so a second harvest of the
		same channel fetches only what is new.

		One line per transcript, tab separated: the video id, the file
		it was written to, and the category it was filed under. The id
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

	entries: ARRAYED_LIST [TUPLE [video_id: STRING_8; file_name, category: STRING_32]]
			-- One per transcript already written.

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

	record (a_id: READABLE_STRING_8; a_file_name, a_category: READABLE_STRING_32)
			-- Note that video `a_id' has been written to `a_file_name'.
		require
			id_given: not a_id.is_empty
		do
			if not has (a_id) then
				entries.extend ([create {STRING_8}.make_from_string (a_id),
					create {STRING_32}.make_from_string (a_file_name),
					create {STRING_32}.make_from_string (a_category)])
			end
		ensure
			recorded: has (a_id)
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
					create l_line.make (80)
					l_line.append_string_general (ic.video_id)
					l_line.append_character ('%T')
					l_line.append (ic.file_name)
					l_line.append_character ('%T')
					l_line.append (ic.category)
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

	Header_line: STRING_8 = "# simple_ocr_capture channel harvest - video id, file, category%N"

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
					entries.extend ([ascii_of (l_parts.i_th (1)),
						part (l_parts, 2),
						part (l_parts, 3)])
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

	utf8 (a_text: READABLE_STRING_GENERAL): STRING_8
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
		end

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
