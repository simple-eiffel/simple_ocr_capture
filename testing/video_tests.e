note
	description: "[
		Tests for the video caption intake's pure parts: the link
		parser, the track URL rewrite, the json3 assembler, the file
		stem cleaner and the output prompt's path arithmetic. The two
		network calls are covered by the --captions CLI mode against a
		real video, not here.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	VIDEO_TESTS

inherit
	TEST_SET_BASE

feature -- Test: OCR_VIDEO_ID

	test_video_id_forms
			-- Every link shape YouTube hands out yields the same id.
		note
			testing: "covers/{OCR_VIDEO_ID}.video_id_of"
		local
			l_ids: OCR_VIDEO_ID
		do
			create l_ids
			assert_true ("watch", l_ids.video_id_of ("https://www.youtube.com/watch?v=fouffdu6dDk").same_string ("fouffdu6dDk"))
			assert_true ("watch with more params", l_ids.video_id_of ("https://www.youtube.com/watch?t=120&v=fouffdu6dDk&list=PL1").same_string ("fouffdu6dDk"))
			assert_true ("short link", l_ids.video_id_of ("https://youtu.be/fouffdu6dDk?si=abc").same_string ("fouffdu6dDk"))
			assert_true ("live", l_ids.video_id_of ("https://www.youtube.com/live/elAhMGTGn48").same_string ("elAhMGTGn48"))
			assert_true ("shorts", l_ids.video_id_of ("https://youtube.com/shorts/elAhMGTGn48/").same_string ("elAhMGTGn48"))
			assert_true ("embed", l_ids.video_id_of ("https://www.youtube.com/embed/elAhMGTGn48?autoplay=1").same_string ("elAhMGTGn48"))
			assert_true ("bare id", l_ids.video_id_of ("  elAhMGTGn48 ").same_string ("elAhMGTGn48"))
		end

	test_video_id_refusals
			-- Not-a-link and wrong-length ids yield nothing.
		note
			testing: "covers/{OCR_VIDEO_ID}.video_id_of"
		local
			l_ids: OCR_VIDEO_ID
		do
			create l_ids
			assert_true ("empty", l_ids.video_id_of ("").is_empty)
			assert_true ("prose", l_ids.video_id_of ("watch this video").is_empty)
			assert_true ("short id", l_ids.video_id_of ("https://youtu.be/abc").is_empty)
			assert_true ("long id", l_ids.video_id_of ("https://www.youtube.com/watch?v=fouffdu6dDkX").is_empty)
			assert_true ("pv is not v", l_ids.video_id_of ("https://example.com/?pv=fouffdu6dDk").is_empty)
			assert_true ("wide characters dropped", l_ids.video_id_of ({STRING_32} "https://youtu.be/fouffdu6dDk%/8364/").same_string ("fouffdu6dDk"))
		end

