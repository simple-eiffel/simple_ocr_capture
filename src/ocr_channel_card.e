note
	description: "[
		The identity of a channel folder, kept in `_channel.md' beside
		the transcripts.

		It exists to answer one question before anything is written:
		DOES THIS FOLDER BELONG TO THIS CHANNEL? A display name is not
		an identity - ten different churches are called "Landmark
		Baptist Church" and two of them are in Florida - so a folder
		named after a channel says nothing about which channel it holds.
		The card carries the "UC..." id, and `belongs_to' refuses a
		harvest that would pour one channel into another one's folder.

		An empty folder has no card and `belongs_to' allows anything:
		the first harvest writes the card and the folder is claimed from
		then on.

		Written as Markdown with YAML front matter so it is legible in a
		vault and parseable without one. Unreadable or missing values
		are treated as unknown, never as a mismatch - a card that cannot
		be read must not be able to block a harvest.
	]"

class
	OCR_CHANNEL_CARD

create
	make

feature {NONE} -- Initialization

	make (a_folder: READABLE_STRING_GENERAL)
			-- The card of `a_folder', read now if it is there.
		require
			folder_given: not a_folder.is_empty
		do
			create folder.make_from_string_general (a_folder)
			create channel_id.make_empty
			create channel_name.make_empty
			create handle.make_empty
			create first_harvested.make_empty
			create last_error.make_empty
			load
		ensure
			folder_kept: folder.same_string_general (a_folder)
		end

feature -- Access

	folder: STRING_32

	channel_id: STRING_8
			-- The "UC..." id this folder holds; empty when there is no
			-- card or it carries none.

	channel_name: STRING_32

	handle: STRING_8
			-- Without the at sign.

	first_harvested: STRING_32
			-- The date the folder was claimed; kept across later runs.

	last_error: STRING_32

	File_name: STRING_8 = "_channel.md"

	path: STRING_32
		do
			Result := joined (folder, File_name)
		end

feature -- Status report

	exists: BOOLEAN
			-- Is there a card on disk?
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

	is_claimed: BOOLEAN
			-- Does this folder name a channel?
		do
			Result := not channel_id.is_empty
		end

	belongs_to (a_id: READABLE_STRING_8): BOOLEAN
			-- May a harvest of channel `a_id' write here?
			--
			-- Yes when the folder is unclaimed, which is the first
			-- harvest; yes when it is claimed by this same channel,
			-- which is every later one. No otherwise, and that "no" is
			-- the whole point of the class.
		do
			Result := not is_claimed or else channel_id.same_string (a_id)
		ensure
			unclaimed_is_free: not is_claimed implies Result
		end

	mismatch_reason (a_id: READABLE_STRING_8; a_name: READABLE_STRING_32): STRING_32
			-- Why `a_id' may not be written here; empty when it may.
		do
			create Result.make_empty
			if not belongs_to (a_id) then
				Result.append_string_general ("That folder already holds a different channel: ")
				Result.append (channel_name)
				Result.append_string_general (" (")
				Result.append_string_general (channel_id)
				Result.append_string_general ("). Refusing to mix ")
				Result.append (a_name)
				Result.append_string_general (" into it - give this harvest a folder of its own.")
			end
		ensure
			empty_when_allowed: belongs_to (a_id) implies Result.is_empty
		end

feature -- Basic operations

	write (a_id: READABLE_STRING_8; a_name: READABLE_STRING_32; a_handle: READABLE_STRING_8;
			a_listed, a_transcripts: INTEGER): BOOLEAN
			-- Claim this folder for channel `a_id' and record what the
			-- last harvest saw. `first_harvested' is preserved.
		require
			id_given: not a_id.is_empty
		local
			l_file: RAW_FILE
			l_now: DATE
			l_retried: BOOLEAN
		do
			last_error.wipe_out
			if not l_retried then
				create l_now.make_now
				if first_harvested.is_empty then
					create first_harvested.make_from_string_general (l_now.formatted_out ("yyyy-[0]mm-[0]dd"))
				end
				create channel_id.make_from_string (a_id)
				create channel_name.make_from_string (a_name.to_string_32)
				create handle.make_from_string (a_handle)
				create l_file.make_with_name (path)
				l_file.create_read_write
				l_file.put_string (utf8 (card_text (create {STRING_32}.make_from_string_general (l_now.formatted_out ("yyyy-[0]mm-[0]dd")), a_listed, a_transcripts)))
				l_file.close
				Result := True
			else
				last_error := {STRING_32} "Could not write "
				last_error.append (path)
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			claimed_on_success: Result implies is_claimed
		rescue
			l_retried := True
			retry
		end

