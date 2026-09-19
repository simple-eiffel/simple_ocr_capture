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
			l_manifest.record ("Rv_8Ez1wOtU", {STRING_32} "A title.md", {STRING_32} "Q&A Sessions")
			assert_true ("knows it now", l_manifest.has ("Rv_8Ez1wOtU"))
			assert_integers_equal ("one entry", 1, l_manifest.count)
			l_manifest.record ("Rv_8Ez1wOtU", {STRING_32} "A renamed title.md", {STRING_32} "Other")
			assert_integers_equal ("a repeat is not doubled", 1, l_manifest.count)
			l_manifest.record ("8Bn_q_w_ohI", {STRING_32} "Another.md", {STRING_32} "Q&A Sessions")
			assert_integers_equal ("two entries", 2, l_manifest.count)
			assert_true ("manifest sits in the channel folder", l_manifest.path.has_substring (l_manifest.File_name))
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

feature {NONE} -- Fixtures

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