feature -- Test: OCR_CAPTION_TRACK

	test_json3_url_replaces_fmt
			-- The Android URL carries fmt=srv3; it must be replaced,
			-- since the server honours the first fmt it sees.
		note
			testing: "covers/{OCR_CAPTION_TRACK}.json3_url"
		local
			l_track: OCR_CAPTION_TRACK
			l_url: STRING_8
		do
			create l_track.make
			l_url := l_track.json3_url ({STRING_32} "https://www.youtube.com/api/timedtext?v=abc&fmt=srv3&lang=en")
			assert_true ("srv3 gone", not l_url.has_substring ("srv3"))
			assert_true ("json3 asked", l_url.ends_with ("&fmt=json3"))
			assert_true ("lang kept", l_url.has_substring ("&lang=en"))
			l_url := l_track.json3_url ({STRING_32} "https://www.youtube.com/api/timedtext?v=abc&lang=en&fmt=srv3")
			assert_true ("trailing fmt gone", l_url.same_string ("https://www.youtube.com/api/timedtext?v=abc&lang=en&fmt=json3"))
			l_url := l_track.json3_url ({STRING_32} "https://www.youtube.com/api/timedtext?fmt=srv3&v=abc")
			assert_true ("leading fmt gone", l_url.same_string ("https://www.youtube.com/api/timedtext?v=abc&fmt=json3"))
			l_url := l_track.json3_url ({STRING_32} "https://www.youtube.com/api/timedtext?v=abc")
			assert_true ("appended when absent", l_url.same_string ("https://www.youtube.com/api/timedtext?v=abc&fmt=json3"))
			l_url := l_track.json3_url ({STRING_32} "https://www.youtube.com/api/timedtext")
			assert_true ("query started when none", l_url.same_string ("https://www.youtube.com/api/timedtext?fmt=json3"))
		end

	test_preferred_track_ranking
			-- Uploaded English beats automatic English beats anything else.
		note
			testing: "covers/{OCR_CAPTION_TRACK}.preferred_track"
		local
			l_track: OCR_CAPTION_TRACK
		do
			create l_track.make
			assert_integers_equal ("none", 0, l_track.preferred_track)
			l_track.tracks.extend ([{STRING_32} "de", {STRING_32} "", {STRING_32} "German", {STRING_32} "u1"])
			l_track.tracks.extend ([{STRING_32} "en", {STRING_32} "asr", {STRING_32} "English (auto-generated)", {STRING_32} "u2"])
			assert_integers_equal ("auto english over uploaded german", 2, l_track.preferred_track)
			l_track.tracks.extend ([{STRING_32} "en-US", {STRING_32} "", {STRING_32} "English", {STRING_32} "u3"])
			assert_integers_equal ("uploaded english wins", 3, l_track.preferred_track)
			assert_true ("auto caption named", l_track.track_caption (2).same_string_general ("English (auto-generated)"))
		end

feature -- Test: OCR_CAPTION_TEXT

	test_caption_text_assembles_events
			-- Timing-only and newline-only events carry no words; a
			-- ">>" event starts a paragraph.
		note
			testing: "covers/{OCR_CAPTION_TEXT}.load_json3"
		local
			l_text: OCR_CAPTION_TEXT
		do
			create l_text.make
			assert_true ("loaded", l_text.load_json3 (Sample_track))
			assert_integers_equal ("text events", 3, l_text.event_count)
			assert_integers_equal ("paragraphs", 2, l_text.paragraphs.count)
			assert_true ("first paragraph", l_text.paragraphs.i_th (1).same_string_general ("We die, we go to heaven."))
			assert_true ("speaker change", l_text.paragraphs.i_th (2).same_string_general (">> Right?"))
			assert_integers_equal ("words", 8, l_text.word_count)
				-- the ">>" speaker mark counts as a word, as it will in the file
			assert_integers_equal ("duration", 1420440, l_text.duration_ms)
			assert_true ("clock", l_text.duration_caption.same_string_general ("23:40"))
			assert_true ("plain text", l_text.plain_text.same_string_general ("We die, we go to heaven.%N%N>> Right?"))
		end

	test_caption_text_breaks_on_time
			-- A sentence end after a minute breaks; mid-sentence does
			-- not; two minutes breaks regardless.
		note
			testing: "covers/{OCR_CAPTION_TEXT}.load_json3"
		local
			l_text: OCR_CAPTION_TEXT
		do
			create l_text.make
			assert_true ("loaded", l_text.load_json3 (Timed_track))
			assert_integers_equal ("paragraphs", 3, l_text.paragraphs.count)
			assert_true ("one", l_text.paragraphs.i_th (1).same_string_general ("One. Two."))
			assert_true ("two", l_text.paragraphs.i_th (2).same_string_general ("Three four"))
			assert_true ("three", l_text.paragraphs.i_th (3).same_string_general ("Five"))
		end

	test_caption_text_refuses_junk
		note
			testing: "covers/{OCR_CAPTION_TEXT}.load_json3"
		local
			l_text: OCR_CAPTION_TEXT
		do
			create l_text.make
			assert_false ("empty", l_text.load_json3 (""))
			assert_true ("says so", not l_text.last_error.is_empty)
			assert_false ("html", l_text.load_json3 ("<!DOCTYPE html><html></html>"))
			assert_false ("no events", l_text.load_json3 ("{%"wireMagic%": %"pb3%"}"))
			assert_false ("nothing loaded", l_text.is_loaded)
		end

	test_clock_caption
		note
			testing: "covers/{OCR_CAPTION_TEXT}.clock_caption"
		local
			l_text: OCR_CAPTION_TEXT
		do
			create l_text.make
			assert_true ("seconds", l_text.clock_caption (7).same_string_general ("0:07"))
			assert_true ("minutes", l_text.clock_caption (1419).same_string_general ("23:39"))
			assert_true ("hours", l_text.clock_caption (3895).same_string_general ("1:04:55"))
		end

