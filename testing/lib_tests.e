note
	description: "[
		Tests for the pure-logic classes of simple_ocr_capture.

		Deliberately scoped to the classes that can be exercised without a
		screen, a hotkey or an OCR server: the indicator reader, the screen
		comparator, the file namer, the JSON escaper and the image store's
		path arithmetic. Everything else in this application is a window, a
		Win32 call or an HTTP round trip, and belongs to manual testing.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	LIB_TESTS

inherit
	TEST_SET_BASE

feature -- Test: OCR_PAGE_POSITION

	test_position_simple
			-- The ordinary "<n> of <m>" indicator.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("Page 224 of 416")
			assert_true ("has_position", l_reader.has_position)
			assert_integers_equal ("position", 224, l_reader.position)
			assert_integers_equal ("total", 416, l_reader.total)
		end

	test_position_slash
			-- A page RANGE over a slash takes the end of the range.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("90-92 / 139")
			assert_integers_equal ("position", 92, l_reader.position)
			assert_integers_equal ("total", 139, l_reader.total)
		end

	test_position_largest_total_wins
			-- A reader showing BOTH counters must not pair across them.
			--
			-- This is the bug the class was rewritten for: pairing a PAGE
			-- position with a LOCATION total gave 12 of 8890 on every capture.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("Page 12 of 170  Location 890 of 8890")
			assert_integers_equal ("position", 890, l_reader.position)
			assert_integers_equal ("total", 8890, l_reader.total)
			assert_integers_equal ("pairs", 2, l_reader.pair_count)
		end

	test_position_refuses_non_numeric
			-- Roman numerals and bare numbers yield nothing, quietly.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("Page iii of 214")
			assert_false ("roman refused", l_reader.has_position)
			l_reader.set_from ("10")
			assert_false ("bare number refused", l_reader.has_position)
			l_reader.set_from ("")
			assert_false ("empty refused", l_reader.has_position)
		end

	test_position_resets_between_labels
			-- A failed read must not leave the previous label's values behind.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("Page 224 of 416")
			assert_true ("first read", l_reader.has_position)
			l_reader.set_from ("no numbers at all")
			assert_false ("second read quiet", l_reader.has_position)
			assert_integers_equal ("position cleared", 0, l_reader.position)
			assert_integers_equal ("total cleared", 0, l_reader.total)
		end

feature -- Test: OCR_TEXT_COMPARE

	test_compare_identical
			-- Identical text is the same screen, at 100 percent.
		note
			testing: "covers/{OCR_TEXT_COMPARE}.is_same_screen"
		local
			l_cmp: OCR_TEXT_COMPARE
		do
			create l_cmp
			assert_true ("same", l_cmp.is_same_screen ("the quick brown fox", "the quick brown fox"))
			assert_integers_equal ("percent", 100, l_cmp.agreement_percent ("the quick brown fox", "the quick brown fox"))
		end

	test_compare_rewrapped
			-- A line rewrapped between two reads is still the same screen.
		note
			testing: "covers/{OCR_TEXT_COMPARE}.flattened"
		local
			l_cmp: OCR_TEXT_COMPARE
		do
			create l_cmp
			assert_true ("rewrapped", l_cmp.is_same_screen ("alpha beta%Ngamma", "alpha  beta%N%Ngamma"))
		end

	test_compare_different
			-- Genuinely different pages are not the same screen.
		note
			testing: "covers/{OCR_TEXT_COMPARE}.is_same_screen"
		local
			l_cmp: OCR_TEXT_COMPARE
		do
			create l_cmp
			assert_false ("different", l_cmp.is_same_screen (
				"In the beginning was the Word, and the Word was with God.",
				"Now the serpent was more crafty than any other beast."))
		end

	test_compare_symmetric
			-- Comparing is order-independent.
		note
			testing: "covers/{OCR_TEXT_COMPARE}.agreement_percent"
		local
			l_cmp: OCR_TEXT_COMPARE
		do
			create l_cmp
			assert_integers_equal ("symmetric",
				l_cmp.agreement_percent ("abcdefghij", "abcdefghXY"),
				l_cmp.agreement_percent ("abcdefghXY", "abcdefghij"))
		end

