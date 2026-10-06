note
	description: "[
		Tests for the channel harvest's pure parts: the link forms a
		channel can be named by, the folder name built from a channel
		title, the brace-balance cutter that isolates one video out of a
		browse reply, and the reading of ids, titles and the
		continuation token out of that reply.

		The reply used here is a small stand-in with the real one's
		shape - a brace inside quoted text, an escaped quote inside a
		title, a Shorts entry among the videos, a continuation item at
		the end - because a real reply is 400 KB. The live sweep is
		covered by the --channel CLI mode against a real channel.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	CHANNEL_TESTS

inherit
	TEST_SET_BASE

feature -- Test: OCR_CHANNEL_SWEEP link forms

	test_channel_page_url_forms
			-- Every way a channel gets named lands on its Videos page.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.channel_page_url"
		local
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_sweep.make
			assert_true ("handle link",
				l_sweep.channel_page_url ("https://www.youtube.com/@BibleLine").same_string ("https://www.youtube.com/@BibleLine/videos"))
			assert_true ("handle link already on videos",
				l_sweep.channel_page_url ("https://www.youtube.com/@BibleLine/videos").same_string ("https://www.youtube.com/@BibleLine/videos"))
			assert_true ("handle with query",
				l_sweep.channel_page_url ("https://www.youtube.com/@BibleLine/streams?view=0").same_string ("https://www.youtube.com/@BibleLine/videos"))
			assert_true ("bare handle",
				l_sweep.channel_page_url ("@BibleLine").same_string ("https://www.youtube.com/@BibleLine/videos"))
			assert_true ("bare name without the at",
				l_sweep.channel_page_url ("BibleLine").same_string ("https://www.youtube.com/@BibleLine/videos"))
			assert_true ("channel id link",
				l_sweep.channel_page_url ("https://www.youtube.com/channel/UClf3emBfLV7ywCTzsUbCz9w").same_string ("https://www.youtube.com/channel/UClf3emBfLV7ywCTzsUbCz9w/videos"))
			assert_true ("bare channel id",
				l_sweep.channel_page_url ("UClf3emBfLV7ywCTzsUbCz9w").same_string ("https://www.youtube.com/channel/UClf3emBfLV7ywCTzsUbCz9w/videos"))
			assert_true ("legacy c link",
				l_sweep.channel_page_url ("https://www.youtube.com/c/SomeName/about").same_string ("https://www.youtube.com/c/SomeName/videos"))
			assert_true ("legacy user link",
				l_sweep.channel_page_url ("https://www.youtube.com/user/SomeName").same_string ("https://www.youtube.com/user/SomeName/videos"))
			assert_true ("surrounding space",
				l_sweep.channel_page_url ("   @BibleLine   ").same_string ("https://www.youtube.com/@BibleLine/videos"))
		end

	test_channel_page_url_refusals
			-- What names no channel yields nothing, quietly.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.channel_page_url"
		local
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_sweep.make
			assert_true ("empty", l_sweep.channel_page_url ("").is_empty)
			assert_true ("blank", l_sweep.channel_page_url ("    ").is_empty)
			assert_true ("a watch link is not a channel", l_sweep.channel_page_url ("https://www.youtube.com/watch?v=fouffdu6dDk").is_empty)
		end

	test_is_channel_id
			-- A channel id is exactly UC and twenty-two more.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.is_channel_id"
		local
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_sweep.make
			assert_true ("real id", l_sweep.is_channel_id ("UClf3emBfLV7ywCTzsUbCz9w"))
			assert_true ("too short", not l_sweep.is_channel_id ("UClf3emBfLV7ywCTzsUbCz9"))
			assert_true ("too long", not l_sweep.is_channel_id ("UClf3emBfLV7ywCTzsUbCz9ww"))
			assert_true ("wrong prefix", not l_sweep.is_channel_id ("UUlf3emBfLV7ywCTzsUbCz9w"))
		end

feature -- Test: OCR_CHANNEL_SWEEP folder naming

	test_folder_name_cleans
			-- A channel title becomes a folder Windows will accept.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.folder_name_of"
		local
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_sweep.make
			assert_true ("plain name kept", l_sweep.folder_name_of ({STRING_32} "BibleLine").same_string_general ("BibleLine"))
				-- A reserved character is dropped, not turned into a space:
				-- the same rule OCR_VIDEO_RUN.safe_file_stem applies to a
				-- video title, so a folder and the files in it are named
				-- by one rule.
			assert_true ("reserved dropped", l_sweep.folder_name_of ({STRING_32} "Q&A: what/now?").same_string_general ("Q&A whatnow"))
			assert_true ("trailing dot dropped", l_sweep.folder_name_of ({STRING_32} "Chapter 1...").same_string_general ("Chapter 1"))
			assert_true ("never empty", not l_sweep.folder_name_of ({STRING_32} "///").is_empty)
			assert_true ("wide characters kept", l_sweep.folder_name_of ({STRING_32} "Caf%/233/").same_string_general ({STRING_32} "Caf%/233/"))
		end

