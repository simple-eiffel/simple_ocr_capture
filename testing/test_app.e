note
	description: "[
		Console test runner for simple_ocr_capture.

		Scoped to the pure-logic classes on purpose. The rest of this
		application is a window, a system-wide hotkey, a screen grab or an HTTP
		call to a local model, and none of those can be asserted about from a
		test runner. Pretending otherwise would produce tests that pass while
		the thing they name is broken.
	]"
	author: "Larry Rix"

class
	TEST_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Run the tests.
		do
			print ("Running simple_ocr_capture tests...%N%N")
			passed := 0
			failed := 0

			print ("-- library tests --%N")
			run_lib_tests
			print ("%N-- adversarial tests --%N")
			run_adversarial_tests
			print ("%N-- store file tests --%N")
			run_store_file_tests

			print ("%N-- simple_widgets rebuild tests --%N")
			run_rebuild_tests

			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed%N")

			if failed > 0 then
				print ("TESTS FAILED%N")
			else
				print ("ALL TESTS PASSED%N")
			end
		end

feature {NONE} -- Test runners

	rebuild_tests: detachable SW_REBUILD_TESTS

	run_rebuild_tests
		local
			t2: SW_REBUILD_TESTS
		do
			create t2
			rebuild_tests := t2
			run_test (agent t2.test_band_normalizes_any_drag_direction, "band_normalizes_any_drag_direction")
			run_test (agent t2.test_handle_index_answers_every_grab_point, "handle_index_answers_every_grab_point")
			run_test (agent t2.test_adjusted_band_moves_the_right_edges, "adjusted_band_moves_the_right_edges")
			run_test (agent t2.test_adjusted_band_clamps_at_min_side, "adjusted_band_clamps_at_min_side")
			run_test (agent t2.test_outlines_show_suspend_resume, "outlines_show_suspend_resume")
			run_test (agent t2.test_strip_sizing_and_transport_zone, "strip_sizing_and_transport_zone")
		end


	run_lib_tests
		do
			create lib_tests
			run_test (agent lib_tests.test_position_simple, "test_position_simple")
			run_test (agent lib_tests.test_position_slash, "test_position_slash")
			run_test (agent lib_tests.test_position_largest_total_wins, "test_position_largest_total_wins")
			run_test (agent lib_tests.test_position_refuses_non_numeric, "test_position_refuses_non_numeric")
			run_test (agent lib_tests.test_position_resets_between_labels, "test_position_resets_between_labels")

			run_test (agent lib_tests.test_compare_identical, "test_compare_identical")
			run_test (agent lib_tests.test_compare_rewrapped, "test_compare_rewrapped")
			run_test (agent lib_tests.test_compare_different, "test_compare_different")
			run_test (agent lib_tests.test_compare_symmetric, "test_compare_symmetric")

			run_test (agent lib_tests.test_image_name_from_indicator, "test_image_name_from_indicator")
			run_test (agent lib_tests.test_image_name_strips_separators, "test_image_name_strips_separators")
			run_test (agent lib_tests.test_image_name_falls_back_to_counter, "test_image_name_falls_back_to_counter")

			run_test (agent lib_tests.test_json_escapes_quotes, "test_json_escapes_quotes")

			run_test (agent lib_tests.test_store_destination_folder, "test_store_destination_folder")
			run_test (agent lib_tests.test_store_normalizes_bare_drive_letter, "test_store_normalizes_bare_drive_letter")
			run_test (agent lib_tests.test_store_trailing_separator, "test_store_trailing_separator")
			run_test (agent lib_tests.test_store_drive_root_has_no_leaf, "test_store_drive_root_has_no_leaf")
		end

	run_adversarial_tests
		do
			create adv_tests
			run_test (agent adv_tests.test_last_page_of_book_reads_as_nothing, "test_last_page_of_book_reads_as_nothing")
			run_test (agent adv_tests.test_zero_position_refused, "test_zero_position_refused")
			run_test (agent adv_tests.test_inverted_pair_refused, "test_inverted_pair_refused")
			run_test (agent adv_tests.test_overlong_numbers_refused, "test_overlong_numbers_refused")
			run_test (agent adv_tests.test_minus_sign_is_ignored, "test_minus_sign_is_ignored")
			run_test (agent adv_tests.test_separator_is_case_insensitive, "test_separator_is_case_insensitive")
			run_test (agent adv_tests.test_adjacent_numbers_are_not_a_pair, "test_adjacent_numbers_are_not_a_pair")
			run_test (agent adv_tests.test_separators_without_numbers, "test_separators_without_numbers")
			run_test (agent adv_tests.test_chained_pairs_take_largest_total, "test_chained_pairs_take_largest_total")
			run_test (agent adv_tests.test_ten_digit_value_is_refused_by_the_cap, "test_ten_digit_value_is_refused_by_the_cap")
			run_test (agent adv_tests.test_nine_digit_value_is_accepted, "test_nine_digit_value_is_accepted")
			run_test (agent adv_tests.test_largest_total_wins_when_it_comes_first, "test_largest_total_wins_when_it_comes_first")

			run_test (agent adv_tests.test_two_blank_screens_compare_equal, "test_two_blank_screens_compare_equal")
			run_test (agent adv_tests.test_whitespace_only_is_empty, "test_whitespace_only_is_empty")
			run_test (agent adv_tests.test_one_empty_one_full_is_not_same, "test_one_empty_one_full_is_not_same")
			run_test (agent adv_tests.test_single_character_texts, "test_single_character_texts")
			run_test (agent adv_tests.test_head_and_tail_cannot_double_count, "test_head_and_tail_cannot_double_count")
			run_test (agent adv_tests.test_very_different_lengths, "test_very_different_lengths")
			run_test (agent adv_tests.test_similar_but_not_identical_is_the_same_screen, "test_similar_but_not_identical_is_the_same_screen")
			run_test (agent adv_tests.test_below_threshold_is_a_different_screen, "test_below_threshold_is_a_different_screen")
			run_test (agent adv_tests.test_threshold_constant_is_where_it_says, "test_threshold_constant_is_where_it_says")
			run_test (agent adv_tests.test_flattened_strips_trailing_space, "test_flattened_strips_trailing_space")
			run_test (agent adv_tests.test_exactly_at_the_threshold_is_the_same_screen, "test_exactly_at_the_threshold_is_the_same_screen")
			run_test (agent adv_tests.test_shorter_text_wholly_contained_is_the_same_screen, "test_shorter_text_wholly_contained_is_the_same_screen")

			run_test (agent adv_tests.test_name_never_exceeds_cap, "test_name_never_exceeds_cap")
			run_test (agent adv_tests.test_name_rejects_every_forbidden_character, "test_name_rejects_every_forbidden_character")
			run_test (agent adv_tests.test_name_never_ends_in_underscore, "test_name_never_ends_in_underscore")
			run_test (agent adv_tests.test_name_never_begins_with_underscore, "test_name_never_begins_with_underscore")
			run_test (agent adv_tests.test_name_of_nothing_falls_back, "test_name_of_nothing_falls_back")
			run_test (agent adv_tests.test_counter_padding_survives_large_index, "test_counter_padding_survives_large_index")

			run_test (agent adv_tests.test_store_refuses_empty_folder_gracefully, "test_store_refuses_empty_folder_gracefully")
			run_test (agent adv_tests.test_store_forward_slashes, "test_store_forward_slashes")
			run_test (agent adv_tests.test_store_folder_with_spaces, "test_store_folder_with_spaces")
			run_test (agent adv_tests.test_store_outcome_starts_clean, "test_store_outcome_starts_clean")
			run_test (agent adv_tests.test_json_escapes_control_characters, "test_json_escapes_control_characters")
			run_test (agent adv_tests.test_json_leaves_ordinary_text_alone, "test_json_leaves_ordinary_text_alone")
		end

	run_store_file_tests
			-- Tests that put real files on disk. Added after X06 mutation
			-- warfare showed the store's matching code was never executed by
			-- the suite at all.
		do
			create store_tests
			run_test (agent store_tests.test_matches_only_ocr_images, "test_matches_only_ocr_images")
			run_test (agent store_tests.test_directory_named_like_an_image_is_not_one, "test_directory_named_like_an_image_is_not_one")
			run_test (agent store_tests.test_counts_and_size_reflect_the_folder, "test_counts_and_size_reflect_the_folder")
			run_test (agent store_tests.test_empty_folder_reports_nothing, "test_empty_folder_reports_nothing")
			run_test (agent store_tests.test_delete_removes_images_and_spares_the_rest, "test_delete_removes_images_and_spares_the_rest")
			run_test (agent store_tests.test_move_transfers_content_and_leaves_decoys, "test_move_transfers_content_and_leaves_decoys")
			run_test (agent store_tests.test_move_skips_a_collision_rather_than_overwriting, "test_move_skips_a_collision_rather_than_overwriting")
			run_test (agent store_tests.test_move_onto_itself_is_refused, "test_move_onto_itself_is_refused")
		end

feature {NONE} -- Implementation

	lib_tests: LIB_TESTS

	store_tests: STORE_FILE_TESTS

	adv_tests: ADVERSARIAL_TESTS

	passed: INTEGER
	failed: INTEGER

	run_test (a_test: PROCEDURE; a_name: STRING)
			-- Run one test, counting the outcome.
			--
			-- A failing assertion raises, so the rescue is what turns a broken
			-- test into a reported failure rather than a dead runner.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				print ("  PASS: " + a_name + "%N")
				passed := passed + 1
			end
		rescue
			print ("  FAIL: " + a_name + "%N")
			failed := failed + 1
			l_retried := True
			retry
		end

end
