note
	description: "[
		The list of channels already harvested, kept at the root that
		holds the channel folders.

		Two files, each good at one job. `_channels.tsv' is the record
		the software reads: one row per channel, keyed by the "UC..."
		id. `_channels.md' is the same thing for a person, regenerated
		from it every time, so a vault shows what has been collected
		without anyone opening a TSV.

		It answers the question a later run has to ask first: WHERE DOES
		THIS CHANNEL LIVE? Not "what would its folder be called" - a
		channel can rename itself, and two channels can want the same
		name - but where its transcripts actually went last time.
		`folder_for' maps id to folder, so a re-harvest lands where the
		previous one did even if the channel is now called something
		else.

		The registry is a convenience and never an authority over the
		folders themselves: a folder's own `_channel.md' (OCR_CHANNEL_CARD)
		decides what that folder holds. If the two ever disagree, the
		card wins, because it sits with the data.
	]"

class
	OCR_CHANNEL_REGISTRY

create
	make

feature {NONE} -- Initialization

	make (a_root: READABLE_STRING_GENERAL)
			-- The registry kept under `a_root', read now if it is there.
		require
			root_given: not a_root.is_empty
		do
			create root.make_from_string_general (a_root)
			create entries.make (8)
			create last_error.make_empty
			load
		ensure
			root_kept: root.same_string_general (a_root)
		end

feature -- Access

	root: STRING_32
			-- The folder the channel folders sit under.

	entries: ARRAYED_LIST [TUPLE [channel_id: STRING_8; folder, channel_name: STRING_32;
		handle: STRING_8; last_harvest: STRING_32; listed, transcripts: INTEGER]]
			-- One per channel harvested under `root'.

	last_error: STRING_32

	Data_file: STRING_8 = "_channels.tsv"

	Readable_file: STRING_8 = "_channels.md"

	path: STRING_32
		do
			Result := joined (Data_file)
		end

feature -- Measurement

	count: INTEGER
		do
			Result := entries.count
		end

feature -- Status report

	has (a_id: READABLE_STRING_8): BOOLEAN
		do
			Result := attached entry_of (a_id)
		end

	entry_of (a_id: READABLE_STRING_8): detachable TUPLE [channel_id: STRING_8; folder, channel_name: STRING_32;
		handle: STRING_8; last_harvest: STRING_32; listed, transcripts: INTEGER]
		do
			across
				entries as ic
			until
				attached Result
			loop
				if ic.channel_id.same_string (a_id) then
					Result := ic
				end
			end
		end

	folder_for (a_id: READABLE_STRING_8): STRING_32
			-- The folder name this channel was harvested into last time;
			-- empty when it has not been. The answer a re-harvest wants,
			-- because a channel that renamed itself must not start a
			-- second folder.
		do
			create Result.make_empty
			if attached entry_of (a_id) as al then
				Result := al.folder.twin
			end
		end

	uses_folder (a_folder: READABLE_STRING_32; a_except: READABLE_STRING_8): BOOLEAN
			-- Is `a_folder' spoken for by a channel other than `a_except'?
		do
			across
				entries as ic
			until
				Result
			loop
				Result := not ic.channel_id.same_string (a_except)
					and then ic.folder.is_case_insensitive_equal (a_folder)
			end
		end

