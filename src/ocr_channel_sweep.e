note
	description: "[
		Harvests every video a YouTube channel lists - under Videos AND
		under Streams - with no browser, no API key and no yt-dlp.

		BOTH listings, because a channel keeps different things in each
		and reading one of them is not reading the channel. Measured on
		@BibleLine, 2026-09-19: 539 under Videos, 759 under Streams,
		zero overlap. The first harvest read Videos only and came back
		with 42% of the channel while reporting success, which is the
		worst kind of wrong answer. The sweep now walks the listings in
		order, one page per call throughout, and `videos' is deduplicated
		by id across both.

		Two steps. The channel page is fetched once for the channel's
		own id: a handle like @BibleLine appears in no API, but its page
		carries exactly one "externalId":"UC..." and one og:title, which
		are the id and the name. Then the browse endpoint is asked for
		the Videos tab and for each continuation it hands back - thirty
		videos a page, which is the tab's own listing in the order the
		tab opens on.

		Measured 2026-09-19 against @BibleLine: 18 pages, 539 videos,
		5.6 seconds. The ANDROID client the caption fetch uses answers
		this endpoint with HTTP 400 - browse wants the WEB client, and
		unlike the caption track URLs (see OCR_CAPTION_TRACK) the WEB
		client serves browse in full.

		A page is one round trip, so `sweep_next_page' is meant to be
		called once per tick: the window stays alive across a channel
		that takes twenty of them.

		Each video arrives inside a "lockupViewModel" object. That
		object is cut out by brace balance and parsed on its own rather
		than parsing the whole 400 KB reply: the id and the title sit
		three keys deep in a document that is otherwise thumbnails and
		click-tracking, and a slice is 11 KB against the reply's 400.

		Which listings are read is a choice (`set_tabs'), both by
		default. Each video remembers the listing it was first found
		under; one listed under both is kept once, as a Videos entry,
		and counted in `repeat_count'. A stream the listing shows as
		upcoming, or live at this moment, has no transcript yet: it is
		set aside in `held_back' rather than put in `videos', so a
		harvest neither fetches it nor records it, and the next run
		finds it finished. Verified 2026-10-06 against
		@LanierTheologicalLibrary, whose Live tab opened on two
		"Upcoming" streams "Scheduled for" later that week.
	]"

class
	OCR_CHANNEL_SWEEP

create
	make

feature {NONE} -- Initialization

	make
		do
			create http.make
			create channel_id.make_empty
			create channel_name.make_empty
			create handle.make_empty
			create page_url.make_empty
			create continuation.make_empty
			create last_error.make_empty
			create videos.make (256)
			create held_back.make (4)
			create seen.make (512)
			create seen_in_listing.make (512)
			create tab_counts.make_filled (0, 1, Tab_count)
			wants_videos := True
			wants_streams := True
		ensure
			both_listings_by_default: wants_videos and wants_streams
		end

feature -- Access

	channel_id: STRING_8
			-- The channel's own "UC..." id; empty before `resolve'.

	channel_name: STRING_32
			-- The channel's display name, which names the folder.

	handle: STRING_8
			-- The channel's "@name", without the at sign; empty when the
			-- page carries none.
			--
			-- Kept because a display name is NOT an identity: ten
			-- different churches call themselves "Landmark Baptist
			-- Church" and two of them are in Florida. The handle tells
			-- two same-named channels apart in a folder name; the
			-- `channel_id' settles which is which.

	page_url: STRING_8
			-- The channel page the last `resolve' fetched.

	videos: ARRAYED_LIST [OCR_CHANNEL_VIDEO]
			-- Every video found so far, in listing order, no duplicates,
			-- each carrying the listing it was found under.

	held_back: ARRAYED_LIST [OCR_CHANNEL_VIDEO]
			-- Videos listed but not yet broadcast, or live right now:
			-- nothing to transcribe yet, so not in `videos'.

	repeat_count: INTEGER
			-- Videos a later listing repeated that an earlier one had
			-- already given: a stream the channel ALSO lists under
			-- Videos. Kept once, so never fetched twice.

	count_in_tab (a_tab: INTEGER): INTEGER
			-- Videos in `videos' that were found under listing `a_tab'.
		require
			in_range: a_tab >= 1 and a_tab <= Tab_count
		do
			Result := tab_counts.item (a_tab)
		ensure
			not_negative: Result >= 0
		end

	upcoming_count: INTEGER
			-- Of `held_back', the ones not yet broadcast.
		do
			across
				held_back as ic
			loop
				if ic.is_upcoming then
					Result := Result + 1
				end
			end
		end

	live_now_count: INTEGER
			-- Of `held_back', the ones live at the moment.
		do
			Result := held_back.count - upcoming_count
		end

	wants_videos: BOOLEAN
			-- Is the Videos listing read?

	wants_streams: BOOLEAN
			-- Is the Live listing (past streams) read?

	continuation: STRING_8
			-- The token for the next page; empty when there is none.

	last_error: STRING_32
			-- Why the last step failed; empty when it did not.

	pages_read: INTEGER
			-- Pages the current sweep has taken.

	last_page_added: INTEGER
			-- Videos the last page contributed that were not already held.

	last_page_fresh: INTEGER
			-- Ids the last page gave that its own listing had not given
			-- before: the measure of whether a continuation went
			-- anywhere.

