note
	description: "[
		One video as the channel sweep found it: its id, its title, and
		the category the local model later puts it in. Nothing here comes
		from the player - length, captions and playability arrive later,
		when the queue looks the video up.
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
		ensure
			id_kept: video_id.same_string (a_id)
			title_kept: title.same_string (a_title)
			uncategorised: not is_categorised
		end

feature -- Access

	video_id: STRING_8
			-- The eleven-character id.

	title: STRING_32
			-- The title as the channel listing spells it.

	category: STRING_32
			-- Where the local model filed it; empty until it has.

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

invariant
	parts_attached: video_id /= Void and title /= Void and category /= Void
	identified: not video_id.is_empty

end