feature -- Element change

	record (a_id: READABLE_STRING_8; a_folder, a_name: READABLE_STRING_32; a_handle: READABLE_STRING_8;
			a_listed, a_transcripts: INTEGER)
			-- Note that channel `a_id' lives in `a_folder' and what the
			-- run just finished saw. An existing row is replaced.
		require
			id_given: not a_id.is_empty
			folder_given: not a_folder.is_empty
		local
			l_now: DATE
		do
			create l_now.make_now
			forget (a_id)
			entries.extend ([create {STRING_8}.make_from_string (a_id),
				create {STRING_32}.make_from_string (a_folder.to_string_32),
				create {STRING_32}.make_from_string (a_name.to_string_32),
				create {STRING_8}.make_from_string (a_handle),
				create {STRING_32}.make_from_string_general (l_now.formatted_out ("yyyy-[0]mm-[0]dd")),
				a_listed, a_transcripts])
		ensure
			recorded: has (a_id)
			folder_known: folder_for (a_id).same_string_general (a_folder)
		end

	forget (a_id: READABLE_STRING_8)
		require
			id_given: not a_id.is_empty
		do
			from
				entries.start
			until
				entries.after
			loop
				if entries.item.channel_id.same_string (a_id) then
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
			-- Write both files. False, with `last_error', when the data
			-- file could not be written; the readable one is a courtesy
			-- and its failure is not reported.
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
					create l_line.make (160)
					l_line.append_string_general (ic.channel_id)
					l_line.append_character ('%T')
					l_line.append (flattened (ic.folder))
					l_line.append_character ('%T')
					l_line.append (flattened (ic.channel_name))
					l_line.append_character ('%T')
					l_line.append_string_general (ic.handle)
					l_line.append_character ('%T')
					l_line.append (ic.last_harvest)
					l_line.append_character ('%T')
					l_line.append_string_general (ic.listed.out)
					l_line.append_character ('%T')
					l_line.append_string_general (ic.transcripts.out)
					l_line.append_character ('%N')
					l_file.put_string (utf8 (l_line))
				end
				l_file.close
				write_readable
				Result := True
			else
				last_error := {STRING_32} "Could not write "
				last_error.append (path)
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
		end

feature -- Conversion

	readable_text: STRING_32
			-- `_channels.md', regenerated from the rows.
		local
			l_now: DATE_TIME
		do
			create l_now.make_now
			create Result.make (1200)
			Result.append_string_general ("# Harvested YouTube channels%N%N")
			Result.append_string_general ("Written by simple_ocr_capture ")
			Result.append_string_general ({OCR_VERSION}.Version)
			Result.append_string_general (". Regenerated on every harvest; edit `_channels.tsv` if you must, not this file.%N%N")
			if entries.is_empty then
				Result.append_string_general ("Nothing harvested here yet.%N")
			else
				Result.append_string_general ("| Channel | Handle | Folder | Last harvest | Listed | Transcripts |%N")
				Result.append_string_general ("|---|---|---|---:|---:|---:|%N")
				across
					entries as ic
				loop
					Result.append_string_general ("| ")
					Result.append (flattened (ic.channel_name))
					Result.append_string_general (" | ")
					if ic.handle.is_empty then
						Result.append_string_general ("-")
					else
						Result.append_string_general ("@")
						Result.append_string_general (ic.handle)
					end
					Result.append_string_general (" | [[")
					Result.append (flattened (ic.folder))
					Result.append_string_general ("/_channel\|")
					Result.append (flattened (ic.folder))
					Result.append_string_general ("]] | ")
					Result.append (ic.last_harvest)
					Result.append_string_general (" | ")
					Result.append_string_general (ic.listed.out)
					Result.append_string_general (" | ")
					Result.append_string_general (ic.transcripts.out)
					Result.append_string_general (" |%N")
				end
				Result.append_string_general ("%NRe-run a harvest of any channel above and only new videos are fetched; a transcript deleted from a folder is restored.%N")
			end
		ensure
			never_empty: not Result.is_empty
		end

	flattened (a_text: READABLE_STRING_32): STRING_32
			-- `a_text' with tabs and line breaks turned into spaces.
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
			single_row: not Result.has ('%T') and not Result.has ('%N')
		end

feature {NONE} -- Implementation

	Header_line: STRING_8 = "# simple_ocr_capture harvested channels - id, folder, name, handle, last harvest, listed, transcripts%N"

	write_readable
			-- Regenerate `_channels.md'. Failure is silent: it is a
			-- convenience, and losing it must not fail a harvest.
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (joined (Readable_file))
				l_file.create_read_write
				l_file.put_string (utf8 (readable_text))
				l_file.close
			end
		rescue
			l_retried := True
			retry
		end

	load
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
		local
			l_text: STRING_32
			l_parts: LIST [STRING_32]
		do
			l_text := decoded (a_raw)
			l_text.right_adjust
			if not l_text.is_empty and then l_text.item (1) /= '#' then
				l_parts := l_text.split ('%T')
				if l_parts.count >= 2 and then not l_parts.i_th (1).is_empty and then not l_parts.i_th (2).is_empty then
					entries.extend ([ascii_of (l_parts.i_th (1)),
						part (l_parts, 2), part (l_parts, 3),
						ascii_of (part (l_parts, 4)), part (l_parts, 5),
						integer_part (l_parts, 6), integer_part (l_parts, 7)])
				end
			end
		end

	part (a_parts: LIST [STRING_32]; a_index: INTEGER): STRING_32
		do
			if a_index <= a_parts.count then
				Result := a_parts.i_th (a_index).twin
			else
				create Result.make_empty
			end
		end

	integer_part (a_parts: LIST [STRING_32]; a_index: INTEGER): INTEGER
		local
			l_text: STRING_32
		do
			l_text := part (a_parts, a_index)
			if l_text.is_integer then
				Result := l_text.to_integer
			end
		end

	joined (a_name: READABLE_STRING_8): STRING_32
		do
			create Result.make (root.count + a_name.count + 1)
			Result.append (root)
			if not root.is_empty and then root.item (root.count) /= '\' then
				Result.append_character ('\')
			end
			Result.append_string_general (a_name)
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
	parts_attached: root /= Void and entries /= Void and last_error /= Void
	root_named: not root.is_empty

end
