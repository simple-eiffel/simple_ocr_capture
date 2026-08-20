note
	description: "[
		The ocr-related images sitting in the designated output folder, as a set
		that can be counted, emptied, or moved to another drive.

		A book scanned a page at a time fills a folder with hundreds of megabytes
		of screenshots that are worth keeping only until the transcript has been
		read through. Clearing them by hand means picking ocr_*.png out of a
		directory that also holds the transcript, the sidecars and the findings
		file, so this does the picking.
	]"
	design: "[
		The match is deliberately narrow: a name beginning "ocr_" and ending
		".png" or ".bmp", case-insensitively, that is a plain file. Those are
		exactly the names OCR_CYCLE.image_path_of produces. Nothing else in the
		folder is touched - not the transcript, not the ocr_NNNN.sidecar.txt
		files, not the .findings.jsonl - and the rule is a whitelist so a file
		type nobody anticipated cannot be swept up by it.

		Nothing here creates the output folder, and nothing here reports through
		a dialog. The caller asks whether the folder is present and whether it
		holds anything BEFORE it asks for either operation; this class answers
		those questions and then does as it is told. Creating a folder in order
		to empty it would be absurd, and creating one in order to move into it
		is the caller's decision to confirm.

		A move copies, verifies, and only then removes the original. `copy_to'
		reports nothing at all, so a move that deleted on faith would lose the
		images to a full destination disk without a word. Cost is one extra
		stat per file; the alternative is losing the thing being archived.
	]"

class
	OCR_IMAGE_STORE

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
			-- Look at the folder `a_settings' designates.
			--
			-- Holds the settings rather than a copy of the path: the folder can
			-- be retyped in the window between one button press and the next,
			-- and a stale path here would empty the wrong directory.
		do
			settings := a_settings
			create last_error.make_empty
		ensure
			set: settings = a_settings
		end