feature -- Test: OCR_IMAGE_NAME

	test_image_name_from_indicator
			-- An indicator becomes a file-name stem.
		note
			testing: "covers/{OCR_IMAGE_NAME}.stem"
		local
			l_namer: OCR_IMAGE_NAME
		do
			create l_namer
			assert_true ("page range", l_namer.stem ("Page 90-92 of 139", 7).same_string ({STRING_32} "Page_90-92_of_139"))
		end

	test_image_name_strips_separators
			-- The oblique in "90-92 / 139" must never reach the file system.
		note
			testing: "covers/{OCR_IMAGE_NAME}.sanitized"
		local
			l_namer: OCR_IMAGE_NAME
		do
			create l_namer
			assert_false ("no slash", l_namer.sanitized ("90-92 / 139").has ('/'))
			assert_false ("no backslash", l_namer.sanitized ("a\b").has ('\'))
		end

	test_image_name_falls_back_to_counter
			-- An unusable indicator gives a zero-padded counter instead.
		note
			testing: "covers/{OCR_IMAGE_NAME}.stem"
		local
			l_namer: OCR_IMAGE_NAME
		do
			create l_namer
			assert_true ("padded", l_namer.stem ("!!!", 7).same_string ({STRING_32} "0007"))
		end

feature -- Test: OCR_JSON_UTIL

	test_json_escapes_quotes
			-- A quote inside a value must not end the value.
		note
			testing: "covers/{OCR_JSON_UTIL}.quoted"
		local
			u: OCR_JSON_UTIL
		do
			create u
			assert_true ("escaped", u.quoted ("say %"hi%"").has_substring ("\%""))
		end

feature -- Test: OCR_IMAGE_STORE

	test_store_destination_folder
			-- The destination is the drive plus the output folder's own name.
		note
			testing: "covers/{OCR_IMAGE_STORE}.destination_folder"
		local
			l_settings: OCR_SETTINGS
			l_store: OCR_IMAGE_STORE
		do
			create l_settings
			l_settings.set_output_folder ({STRING_32} "C:\Books\Boyarin")
			create l_store.make (l_settings)
			assert_true ("leaf", l_store.leaf_name.same_string ({STRING_32} "Boyarin"))
			assert_true ("destination", l_store.destination_folder ("D:").same_string ({STRING_32} "D:\Boyarin"))
		end

	test_store_normalizes_bare_drive_letter
			-- "D" is taken to mean "D:".
		note
			testing: "covers/{OCR_IMAGE_STORE}.destination_folder"
		local
			l_settings: OCR_SETTINGS
			l_store: OCR_IMAGE_STORE
		do
			create l_settings
			l_settings.set_output_folder ({STRING_32} "C:\Books\Boyarin")
			create l_store.make (l_settings)
			assert_true ("bare letter", l_store.destination_folder ("D").same_string ({STRING_32} "D:\Boyarin"))
		end

	test_store_trailing_separator
			-- A trailing separator on either path must not double up.
		note
			testing: "covers/{OCR_IMAGE_STORE}.destination_folder"
		local
			l_settings: OCR_SETTINGS
			l_store: OCR_IMAGE_STORE
		do
			create l_settings
			l_settings.set_output_folder ({STRING_32} "C:\Books\Boyarin\")
			create l_store.make (l_settings)
			assert_true ("leaf", l_store.leaf_name.same_string ({STRING_32} "Boyarin"))
			assert_true ("destination", l_store.destination_folder ("D:\").same_string ({STRING_32} "D:\Boyarin"))
		end

	test_store_drive_root_has_no_leaf
			-- A drive root cannot name a destination.
		note
			testing: "covers/{OCR_IMAGE_STORE}.has_usable_leaf"
		local
			l_settings: OCR_SETTINGS
			l_store: OCR_IMAGE_STORE
		do
			create l_settings
			l_settings.set_output_folder ({STRING_32} "D:\")
			create l_store.make (l_settings)
			assert_false ("no usable leaf", l_store.has_usable_leaf)
		end

end
