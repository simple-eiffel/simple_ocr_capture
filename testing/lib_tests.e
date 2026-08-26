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

feature -- Test: Markdown-mode laws

	test_compare_ignores_markdown_image_lines
			-- Two reads of the same screen whose only difference is
			-- the per-capture figure link must count as the SAME
			-- screen - or every figure page would re-append forever.
		note
			testing: "covers/{OCR_TEXT_COMPARE}.is_same_screen"
		local
			c: OCR_TEXT_COMPARE
		do
			create c
			assert_true ("differing links are jitter, not progress",
				c.is_same_screen (
					{STRING_32} "Alpha beta gamma delta.%N![Figure](images/p1_fig1.png)%NEpsilon zeta.",
					{STRING_32} "Alpha beta gamma delta.%N![Figure](images/p7_fig1.png)%NEpsilon zeta."))
			assert_false ("real new text still reads as a new screen",
				c.is_same_screen (
					{STRING_32} "Alpha beta gamma delta epsilon zeta.",
					{STRING_32} "Entirely different words on this page now."))
		end

	test_settings_markdown_transcript_name
			-- Markdown mode renames the transcript by extension swap;
			-- plain mode leaves the user's name untouched; figures
			-- and Markdown stay coupled both ways.
		note
			testing: "covers/{OCR_SETTINGS}.transcript_file_name"
		local
			st: OCR_SETTINGS
		do
			create st
			assert_strings_equal ("plain mode: the name as given",
				{STRING_32} "ocr_capture.txt", st.transcript_file_name)
			st.set_markdown_output (True)
			assert_strings_equal ("markdown mode: .txt becomes .md",
				{STRING_32} "ocr_capture.md", st.transcript_file_name)
			st.set_text_file_name ("traced.txt")
			assert_strings_equal ("a custom name swaps the same way",
				{STRING_32} "traced.md", st.transcript_file_name)
			st.set_text_file_name ("notes.md")
			assert_strings_equal ("an .md name is already right",
				{STRING_32} "notes.md", st.transcript_file_name)
			st.set_markdown_output (False)
			assert_strings_equal ("plain mode again: untouched",
				{STRING_32} "notes.md", st.transcript_file_name)
			st.set_extract_figures (True)
			assert_true ("figures pull markdown on", st.markdown_output)
			st.set_markdown_output (False)
			assert_false ("markdown off takes figures with it", st.extract_figures)
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

feature -- Test: OCR_FIGURE_FINDER (grid laws, bare arrays)

	test_finder_keeps_the_blob_drops_the_speck
			-- A 12x8 grid: a 4x4 ink blob is a figure candidate (its
			-- one-step dilation makes it 6x6); a far-away 1-cell
			-- speck dilates to 3x3 and dies on Min_extent_cells.
		note
			testing: "covers/{OCR_FIGURE_FINDER}.candidates_from_grids"
		local
			f: OCR_FIGURE_FINDER
			ink, text_mask: ARRAY [BOOLEAN]
			r: ARRAYED_LIST [TUPLE [x, y, w, h: INTEGER]]
			row, col: INTEGER
		do
			create f.make
			create ink.make_filled (False, 1, 12 * 8)
			create text_mask.make_filled (False, 1, 12 * 8)
			from
				row := 2
			until
				row > 5
			loop
				from
					col := 2
				until
					col > 5
				loop
					ink [(row - 1) * 12 + col] := True
					col := col + 1
				end
				row := row + 1
			end
			ink [(7 - 1) * 12 + 11] := True
			r := f.candidates_from_grids (12, 8, ink, text_mask)
			assert_integers_equal ("one candidate - the blob; the speck filtered", 1, r.count)
			assert_integers_equal ("dilated blob starts at cell 1 -> px 0", 0, r.first.x)
			assert_integers_equal ("and spans 6 cells -> 96 px", 96, r.first.w)
			assert_integers_equal ("square", 96, r.first.h)
		end

	test_finder_text_mask_wins
			-- The same ink under the text mask is prose, not a figure.
		note
			testing: "covers/{OCR_FIGURE_FINDER}.candidates_from_grids"
		local
			f: OCR_FIGURE_FINDER
			ink, text_mask: ARRAY [BOOLEAN]
			row, col: INTEGER
		do
			create f.make
			create ink.make_filled (False, 1, 12 * 8)
			create text_mask.make_filled (False, 1, 12 * 8)
			from
				row := 2
			until
				row > 5
			loop
				from
					col := 2
				until
					col > 5
				loop
					ink [(row - 1) * 12 + col] := True
					text_mask [(row - 1) * 12 + col] := True
					col := col + 1
				end
				row := row + 1
			end
			assert_integers_equal ("masked ink is not a candidate", 0,
				f.candidates_from_grids (12, 8, ink, text_mask).count)
		end