feature -- Access

	settings: OCR_SETTINGS
			-- Where the output folder is read from, live.

	folder: STRING_32
			-- The designated output folder.
		do
			Result := settings.output_folder
		end

	image_names: ARRAYED_LIST [STRING_32]
			-- The bare name of every ocr-related image in `folder'.
			--
			-- Empty rather than an error when the folder is absent, so the
			-- caller can ask this without checking first. It reads the
			-- directory on every call by design: a run may have added images
			-- since the window opened.
		local
			l_dir: DIRECTORY
			l_entries: ARRAYED_LIST [STRING_32]
			l_retried: BOOLEAN
		do
			create Result.make (32)
			if not l_retried and then folder_exists then
				create l_dir.make_with_name (folder)
				l_entries := l_dir.linear_representation_32
					-- Explicit cursor, not `across'. In this project `across'
					-- binds the ITEM, so the two forms are not interchangeable
					-- and the cursor form fails VUAR(1) - see the note in
					-- OCR_STATUS_STRIP.preferred_width.
				from
					l_entries.start
				until
					l_entries.after
				loop
					if is_ocr_image (l_entries.item)
						and then is_plain_file (path_of (l_entries.item))
					then
						Result.extend (l_entries.item)
					end
					l_entries.forth
				end
			end
		rescue
			l_retried := True
			retry
		end

	destination_folder (a_drive: READABLE_STRING_GENERAL): STRING_32
			-- Where `move_all_to' would put the images, given root `a_drive'.
			--
			-- "D:" with an output folder of "C:\Books\Boyarin" gives
			-- "D:\Boyarin" - the same folder name on the other drive. That is
			-- what makes the destination predictable enough to confirm in a
			-- sentence instead of asking for a second browse.
		require
			drive_not_empty: not a_drive.is_empty
		do
			create Result.make_from_string_general (a_drive)
			trim_separators (Result)
				-- A bare letter is what gets typed. Accepting "D" and meaning
				-- "D:" costs one line and saves a confusing "D\Boyarin".
			if Result.count = 1 and then is_letter (Result.item (1)) then
				Result.append_character (':')
			end
			Result.append_character ('\')
			Result.append (leaf_name)
		ensure
			non_empty: not Result.is_empty
		end

	leaf_name: STRING_32
			-- The last component of `folder', without separators.
		local
			l_path: STRING_32
			l_at: INTEGER
		do
			l_path := folder.twin
			trim_separators (l_path)
			from
				l_at := l_path.count
			until
				l_at < 1 or else is_separator (l_path.item (l_at))
			loop
				l_at := l_at - 1
			end
			Result := l_path.substring (l_at + 1, l_path.count)
		end

	size_caption: STRING_32
			-- `total_bytes' as something readable in a dialog.
		local
			l_bytes: INTEGER_64
		do
			l_bytes := total_bytes
			create Result.make (12)
			if l_bytes >= 1048576 then
				Result.append_string_general ((l_bytes // 1048576).out)
				Result.append_string_general (" MB")
			elseif l_bytes >= 1024 then
				Result.append_string_general ((l_bytes // 1024).out)
				Result.append_string_general (" KB")
			else
				Result.append_string_general (l_bytes.out)
				Result.append_string_general (" bytes")
			end
		ensure
			non_empty: not Result.is_empty
		end

feature -- Measurement

	image_count: INTEGER
			-- How many ocr-related images are in `folder'?
		do
			Result := image_names.count
		ensure
			not_negative: Result >= 0
		end

	total_bytes: INTEGER_64
			-- Combined size of every ocr-related image in `folder'.
		local
			l_names: ARRAYED_LIST [STRING_32]
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				l_names := image_names
				from
					l_names.start
				until
					l_names.after
				loop
					create l_file.make_with_name (path_of (l_names.item))
					if l_file.exists and then l_file.is_plain then
						Result := Result + l_file.count
					end
					l_names.forth
				end
			end
		ensure
			not_negative: Result >= 0
		rescue
			l_retried := True
			retry
		end

feature -- Status report

	folder_exists: BOOLEAN
			-- Is the output folder actually there?
		do
			Result := settings.output_folder_exists
		end

	has_images: BOOLEAN
			-- Is there anything here for the two operations to work on?
		do
			Result := not image_names.is_empty
		end

	has_usable_leaf: BOOLEAN
			-- Does `folder' end in a name a destination can be built from?
			--
			-- A drive root has no such name. "D:\" would otherwise produce a
			-- destination of "E:\D:", which is not a path at all.
		local
			l_leaf: STRING_32
		do
			l_leaf := leaf_name
			Result := not l_leaf.is_empty and then not l_leaf.has (':')
		end

feature -- Outcome of the last operation

	last_done: INTEGER
			-- How many images the last operation deleted or moved.

	last_skipped: INTEGER
			-- How many a move left alone because the destination already had
			-- a file of that name.

	last_failed: INTEGER
			-- How many could not be deleted or moved.

	last_error: STRING_32
			-- Why the last operation could not start at all, or empty.

feature -- Basic operations

	delete_all
			-- Remove every ocr-related image from `folder'.
		require
			folder_there: folder_exists
		local
			l_names: ARRAYED_LIST [STRING_32]
		do
			reset_outcome
			l_names := image_names
			from
				l_names.start
			until
				l_names.after
			loop
				delete_one (l_names.item)
				l_names.forth
			end
		ensure
			all_accounted_for: last_done + last_failed <= old image_count
		end

	move_all_to (a_drive: READABLE_STRING_GENERAL)
			-- Move every ocr-related image in `folder' onto `a_drive', into a
			-- folder of the same name.
			--
			-- Creates the destination. That is not the silent folder creation
			-- the capture path forbids: the caller has already shown the user
			-- the full destination path and been told to go ahead.
		require
			drive_not_empty: not a_drive.is_empty
			folder_there: folder_exists
			leaf_usable: has_usable_leaf
		local
			l_names: ARRAYED_LIST [STRING_32]
			l_target: STRING_32
			l_dir: DIRECTORY
			l_retried: BOOLEAN
		do
			if not l_retried then
				reset_outcome
				l_target := destination_folder (a_drive)
				if l_target.is_case_insensitive_equal (folder) then
						-- Moving a folder onto itself would delete every source
						-- after "copying" it over itself. Refused outright.
					create last_error.make_from_string_general (
						"The destination is the output folder itself.")
				else
					create l_dir.make_with_name (l_target)
					if not l_dir.exists then
						l_dir.recursive_create_dir
					end
					if not l_dir.exists then
						create last_error.make_from_string_general ("Could not create ")
						last_error.append (l_target)
					else
						l_names := image_names
						from
							l_names.start
						until
							l_names.after
						loop
							move_one (l_names.item, l_target)
							l_names.forth
						end
					end
				end
			end
		rescue
			l_retried := True
			create last_error.make_from_string_general (
				"Stopped early after an unexpected error. Nothing already moved was lost.")
			retry
		end

feature {NONE} -- Implementation

	reset_outcome
			-- Forget what the previous operation did.
		do
			last_done := 0
			last_skipped := 0
			last_failed := 0
			create last_error.make_empty
		ensure
			cleared: last_done = 0 and last_skipped = 0 and last_failed = 0
			no_error: last_error.is_empty
		end

	delete_one (a_name: READABLE_STRING_32)
			-- Remove `a_name' from `folder', counting the outcome.
			--
			-- One file failing - locked by a viewer, most likely - must not
			-- abandon the rest, so the rescue is here rather than around the
			-- loop that calls this.
		require
			name_not_empty: not a_name.is_empty
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (path_of (a_name))
				if l_file.exists and then l_file.is_plain then
					l_file.delete
					last_done := last_done + 1
				else
					last_failed := last_failed + 1
				end
			end
		rescue
			l_retried := True
			last_failed := last_failed + 1
			retry
		end

	move_one (a_name: READABLE_STRING_32; a_target: READABLE_STRING_32)
			-- Move `a_name' from `folder' into `a_target', counting the outcome.
		require
			name_not_empty: not a_name.is_empty
			target_not_empty: not a_target.is_empty
		local
			l_src, l_dst, l_check: RAW_FILE
			l_dst_path: STRING_32
			l_size: INTEGER
			l_retried: BOOLEAN
		do
			if not l_retried then
				l_dst_path := joined (a_target, a_name)
				create l_dst.make_with_name (l_dst_path)
				if l_dst.exists then
						-- Never overwritten. A collision means two books were
						-- scanned into folders of the same name, and replacing
						-- the earlier one destroys exactly what is being kept.
					last_skipped := last_skipped + 1
				else
					create l_src.make_with_name (path_of (a_name))
					if l_src.exists and then l_src.is_plain then
						l_size := l_src.count
						l_src.open_read
						l_dst.open_write
						l_src.copy_to (l_dst)
						l_dst.close
						l_src.close
							-- The original goes only once the copy is there and
							-- the right size. `copy_to' reports nothing, so a
							-- full destination disk is otherwise indistinguishable
							-- from a clean move.
						create l_check.make_with_name (l_dst_path)
						if l_check.exists and then l_check.count = l_size then
							l_src.delete
							last_done := last_done + 1
						else
							last_failed := last_failed + 1
						end
					else
						last_failed := last_failed + 1
					end
				end
			end
		rescue
			l_retried := True
			last_failed := last_failed + 1
			retry
		end

	is_ocr_image (a_name: READABLE_STRING_32): BOOLEAN
			-- Is `a_name' one of the images a capture wrote?
			--
			-- Whitelisted on both ends. Matching the extension alone would
			-- take in a cover scan the user dropped in the folder by hand;
			-- matching the prefix alone would take in the sidecar text files.
		local
			l_lower: STRING_32
		do
			l_lower := a_name.as_lower
			Result := l_lower.starts_with_general (Image_prefix)
				and then (l_lower.ends_with_general (Png_suffix)
					or else l_lower.ends_with_general (Bmp_suffix))
		end

	is_plain_file (a_path: READABLE_STRING_32): BOOLEAN
			-- Is there an ordinary file at `a_path'?
			--
			-- A directory named ocr_something.png is far-fetched, but `delete'
			-- on one would fail per file rather than being skipped, and the
			-- count shown to the user would be wrong before it started.
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (a_path)
				Result := l_file.exists and then l_file.is_plain
			end
		rescue
			l_retried := True
			retry
		end

	path_of (a_name: READABLE_STRING_32): STRING_32
			-- Full path of `a_name' inside `folder'.
		do
			Result := joined (folder, a_name)
		end

	joined (a_folder: READABLE_STRING_32; a_name: READABLE_STRING_32): STRING_32
			-- `a_name' inside `a_folder', with exactly one separator between.
		do
			create Result.make_from_string (a_folder)
			if not Result.is_empty and then not is_separator (Result.item (Result.count)) then
				Result.append_character ('\')
			end
			Result.append (a_name)
		end

	trim_separators (a_path: STRING_32)
			-- Remove any trailing separators from `a_path' in place.
		do
			from
			until
				a_path.is_empty or else not is_separator (a_path.item (a_path.count))
			loop
				a_path.remove_tail (1)
			end
		end

	is_separator (a_char: CHARACTER_32): BOOLEAN
			-- Does `a_char' divide one path component from the next?
		do
			Result := a_char = '\' or a_char = '/'
		end

	is_letter (a_char: CHARACTER_32): BOOLEAN
			-- Is `a_char' a drive letter?
		do
			Result := (a_char >= 'a' and a_char <= 'z')
				or (a_char >= 'A' and a_char <= 'Z')
		end

feature -- Constants

	Image_prefix: STRING_8 = "ocr_"
			-- What OCR_CYCLE.image_path_of puts in front of every capture.

	Png_suffix: STRING_8 = ".png"
	Bmp_suffix: STRING_8 = ".bmp"
			-- The two formats OCR_SETTINGS.image_format allows. Both are
			-- matched regardless of which is currently selected: a folder
			-- scanned last month under the other setting is still full of
			-- images the user means to clear.

invariant
	settings_attached: settings /= Void
	error_attached: last_error /= Void
	counts_not_negative: last_done >= 0 and last_skipped >= 0 and last_failed >= 0

end