feature -- Test: OCR_CHANNEL_SWEEP reply reading

	test_matching_brace_respects_strings
			-- A brace inside quoted text does not close an object, and
			-- a quote an escape protects does not end a string.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.matching_brace"
		local
			l_sweep: OCR_CHANNEL_SWEEP
			l_text: STRING_8
		do
			create l_sweep.make
			l_text := "{%"a%":1}"
			assert_integers_equal ("simple object", l_text.count, l_sweep.matching_brace (l_text, 1))
			l_text := "{%"a%":%"}}}%"}"
			assert_integers_equal ("braces inside a string ignored", l_text.count, l_sweep.matching_brace (l_text, 1))
			l_text := "{%"a%":{%"b%":2}}"
			assert_integers_equal ("nested object", l_text.count, l_sweep.matching_brace (l_text, 1))
				-- {"a":"say \"}"} - the escape protects the quote, so the
				-- brace after it is still inside the string.
			l_text := "{%"a%":%"say \%"}%"}"
			assert_integers_equal ("escaped quote inside a string", l_text.count, l_sweep.matching_brace (l_text, 1))
			assert_integers_equal ("unclosed object", 0, l_sweep.matching_brace ("{%"a%":1", 1))
		end

	test_videos_in_reads_ids_and_titles
			-- Videos come out with their ids and titles; Shorts do not.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.videos_in"
		local
			l_sweep: OCR_CHANNEL_SWEEP
			l_found: ARRAYED_LIST [OCR_CHANNEL_VIDEO]
		do
			create l_sweep.make
			l_found := l_sweep.videos_in (sample_reply)
			assert_integers_equal ("two videos, the Shorts entry left out", 2, l_found.count)
			assert_true ("first id", l_found.i_th (1).video_id.same_string ("Rv_8Ez1wOtU"))
			assert_true ("first title keeps its escaped quote",
				l_found.i_th (1).title.same_string_general ({STRING_32} "The %"comments%" never hold back"))
			assert_true ("second id", l_found.i_th (2).video_id.same_string ("8Bn_q_w_ohI"))
			assert_true ("second title", l_found.i_th (2).title.same_string_general ("Another study"))
			assert_true ("nothing is categorised yet", not l_found.i_th (1).is_categorised)
		end

	test_next_token_finds_the_grid_continuation
			-- The grid's own token is taken, not a sort chip's.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.next_token"
		local
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_sweep.make
			assert_true ("token read", l_sweep.next_token (sample_reply).same_string ("4qmFsgTOKEN"))
			assert_true ("no continuation item, no token",
				l_sweep.next_token ("{%"contents%":[],%"token%":%"not-a-continuation%"}").is_empty)
		end

	test_sweep_starts_empty
			-- Before a resolve there is no channel and nothing to sweep.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.make"
		local
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_sweep.make
			assert_true ("not resolved", not l_sweep.is_resolved)
			assert_true ("not sweeping", not l_sweep.is_sweeping)
			assert_true ("not swept", not l_sweep.is_swept)
			assert_integers_equal ("no videos", 0, l_sweep.count)
			assert_true ("says what to do", not l_sweep.summary_line.is_empty)
			assert_integers_equal ("no listing open yet", 0, l_sweep.tab_index)
		end

	test_sweep_walks_both_listings
			-- Videos and Streams are different tabs and a channel keeps
			-- different things in each; reading one is not reading the
			-- channel.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.tab_params"
		local
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_sweep.make
			assert_integers_equal ("two listings", 2, l_sweep.Tab_count)
			assert_true ("first is Videos", l_sweep.tab_params (1).same_string (l_sweep.Videos_tab_params))
			assert_true ("second is Streams", l_sweep.tab_params (2).same_string (l_sweep.Streams_tab_params))
				-- The params are what YouTube sorts on; two listings that
				-- asked the same thing would sweep one tab twice.
			assert_true ("and they differ", not l_sweep.Videos_tab_params.same_string (l_sweep.Streams_tab_params))
			assert_true ("named for the status line", l_sweep.tab_name (1).same_string_general ("Videos"))
			assert_true ("named for the status line", l_sweep.tab_name (2).same_string_general ("Live"))
			assert_true ("recorded as videos", l_sweep.tab_key (1).same_string ("videos"))
			assert_true ("recorded as streams", l_sweep.tab_key (2).same_string ("streams"))
		end

	test_tab_choice_reads_a_tab_list
			-- What `--tabs' accepts, and what it refuses.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.tab_choice"
		local
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_sweep.make
			assert_true ("both by list", attached l_sweep.tab_choice ("videos,streams") as al
				and then al.error.is_empty and then al.videos and then al.streams)
			assert_true ("streams alone", attached l_sweep.tab_choice ("streams") as al
				and then al.error.is_empty and then not al.videos and then al.streams)
			assert_true ("live is the tab's own label", attached l_sweep.tab_choice ("live") as al
				and then al.error.is_empty and then not al.videos and then al.streams)
			assert_true ("videos alone", attached l_sweep.tab_choice ("videos") as al
				and then al.error.is_empty and then al.videos and then not al.streams)
			assert_true ("case, plus and spaces", attached l_sweep.tab_choice ("Videos + LIVE") as al
				and then al.error.is_empty and then al.videos and then al.streams)
			assert_true ("both", attached l_sweep.tab_choice ("both") as al
				and then al.error.is_empty and then al.videos and then al.streams)
			assert_true ("all", attached l_sweep.tab_choice ("all") as al
				and then al.error.is_empty and then al.videos and then al.streams)
			assert_true ("a tab that is not one is refused, by name", attached l_sweep.tab_choice ("videos,shorts") as al
				and then al.error.has_substring ({STRING_32} "shorts"))
			assert_true ("nothing named is refused", attached l_sweep.tab_choice (" , ") as al
				and then not al.error.is_empty)
		end

	test_sweep_reads_only_the_wanted_tabs
			-- Both listings by default; narrowed, the sweep opens only
			-- the one asked for.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.set_tabs"
		local
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_sweep.make
			assert_true ("both by default", l_sweep.wants_videos and l_sweep.wants_streams)
			assert_integers_equal ("Videos first", 1, l_sweep.first_wanted_tab)
			assert_integers_equal ("then Live", 2, l_sweep.next_wanted_tab (1))
			assert_integers_equal ("then nothing", 0, l_sweep.next_wanted_tab (2))
			assert_true ("said in full", l_sweep.wanted_tabs_text.same_string_general ("Videos and Live"))
			l_sweep.set_tabs (False, True)
			assert_integers_equal ("Live alone opens on Live", 2, l_sweep.first_wanted_tab)
			assert_integers_equal ("and nothing follows it", 0, l_sweep.next_wanted_tab (2))
			assert_true ("said", l_sweep.wanted_tabs_text.same_string_general ("Live"))
			l_sweep.set_tabs (True, False)
			assert_integers_equal ("Videos alone", 1, l_sweep.first_wanted_tab)
			assert_integers_equal ("is not followed by Live", 0, l_sweep.next_wanted_tab (1))
				-- a new resolve is a new channel, not a new choice
			l_sweep.set_tabs (False, True)
			assert_true ("a link that names nothing", not l_sweep.resolve ("https://www.youtube.com/watch?v=fouffdu6dDk"))
			assert_true ("leaves the choice alone", not l_sweep.wants_videos and l_sweep.wants_streams)
		end

	test_broadcast_state_reads_the_badge
			-- An upcoming stream, a live one and a finished one, told
			-- apart from the listing alone; the badge's clock is the
			-- length.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.broadcast_state_of"
		local
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_sweep.make
			assert_integers_equal ("finished", l_sweep.Broadcast_done, l_sweep.broadcast_state_of (finished_lockup))
			assert_integers_equal ("upcoming", l_sweep.Broadcast_upcoming, l_sweep.broadcast_state_of (upcoming_lockup))
			assert_integers_equal ("live", l_sweep.Broadcast_live, l_sweep.broadcast_state_of (live_lockup))
			assert_integers_equal ("scheduled with no badge is upcoming", l_sweep.Broadcast_upcoming,
				l_sweep.broadcast_state_of ("{%"metadataParts%":[{%"text%":{%"content%":%"Scheduled for 10/10/26, 5:00 PM%"}}]}"))
			assert_integers_equal ("length from the badge", 7080, l_sweep.listed_seconds_of (finished_lockup))
			assert_integers_equal ("no length while upcoming", 0, l_sweep.listed_seconds_of (upcoming_lockup))
			assert_integers_equal ("minutes and seconds", 2783, l_sweep.clock_seconds ("46:23"))
			assert_integers_equal ("hours", 21600, l_sweep.clock_seconds ("6:00:00"))
			assert_integers_equal ("not a clock", 0, l_sweep.clock_seconds ("Upcoming"))
			assert_integers_equal ("not a clock either", 0, l_sweep.clock_seconds ("1:2:3:4"))
			assert_integers_equal ("nor this", 0, l_sweep.clock_seconds ("a:b"))
		end

	test_absorb_dedupes_across_tabs_and_holds_back_upcoming
			-- A stream ALSO listed under Videos is kept once, as Videos;
			-- an upcoming or live stream is set aside, not listed; the
			-- counts per tab add up.
		note
			testing: "covers/{OCR_CHANNEL_SWEEP}.absorb"
		local
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_sweep.make
			l_sweep.absorb (sample_reply, l_sweep.Tab_videos)
			assert_integers_equal ("two from Videos", 2, l_sweep.count_in_tab (l_sweep.Tab_videos))
			assert_true ("tagged videos", l_sweep.videos.first.tab.same_string ("videos"))
			l_sweep.absorb (sample_streams_reply, l_sweep.Tab_streams)
			assert_integers_equal ("one new from Live", 1, l_sweep.count_in_tab (l_sweep.Tab_streams))
			assert_integers_equal ("three in all", 3, l_sweep.count)
			assert_integers_equal ("one listed under both", 1, l_sweep.repeat_count)
			assert_true ("the repeat keeps its first tab",
				across l_sweep.videos as ic some ic.video_id.same_string ("Rv_8Ez1wOtU") and then ic.tab.same_string ("videos") end)
			assert_true ("the stream is tagged streams", l_sweep.videos.last.tab.same_string ("streams")
				and then l_sweep.videos.last.is_stream)
			assert_integers_equal ("its badge length kept", 7080, l_sweep.videos.last.listed_seconds)
			assert_integers_equal ("two held back", 2, l_sweep.held_back.count)
			assert_integers_equal ("one upcoming", 1, l_sweep.upcoming_count)
			assert_integers_equal ("one live now", 1, l_sweep.live_now_count)
			assert_true ("held back is not listed", not across l_sweep.videos as ic some ic.is_held_back end)
			assert_true ("but is known, so it is not taken twice", l_sweep.has_video ("UpComing001"))
				-- the same Live page again adds nothing and repeats nothing:
				-- a repeat within one listing is not a cross-listing
			l_sweep.absorb (sample_streams_reply, l_sweep.Tab_streams)
			assert_integers_equal ("nothing new", 0, l_sweep.last_page_added)
			assert_integers_equal ("nothing fresh to this listing", 0, l_sweep.last_page_fresh)
			assert_integers_equal ("repeat count unchanged", 1, l_sweep.repeat_count)
			assert_integers_equal ("still three", 3, l_sweep.count)
		end

feature -- Test: OCR_CHANNEL_VIDEO

	test_channel_video_link_and_category
			-- A found video carries its watch link and takes a category.
		note
			testing: "covers/{OCR_CHANNEL_VIDEO}.watch_url"
		local
			l_video: OCR_CHANNEL_VIDEO
		do
			create l_video.make ("Rv_8Ez1wOtU", {STRING_32} "A title")
			assert_true ("watch link", l_video.watch_url.same_string_general ("https://www.youtube.com/watch?v=Rv_8Ez1wOtU"))
			assert_true ("uncategorised at first", not l_video.is_categorised)
			l_video.set_category ("Q&A")
			assert_true ("categorised", l_video.is_categorised)
			assert_true ("category kept", l_video.category.same_string_general ("Q&A"))
		end

feature -- Test: OCR_TITLE_CATEGORIZER

	test_read_categories_strips_decoration
			-- Numbering, bullets and quotes come off; a sentence-long
			-- "category" and a repeat are refused.
		note
			testing: "covers/{OCR_TITLE_CATEGORIZER}.read_categories"
		local
			l_cat: OCR_TITLE_CATEGORIZER
		do
			create l_cat.make (create {OCR_SETTINGS})
			l_cat.read_categories ({STRING_32} "1. Prophecy And Eschatology%N- Q&A Sessions%N* %"Book Studies%"%NBook Studies%NThis one is far too long to be a folder name and is really a sentence%N%NComments Section%N")
			assert_integers_equal ("four kept", 4, l_cat.categories.count)
			assert_true ("numbering off", l_cat.categories.i_th (1).same_string_general ("Prophecy And Eschatology"))
			assert_true ("bullet off", l_cat.categories.i_th (2).same_string_general ("Q&A Sessions"))
			assert_true ("quotes off", l_cat.categories.i_th (3).same_string_general ("Book Studies"))
			assert_true ("last one", l_cat.categories.i_th (4).same_string_general ("Comments Section"))
			assert_true ("known", l_cat.is_known_category ({STRING_32} "book studies"))
			assert_true ("uncategorised is always known", l_cat.is_known_category (l_cat.Uncategorised))
			assert_true ("unknown", not l_cat.is_known_category ({STRING_32} "Cooking"))
		end

	test_read_categories_drops_the_models_thinking
			-- A thinking model's reasoning must not become categories.
		note
			testing: "covers/{OCR_TITLE_CATEGORIZER}.read_categories"
		local
			l_cat: OCR_TITLE_CATEGORIZER
		do
			create l_cat.make (create {OCR_SETTINGS})
			l_cat.read_categories ({STRING_32} "<think>%NLet me see. Maybe Cooking?%NOr Gardening?%N</think>%NProphecy And Eschatology%NQ&A Sessions%N")
			assert_integers_equal ("only the answer", 2, l_cat.categories.count)
			assert_true ("no thinking leaked", not l_cat.is_known_category ({STRING_32} "Cooking"))
			assert_true ("no thinking leaked either", not l_cat.is_known_category ({STRING_32} "Or Gardening"))
		end

	test_seed_adopts_categories_already_in_use
			-- A second harvest keeps the first one's vocabulary, and
			-- does not adopt the catch-all or a repeat as a heading.
		note
			testing: "covers/{OCR_TITLE_CATEGORIZER}.seed"
		local
			l_cat: OCR_TITLE_CATEGORIZER
			l_names: ARRAYED_LIST [STRING_32]
		do
			create l_cat.make (create {OCR_SETTINGS})
			create l_names.make (4)
			l_names.extend ({STRING_32} "Salvation Assurance")
			l_names.extend ({STRING_32} "Uncategorized")
			l_names.extend ({STRING_32} "salvation assurance")
			l_names.extend ({STRING_32} "Live Show Replays")
			l_names.extend ({STRING_32} "")
			l_cat.seed (l_names)
			assert_integers_equal ("two real headings", 2, l_cat.categories.count)
			assert_true ("first kept", l_cat.categories.i_th (1).same_string_general ("Salvation Assurance"))
			assert_true ("second kept", l_cat.categories.i_th (2).same_string_general ("Live Show Replays"))
			assert_true ("catch-all is not a heading", not l_cat.categories.i_th (1).same_string (l_cat.Uncategorised))
			assert_true ("but is still a known place", l_cat.is_known_category (l_cat.Uncategorised))
		end

	test_categorizer_starts_bare
			-- Nothing is proposed until the model has been asked.
		note
			testing: "covers/{OCR_TITLE_CATEGORIZER}.make"
		local
			l_cat: OCR_TITLE_CATEGORIZER
		do
			create l_cat.make (create {OCR_SETTINGS})
			assert_true ("no categories", not l_cat.has_categories)
			assert_true ("no model settled yet", l_cat.resolved_model.is_empty)
			assert_true ("no error yet", l_cat.last_error.is_empty)
		end

feature -- Test: OCR_SETTINGS channel fields

	test_channel_settings_defaults_and_overrides
			-- The harvest's settings start usable and take an override.
		note
			testing: "covers/{OCR_SETTINGS}.channel_folder_name"
		local
			l_settings: OCR_SETTINGS
			l_sweep: OCR_CHANNEL_SWEEP
		do
			create l_settings
			create l_sweep.make
			assert_true ("no folder override by default", l_settings.channel_folder_name.is_empty)
			assert_true ("categorising is on by default", l_settings.categorize_channel)
			assert_integers_equal ("batches of five", 5, l_settings.channel_batch_size)
			assert_true ("a root is always answerable", not l_settings.channel_root_or_default.is_empty)
			l_settings.set_channel_folder_name ({STRING_32} "Transcripts")
			assert_true ("override kept", l_settings.channel_folder_name.same_string_general ("Transcripts"))
				-- Whatever is typed still has to survive the folder namer.
			assert_true ("override is cleaned like a channel name",
				l_sweep.folder_name_of (l_settings.channel_folder_name).same_string_general ("Transcripts"))
			l_settings.set_channel_folder_name ({STRING_32} "Bad/Name:Here")
			assert_true ("reserved characters come out",
				l_sweep.folder_name_of (l_settings.channel_folder_name).same_string_general ("BadNameHere"))
		end

feature -- Test: OCR_CHANNEL_MANIFEST

	test_manifest_records_by_id
			-- The id is what is matched on, and a repeat is not doubled.
		note
			testing: "covers/{OCR_CHANNEL_MANIFEST}.record"
		local
			l_manifest: OCR_CHANNEL_MANIFEST
		do
			create l_manifest.make (temp_folder)
			assert_integers_equal ("empty to begin with", 0, l_manifest.count)
			assert_true ("knows nothing", not l_manifest.has ("Rv_8Ez1wOtU"))
			l_manifest.record ("Rv_8Ez1wOtU", {STRING_32} "A title.md", {STRING_32} "Q&A Sessions", {STRING_32} "A title", 754, "videos")
			assert_true ("knows it now", l_manifest.has ("Rv_8Ez1wOtU"))
			assert_integers_equal ("one entry", 1, l_manifest.count)
			l_manifest.record ("Rv_8Ez1wOtU", {STRING_32} "A renamed title.md", {STRING_32} "Other", {STRING_32} "A renamed title", 99, "streams")
			assert_integers_equal ("a repeat is not doubled", 1, l_manifest.count)
			l_manifest.record ("8Bn_q_w_ohI", {STRING_32} "Another.md", {STRING_32} "Q&A Sessions", {STRING_32} "Another", 120, "")
			assert_integers_equal ("two entries", 2, l_manifest.count)
			assert_true ("manifest sits in the channel folder", l_manifest.path.has_substring (l_manifest.File_name))

				-- the title and length are carried, so a later run can see
				-- an upstream rename without asking YouTube anything
			assert_true ("title kept", attached l_manifest.entry_of ("Rv_8Ez1wOtU") as al
				and then al.title.same_string_general ("A title"))
			assert_true ("length kept", attached l_manifest.entry_of ("Rv_8Ez1wOtU") as al2
				and then al2.length_seconds = 754)
			assert_true ("nothing recorded for a stranger", not attached l_manifest.entry_of ("ZZZZZZZZZZZ"))

				-- forget, which is how a transcript deleted from the folder
				-- gets fetched again rather than skipped for ever
			l_manifest.forget ("Rv_8Ez1wOtU")
			assert_true ("forgotten", not l_manifest.has ("Rv_8Ez1wOtU"))
			assert_integers_equal ("and only that one", 1, l_manifest.count)
			assert_true ("the other survives", l_manifest.has ("8Bn_q_w_ohI"))

				-- the file it names is not on disk in this temp folder, so
				-- the disk must win over the record
			assert_true ("recorded but absent counts as absent",
				not l_manifest.is_file_present ("8Bn_q_w_ohI"))
			assert_true ("and its path is under the channel folder",
				l_manifest.file_of ("8Bn_q_w_ohI").has_substring ({STRING_32} "Another.md"))
		end

	test_manifest_flattens_a_title_that_would_break_a_row
			-- A title carrying a tab or a newline must not be able to
			-- split the row it is written into.
		note
			testing: "covers/{OCR_CHANNEL_MANIFEST}.flattened"
		local
			l_manifest: OCR_CHANNEL_MANIFEST
		do
			create l_manifest.make (temp_folder)
			assert_true ("tab becomes a space",
				l_manifest.flattened ({STRING_32} "a%Tb").same_string_general ("a b"))
			assert_true ("newline becomes a space",
				l_manifest.flattened ({STRING_32} "a%Nb").same_string_general ("a b"))
			assert_true ("ordinary text untouched",
				l_manifest.flattened ({STRING_32} "Romans 8:1 Explained").same_string_general ("Romans 8:1 Explained"))
		end

feature -- Test: OCR_CHANNEL_HARVEST

	test_yaml_text_survives_a_hostile_title
			-- A title with a colon, a quote or a backslash must not
			-- break the front matter it goes into.
		note
			testing: "covers/{OCR_CHANNEL_HARVEST}.yaml_text"
		local
			l_harvest: OCR_CHANNEL_HARVEST
		do
			l_harvest := new_harvest
			assert_true ("plain", l_harvest.yaml_text ({STRING_32} "A title").same_string_general ("%"A title%""))
			assert_true ("colon is safe inside quotes",
				l_harvest.yaml_text ({STRING_32} "Romans: a study").same_string_general ("%"Romans: a study%""))
			assert_true ("quote escaped",
				l_harvest.yaml_text ({STRING_32} "The %"comments%" section").same_string_general ("%"The \%"comments\%" section%""))
			assert_true ("backslash escaped",
				l_harvest.yaml_text ({STRING_32} "a\b").same_string_general ("%"a\\b%""))
			assert_true ("newline dropped, not written raw",
				l_harvest.yaml_text ({STRING_32} "two%Nlines").same_string_general ("%"twolines%""))
		end

	test_slug_makes_a_tag
			-- A category becomes a tag a vault will accept.
		note
			testing: "covers/{OCR_CHANNEL_HARVEST}.slug"
		local
			l_harvest: OCR_CHANNEL_HARVEST
		do
			l_harvest := new_harvest
			assert_true ("words joined", l_harvest.slug ({STRING_32} "Prophecy And Eschatology").same_string_general ("prophecy-and-eschatology"))
			assert_true ("punctuation becomes a join", l_harvest.slug ({STRING_32} "Q&A Sessions").same_string_general ("q-a-sessions"))
			assert_true ("no leading or trailing hyphen", l_harvest.slug ({STRING_32} "  Bible Line  ").same_string_general ("bible-line"))
			assert_true ("never empty", l_harvest.slug ({STRING_32} "!!!").same_string_general ("untitled"))
		end

	test_harvest_starts_idle
			-- Nothing happens until a channel is given.
		note
			testing: "covers/{OCR_CHANNEL_HARVEST}.make"
		local
			l_harvest: OCR_CHANNEL_HARVEST
		do
			l_harvest := new_harvest
			assert_true ("not running", not l_harvest.is_running)
			assert_true ("not done", not l_harvest.is_done)
			assert_true ("not failed", not l_harvest.is_failed)
			assert_integers_equal ("nothing written", 0, l_harvest.saved_count)
			assert_integers_equal ("nothing remaining", 0, l_harvest.remaining)
			assert_true ("says what to do", not l_harvest.progress_line.is_empty)
		end

	test_harvest_refuses_a_link_that_names_no_channel
			-- A bad link fails the run rather than sweeping nothing.
		note
			testing: "covers/{OCR_CHANNEL_HARVEST}.start"
		local
			l_harvest: OCR_CHANNEL_HARVEST
		do
			l_harvest := new_harvest
			assert_true ("start accepted", l_harvest.start ("https://www.youtube.com/watch?v=fouffdu6dDk"))
			assert_true ("now resolving", l_harvest.is_running)
			l_harvest.step
			assert_true ("resolving refused it", l_harvest.is_failed)
			assert_true ("and said why", not l_harvest.last_error.is_empty)
		end

	test_manifest_keeps_the_tab_across_a_save
			-- The tab survives a save and a reload; a row written before
			-- the column reads back with none, and can be given one.
		note
			testing: "covers/{OCR_CHANNEL_MANIFEST}.set_tab"
		local
			l_manifest, l_again: OCR_CHANNEL_MANIFEST
			l_folder: STRING_32
		do
			l_folder := scratch_folder + {STRING_32} "\manifest_tab"
			fresh_folder (l_folder)
			create l_manifest.make (l_folder)
			l_manifest.record ("hVYmspocPGM", {STRING_32} "A stream.md", {STRING_32} "Lectures", {STRING_32} "A stream", 7080, "streams")
			l_manifest.record ("Rv_8Ez1wOtU", {STRING_32} "A video.md", {STRING_32} "Lectures", {STRING_32} "A video", 754, "videos")
			assert_true ("saved", l_manifest.save)
			create l_again.make (l_folder)
			assert_integers_equal ("both read back", 2, l_again.count)
			assert_true ("stream tab kept", attached l_again.entry_of ("hVYmspocPGM") as al
				and then al.tab.same_string ("streams"))
			assert_true ("video tab kept", attached l_again.entry_of ("Rv_8Ez1wOtU") as al
				and then al.tab.same_string ("videos"))

				-- a row in the five-column shape the manifest had before
			write_text (l_again.path, "# old%NoldRow0001%TOld.md%TLectures%TOld%T60%N")
			create l_again.make (l_folder)
			assert_true ("old row read", l_again.has ("oldRow0001"))
			assert_true ("with no tab", attached l_again.entry_of ("oldRow0001") as al
				and then al.tab.is_empty)
			l_again.set_tab ("oldRow0001", "streams")
			assert_true ("given one", attached l_again.entry_of ("oldRow0001") as al
				and then al.tab.same_string ("streams"))

				-- a sixth column that is not a tab key is "not known"
			write_text (l_again.path, "oddRow00001%TOdd.md%TLectures%TOdd%T60%Tshorts%N")
			create l_again.make (l_folder)
			assert_true ("an unknown tab reads as none", attached l_again.entry_of ("oddRow00001") as al
				and then al.tab.is_empty)
		end

	test_front_matter_records_the_tab
			-- A harvested transcript says which tab it came from.
		note
			testing: "covers/{OCR_CHANNEL_HARVEST}.front_matter_for"
		local
			l_harvest: OCR_CHANNEL_HARVEST
			l_video: OCR_CHANNEL_VIDEO
			l_text: STRING_32
		do
			l_harvest := new_harvest
			create l_video.make ("hVYmspocPGM", {STRING_32} "Exploring Exodus")
			l_video.set_category ({STRING_32} "Lectures")
			l_video.set_tab ("streams")
			l_text := l_harvest.front_matter_for (l_video)
			assert_true ("fenced", l_text.starts_with ({STRING_32} "---%N"))
			assert_true ("tab line", l_text.has_substring ({STRING_32} "%Ntab: streams%N"))
			assert_true ("after the id", l_text.substring_index ({STRING_32} "video_id: hVYmspocPGM", 1)
				< l_text.substring_index ({STRING_32} "tab: streams", 1))
			create l_video.make ("Rv_8Ez1wOtU", {STRING_32} "A video")
			l_video.set_category ({STRING_32} "Lectures")
			l_video.set_tab ("videos")
			assert_true ("videos too", l_harvest.front_matter_for (l_video).has_substring ({STRING_32} "%Ntab: videos%N"))
			create l_video.make ("Rv_8Ez1wOtU", {STRING_32} "A video")
			l_video.set_category ({STRING_32} "Lectures")
			assert_true ("no tab known, no tab line", not l_harvest.front_matter_for (l_video).has_substring ({STRING_32} "tab:"))
		end

	test_index_names_each_entry_tab
			-- The index says, per transcript, which tab it came from.
		note
			testing: "covers/{OCR_CHANNEL_HARVEST}.index_text"
		local
			l_harvest: OCR_CHANNEL_HARVEST
			l_manifest: OCR_CHANNEL_MANIFEST
			l_text: STRING_32
		do
			l_harvest := new_harvest
			create l_manifest.make (temp_folder)
			l_manifest.record ("hVYmspocPGM", {STRING_32} "A stream.md", {STRING_32} "Uncategorized", {STRING_32} "A stream", 7080, "streams")
			l_manifest.record ("Rv_8Ez1wOtU", {STRING_32} "A video.md", {STRING_32} "Uncategorized", {STRING_32} "A video", 754, "videos")
			l_manifest.record ("8Bn_q_w_ohI", {STRING_32} "Older.md", {STRING_32} "Uncategorized", {STRING_32} "Older", 60, "")
			l_text := l_harvest.index_text (l_manifest)
			assert_true ("stream entry", l_text.has_substring ({STRING_32} "- [[A stream]] (streams)%N"))
			assert_true ("video entry", l_text.has_substring ({STRING_32} "- [[A video]] (videos)%N"))
			assert_true ("unknown tab, plain entry", l_text.has_substring ({STRING_32} "- [[Older]]%N"))
			assert_true ("per-tab rows", l_text.has_substring ({STRING_32} "| Listed under Live (streams) |"))
		end

	test_channel_tab_settings
			-- Both tabs by default, and either can be chosen alone.
		note
			testing: "covers/{OCR_SETTINGS}.set_channel_tabs"
		local
			l_settings: OCR_SETTINGS
		do
			create l_settings
			assert_true ("videos on by default", l_settings.harvest_videos_tab)
			assert_true ("live on by default", l_settings.harvest_streams_tab)
			l_settings.set_channel_tabs (False, True)
			assert_true ("live alone", not l_settings.harvest_videos_tab and l_settings.harvest_streams_tab)
			l_settings.set_channel_tabs (True, True)
			assert_true ("both again", l_settings.harvest_videos_tab and l_settings.harvest_streams_tab)
		end

feature -- Test: OCR_CHANNEL_CARD (folder identity)

	test_card_claims_a_folder_and_refuses_another_channel
			-- The guard against pouring one channel into another's
			-- folder. Ten churches are called "Landmark Baptist Church";
			-- the name cannot be what decides.
		note
			testing: "covers/{OCR_CHANNEL_CARD}.belongs_to"
		local
			l_card: OCR_CHANNEL_CARD
			l_dir: DIRECTORY
		do
			fresh_folder (scratch_folder)
			create l_card.make (scratch_folder)
			assert_true ("a new folder has no card", not l_card.exists)
			assert_true ("and is unclaimed", not l_card.is_claimed)
			assert_true ("so anyone may write there", l_card.belongs_to ("UClf3emBfLV7ywCTzsUbCz9w"))
			assert_true ("with no complaint", l_card.mismatch_reason ("UClf3emBfLV7ywCTzsUbCz9w", {STRING_32} "BibleLine").is_empty)

				-- claim it, then read it back from disk with a new object
			assert_true ("card written",
				l_card.write ("UClf3emBfLV7ywCTzsUbCz9w", {STRING_32} "BibleLine", "BibleLine", 1298, 1297))
			create l_card.make (scratch_folder)
			assert_true ("card is on disk", l_card.exists)
			assert_true ("and claimed", l_card.is_claimed)
			assert_true ("by the right channel", l_card.channel_id.same_string ("UClf3emBfLV7ywCTzsUbCz9w"))
			assert_true ("name round-tripped", l_card.channel_name.same_string_general ("BibleLine"))
			assert_true ("handle round-tripped, at sign stripped", l_card.handle.same_string ("BibleLine"))
			assert_true ("and a first-harvest date was kept", not l_card.first_harvested.is_empty)

				-- the point of the whole class
			assert_true ("the same channel may write again", l_card.belongs_to ("UClf3emBfLV7ywCTzsUbCz9w"))
			assert_true ("a DIFFERENT channel may not", not l_card.belongs_to ("UCJzQut_blkuasyIgds_D7Iw"))
			assert_true ("and is told why",
				l_card.mismatch_reason ("UCJzQut_blkuasyIgds_D7Iw", {STRING_32} "Landmark Baptist Church").has_substring ({STRING_32} "different channel"))
			create l_dir.make_with_name (scratch_folder)
			if l_dir.exists then
				l_dir.recursive_delete
			end
		end

feature -- Test: OCR_CHANNEL_REGISTRY

	test_registry_maps_channel_id_to_its_folder
			-- A channel keeps its folder even when it renames itself.
		note
			testing: "covers/{OCR_CHANNEL_REGISTRY}.folder_for"
		local
			l_reg: OCR_CHANNEL_REGISTRY
		do
			create l_reg.make (temp_folder)
			assert_integers_equal ("starts empty", 0, l_reg.count)
			assert_true ("knows nothing", not l_reg.has ("UClf3emBfLV7ywCTzsUbCz9w"))
			assert_true ("and has no folder for it", l_reg.folder_for ("UClf3emBfLV7ywCTzsUbCz9w").is_empty)

			l_reg.record ("UClf3emBfLV7ywCTzsUbCz9w", {STRING_32} "BibleLine", {STRING_32} "BibleLine", "BibleLine", 1298, 1297)
			assert_true ("recorded", l_reg.has ("UClf3emBfLV7ywCTzsUbCz9w"))
			assert_true ("folder known", l_reg.folder_for ("UClf3emBfLV7ywCTzsUbCz9w").same_string_general ("BibleLine"))

				-- the channel renames itself; the folder must not move
			l_reg.record ("UClf3emBfLV7ywCTzsUbCz9w", {STRING_32} "BibleLine", {STRING_32} "BibleLine Ministries", "BibleLine", 1300, 1299)
			assert_integers_equal ("still one row", 1, l_reg.count)
			assert_true ("same folder as before", l_reg.folder_for ("UClf3emBfLV7ywCTzsUbCz9w").same_string_general ("BibleLine"))

				-- a second, differently-identified channel wanting the same folder
			assert_true ("folder is spoken for by someone else",
				l_reg.uses_folder ({STRING_32} "BibleLine", "UCJzQut_blkuasyIgds_D7Iw"))
			assert_true ("but not by its own owner",
				not l_reg.uses_folder ({STRING_32} "BibleLine", "UClf3emBfLV7ywCTzsUbCz9w"))

			l_reg.forget ("UClf3emBfLV7ywCTzsUbCz9w")
			assert_integers_equal ("forgotten", 0, l_reg.count)
			assert_true ("readable form still renders", not l_reg.readable_text.is_empty)
		end

feature -- Test: the dangerous hole

	test_folder_listing_is_the_authority_on_taken_names
			-- Hole 6, and the worst of them.
			--
			-- Reserved names used to be read from the MANIFEST. A folder
			-- whose manifest was deleted, renamed or never copied
			-- therefore reserved nothing, every fetch matched an existing
			-- file by name, and the writer APPENDED to it - for the whole
			-- channel, silently. The folder itself is now the authority,
			-- so the names are found whether a manifest exists or not.
		note
			testing: "covers/{OCR_CHANNEL_HARVEST}.names_in_folder"
		local
			l_harvest: OCR_CHANNEL_HARVEST
			l_names: ARRAYED_LIST [STRING_32]
			l_dir: DIRECTORY
		do
			fresh_folder (scratch_folder)
			write_stub (scratch_folder, {STRING_32} "The Book of John.md")
			write_stub (scratch_folder, {STRING_32} "Weekly Service.md")
			write_stub (scratch_folder, {STRING_32} "notes.txt")
				-- deliberately NO .harvested.tsv in this folder
			l_harvest := new_harvest
			l_names := l_harvest.names_in_folder (scratch_folder)
			assert_integers_equal ("both transcripts seen, the .txt ignored", 2, l_names.count)
			assert_true ("first found", has_name (l_names, {STRING_32} "The Book of John.md"))
			assert_true ("second found", has_name (l_names, {STRING_32} "Weekly Service.md"))
			assert_true ("and these are exactly what a queue would reserve",
				not has_name (l_names, {STRING_32} "notes.txt"))
			create l_dir.make_with_name (scratch_folder)
			if l_dir.exists then
				l_dir.recursive_delete
			end
		end

	test_candidate_leaf_prefers_the_handle_over_a_number
			-- Two channels with one name: "(@handle)" says which, "(2)"
			-- does not.
		note
			testing: "covers/{OCR_CHANNEL_HARVEST}.candidate_leaf"
		local
			l_harvest: OCR_CHANNEL_HARVEST
		do
			l_harvest := new_harvest
				-- no handle resolved on a bare harvest, so it falls to numbers
			assert_true ("numbered when no handle is known",
				l_harvest.candidate_leaf ({STRING_32} "Landmark Baptist Church", 2).same_string_general ("Landmark Baptist Church (2)"))
			assert_true ("and keeps counting",
				l_harvest.candidate_leaf ({STRING_32} "Landmark Baptist Church", 3).same_string_general ("Landmark Baptist Church (3)"))
			assert_true ("result is always a legal folder name",
				not l_harvest.candidate_leaf ({STRING_32} "Q: A/B", 2).has ('/'))
		end

feature {NONE} -- Fixtures

	scratch_folder: STRING_32
			-- A folder these tests make and delete for themselves.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			create Result.make_empty
			if attached l_env.item ("TEMP") as al_temp and then not al_temp.is_empty then
				Result.append_string_general (al_temp)
			else
				Result.append_string_general (".")
			end
			Result.append_string_general ("\simple_ocr_capture_test_scratch")
		ensure
			never_empty: not Result.is_empty
		end

	fresh_folder (a_path: READABLE_STRING_32)
			-- Make `a_path' exist and hold nothing.
		local
			l_dir: DIRECTORY
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_dir.make_with_name (a_path)
				if l_dir.exists then
					l_dir.recursive_delete
				end
				l_dir.recursive_create_dir
			end
		rescue
			l_retried := True
			retry
		end

	write_stub (a_folder, a_name: READABLE_STRING_32)
			-- Put a token file called `a_name' in `a_folder'.
		local
			l_file: RAW_FILE
			l_path: STRING_32
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_path.make_from_string (a_folder.to_string_32)
				l_path.append_character ('\')
				l_path.append (a_name.to_string_32)
				create l_file.make_with_name (l_path)
				l_file.create_read_write
				l_file.put_string ("stub%N")
				l_file.close
			end
		rescue
			l_retried := True
			retry
		end

	has_name (a_names: LIST [STRING_32]; a_name: READABLE_STRING_32): BOOLEAN
		do
			across
				a_names as ic
			until
				Result
			loop
				Result := ic.is_case_insensitive_equal (a_name.to_string_32)
			end
		end

	new_harvest: OCR_CHANNEL_HARVEST
			-- A harvest over its own settings and its own queue.
		local
			l_settings: OCR_SETTINGS
		do
			create l_settings
			create Result.make (l_settings, create {OCR_VIDEO_QUEUE}.make (l_settings))
		end



	temp_folder: STRING_32
			-- A folder no manifest file is expected in, so the test
			-- reads nothing from disk and writes nothing to it.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			create Result.make_empty
			if attached l_env.item ("TEMP") as al_temp and then not al_temp.is_empty then
				Result.append_string_general (al_temp)
			else
				Result.append_string_general (".")
			end
			Result.append_string_general ("\simple_ocr_capture_test_channel")
		ensure
			never_empty: not Result.is_empty
		end



	write_text (a_path: READABLE_STRING_32; a_text: STRING_8)
			-- Replace whatever is at `a_path' with `a_text'.
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (a_path)
				l_file.create_read_write
				l_file.put_string (a_text)
				l_file.close
			end
		rescue
			l_retried := True
			retry
		end

	finished_lockup: STRING_8
			-- A Live-tab lockup for a stream that has been broadcast, in
			-- the shape @LanierTheologicalLibrary's listing had on
			-- 2026-10-06: the badge carries the length.
		do
			Result := "{%"contentImage%":{%"thumbnailViewModel%":{%"overlays%":[{%"thumbnailBottomOverlayViewModel%":{%"badges%":[{%"thumbnailBadgeViewModel%":{%"text%":%"1:58:00%",%"badgeStyle%":%"THUMBNAIL_OVERLAY_BADGE_STYLE_DEFAULT%",%"animatedText%":%"Now playing%"}}]}}]}},"
			Result.append ("%"metadata%":{%"lockupMetadataViewModel%":{%"title%":{%"content%":%"Religion and Public Life%"},%"metadata%":{%"contentMetadataViewModel%":{%"metadataRows%":[{%"metadataParts%":[{%"text%":{%"content%":%"1.4K views%"}},{%"text%":{%"content%":%"Streamed 3 weeks ago%"}}]}]}}}},")
			Result.append ("%"contentId%":%"vnyLScyMlOM%",%"contentType%":%"LOCKUP_CONTENT_TYPE_VIDEO%"}")
		end

	upcoming_lockup: STRING_8
			-- The same shape for a stream scheduled but not yet begun.
		do
			Result := "{%"contentImage%":{%"thumbnailViewModel%":{%"overlays%":[{%"thumbnailBottomOverlayViewModel%":{%"badges%":[{%"thumbnailBadgeViewModel%":{%"text%":%"Upcoming%",%"badgeStyle%":%"THUMBNAIL_OVERLAY_BADGE_STYLE_DEFAULT%",%"animatedText%":%"Now playing%"}}]}}]}},"
			Result.append ("%"metadata%":{%"lockupMetadataViewModel%":{%"title%":{%"content%":%"Exploring Exodus%"},%"metadata%":{%"contentMetadataViewModel%":{%"metadataRows%":[{%"metadataParts%":[{%"text%":{%"content%":%"Scheduled for 10/10/26, 5:00 PM%"}}]}]}}}},")
			Result.append ("%"contentId%":%"UpComing001%",%"contentType%":%"LOCKUP_CONTENT_TYPE_VIDEO%"}")
		end

	live_lockup: STRING_8
			-- And for one on the air.
		do
			Result := "{%"contentImage%":{%"thumbnailViewModel%":{%"overlays%":[{%"thumbnailBottomOverlayViewModel%":{%"badges%":[{%"thumbnailBadgeViewModel%":{%"text%":%"LIVE%",%"badgeStyle%":%"THUMBNAIL_OVERLAY_BADGE_STYLE_LIVE%"}}]}}]}},"
			Result.append ("%"metadata%":{%"lockupMetadataViewModel%":{%"title%":{%"content%":%"On the air%"}}},")
			Result.append ("%"contentId%":%"LiveNow0001%",%"contentType%":%"LOCKUP_CONTENT_TYPE_VIDEO%"}")
		end

	sample_streams_reply: STRING_8
			-- A Live-tab reply: a stream ALSO listed under Videos (the
			-- first id of `sample_reply'), a finished one, an upcoming
			-- one and a live one.
		do
			Result := "{%"contents%":{%"richGridRenderer%":{%"contents%":["
			Result.append ("{%"richItemRenderer%":{%"content%":{%"lockupViewModel%":")
			Result.append (upcoming_lockup)
			Result.append ("}}},{%"richItemRenderer%":{%"content%":{%"lockupViewModel%":")
			Result.append (live_lockup)
			Result.append ("}}},{%"richItemRenderer%":{%"content%":{%"lockupViewModel%":{")
			Result.append ("%"metadata%":{%"lockupMetadataViewModel%":{%"title%":{%"content%":%"The comments never hold back%"}}},")
			Result.append ("%"contentId%":%"Rv_8Ez1wOtU%",%"contentType%":%"LOCKUP_CONTENT_TYPE_VIDEO%"}}}},")
			Result.append ("{%"richItemRenderer%":{%"content%":{%"lockupViewModel%":")
			Result.append (finished_lockup)
			Result.append ("}}}]}}}")
		end

	sample_reply: STRING_8
			-- A browse reply with the real one's shape: a brace inside
			-- quoted text, an escaped quote in a title, a Shorts entry
			-- among the videos, and the grid's continuation item last.
		do
			Result := "{%"contents%":{%"richGridRenderer%":{%"contents%":["
			Result.append ("{%"richItemRenderer%":{%"content%":{%"lockupViewModel%":{")
			Result.append ("%"contentImage%":{%"note%":%"a { brace in text%"},")
			Result.append ("%"metadata%":{%"lockupMetadataViewModel%":{%"title%":{%"content%":%"The \%"comments\%" never hold back%"}}},")
			Result.append ("%"contentId%":%"Rv_8Ez1wOtU%",%"contentType%":%"LOCKUP_CONTENT_TYPE_VIDEO%"}}},")
			Result.append ("{%"richItemRenderer%":{%"content%":{%"lockupViewModel%":{")
			Result.append ("%"metadata%":{%"lockupMetadataViewModel%":{%"title%":{%"content%":%"A short clip%"}}},")
			Result.append ("%"contentId%":%"ZZZZZZZZZZZ%",%"contentType%":%"LOCKUP_CONTENT_TYPE_SHORTS%"}}},")
			Result.append ("{%"richItemRenderer%":{%"content%":{%"lockupViewModel%":{")
			Result.append ("%"metadata%":{%"lockupMetadataViewModel%":{%"title%":{%"content%":%"Another study%"}}},")
			Result.append ("%"contentId%":%"8Bn_q_w_ohI%",%"contentType%":%"LOCKUP_CONTENT_TYPE_VIDEO%"}}},")
			Result.append ("{%"continuationItemRenderer%":{%"continuationEndpoint%":{%"continuationCommand%":{%"token%":%"4qmFsgTOKEN%"}}}}")
			Result.append ("]}}}")
		end

end