feature -- Test: OCR_VIDEO_RUN

	test_safe_file_stem
			-- Reserved characters go, spaces collapse, length is capped,
			-- nothing yields "video".
		note
			testing: "covers/{OCR_VIDEO_RUN}.safe_file_stem"
		local
			l_run: OCR_VIDEO_RUN
			l_long: STRING_32
		do
			create l_run.make (create {OCR_SETTINGS})
			assert_true ("apostrophe kept", l_run.safe_file_stem ({STRING_32} "Heaven Isn't the Whole Story").same_string_general ("Heaven Isn't the Whole Story"))
			assert_true ("reserved dropped", l_run.safe_file_stem ({STRING_32} "Q: What/Why? *A* <B> |C| %"D%"").same_string_general ("Q WhatWhy A B C D"))
			assert_true ("newlines collapse", l_run.safe_file_stem ({STRING_32} "  a %N%N b   c  ").same_string_general ("a b c"))
			assert_true ("empty falls back", l_run.safe_file_stem ({STRING_32} "???").same_string_general ("video"))
			create l_long.make_filled ('x', 200)
			assert_integers_equal ("capped", l_run.Stem_cap, l_run.safe_file_stem (l_long).count)
			assert_true ("suggested name is markdown", l_run.suggested_file_name.same_string_general ("video.md"))
			assert_true ("md path", l_run.is_markdown_path ("C:\x\Talk.MD"))
			assert_false ("txt path", l_run.is_markdown_path ("C:\x\Talk.txt"))
		end

	test_safe_file_stem_caps_a_title_that_breaks_on_the_boundary
			-- A space landing one short of the cap used to overshoot it.
			--
			-- The old loop tested the cap only at the top but could append
			-- TWO characters in a pass - a held-over space, then the
			-- character after it - so a title with a space at exactly
			-- `Stem_cap' - 1 came out one character too long and the
			-- routine failed its own postcondition. The existing cap test
			-- could not catch it: 200 identical characters have no space
			-- in them. Found by the first channel harvest, 125 titles in.
		note
			testing: "covers/{OCR_VIDEO_RUN}.safe_file_stem"
		local
			l_run: OCR_VIDEO_RUN
			l_title: STRING_32
			i: INTEGER
		do
			create l_run.make (create {OCR_SETTINGS})
				-- Every offset a space can land on, not just the bad one:
				-- the boundary is what broke, so walk across it.
			from
				i := l_run.Stem_cap - 4
			until
				i > l_run.Stem_cap + 4
			loop
				create l_title.make_filled ('x', i)
				l_title.append_string_general (" and more words after the cap")
				assert_true ("capped with a space at offset " + i.out,
					l_run.safe_file_stem (l_title).count <= l_run.Stem_cap)
				i := i + 1
			end
			create l_title.make_filled ('x', l_run.Stem_cap - 1)
			l_title.append_string_general (" a")
			assert_integers_equal ("the exact case that failed", l_run.Stem_cap - 1,
				l_run.safe_file_stem (l_title).count)
			assert_false ("and no trailing space is left behind",
				l_run.safe_file_stem (l_title).item (l_run.safe_file_stem (l_title).count).is_space)
		end

	test_blocking_before_probe
		note
			testing: "covers/{OCR_VIDEO_RUN}.blocking_reason"
		local
			l_run: OCR_VIDEO_RUN
		do
			create l_run.make (create {OCR_SETTINGS})
			assert_false ("not fetchable", l_run.can_fetch)
			assert_true ("reason given", not l_run.blocking_reason.is_empty)
			assert_true ("summary invites", l_run.summary_line.has_substring ({STRING_32} "Look Up"))
		end

feature -- Test: OCR_VIDEO_QUEUE

	test_queue_adds_and_folds_links
			-- Several links at once; duplicates by id fold; junk is
			-- counted and left out.
		note
			testing: "covers/{OCR_VIDEO_QUEUE}.add_links"
		local
			l_queue: OCR_VIDEO_QUEUE
			l_added: INTEGER
		do
			create l_queue.make (create {OCR_SETTINGS})
			l_added := l_queue.add_links ("https://youtu.be/fouffdu6dDk%Nhttps://www.youtube.com/watch?v=fouffdu6dDk, notalink%N  https://www.youtube.com/live/elAhMGTGn48  ")
			assert_integers_equal ("two added", 2, l_added)
			assert_integers_equal ("one duplicate", 1, l_queue.last_duplicates)
			assert_integers_equal ("one rejected", 1, l_queue.last_rejected)
			assert_integers_equal ("two rows", 2, l_queue.count)
			assert_integers_equal ("both pending", 2, l_queue.pending_count)
			assert_true ("pending lookup", l_queue.has_pending_lookup)
			assert_false ("not fetching", l_queue.is_fetching)
			assert_true ("found by id", attached l_queue.item_of_id ("elAhMGTGn48"))
			assert_integers_equal ("nothing on empty", 0, l_queue.add_links (""))
		end

	test_queue_names_stay_distinct
			-- Two rows named alike get numeric suffixes; renaming keeps
			-- the .md extension.
		note
			testing: "covers/{OCR_VIDEO_QUEUE}.distinct_name"
		local
			l_queue: OCR_VIDEO_QUEUE
			l_added: INTEGER
		do
			create l_queue.make (create {OCR_SETTINGS})
			l_added := l_queue.add_links ("https://youtu.be/fouffdu6dDk https://youtu.be/elAhMGTGn48 https://youtu.be/b_QpN0VRndQ")
			l_queue.rename_item (1, "Talk")
			assert_true ("md appended", l_queue.items.i_th (1).file_name.same_string_general ("Talk.md"))
			l_queue.rename_item (2, "Talk.md")
			assert_true ("second distinct", l_queue.items.i_th (2).file_name.same_string_general ("Talk (2).md"))
			l_queue.rename_item (3, "talk.MD")
			assert_true ("case-insensitive distinct", l_queue.items.i_th (3).file_name.same_string_general ("talk (2).MD") or l_queue.items.i_th (3).file_name.same_string_general ("talk (3).MD"))
			assert_true ("own name is not a clash", l_queue.distinct_name ("Talk.md", l_queue.items.i_th (1)).same_string_general ("Talk.md"))
		end

	test_queue_remove_and_clear
		note
			testing: "covers/{OCR_VIDEO_QUEUE}.remove, covers/{OCR_VIDEO_QUEUE}.clear_finished"
		local
			l_queue: OCR_VIDEO_QUEUE
			l_added: INTEGER
		do
			create l_queue.make (create {OCR_SETTINGS})
			l_added := l_queue.add_links ("https://youtu.be/fouffdu6dDk https://youtu.be/elAhMGTGn48")
			l_queue.remove (1)
			assert_integers_equal ("one left", 1, l_queue.count)
			assert_true ("the second remains", l_queue.items.i_th (1).video_id.same_string ("elAhMGTGn48"))
			l_queue.clear_finished
			assert_integers_equal ("pending rows stay", 1, l_queue.count)
		end

	test_item_states_before_lookup
		note
			testing: "covers/{OCR_VIDEO_ITEM}.status_caption"
		local
			l_item: OCR_VIDEO_ITEM
		do
			create l_item.make ("https://youtu.be/fouffdu6dDk", create {OCR_SETTINGS})
			assert_true ("pending", l_item.is_pending)
			assert_false ("not finished", l_item.is_finished)
			assert_true ("title is the link until looked up", l_item.title.same_string_general ("https://youtu.be/fouffdu6dDk"))
			assert_true ("status says waiting", l_item.status_caption.has_substring ({STRING_32} "waiting"))
			assert_true ("no captions caption yet", l_item.captions_caption.is_empty)
			l_item.set_file_name ("x")
			assert_true ("md by default", l_item.file_name.same_string_general ("x.md"))
		end

feature -- Test: OCR_SW_OUTPUT_PROMPT

	test_output_prompt_paths
			-- Folder and name join with one backslash; either missing
			-- leaves the path empty and the prompt incomplete.
		note
			testing: "covers/{OCR_SW_OUTPUT_PROMPT}.full_path"
		local
			l_prompt: OCR_SW_OUTPUT_PROMPT
		do
			create l_prompt.make_prompt ("Start", "why", "C:\Books", "book.txt", "Start")
			assert_true ("complete", l_prompt.is_complete)
			assert_true ("joined", l_prompt.full_path.same_string_general ("C:\Books\book.txt"))
			l_prompt.set_folder ("C:\Books\")
			assert_true ("no double slash", l_prompt.full_path.same_string_general ("C:\Books\book.txt"))
			l_prompt.set_file_name ("   ")
			assert_false ("name missing", l_prompt.is_complete)
			assert_true ("path empty", l_prompt.full_path.is_empty)
			assert_true ("status names the gap", l_prompt.status_line.has_substring ({STRING_32} "Name the file"))
			l_prompt.set_file_name ("x.txt")
			l_prompt.set_folder ("")
			assert_true ("folder status", l_prompt.status_line.has_substring ({STRING_32} "Choose the folder"))
		end

	test_output_prompt_accept_needs_both
			-- The verb does nothing until both values are present.
		note
			testing: "covers/{OCR_SW_OUTPUT_PROMPT}.press_accept"
		local
			l_prompt: OCR_SW_OUTPUT_PROMPT
			l_seen: ARRAYED_LIST [STRING_32]
		do
			create l_seen.make (2)
			create l_prompt.make_prompt ("Start", "why", "", "book.txt", "Start")
			l_prompt.set_on_accept (agent (a_f, a_n: STRING_32; a_list: ARRAYED_LIST [STRING_32])
				do
					a_list.extend (a_f)
					a_list.extend (a_n)
				end (?, ?, l_seen))
			l_prompt.press_accept
			assert_integers_equal ("refused without folder", 0, l_seen.count)
			l_prompt.set_folder ("D:\out")
			l_prompt.press_accept
			assert_integers_equal ("accepted", 2, l_seen.count)
			assert_true ("folder passed", l_seen.i_th (1).same_string_general ("D:\out"))
			assert_true ("name passed", l_seen.i_th (2).same_string_general ("book.txt"))
		end

feature {NONE} -- Samples

	Sample_track: STRING_32 = "[
		{"events":[{"tStartMs":0,"dDurationMs":1420440,"id":1,"wpWinPosId":1},
		{"tStartMs":0,"dDurationMs":6040,"wWinId":1,"segs":[{"utf8":"We"},{"utf8":" die,","tOffsetMs":280},{"utf8":" we"}]},
		{"tStartMs":4710,"dDurationMs":1330,"wWinId":1,"aAppend":1,"segs":[{"utf8":"\n"}]},
		{"tStartMs":6030,"dDurationMs":2000,"wWinId":1,"segs":[{"utf8":"go to heaven."}]},
		{"tStartMs":70000,"dDurationMs":2000,"wWinId":1,"segs":[{"utf8":">> Right?"}]}]}
	]"
			-- Five events shaped like the real track: a timing-only
			-- event, a word event, a newline-only append event, a
			-- second word event, and a speaker change.

	Timed_track: STRING_32 = "[
		{"events":[
		{"tStartMs":0,"dDurationMs":1000,"segs":[{"utf8":"One."}]},
		{"tStartMs":30000,"dDurationMs":1000,"segs":[{"utf8":"Two."}]},
		{"tStartMs":61000,"dDurationMs":1000,"segs":[{"utf8":"Three"}]},
		{"tStartMs":125000,"dDurationMs":1000,"segs":[{"utf8":"four"}]},
		{"tStartMs":190000,"dDurationMs":1000,"segs":[{"utf8":"Five"}]}]}
	]"
			-- "Two." ends a sentence after 30 s: no break yet. "Three"
			-- arrives at 61 s after a sentence end: break. "four" at
			-- 125 s is 64 s into a paragraph with no sentence end: no
			-- break. "Five" at 190 s is 129 s in: hard break.

end
