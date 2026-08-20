note
	description: "[
		Tests that put real files on disk and let OCR_IMAGE_STORE find them.

		Written in response to X06 GAP-A. The original store tests exercised
		path arithmetic only - leaf_name, destination_folder, has_usable_leaf -
		so `is_ocr_image', `is_plain_file' and `joined' were never called by the
		suite at all. Mutation warfare proved it: making `is_ocr_image' return
		True for EVERY file left all 41 tests passing, and that mutation would
		have deleted the transcript along with the images.

		The behaviour had been checked by hand through the --images CLI verb.
		Hand-checked once is unprotected forever, which is the whole point.
	]"
	design: "[
		Every test builds its own fixture under TEMP and removes it afterwards,
		so a failure cannot leave litter that makes the next run lie. Nothing
		here touches the user's configured output folder.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	STORE_FILE_TESTS

inherit
	TEST_SET_BASE

feature -- Test: matching

	test_matches_only_ocr_images
			-- The whitelist takes the images and nothing else.
			--
			-- Kills X06-M50 (prefix ignored) and X06-M51 (prefix OR extension
			-- instead of AND).
		note
			testing: "covers/{OCR_IMAGE_STORE}.image_names"
		local
			l_store: OCR_IMAGE_STORE
			l_names: ARRAYED_LIST [STRING_32]
		do
			make_fixture ("match")
			put_file ("ocr_0001.png", "image one")
			put_file ("ocr_0002.png", "image two")
			put_file ("ocr_OLD.BMP", "uppercase bmp")
				-- Decoys. Every one of these must survive.
			put_file ("ocr_capture.txt", "the transcript")
			put_file ("ocr_0001.sidecar.txt", "sidecar text")
			put_file ("ocr_capture.findings.jsonl", "findings")
			put_file ("cover.png", "not an ocr image")
			put_file ("ocr_notes.md", "not an image at all")

			l_store := store_on_fixture
			l_names := l_store.image_names

			assert_integers_equal ("three images", 3, l_names.count)
			assert_true ("png one", has_name (l_names, "ocr_0001.png"))
			assert_true ("png two", has_name (l_names, "ocr_0002.png"))
			assert_true ("uppercase bmp", has_name (l_names, "ocr_OLD.BMP"))

			assert_false ("transcript excluded", has_name (l_names, "ocr_capture.txt"))
			assert_false ("sidecar excluded", has_name (l_names, "ocr_0001.sidecar.txt"))
			assert_false ("findings excluded", has_name (l_names, "ocr_capture.findings.jsonl"))
			assert_false ("cover excluded", has_name (l_names, "cover.png"))
			assert_false ("notes excluded", has_name (l_names, "ocr_notes.md"))

			remove_fixture
		end

	test_directory_named_like_an_image_is_not_one
			-- A directory called ocr_x.png must not be offered for deletion.
		note
			testing: "covers/{OCR_IMAGE_STORE}.image_names"
		local
			l_store: OCR_IMAGE_STORE
		do
			make_fixture ("dir")
			put_file ("ocr_real.png", "a real image")
			put_directory ("ocr_folder.png")

			l_store := store_on_fixture
			assert_integers_equal ("only the file", 1, l_store.image_names.count)
			assert_true ("the file", has_name (l_store.image_names, "ocr_real.png"))

			remove_fixture
		end

	test_counts_and_size_reflect_the_folder
			-- image_count and total_bytes read what is actually there.
		note
			testing: "covers/{OCR_IMAGE_STORE}.total_bytes"
		local
			l_store: OCR_IMAGE_STORE
		do
			make_fixture ("size")
			put_file ("ocr_a.png", "12345")
			put_file ("ocr_b.png", "12345")
			put_file ("ignored.txt", "9999999999999999999999")

			l_store := store_on_fixture
			assert_integers_equal ("count", 2, l_store.image_count)
			assert_true ("has images", l_store.has_images)
			assert_true ("size is the two images only", l_store.total_bytes = 10)

			remove_fixture
		end

	test_empty_folder_reports_nothing
			-- A folder holding only a transcript has no images.
		note
			testing: "covers/{OCR_IMAGE_STORE}.has_images"
		local
			l_store: OCR_IMAGE_STORE
		do
			make_fixture ("empty")
			put_file ("ocr_capture.txt", "transcript only")

			l_store := store_on_fixture
			assert_true ("folder is there", l_store.folder_exists)
			assert_false ("no images", l_store.has_images)
			assert_integers_equal ("zero count", 0, l_store.image_count)

			remove_fixture
		end

feature -- Test: deletion

	test_delete_removes_images_and_spares_the_rest
			-- The decoys must still be on disk afterwards.
		note
			testing: "covers/{OCR_IMAGE_STORE}.delete_all"
		local
			l_store: OCR_IMAGE_STORE
		do
			make_fixture ("del")
			put_file ("ocr_1.png", "one")
			put_file ("ocr_2.BMP", "two")
			put_file ("ocr_capture.txt", "the transcript")
			put_file ("cover.png", "cover")

			l_store := store_on_fixture
			l_store.delete_all

			assert_integers_equal ("two deleted", 2, l_store.last_done)
			assert_integers_equal ("none failed", 0, l_store.last_failed)
			assert_false ("image one gone", file_exists ("ocr_1.png"))
			assert_false ("image two gone", file_exists ("ocr_2.BMP"))
			assert_true ("transcript survives", file_exists ("ocr_capture.txt"))
			assert_true ("cover survives", file_exists ("cover.png"))
			assert_false ("nothing left to do", l_store.has_images)

			remove_fixture
		end

feature -- Test: moving

	test_move_transfers_content_and_leaves_decoys
			-- A move relocates the bytes and removes the source.
		note
			testing: "covers/{OCR_IMAGE_STORE}.move_all_to"
		local
			l_store: OCR_IMAGE_STORE
			l_target: STRING_32
		do
			make_fixture ("mv")
			put_file ("ocr_1.png", "the first image")
			put_file ("ocr_capture.txt", "the transcript")

			l_store := store_on_fixture
			l_target := destination_root
			l_store.move_all_to (l_target)

			assert_integers_equal ("one moved", 1, l_store.last_done)
			assert_integers_equal ("none failed", 0, l_store.last_failed)
			assert_true ("no error", l_store.last_error.is_empty)
			assert_false ("source gone", file_exists ("ocr_1.png"))
			assert_true ("transcript stays", file_exists ("ocr_capture.txt"))
			assert_true ("arrived with content",
				content_of (l_store.destination_folder (l_target) + {STRING_32} "\ocr_1.png").same_string ({STRING_32} "the first image"))

			remove_tree (destination_root)
			remove_fixture
		end

	test_move_skips_a_collision_rather_than_overwriting
			-- An archive file already at the destination must survive intact.
		note
			testing: "covers/{OCR_IMAGE_STORE}.move_all_to"
		local
			l_store: OCR_IMAGE_STORE
			l_target, l_dest: STRING_32
		do
			make_fixture ("clash")
			put_file ("ocr_1.png", "NEW version")
			put_file ("ocr_2.png", "moves cleanly")

			l_store := store_on_fixture
			l_target := destination_root
			l_dest := l_store.destination_folder (l_target)
			make_directory (l_dest)
			put_file_at (l_dest + {STRING_32} "\ocr_1.png", "ORIGINAL archive")

			l_store.move_all_to (l_target)

			assert_integers_equal ("one moved", 1, l_store.last_done)
			assert_integers_equal ("one skipped", 1, l_store.last_skipped)
			assert_integers_equal ("none failed", 0, l_store.last_failed)
			assert_true ("archive untouched",
				content_of (l_dest + {STRING_32} "\ocr_1.png").same_string ({STRING_32} "ORIGINAL archive"))
			assert_true ("skipped source kept", file_exists ("ocr_1.png"))
			assert_false ("moved source gone", file_exists ("ocr_2.png"))

			remove_tree (destination_root)
			remove_fixture
		end

	test_move_onto_itself_is_refused
			-- Moving a folder into itself would delete every source.
		note
			testing: "covers/{OCR_IMAGE_STORE}.move_all_to"
		local
			l_store: OCR_IMAGE_STORE
			l_parent: STRING_32
		do
			make_fixture ("self")
			put_file ("ocr_1.png", "precious")

			l_store := store_on_fixture
				-- The fixture's own parent, so destination_folder resolves back
				-- onto the fixture itself.
			l_parent := temp_root
			l_store.move_all_to (l_parent)

			assert_integers_equal ("nothing moved", 0, l_store.last_done)
			assert_false ("refused with a reason", l_store.last_error.is_empty)
			assert_true ("file still there", file_exists ("ocr_1.png"))
			assert_true ("content intact", content_of (fixture_folder + {STRING_32} "\ocr_1.png").same_string ({STRING_32} "precious"))

			remove_fixture
		end

feature {NONE} -- Fixture

	fixture_folder: STRING_32
			-- The folder this test is working in.
		attribute
			create Result.make_empty
		end

	temp_root: STRING_32
			-- Where fixtures are built.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			create Result.make (64)
			if attached l_env.item ("TEMP") as al_temp and then not al_temp.is_empty then
				Result.append_string_general (al_temp)
			else
				Result.append_string_general (".")
			end
			Result.append_string_general ("\ocr_x08")
		end

	destination_root: STRING_32
			-- Where move tests send their images.
		do
			Result := temp_root + {STRING_32} "\dest"
		end

	make_fixture (a_name: READABLE_STRING_GENERAL)
			-- Build a clean folder named `a_name' under the temp root.
		do
			fixture_folder := temp_root + {STRING_32} "\" + a_name.to_string_32
			remove_tree (fixture_folder)
			make_directory (fixture_folder)
		end

	remove_fixture
			-- Take the fixture away again, and the shared root with it once
			-- the last test has emptied it.
			--
			-- Leaving empty shells behind is not harmful, but a temp folder
			-- that accumulates across runs is how a fixture starts finding
			-- files it did not create.
		do
			remove_tree (fixture_folder)
			remove_if_empty (destination_root)
			remove_if_empty (temp_root)
		end

	remove_if_empty (a_path: READABLE_STRING_GENERAL)
			-- Delete `a_path' only when nothing is left in it.
		local
			l_dir: DIRECTORY
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_dir.make_with_name (a_path)
				if l_dir.exists and then l_dir.is_empty then
					l_dir.delete
				end
			end
		rescue
			l_retried := True
			retry
		end

	store_on_fixture: OCR_IMAGE_STORE
			-- A store pointed at the current fixture.
		local
			l_settings: OCR_SETTINGS
		do
			create l_settings
			l_settings.set_output_folder (fixture_folder)
			create Result.make (l_settings)
		end

	put_file (a_name: READABLE_STRING_GENERAL; a_content: READABLE_STRING_GENERAL)
			-- Write `a_content' into `a_name' inside the fixture.
		do
			put_file_at (fixture_folder + {STRING_32} "\" + a_name.to_string_32, a_content)
		end

	put_file_at (a_path: READABLE_STRING_GENERAL; a_content: READABLE_STRING_GENERAL)
			-- Write `a_content' to `a_path'.
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			l_file.create_read_write
			l_file.put_string (a_content.to_string_8)
			l_file.close
		end

	put_directory (a_name: READABLE_STRING_GENERAL)
			-- Make a subdirectory inside the fixture.
		do
			make_directory (fixture_folder + {STRING_32} "\" + a_name.to_string_32)
		end

	make_directory (a_path: READABLE_STRING_GENERAL)
			-- Create `a_path' and any missing parents.
		local
			l_dir: DIRECTORY
		do
			create l_dir.make_with_name (a_path)
			if not l_dir.exists then
				l_dir.recursive_create_dir
			end
		end

	remove_tree (a_path: READABLE_STRING_GENERAL)
			-- Delete `a_path' and everything under it, if it is there.
		local
			l_dir: DIRECTORY
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_dir.make_with_name (a_path)
				if l_dir.exists then
					l_dir.recursive_delete
				end
			end
		rescue
			l_retried := True
			retry
		end

	file_exists (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_name' present in the fixture?
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (fixture_folder + {STRING_32} "\" + a_name.to_string_32)
			Result := l_file.exists
		end

	content_of (a_path: READABLE_STRING_GENERAL): STRING_32
			-- What is in the file at `a_path'?
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			create Result.make_empty
			if not l_retried then
				create l_file.make_with_name (a_path)
				if l_file.exists and then l_file.count > 0 then
					l_file.open_read
					l_file.read_stream (l_file.count)
					Result := l_file.last_string.to_string_32
					l_file.close
				end
			end
		rescue
			l_retried := True
			retry
		end

	has_name (a_names: ARRAYED_LIST [STRING_32]; a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_names' hold `a_name'?
			--
			-- Explicit cursor: `across' binds the item in this project, and
			-- ARRAYED_LIST.has compares by object identity, not content.
		local
			l_wanted: STRING_32
		do
			l_wanted := a_name.to_string_32
			from
				a_names.start
			until
				a_names.after or Result
			loop
				Result := a_names.item.same_string (l_wanted)
				a_names.forth
			end
		end

end
