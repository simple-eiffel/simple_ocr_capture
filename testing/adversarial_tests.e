note
	description: "[
		Adversarial tests for simple_ocr_capture: the X03/X04 contract assault.

		These are not confirmations. Each one was written to BREAK something,
		and the ones that pass are hardening rather than proof. Where a test
		documents behaviour that is arguably wrong, it says so and asserts what
		the code ACTUALLY does, so a deliberate fix shows up here as a failure
		rather than silently changing meaning.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	ADVERSARIAL_TESTS

inherit
	TEST_SET_BASE

feature -- Assault: OCR_PAGE_POSITION boundaries

	test_last_page_of_book_reads_as_nothing
			-- FINDING X03-001. The final page of a book yields NO position.
			--
			-- The pairing loop requires the total to be strictly greater than
			-- the position, so "Page 416 of 416" - the last page, and exactly
			-- when a progress readout matters most - is not a pair at all.
			-- Same for "1 of 1", a single-page document.
			--
			-- Asserted as-is rather than as a failure: the behaviour is
			-- currently intended (the postcondition `ordered' states it), and
			-- this test is here so that changing it is a deliberate act.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("Page 416 of 416")
			assert_false ("last page yields nothing", l_reader.has_position)

			l_reader.set_from ("1 of 1")
			assert_false ("single page yields nothing", l_reader.has_position)
		end

	test_zero_position_refused
			-- "Page 0 of 416" is a misread, not a position.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("Page 0 of 416")
			assert_false ("zero refused", l_reader.has_position)
		end

	test_inverted_pair_refused
			-- A position beyond the total is garbage and must be dropped.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("Page 500 of 416")
			assert_false ("inverted refused", l_reader.has_position)
		end

	test_overlong_numbers_refused
			-- Beyond nine digits `to_integer' overflows, so the run is dropped.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("9999999999 of 99999999999")
			assert_false ("overflow refused", l_reader.has_position)
		end

	test_minus_sign_is_ignored
			-- FINDING X03-002. A leading minus is not read as a sign.
			--
			-- "Page -5 of 416" gives 5, because digit runs are collected
			-- without their punctuation. Harmless here - the class is an
			-- extractor and a negative page cannot occur - but it means the
			-- reader cannot distinguish "-5" from "5".
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("Page -5 of 416")
			assert_true ("still reads", l_reader.has_position)
			assert_integers_equal ("sign dropped", 5, l_reader.position)
		end

	test_separator_is_case_insensitive
			-- An uppercase "OF" from the model must still pair.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("Page 224 OF 416")
			assert_integers_equal ("uppercase of", 224, l_reader.position)
		end

	test_adjacent_numbers_are_not_a_pair
			-- Two numbers side by side are not a ratio.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("12 34")
			assert_false ("no invented pair", l_reader.has_position)
		end

	test_separators_without_numbers
			-- Nothing but separators must not crash or invent a pair.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("of of of / / /")
			assert_false ("quiet", l_reader.has_position)
			assert_integers_equal ("no pairs", 0, l_reader.pair_count)
		end

	test_chained_pairs_take_largest_total
			-- "1 of 2 of 3" is ambiguous; the largest total wins.
		note
			testing: "covers/{OCR_PAGE_POSITION}.set_from"
		local
			l_reader: OCR_PAGE_POSITION
		do
			create l_reader
			l_reader.set_from ("Page 1 of 2 of 3")
			assert_integers_equal ("total", 3, l_reader.total)
			assert_integers_equal ("position", 2, l_reader.position)
		end

feature -- Assault: OCR_TEXT_COMPARE boundaries

	test_two_blank_screens_compare_equal
			-- FINDING X03-003. Two failed OCR reads look like a stalled page.
			--
			-- Both empty flattens to both-same, so `is_same_screen' is True.
			-- A model that returns nothing twice therefore reads as "the page
			-- did not turn" and stops an unattended run. That is arguably the
			-- right outcome - a run producing no text should stop - but it is
			-- reached by accident rather than by decision.
		note
			testing: "covers/{OCR_TEXT_COMPARE}.is_same_screen"
		local
			l_cmp: OCR_TEXT_COMPARE
		do
			create l_cmp
			assert_true ("both empty are same", l_cmp.is_same_screen ("", ""))
			assert_integers_equal ("both empty are 100", 100, l_cmp.agreement_percent ("", ""))
		end

	test_whitespace_only_is_empty
			-- Whitespace flattens away entirely.
		note
			testing: "covers/{OCR_TEXT_COMPARE}.flattened"
		local
			l_cmp: OCR_TEXT_COMPARE
		do
			create l_cmp
			assert_true ("blank is empty", l_cmp.flattened ("   %N%T  %R ").is_empty)
			assert_true ("blank equals empty", l_cmp.is_same_screen ("   %N  ", ""))
		end

	test_one_empty_one_full_is_not_same
			-- A blank read against real text is a change, not a stall.
		note
			testing: "covers/{OCR_TEXT_COMPARE}.is_same_screen"
		local
			l_cmp: OCR_TEXT_COMPARE
		do
			create l_cmp
			assert_false ("not same", l_cmp.is_same_screen ("", "real page content here"))
			assert_integers_equal ("zero percent", 0, l_cmp.agreement_percent ("", "real page content here"))
		end

	test_single_character_texts
			-- The shortest possible non-empty comparison.
		note
			testing: "covers/{OCR_TEXT_COMPARE}.agreement_percent"
		local
			l_cmp: OCR_TEXT_COMPARE
		do
			create l_cmp
			assert_integers_equal ("same char", 100, l_cmp.agreement_percent ("a", "a"))
			assert_integers_equal ("different char", 0, l_cmp.agreement_percent ("a", "b"))
		end

	test_head_and_tail_cannot_double_count
			-- A character must not be counted as both head and tail.
			--
			-- Without the cap, "aaa" against "aaaa" would count three from the
			-- front and three from the back out of a three-character string.
		note
			testing: "covers/{OCR_TEXT_COMPARE}.agreement_percent"
		local
			l_cmp: OCR_TEXT_COMPARE
		do
			create l_cmp
			assert_true ("bounded", l_cmp.agreement_percent ("aaa", "aaaa") <= 100)
			assert_true ("bounded reversed", l_cmp.agreement_percent ("aaaa", "aaa") <= 100)
		end

	test_very_different_lengths
			-- A one-character page against a long one must not divide by zero
			-- or overrun either string.
		note
			testing: "covers/{OCR_TEXT_COMPARE}.agreement_percent"
		local
			l_cmp: OCR_TEXT_COMPARE
			l_long: STRING_32
			i: INTEGER
		do
			create l_cmp
			create l_long.make (4000)
			from i := 1 until i > 4000 loop
				l_long.append_character ('x')
				i := i + 1
			end
			assert_true ("in range", l_cmp.agreement_percent ("x", l_long) <= 100)
			assert_true ("in range reversed", l_cmp.agreement_percent (l_long, "x") <= 100)
		end

feature -- Assault: OCR_IMAGE_NAME boundaries

	test_name_never_exceeds_cap
			-- A model can return a paragraph where a page number was expected.
		note
			testing: "covers/{OCR_IMAGE_NAME}.sanitized"
		local
			l_namer: OCR_IMAGE_NAME
			l_long: STRING_32
			i: INTEGER
		do
			create l_namer
			create l_long.make (600)
			from i := 1 until i > 600 loop
				l_long.append_character ('a')
				i := i + 1
			end
			assert_true ("capped", l_namer.sanitized (l_long).count <= l_namer.Maximum_length)
			assert_true ("stem capped", l_namer.stem (l_long, 1).count <= l_namer.Maximum_length)
		end

	test_name_rejects_every_forbidden_character
			-- Whitelist, not blacklist: nothing outside a-zA-Z0-9- survives.
		note
			testing: "covers/{OCR_IMAGE_NAME}.sanitized"
		local
			l_namer: OCR_IMAGE_NAME
			l_result: STRING_32
		do
			create l_namer
			l_result := l_namer.sanitized ("a<>:%"/\|?*%Tb")
			assert_false ("no angle", l_result.has ('<'))
			assert_false ("no colon", l_result.has (':'))
			assert_false ("no quote", l_result.has ('%"'))
			assert_false ("no pipe", l_result.has ('|'))
			assert_false ("no star", l_result.has ('*'))
			assert_false ("no tab", l_result.has ('%T'))
		end

	test_name_never_ends_in_underscore
			-- A trailing underscore reads as a mistake in a directory listing.
		note
			testing: "covers/{OCR_IMAGE_NAME}.sanitized"
		local
			l_namer: OCR_IMAGE_NAME
			l_result: STRING_32
		do
			create l_namer
			l_result := l_namer.sanitized ("Page 12 of 99 ...")
			assert_true ("not empty", not l_result.is_empty)
			assert_true ("no trailing underscore", l_result.item (l_result.count) /= '_')
		end

	test_name_of_nothing_falls_back
			-- Empty and all-punctuation both fall back to the counter.
		note
			testing: "covers/{OCR_IMAGE_NAME}.stem"
		local
			l_namer: OCR_IMAGE_NAME
		do
			create l_namer
			assert_true ("empty falls back", l_namer.stem ("", 1).same_string ({STRING_32} "0001"))
			assert_true ("punctuation falls back", l_namer.stem ("///", 42).same_string ({STRING_32} "0042"))
		end

	test_counter_padding_survives_large_index
			-- Past four digits the counter grows rather than truncating.
		note
			testing: "covers/{OCR_IMAGE_NAME}.padded"
		local
			l_namer: OCR_IMAGE_NAME
		do
			create l_namer
			assert_true ("five digits", l_namer.padded (12345).same_string ({STRING_32} "12345"))
			assert_true ("one digit padded", l_namer.padded (1).same_string ({STRING_32} "0001"))
		end

feature -- Assault: OCR_IMAGE_STORE path arithmetic

	test_store_refuses_empty_folder_gracefully
			-- An unset output folder must answer, not crash.
		note
			testing: "covers/{OCR_IMAGE_STORE}.folder_exists"
		local
			l_settings: OCR_SETTINGS
			l_store: OCR_IMAGE_STORE
		do
			create l_settings
			l_settings.set_output_folder ("")
			create l_store.make (l_settings)
			assert_false ("no folder", l_store.folder_exists)
			assert_false ("no images", l_store.has_images)
			assert_integers_equal ("no count", 0, l_store.image_count)
		end

	test_store_forward_slashes
			-- A path typed with forward slashes still yields its leaf.
		note
			testing: "covers/{OCR_IMAGE_STORE}.leaf_name"
		local
			l_settings: OCR_SETTINGS
			l_store: OCR_IMAGE_STORE
		do
			create l_settings
			l_settings.set_output_folder ({STRING_32} "C:/Books/Boyarin")
			create l_store.make (l_settings)
			assert_true ("leaf", l_store.leaf_name.same_string ({STRING_32} "Boyarin"))
		end

	test_store_folder_with_spaces
			-- Real book folders have spaces in them.
		note
			testing: "covers/{OCR_IMAGE_STORE}.destination_folder"
		local
			l_settings: OCR_SETTINGS
			l_store: OCR_IMAGE_STORE
		do
			create l_settings
			l_settings.set_output_folder ({STRING_32} "C:\My Books\Wise Abegg Cook")
			create l_store.make (l_settings)
			assert_true ("leaf", l_store.leaf_name.same_string ({STRING_32} "Wise Abegg Cook"))
			assert_true ("destination",
				l_store.destination_folder ("D:").same_string ({STRING_32} "D:\Wise Abegg Cook"))
		end

	test_store_outcome_starts_clean
			-- A store that has done nothing reports nothing.
		note
			testing: "covers/{OCR_IMAGE_STORE}.last_done"
		local
			l_settings: OCR_SETTINGS
			l_store: OCR_IMAGE_STORE
		do
			create l_settings
			l_settings.set_output_folder ({STRING_32} "C:\Books\Boyarin")
			create l_store.make (l_settings)
			assert_integers_equal ("done", 0, l_store.last_done)
			assert_integers_equal ("skipped", 0, l_store.last_skipped)
			assert_integers_equal ("failed", 0, l_store.last_failed)
			assert_true ("no error", l_store.last_error.is_empty)
		end

end