feature -- Conversion

	card_text (a_today: READABLE_STRING_32; a_listed, a_transcripts: INTEGER): STRING_32
			-- What `_channel.md' says.
		do
			create Result.make (900)
			Result.append_string_general ("---%Nchannel_id: ")
			Result.append_string_general (channel_id)
			Result.append_string_general ("%Nchannel_name: %"")
			Result.append (quoted_safe (channel_name))
			Result.append_string_general ("%"%Nhandle: ")
			if handle.is_empty then
				Result.append_string_general ("%"%"")
			else
				Result.append_string_general ("%"@")
				Result.append_string_general (handle)
				Result.append_string_general ("%"")
			end
			Result.append_string_general ("%Nurl: https://www.youtube.com/channel/")
			Result.append_string_general (channel_id)
			Result.append_string_general ("%Nfirst_harvested: ")
			Result.append (first_harvested)
			Result.append_string_general ("%Nlast_harvested: ")
			Result.append (a_today.to_string_32)
			Result.append_string_general ("%Nvideos_listed: ")
			Result.append_string_general (a_listed.out)
			Result.append_string_general ("%Ntranscripts: ")
			Result.append_string_general (a_transcripts.out)
			Result.append_string_general ("%Nharvested_by: simple_ocr_capture ")
			Result.append_string_general ({OCR_VERSION}.Version)
			Result.append_string_general ("%Ntags:%N  - youtube-channel%N---%N%N# ")
			Result.append (channel_name)
			Result.append_string_general ("%N%NThis folder holds YouTube transcripts harvested from the channel above, one Markdown file per video, with an index grouping them by category.%N%N")
			Result.append_string_general ("`.harvested.tsv` records which videos have already been written, matched on the video id rather than the title. Re-running a harvest of this channel fetches only what is new, and restores anything whose transcript has been deleted.%N%N")
			Result.append_string_general ("**Do not point a different channel at this folder.** The `channel_id` above is what a harvest checks before it writes; a run for another channel is refused rather than mixed in.%N")
		ensure
			fenced: Result.starts_with ({STRING_32} "---%N")
		end

	quoted_safe (a_text: READABLE_STRING_32): STRING_32
			-- `a_text' fit to sit inside a double-quoted YAML scalar.
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
				if c = '%"' or c = '\' then
					Result.append_character ('\')
					Result.append_character (c)
				elseif c.natural_32_code >= 32 then
					Result.append_character (c)
				end
				i := i + 1
			end
		end

	value_of (a_text: READABLE_STRING_32; a_key: READABLE_STRING_32): STRING_32
			-- The value of front-matter key `a_key' in `a_text', with
			-- surrounding quotes and a leading at sign removed; empty
			-- when the key is absent.
		local
			i, l_end: INTEGER
			l_needle: STRING_32
		do
			create Result.make_empty
			create l_needle.make (a_key.count + 2)
			l_needle.append_character ('%N')
			l_needle.append (a_key.to_string_32)
			l_needle.append_character (':')
			i := a_text.substring_index (l_needle, 1)
			if i > 0 then
				i := i + l_needle.count
				l_end := a_text.index_of ('%N', i)
				if l_end = 0 then
					l_end := a_text.count + 1
				end
				if l_end > i then
					Result := a_text.substring (i, l_end - 1)
					Result.left_adjust
					Result.right_adjust
					if Result.count >= 2 and then Result.item (1) = '%"' and then Result.item (Result.count) = '%"' then
						Result := Result.substring (2, Result.count - 1)
					end
					if not Result.is_empty and then Result.item (1) = '@' then
						Result := Result.substring (2, Result.count)
					end
				end
			end
		end

feature {NONE} -- Implementation

	load
			-- Read the card, if there is one. Anything unreadable leaves
			-- the folder unclaimed rather than blocking a harvest.
		local
			l_file: PLAIN_TEXT_FILE
			l_text: STRING_32
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (path)
				if l_file.exists and then l_file.is_readable then
					l_file.open_read
					l_file.read_stream (l_file.count)
					l_text := decoded (l_file.last_string)
					l_file.close
						-- a leading newline so `value_of' can anchor on one
					l_text.prepend_character ('%N')
					channel_id := ascii_of (value_of (l_text, {STRING_32} "channel_id"))
					channel_name := value_of (l_text, {STRING_32} "channel_name")
					handle := ascii_of (value_of (l_text, {STRING_32} "handle"))
					first_harvested := value_of (l_text, {STRING_32} "first_harvested")
				end
			end
		rescue
			l_retried := True
			retry
		end

	joined (a_folder: READABLE_STRING_32; a_name: READABLE_STRING_8): STRING_32
		do
			create Result.make (a_folder.count + a_name.count + 1)
			Result.append (a_folder)
			if not a_folder.is_empty and then a_folder.item (a_folder.count) /= '\' then
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
	parts_attached: folder /= Void and channel_id /= Void and channel_name /= Void
		and handle /= Void and first_harvested /= Void and last_error /= Void
	folder_named: not folder.is_empty

end