feature -- Test: OCR_MD_WEAVER (marker pairing)

	test_weaver_pairs_extras_and_leftovers
		note
			testing: "covers/{OCR_MD_WEAVER}.woven"
		local
			w: OCR_MD_WEAVER
			links: ARRAYED_LIST [READABLE_STRING_32]
		do
			create w
			create links.make (2)
			links.extend ({STRING_32} "images/p1_fig1.png")
			links.extend ({STRING_32} "images/p1_fig2.png")
			assert_strings_equal ("marker replaced in place, extra appended",
				{STRING_32} "alpha%N![Figure](images/p1_fig1.png)%Nbeta%N%N![Figure](images/p1_fig2.png)",
				w.woven ({STRING_32} "alpha%N![figure](figure)%Nbeta", links))
			create links.make (1)
			links.extend ({STRING_32} "images/p2_fig1.png")
			assert_strings_equal ("leftover marker dropped whole",
				{STRING_32} "![Figure](images/p2_fig1.png)%Nmiddle",
				w.woven ({STRING_32} "![figure](figure)%Nmiddle%N![figure](figure)", links))
			create links.make (0)
			assert_strings_equal ("no links: markers vanish, prose stands",
				{STRING_32} "only%Nprose",
				w.woven ({STRING_32} "only%N![figure](figure)%Nprose", links))
		end

feature -- Test: OCR_RUN_METRICS (first-guess freeze and drift)

	test_metrics_freezes_first_estimate
			-- The first computable ETA is frozen and never re-frozen.
		note
			testing: "covers/{OCR_RUN_METRICS}.note_capture_at"
		local
			m: OCR_RUN_METRICS
		do
			create m.make
			m.note_start
			assert_false ("nothing frozen at start", m.has_initial_estimate)
			m.note_capture_at ("Page 10 of 100", 10)
			assert_false ("one sample cannot project", m.has_initial_estimate)
			m.note_capture_at ("Page 12 of 100", 70)
				-- 2 pages over 60s: 2.0 pg/min; 88 left -> 44 minutes
			assert_true ("the first ETA freezes the moment it exists", m.has_initial_estimate)
			assert_integers_equal ("frozen at 44 minutes", 44, m.initial_eta_minutes)
			assert_integers_equal ("on pace at the freeze", 0, m.drift_minutes)
			m.note_capture_at ("Page 14 of 100", 130)
			assert_integers_equal ("still frozen at 44", 44, m.initial_eta_minutes)
			assert_true ("started stamp reads back", not m.started_display.is_empty)
		end

	test_metrics_drift_runs_late
			-- A slowdown moves the projected finish past the first
			-- guess; drift reports the gap in minutes, positive.
		note
			testing: "covers/{OCR_RUN_METRICS}.drift_minutes"
		local
			m: OCR_RUN_METRICS
		do
			create m.make
			m.note_start
			m.note_capture_at ("Page 10 of 100", 10)
			m.note_capture_at ("Page 12 of 100", 70)
				-- frozen: 44 min at 70s -> finish at 2710s
			m.note_capture_at ("Page 14 of 100", 130)
				-- window 120s / 4 pages: still 2.0 pg/min -> ETA 43 at 130s
			assert_integers_equal ("steady pace drifts nothing", 0, m.drift_minutes)
			m.note_capture_at ("Page 15 of 100", 250)
				-- window 240s / 5 pages: 1.25 pg/min -> ETA 68 at 250s
				-- projected 4330s vs frozen 2710s = +27 minutes late
			assert_integers_equal ("the slowdown shows as +27", 27, m.drift_minutes)
		end

	test_metrics_drift_beats_the_guess
			-- A speedup pulls the finish ahead of the first guess;
			-- drift goes negative.
		note
			testing: "covers/{OCR_RUN_METRICS}.drift_minutes"
		local
			m: OCR_RUN_METRICS
		do
			create m.make
			m.note_start
			m.note_capture_at ("Page 10 of 100", 60)
			m.note_capture_at ("Page 12 of 100", 120)
				-- frozen: 44 min at 120s -> finish at 2760s
			m.note_capture_at ("Page 20 of 100", 180)
				-- window 120s / 10 pages: 5.0 pg/min -> ETA 16 at 180s
				-- projected 1140s vs frozen 2760s = -27 minutes
			assert_integers_equal ("the speedup shows as -27", -27, m.drift_minutes)
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