feature -- Status report

	is_resolved: BOOLEAN
			-- Has `resolve' found a channel?
		do
			Result := not channel_id.is_empty
		end

	tab_index: INTEGER
			-- The listing being read: 1 Videos, 2 Streams; 0 before the
			-- sweep starts.

	is_sweeping: BOOLEAN
			-- Is there another page to take - in this listing, or in a
			-- wanted one after it?
		do
			Result := is_resolved and then pages_read > 0
				and then pages_read < Max_pages
				and then (not continuation.is_empty or next_wanted_tab (tab_index) > 0)
		end

	wants_tab (a_tab: INTEGER): BOOLEAN
			-- Is listing `a_tab' to be read?
		require
			in_range: a_tab >= 1 and a_tab <= Tab_count
		do
			if a_tab = Tab_videos then
				Result := wants_videos
			else
				Result := wants_streams
			end
		end

	first_wanted_tab: INTEGER
			-- The first listing to read.
		do
			Result := next_wanted_tab (0)
		ensure
			there_is_one: Result >= 1 and Result <= Tab_count
			wanted: wants_tab (Result)
		end

	next_wanted_tab (a_after: INTEGER): INTEGER
			-- The first wanted listing after `a_after'; 0 when none is.
		require
			in_range: a_after >= 0 and a_after <= Tab_count
		local
			i: INTEGER
		do
			from
				i := a_after + 1
			until
				i > Tab_count or Result > 0
			loop
				if wants_tab (i) then
					Result := i
				end
				i := i + 1
			end
		ensure
			later_or_none: Result = 0 or else (Result > a_after and Result <= Tab_count and then wants_tab (Result))
		end

	is_swept: BOOLEAN
			-- Has a sweep run to the end of the listing?
		do
			Result := pages_read > 0 and then not is_sweeping
		end

	count: INTEGER
		do
			Result := videos.count
		end

	has_video (a_id: READABLE_STRING_8): BOOLEAN
			-- Has any listing given `a_id' - for `videos' or for
			-- `held_back'?
		do
			Result := seen.has (a_id.to_string_8)
		end

	summary_line: STRING_32
			-- Where the sweep stands, for the status line.
		do
			create Result.make (90)
			if not is_resolved then
				Result.append_string_general ("Paste a channel link and press Harvest.")
			else
				Result.append (channel_name)
				Result.append_string_general (" - ")
				Result.append_string_general (videos.count.out)
				Result.append_string_general (" videos")
				if wants_videos and wants_streams then
					Result.append_string_general (" (")
					Result.append_string_general (count_in_tab (Tab_videos).out)
					Result.append_character (' ')
					Result.append (tab_name (Tab_videos))
					Result.append_string_general (", ")
					Result.append_string_general (count_in_tab (Tab_streams).out)
					Result.append_character (' ')
					Result.append (tab_name (Tab_streams))
					Result.append_character (')')
				end
				Result.append_string_general (" in ")
				Result.append_string_general (pages_read.out)
				Result.append_string_general (" page(s)")
				if is_sweeping and then tab_index >= 1 and then tab_index <= Tab_count then
					Result.append_string_general (", still reading ")
					Result.append (tab_name (tab_index))
					Result.append_string_general ("...")
				end
			end
		ensure
			never_empty: not Result.is_empty
		end

feature -- Basic operations

	resolve (a_url: READABLE_STRING_GENERAL): BOOLEAN
			-- Find the channel `a_url' names: its id and its name.
		require
			url_given: not a_url.is_empty
		local
			l_body: STRING_8
		do
			reset
			page_url := channel_page_url (a_url)
			if page_url.is_empty then
				last_error := {STRING_32} "That does not look like a YouTube channel link. Use a handle (@name), a /channel/UC... link, or a /c/ or /user/ link."
			elseif not http.get (page_url, Page_timeout_seconds) then
				last_error := http.last_error.twin
			else
				l_body := http.last_body
				channel_id := value_after (l_body, External_id_marker, 1)
				channel_name := html_text (value_after (l_body, Og_title_marker, 1))
				handle := value_after (l_body, Handle_marker, 1)
				if channel_id.is_empty then
					last_error := {STRING_32} "That page carries no channel id. If the channel exists, YouTube may have served a consent page instead."
				else
					if channel_name.is_empty then
						channel_name := {STRING_32} "channel"
					end
					Result := True
				end
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			named_on_success: Result implies (is_resolved and then not channel_name.is_empty)
		end

	sweep_first_page: BOOLEAN
			-- Ask for the first listing and read its first page.
		require
			resolved: is_resolved
		do
			clear_listing
			pages_read := 0
			tab_index := first_wanted_tab
			Result := read_page (tab_body (tab_index), False)
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			started_at_the_first_wanted_listing: tab_index = first_wanted_tab
		end

	sweep_next_page: BOOLEAN
			-- Read the page `continuation' points at; or, when this
			-- listing is spent, open the next wanted one.
		require
			more: is_sweeping
		do
			if not continuation.is_empty then
				Result := read_page (continuation_body (continuation), True)
			else
				tab_index := next_wanted_tab (tab_index)
				Result := read_page (tab_body (tab_index), False)
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			within_the_listings: tab_index >= 1 and tab_index <= Tab_count
			only_wanted_listings: wants_tab (tab_index)
		end

	absorb (a_reply: STRING_8; a_tab: INTEGER)
			-- Take the videos the browse reply `a_reply' lists, as found
			-- under listing `a_tab'. Pure of the network, so the listing
			-- arithmetic - dedupe across listings, held-back streams,
			-- per-listing counts - is testable without YouTube.
		require
			in_range: a_tab >= 1 and a_tab <= Tab_count
		local
			l_key: STRING_8
		do
			last_page_added := 0
			last_page_fresh := 0
			if a_tab /= listing_of_seen then
					-- A new listing: what counts as "already met in this
					-- listing" starts again.
				seen_in_listing.wipe_out
				listing_of_seen := a_tab
			end
			l_key := tab_key (a_tab)
			across
				videos_in (a_reply) as ic
			loop
				if not seen_in_listing.has (ic.video_id) then
					seen_in_listing.put (True, ic.video_id)
					last_page_fresh := last_page_fresh + 1
					if seen.has (ic.video_id) then
							-- An earlier listing gave it already: kept
							-- once, under that listing.
						repeat_count := repeat_count + 1
					else
						seen.put (l_key, ic.video_id)
						ic.set_tab (l_key)
						if ic.is_held_back then
							held_back.extend (ic)
						else
							videos.extend (ic)
							tab_counts.put (tab_counts.item (a_tab) + 1, a_tab)
							last_page_added := last_page_added + 1
						end
					end
				end
			end
		ensure
			no_fewer: videos.count >= old videos.count
			counted: videos.count = old videos.count + last_page_added
		end

feature -- Element change

	set_tabs (a_videos, a_streams: BOOLEAN)
			-- Read the Videos listing when `a_videos', the Live listing
			-- (past streams) when `a_streams'.
		require
			at_least_one: a_videos or a_streams
			not_mid_sweep: not is_sweeping
		do
			wants_videos := a_videos
			wants_streams := a_streams
		ensure
			videos_set: wants_videos = a_videos
			streams_set: wants_streams = a_streams
		end

feature -- Conversion

	channel_page_url (a_url: READABLE_STRING_GENERAL): STRING_8
			-- The Videos page for whatever `a_url' names; empty when it
			-- names no channel. Accepts a bare handle, a bare UC id, and
			-- the /channel/, /@, /c/ and /user/ link forms.
		local
			l_text, l_part: STRING_8
			i: INTEGER
		do
			create Result.make_empty
			l_text := ascii_of (a_url)
			l_text.left_adjust
			l_text.right_adjust
			if l_text.is_empty then
					-- nothing to go on
			elseif attached segment_after (l_text, "/channel/") as al_id and then is_channel_id (al_id) then
				Result := "https://www.youtube.com/channel/" + al_id + "/videos"
			elseif is_channel_id (l_text) then
				Result := "https://www.youtube.com/channel/" + l_text + "/videos"
			else
				i := l_text.index_of ('@', 1)
				if i > 0 then
					l_part := stop_at_delimiter (l_text.substring (i + 1, l_text.count))
					if not l_part.is_empty then
						Result := "https://www.youtube.com/@" + l_part + "/videos"
					end
				elseif attached segment_after (l_text, "/c/") as al_c and then not al_c.is_empty then
					Result := "https://www.youtube.com/c/" + al_c + "/videos"
				elseif attached segment_after (l_text, "/user/") as al_u and then not al_u.is_empty then
					Result := "https://www.youtube.com/user/" + al_u + "/videos"
				elseif not l_text.has ('/') and then not l_text.has (':') then
						-- a bare name typed without its @
					Result := "https://www.youtube.com/@" + l_text + "/videos"
				end
			end
		ensure
			asks_for_videos: not Result.is_empty implies Result.ends_with ("/videos")
		end

	is_channel_id (a_text: READABLE_STRING_8): BOOLEAN
			-- Is `a_text' a bare "UC..." channel id?
		do
			Result := a_text.count = 24 and then a_text.starts_with ("UC")
		end

	folder_name: STRING_32
			-- `channel_name' fit to be a folder name.
		require
			resolved: is_resolved
		do
			Result := folder_name_of (channel_name)
		ensure
			never_empty: not Result.is_empty
		end

	folder_name_of (a_name: READABLE_STRING_32): STRING_32
			-- `a_name' fit to be a folder name: the characters Windows
			-- reserves and the controls dropped, trailing dots removed
			-- (Windows refuses a folder whose name ends in one), never
			-- empty.
		local
			i: INTEGER
			c: CHARACTER_32
		do
			create Result.make (a_name.count)
			from
				i := 1
			until
				i > a_name.count
			loop
				c := a_name.item (i)
				if c.natural_32_code >= 32 and then not Folder_reserved.has (c) then
					Result.append_character (c)
				end
				i := i + 1
			end
			Result.left_adjust
			Result.right_adjust
			from
			until
				Result.is_empty or else Result.item (Result.count) /= '.'
			loop
				Result.remove_tail (1)
			end
			if Result.is_empty then
				Result.append_string_general ("channel")
			end
		ensure
			never_empty: not Result.is_empty
			clean: not Result.has ('\') and not Result.has ('/') and not Result.has (':')
		end

	Folder_reserved: STRING_32 = "\/:*?%"<>|"

feature {NONE} -- The browse endpoint

	http: OCR_HTTP

	Browse_url: STRING_8 = "https://www.youtube.com/youtubei/v1/browse?prettyPrint=false"

feature -- The listings

	Videos_tab_params: STRING_8 = "EgZ2aWRlb3PyBgQKAjoA"
			-- The Videos tab, in the listing order the tab opens on.
			-- Verified 2026-09-19: browsing a channel with this returns
			-- richGridRenderer pages of thirty videos and no Shorts.

	Streams_tab_params: STRING_8 = "EgdzdHJlYW1z8gYECgJ6AA"
			-- The Streams tab: past live broadcasts, which the Videos
			-- tab does NOT list.
			--
			-- Reading only Videos is how the first harvest of @BibleLine
			-- came back with 42% of the channel and no idea it had. That
			-- channel lists 539 videos under Videos and 759 under
			-- Streams, with ZERO overlap, and the long-form material -
			-- the teaching series, the hour-long sermons - is all on the
			-- Streams side. A channel harvest that silently returns less
			-- than half a channel is a bug, so both listings are swept by
			-- default; `set_tabs' narrows it only when asked to.
			--
			-- Shorts are still left out. The Videos tab excludes them
			-- and a transcript of a sixty-second clip is not worth a
			-- file.

	Tab_count: INTEGER = 2
			-- Listings swept, in order: 1 Videos, 2 Streams.

	Tab_videos: INTEGER = 1

	Tab_streams: INTEGER = 2
			-- YouTube's "Live" tab, served at /streams.

	tab_key (a_tab: INTEGER): STRING_8
			-- The key listing `a_tab' is recorded under, in front matter,
			-- the manifest and the index.
		require
			in_range: a_tab >= 1 and a_tab <= Tab_count
		do
			if a_tab = Tab_videos then
				Result := {OCR_CHANNEL_VIDEO}.Tab_videos
			else
				Result := {OCR_CHANNEL_VIDEO}.Tab_streams
			end
		ensure
			given: not Result.is_empty
		end

	wanted_tabs_text: STRING_32
			-- The listings to be read, for a status line: "Videos",
			-- "Live" or "Videos and Live".
		do
			create Result.make (16)
			if wants_videos then
				Result.append (tab_name (Tab_videos))
			end
			if wants_streams then
				if not Result.is_empty then
					Result.append_string_general (" and ")
				end
				Result.append (tab_name (Tab_streams))
			end
		ensure
			never_empty: not Result.is_empty
		end

	tab_choice (a_text: READABLE_STRING_GENERAL): TUPLE [videos, streams: BOOLEAN; error: STRING_32]
			-- The listings `a_text' names, as `--tabs' takes them: a list
			-- of "videos" and "streams" (or "live", which is what YouTube
			-- labels the tab), separated by commas, plus signs or spaces,
			-- in any case; "both" or "all" for both. `error' says what
			-- was not understood, and is empty when all of it was.
		local
			l_text: STRING_32
			l_word: STRING_32
			l_error: STRING_32
			l_videos, l_streams: BOOLEAN
		do
			create l_error.make_empty
			l_text := a_text.as_string_32.as_lower
			across
				<<',', '+', ';'>> as ic
			loop
				l_text.replace_substring_all (create {STRING_32}.make_filled (ic, 1), {STRING_32} " ")
			end
			across
				l_text.split (' ') as ic
			loop
				l_word := ic.twin
				l_word.left_adjust
				l_word.right_adjust
				if l_word.is_empty then
						-- the gap between two separators
				elseif l_word.same_string_general ("videos") or l_word.same_string_general ("video") then
					l_videos := True
				elseif l_word.same_string_general ("streams") or l_word.same_string_general ("stream")
					or l_word.same_string_general ("live")
				then
					l_streams := True
				elseif l_word.same_string_general ("both") or l_word.same_string_general ("all") then
					l_videos := True
					l_streams := True
				elseif l_error.is_empty then
					l_error := {STRING_32} "Unknown tab %"" + l_word + {STRING_32} "%": use videos, streams (or live), or both."
				end
			end
			if l_error.is_empty and not l_videos and not l_streams then
				l_error := {STRING_32} "No tab named: use videos, streams (or live), or both."
			end
			Result := [l_videos, l_streams, l_error]
		ensure
			understood_means_something_chosen: Result.error.is_empty implies (Result.videos or Result.streams)
		end

	tab_params (a_tab: INTEGER): STRING_8
			-- The browse params for listing `a_tab'.
		require
			in_range: a_tab >= 1 and a_tab <= Tab_count
		do
			if a_tab = 1 then
				Result := Videos_tab_params
			else
				Result := Streams_tab_params
			end
		ensure
			given: not Result.is_empty
		end

	tab_name (a_tab: INTEGER): STRING_32
			-- What to call listing `a_tab' in the status line: the
			-- label YouTube's own channel page gives the tab.
		require
			in_range: a_tab >= 1 and a_tab <= Tab_count
		do
			if a_tab = Tab_videos then
				Result := {STRING_32} "Videos"
			else
				Result := {STRING_32} "Live"
			end
		ensure
			named: not Result.is_empty
		end

feature {NONE} -- The browse endpoint, continued

	Client_context: STRING_8 = "{%"context%":{%"client%":{%"clientName%":%"WEB%",%"clientVersion%":%"2.20260918.00.00%",%"hl%":%"en%",%"gl%":%"US%"}}"

	Page_timeout_seconds: INTEGER = 30

	Browse_timeout_seconds: INTEGER = 30

	Max_pages: INTEGER = 500
			-- A stop, so a continuation that never empties cannot spin
			-- the tick for ever.

	tab_body (a_tab: INTEGER): STRING_8
			-- The request for the first page of listing `a_tab'.
		require
			in_range: a_tab >= 1 and a_tab <= Tab_count
		do
			create Result.make (200)
			Result.append (Client_context)
			Result.append (",%"browseId%":%"")
			Result.append (channel_id)
			Result.append ("%",%"params%":%"")
			Result.append (tab_params (a_tab))
			Result.append ("%"}")
		end

	continuation_body (a_token: READABLE_STRING_8): STRING_8
			-- The request for the page `a_token' points at.
		require
			token_given: not a_token.is_empty
		do
			create Result.make (a_token.count + 200)
			Result.append (Client_context)
			Result.append (",%"continuation%":")
			Result.append ((create {OCR_JSON_UTIL}).quoted (a_token))
			Result.append ("}")
		end

	read_page (a_body: STRING_8; a_is_continuation: BOOLEAN): BOOLEAN
			-- POST `a_body' to browse, add the videos it lists and keep
			-- the token for the page after it.
			--
			-- `a_is_continuation' says whether this page continues the
			-- listing already being read, and it governs the
			-- nothing-new guard below: the FIRST page of a listing may
			-- legitimately add nothing (every video already held from
			-- the previous listing) and that must not end the sweep.
			--
			-- The guard asks what is new to THIS listing, not what is
			-- new to the harvest. A channel that also lists its streams
			-- under Videos hands back Live pages whose every id is
			-- already held; judged by "added nothing", the first such
			-- continuation would end the Live listing with the rest of
			-- its pages unread.
		local
			l_reply: STRING_8
		do
			last_error.wipe_out
			last_page_added := 0
			last_page_fresh := 0
			if not http.post (Browse_url, "application/json", a_body, Browse_timeout_seconds) then
				last_error := http.last_error.twin
			elseif http.last_body.is_empty then
				last_error := {STRING_32} "YouTube answered the channel listing with an empty body."
			else
				l_reply := http.last_body
				pages_read := pages_read + 1
				absorb (l_reply, tab_index)
				continuation := next_token (l_reply)
				if a_is_continuation and then last_page_fresh = 0 then
						-- A continuation that repeats what this listing
						-- has already given is its end however the token
						-- reads. A listing's FIRST page is exempt: see the
						-- header comment.
					continuation.wipe_out
				end
				Result := True
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			page_counted: Result implies pages_read = old pages_read + 1
		end

feature -- Reading a reply

	videos_in (a_reply: STRING_8): ARRAYED_LIST [OCR_CHANNEL_VIDEO]
			-- Every video the browse reply `a_reply' lists, in its own
			-- order. Pure: it reads the text and holds nothing.
		local
			l_json: SIMPLE_JSON
			i, l_open, l_close: INTEGER
			l_slice: STRING_8
			l_id, l_kind, l_title: STRING_32
			l_video: OCR_CHANNEL_VIDEO
		do
			create Result.make (32)
			create l_json
			from
				i := a_reply.substring_index (Lockup_marker, 1)
			until
				i = 0
			loop
				l_open := a_reply.index_of ('{', i + Lockup_marker.count - 1)
				if l_open = 0 then
					i := 0
				else
					l_close := matching_brace (a_reply, l_open)
					if l_close = 0 then
						i := 0
					else
						l_slice := a_reply.substring (l_open, l_close)
						if attached l_json.parse (decoded (l_slice)) as al_value and then al_value.is_object then
							create l_id.make_empty
							create l_kind.make_empty
							create l_title.make_empty
							if attached al_value.as_object.string_item ({STRING_32} "contentId") as al_id then
								l_id := al_id
							end
							if attached al_value.as_object.string_item ({STRING_32} "contentType") as al_kind then
								l_kind := al_kind
							end
							if attached al_value.as_object.object_item ({STRING_32} "metadata") as al_meta and then
								attached al_meta.object_item ({STRING_32} "lockupMetadataViewModel") as al_lock and then
								attached al_lock.object_item ({STRING_32} "title") as al_t and then
								attached al_t.string_item ({STRING_32} "content") as al_c
							then
								l_title := al_c
							end
							if l_id.count = 11 and then l_kind.same_string_general (Video_kind) then
								create l_video.make (ascii_of (l_id), l_title)
								inspect broadcast_state_of (l_slice)
								when Broadcast_upcoming then
									l_video.mark_upcoming
								when Broadcast_live then
									l_video.mark_live_now
								else
										-- broadcast and finished: the usual case
								end
								l_video.set_listed_seconds (listed_seconds_of (l_slice))
								Result.extend (l_video)
							end
						end
						i := a_reply.substring_index (Lockup_marker, l_close + 1)
					end
				end
			end
		end

	Broadcast_done: INTEGER = 0
			-- Broadcast and over, or never a broadcast: a transcript may
			-- be there.

	Broadcast_upcoming: INTEGER = 1
			-- Scheduled - a stream or a premiere - and not yet started.

	Broadcast_live: INTEGER = 2
			-- Being broadcast right now.

	broadcast_state_of (a_slice: STRING_8): INTEGER
			-- What one video's lockup slice says about its broadcast.
			--
			-- Read from the thumbnail badge, which says "Upcoming" where
			-- a finished video's says its length, and whose style names
			-- LIVE for a stream that is on the air; and, behind that,
			-- from the "Scheduled for" or "Premieres" line under the
			-- title. The browse request asks for English (hl=en), so
			-- these words are the words that come back.
		do
			Result := Broadcast_done
			across
				badges_of (a_slice) as ic
			loop
				if ic.text.is_case_insensitive_equal (Upcoming_badge) then
					Result := Broadcast_upcoming
				elseif Result = Broadcast_done and then
					(ic.style.has_substring (Live_style_part) or ic.text.is_case_insensitive_equal (Live_badge))
				then
					Result := Broadcast_live
				end
			end
			if Result = Broadcast_done and then
				(a_slice.has_substring (Scheduled_marker) or a_slice.has_substring (Premieres_marker))
			then
				Result := Broadcast_upcoming
			end
		ensure
			known: Result = Broadcast_done or Result = Broadcast_upcoming or Result = Broadcast_live
		end

	listed_seconds_of (a_slice: STRING_8): INTEGER
			-- The length one video's thumbnail badge shows; 0 when no
			-- badge shows one.
		do
			across
				badges_of (a_slice) as ic
			until
				Result > 0
			loop
				Result := clock_seconds (ic.text)
			end
		ensure
			not_negative: Result >= 0
		end

	clock_seconds (a_text: READABLE_STRING_8): INTEGER
			-- "1:58:00" or "46:23" as seconds; 0 when `a_text' is not a
			-- clock.
		local
			l_parts: LIST [READABLE_STRING_8]
			l_ok: BOOLEAN
		do
			if not a_text.is_empty and then a_text.has (':') then
				l_parts := a_text.split (':')
				l_ok := l_parts.count >= 2 and l_parts.count <= 3
				across
					l_parts as ic
				until
					not l_ok
				loop
					l_ok := not ic.is_empty and then ic.count <= 3 and then ic.is_natural
				end
				if l_ok then
					across
						l_parts as ic
					loop
						Result := Result * 60 + ic.to_integer
					end
				end
			end
		ensure
			not_negative: Result >= 0
		end

	badges_of (a_slice: STRING_8): ARRAYED_LIST [TUPLE [text, style: STRING_8]]
			-- The text and style of every thumbnail badge in `a_slice',
			-- each badge cut out by brace balance so a key from some
			-- other object cannot be read as its.
		local
			i, l_open, l_close: INTEGER
			l_badge: STRING_8
		do
			create Result.make (2)
			from
				i := a_slice.substring_index (Badge_marker, 1)
			until
				i = 0
			loop
				l_open := a_slice.index_of ('{', i + Badge_marker.count - 1)
				if l_open = 0 then
					i := 0
				else
					l_close := matching_brace (a_slice, l_open)
					if l_close = 0 then
						i := 0
					else
						l_badge := a_slice.substring (l_open, l_close)
						Result.extend ([value_after (l_badge, Badge_text_marker, 1), value_after (l_badge, Badge_style_marker, 1)])
						i := a_slice.substring_index (Badge_marker, l_close + 1)
					end
				end
			end
		end

	next_token (a_reply: STRING_8): STRING_8
			-- The token of the reply's "load more" item; empty when the
			-- listing has ended. Taken from the first
			-- continuationItemRenderer, which is the grid's own: the
			-- other tokens in a channel reply belong to the sort chips
			-- and to side panels, and all of them sit later in the
			-- document.
		local
			i: INTEGER
		do
			create Result.make_empty
			i := a_reply.substring_index (Continuation_item_marker, 1)
			if i > 0 then
				Result := value_after (a_reply, Token_marker, i)
			end
		end

	matching_brace (a_text: STRING_8; a_open: INTEGER): INTEGER
			-- Where the object opening at `a_open' closes; 0 when it
			-- does not. Braces inside quoted text, and a quote an
			-- escape protects, do not count.
		require
			opens_there: a_open >= 1 and a_open <= a_text.count and then a_text.item (a_open) = '{'
		local
			i, l_depth: INTEGER
			c: CHARACTER_8
			l_in_string, l_escaped: BOOLEAN
		do
			from
				i := a_open
			until
				i > a_text.count or Result > 0
			loop
				c := a_text.item (i)
				if l_in_string then
					if l_escaped then
						l_escaped := False
					elseif c = '\' then
						l_escaped := True
					elseif c = '%"' then
						l_in_string := False
					end
				elseif c = '%"' then
					l_in_string := True
				elseif c = '{' then
					l_depth := l_depth + 1
				elseif c = '}' then
					l_depth := l_depth - 1
					if l_depth = 0 then
						Result := i
					end
				end
				i := i + 1
			end
		ensure
			inside: Result > 0 implies (Result > a_open and Result <= a_text.count)
		end

feature {NONE} -- Reading text out of a reply

	Lockup_marker: STRING_8 = "%"lockupViewModel%":"

	Continuation_item_marker: STRING_8 = "%"continuationItemRenderer%""

	Token_marker: STRING_8 = "%"token%":%""

	External_id_marker: STRING_8 = "%"externalId%":%""

	Og_title_marker: STRING_8 = "<meta property=%"og:title%" content=%""

	Handle_marker: STRING_8 = "%"canonicalBaseUrl%":%"/@"

	Video_kind: STRING_8 = "LOCKUP_CONTENT_TYPE_VIDEO"

	Badge_marker: STRING_8 = "%"thumbnailBadgeViewModel%":"

	Badge_text_marker: STRING_8 = "%"text%":%""

	Badge_style_marker: STRING_8 = "%"badgeStyle%":%""

	Upcoming_badge: STRING_8 = "Upcoming"

	Live_badge: STRING_8 = "LIVE"

	Live_style_part: STRING_8 = "_LIVE"
			-- As in THUMBNAIL_OVERLAY_BADGE_STYLE_LIVE.

	Scheduled_marker: STRING_8 = "%"content%":%"Scheduled for "

	Premieres_marker: STRING_8 = "%"content%":%"Premieres "

	value_after (a_text: STRING_8; a_marker: STRING_8; a_from: INTEGER): STRING_8
			-- What follows the first `a_marker' at or after `a_from', up
			-- to the next quote; empty when the marker is absent.
		require
			from_positive: a_from >= 1
		local
			i, l_end: INTEGER
		do
			create Result.make_empty
			i := a_text.substring_index (a_marker, a_from)
			if i > 0 then
				i := i + a_marker.count
				l_end := a_text.index_of ('%"', i)
				if l_end > i then
					Result := a_text.substring (i, l_end - 1)
				end
			end
		end

	stop_at_delimiter (a_text: STRING_8): STRING_8
			-- `a_text' up to the first of / ? & # or space.
		local
			i: INTEGER
			c: CHARACTER_8
			l_done: BOOLEAN
		do
			create Result.make (a_text.count)
			from
				i := 1
			until
				i > a_text.count or l_done
			loop
				c := a_text.item (i)
				if c = '/' or c = '?' or c = '&' or c = '#' or c = ' ' then
					l_done := True
				else
					Result.extend (c)
				end
				i := i + 1
			end
		end

	segment_after (a_text: STRING_8; a_marker: STRING_8): detachable STRING_8
			-- The path piece following `a_marker'; Void when absent.
		local
			i: INTEGER
		do
			i := a_text.substring_index (a_marker, 1)
			if i > 0 then
				Result := stop_at_delimiter (a_text.substring (i + a_marker.count, a_text.count))
			end
		end

	html_text (a_raw: READABLE_STRING_8): STRING_32
			-- `a_raw' with the entities a title can carry turned back
			-- into their characters.
		local
			l_utf8: STRING_8
		do
			create l_utf8.make_from_string (a_raw)
			l_utf8.replace_substring_all ("&quot;", "%"")
			l_utf8.replace_substring_all ("&#39;", "'")
			l_utf8.replace_substring_all ("&apos;", "'")
			l_utf8.replace_substring_all ("&lt;", "<")
			l_utf8.replace_substring_all ("&gt;", ">")
				-- last, so an entity written &amp;quot; is not undone twice
			l_utf8.replace_substring_all ("&amp;", "&")
			Result := decoded (l_utf8)
		end

	ascii_of (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' as UTF-8 bytes, for the link and marker work.
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
		end

	decoded (a_utf8: STRING_8): STRING_32
			-- `a_utf8' bytes as characters.
		do
			Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_utf8)
		end

	reset
		do
			channel_id.wipe_out
			channel_name.wipe_out
			handle.wipe_out
			page_url.wipe_out
			continuation.wipe_out
			last_error.wipe_out
			clear_listing
			pages_read := 0
			tab_index := 0
				-- `wants_videos' and `wants_streams' survive: they are the
				-- caller's choice, not the state of a sweep.
		end

	clear_listing
			-- Forget every video found, and every count about them.
		do
			continuation.wipe_out
			videos.wipe_out
			held_back.wipe_out
			seen.wipe_out
			seen_in_listing.wipe_out
			listing_of_seen := 0
			tab_counts.fill_with (0)
			repeat_count := 0
			last_page_added := 0
			last_page_fresh := 0
		ensure
			nothing_held: videos.is_empty and held_back.is_empty and repeat_count = 0
		end

	seen: HASH_TABLE [STRING_8, STRING_8]
			-- Every id any listing has given, to the key of the listing
			-- that gave it first.

	seen_in_listing: HASH_TABLE [BOOLEAN, STRING_8]
			-- The ids the listing `listing_of_seen' has given so far.

	listing_of_seen: INTEGER
			-- The listing `seen_in_listing' is about; 0 before any.

	tab_counts: ARRAY [INTEGER]
			-- Per listing, the videos it put in `videos'.

invariant
	parts_attached: http /= Void and channel_id /= Void and channel_name /= Void and handle /= Void
		and page_url /= Void and continuation /= Void and last_error /= Void and videos /= Void
		and held_back /= Void and seen /= Void and seen_in_listing /= Void and tab_counts /= Void
	pages_not_negative: pages_read >= 0
	tab_in_range: tab_index >= 0 and tab_index <= Tab_count
	tab_started_once_swept: pages_read > 0 implies tab_index >= 1
	some_listing_wanted: wants_videos or wants_streams
	one_count_per_listing: tab_counts.lower = 1 and tab_counts.count = Tab_count
	counts_add_up: tab_counts.item (Tab_videos) + tab_counts.item (Tab_streams) = videos.count
	repeats_not_negative: repeat_count >= 0

end
