note
	description: "[
		Harvests every video a YouTube channel lists under Videos,
		with no browser, no API key and no yt-dlp.

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
			create page_url.make_empty
			create continuation.make_empty
			create last_error.make_empty
			create videos.make (256)
		end

feature -- Access

	channel_id: STRING_8
			-- The channel's own "UC..." id; empty before `resolve'.

	channel_name: STRING_32
			-- The channel's display name, which names the folder.

	page_url: STRING_8
			-- The channel page the last `resolve' fetched.

	videos: ARRAYED_LIST [OCR_CHANNEL_VIDEO]
			-- Every video found so far, in listing order, no duplicates.

	continuation: STRING_8
			-- The token for the next page; empty when there is none.

	last_error: STRING_32
			-- Why the last step failed; empty when it did not.

	pages_read: INTEGER
			-- Pages the current sweep has taken.

	last_page_added: INTEGER
			-- Videos the last page contributed that were not already held.

feature -- Status report

	is_resolved: BOOLEAN
			-- Has `resolve' found a channel?
		do
			Result := not channel_id.is_empty
		end

	is_sweeping: BOOLEAN
			-- Is there another page to take?
		do
			Result := is_resolved and then not continuation.is_empty
				and then pages_read < Max_pages
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
		do
			across
				videos as ic
			until
				Result
			loop
				Result := ic.video_id.same_string (a_id)
			end
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
				Result.append_string_general (" videos in ")
				Result.append_string_general (pages_read.out)
				Result.append_string_general (" page(s)")
				if is_sweeping then
					Result.append_string_general (", still listing...")
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
			-- Ask for the Videos tab and read its first page.
		require
			resolved: is_resolved
		do
			videos.wipe_out
			pages_read := 0
			continuation.wipe_out
			Result := read_page (videos_tab_body)
		ensure
			error_on_failure: not Result implies not last_error.is_empty
		end

	sweep_next_page: BOOLEAN
			-- Read the page `continuation' points at.
		require
			more: is_sweeping
		do
			Result := read_page (continuation_body (continuation))
		ensure
			error_on_failure: not Result implies not last_error.is_empty
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

	Videos_tab_params: STRING_8 = "EgZ2aWRlb3PyBgQKAjoA"
			-- The Videos tab, in the listing order the tab opens on.
			-- Verified 2026-09-19: browsing a channel with this returns
			-- richGridRenderer pages of thirty videos and no Shorts.

	Client_context: STRING_8 = "{%"context%":{%"client%":{%"clientName%":%"WEB%",%"clientVersion%":%"2.20260918.00.00%",%"hl%":%"en%",%"gl%":%"US%"}}"

	Page_timeout_seconds: INTEGER = 30

	Browse_timeout_seconds: INTEGER = 30

	Max_pages: INTEGER = 500
			-- A stop, so a continuation that never empties cannot spin
			-- the tick for ever.

	videos_tab_body: STRING_8
			-- The request for the first page of the Videos tab.
		do
			create Result.make (200)
			Result.append (Client_context)
			Result.append (",%"browseId%":%"")
			Result.append (channel_id)
			Result.append ("%",%"params%":%"")
			Result.append (Videos_tab_params)
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

	read_page (a_body: STRING_8): BOOLEAN
			-- POST `a_body' to browse, add the videos it lists and keep
			-- the token for the page after it.
		local
			l_reply: STRING_8
		do
			last_error.wipe_out
			last_page_added := 0
			if not http.post (Browse_url, "application/json", a_body, Browse_timeout_seconds) then
				last_error := http.last_error.twin
			elseif http.last_body.is_empty then
				last_error := {STRING_32} "YouTube answered the channel listing with an empty body."
			else
				l_reply := http.last_body
				pages_read := pages_read + 1
				add_lockups (l_reply)
				continuation := next_token (l_reply)
				if last_page_added = 0 then
						-- A page that repeats what we already hold is the
						-- end of the listing however the token reads.
					continuation.wipe_out
				end
				Result := True
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			page_counted: Result implies pages_read = old pages_read + 1
		end

	add_lockups (a_reply: STRING_8)
			-- Add every video the reply lists that is not already held.
		do
			across
				videos_in (a_reply) as ic
			loop
				if not has_video (ic.video_id) then
					videos.extend (ic)
					last_page_added := last_page_added + 1
				end
			end
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
								Result.extend (l_video)
							end
						end
						i := a_reply.substring_index (Lockup_marker, l_close + 1)
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

	Video_kind: STRING_8 = "LOCKUP_CONTENT_TYPE_VIDEO"

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
			page_url.wipe_out
			continuation.wipe_out
			last_error.wipe_out
			videos.wipe_out
			pages_read := 0
			last_page_added := 0
		end

invariant
	parts_attached: http /= Void and channel_id /= Void and channel_name /= Void
		and page_url /= Void and continuation /= Void and last_error /= Void and videos /= Void
	pages_not_negative: pages_read >= 0

end
