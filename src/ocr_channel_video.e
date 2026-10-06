note
	description: "[
		One video as the channel sweep found it: its id, its title, the
		listing it was found under, and the category the local model
		later puts it in. Nothing here comes from the player - captions
		and playability arrive later, when the queue looks the video up.

		Two things the LISTING says that the player would only say at
		the price of a request: whether the broadcast has happened yet
		(an upcoming stream or premiere, or one live right now, has no
		transcript to give), and the length the thumbnail badge shows.
	]"

class
	OCR_CHANNEL_VIDEO

create
	make

feature {NONE} -- Initialization

	make (a_id: READABLE_STRING_8; a_title: READABLE_STRING_32)
			-- A video the sweep found, not yet categorised.
		require
			id_given: not a_id.is_empty
		do
			create video_id.make_from_string (a_id)
			create title.make_from_string (a_title)
			create category.make_empty
			create tab.make_empty
		ensure
			id_kept: video_id.same_string (a_id)
			title_kept: title.same_string (a_title)
			uncategorised: not is_categorised
			no_tab_yet: tab.is_empty
			broadcast: not is_held_back
		end

feature -- Access

	video_id: STRING_8
			-- The eleven-character id.

	title: STRING_32
			-- The title as the channel listing spells it.

	category: STRING_32
			-- Where the local model filed it; empty until it has.

	tab: STRING_8
			-- The channel listing it was found under - "videos" or
			-- "streams" (YouTube's Live tab) - or empty before the sweep
			-- says. A video listed under both keeps the first, which is
			-- "videos": see OCR_CHANNEL_SWEEP.absorb.

	listed_seconds: INTEGER
			-- The length the listing's thumbnail badge shows; 0 when it
			-- showed none (an upcoming stream, a live one).

	watch_url: STRING_32
			-- The link the queue is given.
		do
			create Result.make (44)
			Result.append_string_general ("https://www.youtube.com/watch?v=")
			Result.append_string_general (video_id)
		ensure
			carries_id: Result.has_substring (video_id.as_string_32)
		end

feature -- Status report

	is_categorised: BOOLEAN
			-- Has a category been set?
		do
			Result := not category.is_empty
		end

	is_upcoming: BOOLEAN
			-- Did the listing show it as not yet broadcast - a scheduled
			-- stream or a premiere?

	is_live_now: BOOLEAN
			-- Did the listing show it as being broadcast right now?

	is_held_back: BOOLEAN
			-- Is there, as yet, nothing to transcribe? A harvest skips
			-- such a video and notes it; the next run finds it finished.
		do
			Result := is_upcoming or is_live_now
		end

	is_stream: BOOLEAN
			-- Was it found under the Live tab?
		do
			Result := tab.same_string (Tab_streams)
		end

feature -- Tab keys

	Tab_videos: STRING_8 = "videos"
			-- The key for the Videos tab, as front matter, the manifest
			-- and the index spell it.

	Tab_streams: STRING_8 = "streams"
			-- The key for the Live tab. YouTube labels the tab "Live" and
			-- serves it at /streams; the key follows the URL, because
			-- that is what anyone checking a channel by hand will type.

	is_tab_key (a_key: READABLE_STRING_8): BOOLEAN
			-- Is `a_key' one of the two tab keys?
		do
			Result := a_key.same_string (Tab_videos) or a_key.same_string (Tab_streams)
		ensure
			instance_free: class
		end

feature -- Element change

	set_category (a_category: READABLE_STRING_GENERAL)
			-- File this video under `a_category'.
		require
			given: not a_category.is_empty
		do
			create category.make_from_string_general (a_category)
		ensure
			set: category.same_string_general (a_category)
			categorised: is_categorised
		end

	set_tab (a_key: READABLE_STRING_8)
			-- Note that the video was found under listing `a_key'.
		require
			known: is_tab_key (a_key)
		do
			create tab.make_from_string (a_key)
		ensure
			set: tab.same_string (a_key)
		end

	set_listed_seconds (a_seconds: INTEGER)
			-- Keep the length the listing's badge shows.
		require
			not_negative: a_seconds >= 0
		do
			listed_seconds := a_seconds
		ensure
			set: listed_seconds = a_seconds
		end

	mark_upcoming
			-- The listing shows it as scheduled, not yet broadcast.
		do
			is_upcoming := True
		ensure
			upcoming: is_upcoming
			held_back: is_held_back
		end

	mark_live_now
			-- The listing shows it as live at this moment.
		do
			is_live_now := True
		ensure
			live: is_live_now
			held_back: is_held_back
		end

invariant
	parts_attached: video_id /= Void and title /= Void and category /= Void and tab /= Void
	identified: not video_id.is_empty
	tab_known: tab.is_empty or else is_tab_key (tab)
	length_not_negative: listed_seconds >= 0

end
