note
	description: "[
		One row of the Video queue: a link, the run that looks it up
		and fetches it, the file it will be written to, and where it
		stands - waiting for its lookup, ready, refused by YouTube,
		saved, or failed. The queue advances rows one at a time on the
		tick; the grid shows each row's own words.
	]"

class
	OCR_VIDEO_ITEM

create
	make

feature {NONE} -- Initialization

	make (a_url: READABLE_STRING_GENERAL; a_settings: OCR_SETTINGS)
		require
			link_given: not a_url.is_empty
		do
			create url.make_from_string_general (a_url)
			create run.make (a_settings)
			create file_name.make_empty
			create detail.make_empty
			state := State_pending
		ensure
			url_kept: url.same_string_general (a_url)
			pending: is_pending
		end

feature -- States

	State_pending: INTEGER = 1
			-- Not looked up yet.

	State_ready: INTEGER = 2
			-- Looked up; captions can be fetched.

	State_refused: INTEGER = 3
			-- Looked up; YouTube will not give captions (or has none).

	State_saved: INTEGER = 4
			-- Transcript written.

	State_failed: INTEGER = 5
			-- Lookup or fetch hit a fault (network, parse, file).

feature -- Access

	url: STRING_32
			-- The link as added.

	run: OCR_VIDEO_RUN
			-- The lookup and the fetch for this video.

	file_name: STRING_32
			-- The file the transcript goes to, inside the batch folder;
			-- empty until the lookup names it.

	state: INTEGER

	detail: STRING_32
			-- The words behind the state: a refusal reason, the saved
			-- message, a fault.

	video_id: STRING_8
			-- The 11-character id in `url'; empty when the link is not
			-- a video link.
		do
			Result := (create {OCR_VIDEO_ID}).video_id_of (url)
		end

	title: STRING_32
		do
			if run.is_probed and then not run.track.title.is_empty then
				Result := run.track.title
			else
				Result := url
			end
		end

	channel: STRING_32
		do
			Result := run.track.channel
		end

	length_caption: STRING_32
		do
			if run.track.length_seconds > 0 then
				Result := run.text.clock_caption (run.track.length_seconds)
			else
				create Result.make_empty
			end
		end

	captions_caption: STRING_32
			-- Which track would be read, or why none.
		do
			if not run.is_probed then
				create Result.make_empty
			elseif run.track.is_members_only then
				Result := {STRING_32} "members only"
			elseif run.track.needs_login then
				Result := {STRING_32} "sign-in required"
			elseif not run.track.is_playable then
				Result := {STRING_32} "unavailable"
			elseif not run.track.has_captions then
				Result := {STRING_32} "none"
			else
				Result := run.track.track_caption (run.track.preferred_track)
			end
		end

	is_session_fetching: BOOLEAN
			-- Is a signed-in browser session fetching this row right now?
			-- A transient flag over the real state, so the row reads
			-- "fetching..." instead of its stale "refused" while the helper
			-- window works. Cleared when the session decides the row.

	status_caption: STRING_32
			-- The state in words, with its detail.
		do
			if is_session_fetching then
				Result := {STRING_32} "fetching through your signed-in browser..."
			else
			inspect state
			when State_pending then
				Result := {STRING_32} "waiting for lookup"
			when State_ready then
				Result := {STRING_32} "ready"
			when State_refused then
				Result := {STRING_32} "refused: " + detail
			when State_saved then
				Result := detail.twin
			else
				Result := {STRING_32} "failed: " + detail
			end
			end
		ensure
			never_empty: not Result.is_empty
		end

	mark_session_running
			-- The signed-in browser session has taken this row on.
		do
			is_session_fetching := True
		ensure
			fetching: is_session_fetching
		end

feature -- Status report

	is_pending: BOOLEAN
		do
			Result := state = State_pending
		end

	is_ready: BOOLEAN
		do
			Result := state = State_ready
		end

	is_refused: BOOLEAN
		do
			Result := state = State_refused
		end

	is_saved: BOOLEAN
		do
			Result := state = State_saved
		end

	is_failed: BOOLEAN
		do
			Result := state = State_failed
		end

	is_finished: BOOLEAN
			-- Nothing more will happen to this row.
		do
			Result := is_saved or is_refused or is_failed
		end

	is_queued: BOOLEAN
			-- Waiting its turn in a fetch pass?

feature -- Element change

	set_file_name (a_name: READABLE_STRING_GENERAL)
			-- Name the file; a name without an extension gets ".md".
		require
			named: not a_name.is_empty
		do
			create file_name.make_from_string_general (a_name)
			file_name.left_adjust
			file_name.right_adjust
			if file_name.last_index_of ('.', file_name.count) <= 1 then
				file_name.append_string_general (".md")
			end
		ensure
			named: not file_name.is_empty
		end

	set_queued (a_flag: BOOLEAN)
		do
			is_queued := a_flag
		ensure
			set: is_queued = a_flag
		end

	set_front_matter (a_yaml: READABLE_STRING_GENERAL)
			-- Open this row's Markdown transcript with `a_yaml'. The
			-- channel harvest uses it to record the channel and the
			-- category; a row added by hand leaves it empty.
		do
			run.set_front_matter (a_yaml)
		ensure
			set: run.front_matter.same_string_general (a_yaml)
		end

feature -- Basic operations

	look_up
			-- Ask YouTube about the link; land in ready, refused or
			-- failed. Also proposes the file name from the title.
		require
			pending: is_pending
		do
			if run.probe (url) then
				if run.can_fetch then
					state := State_ready
					detail.wipe_out
				else
					state := State_refused
					detail := run.blocking_reason
				end
				if file_name.is_empty then
					set_file_name (run.suggested_file_name)
				end
			else
				state := State_failed
				detail := run.last_error.twin
			end
		ensure
			decided: not is_pending
		end

	fetch_into (a_folder: READABLE_STRING_GENERAL)
			-- Write the transcript to `a_folder' \ `file_name'.
		require
			ready: is_ready
			named: not file_name.is_empty
			folder_given: not a_folder.is_empty
		do
			if run.fetch_and_save (path_in (a_folder)) then
				state := State_saved
				detail := run.last_message.twin
			else
				state := State_failed
				detail := run.last_error.twin
			end
			is_queued := False
		ensure
			decided: is_saved or is_failed
			unqueued: not is_queued
		end

	session_fetch_into (a_json3: READABLE_STRING_32; a_folder: READABLE_STRING_GENERAL)
			-- Write the transcript from a track the sign-in helper fetched.
		require
			probed: run.is_probed
			named: not file_name.is_empty
			folder_given: not a_folder.is_empty
			json3_given: not a_json3.is_empty
		do
			if run.save_session_track (a_json3, path_in (a_folder)) then
				state := State_saved
				detail := run.last_message.twin
			else
				state := State_failed
				detail := run.last_error.twin
			end
			is_queued := False
			is_session_fetching := False
		ensure
			decided: is_saved or is_failed
			not_fetching: not is_session_fetching
		end

	mark_refused (a_reason: READABLE_STRING_GENERAL)
			-- The sign-in helper could not get this one.
		do
			state := State_refused
			create detail.make_from_string_general (a_reason)
			is_queued := False
			is_session_fetching := False
		ensure
			refused: is_refused
			not_fetching: not is_session_fetching
		end

	path_in (a_folder: READABLE_STRING_GENERAL): STRING_32
			-- `a_folder' joined with `file_name'.
		require
			named: not file_name.is_empty
		do
			create Result.make_from_string_general (a_folder)
			if not Result.is_empty and then Result.item (Result.count) /= '\' then
				Result.append_character ('\')
			end
			Result.append (file_name)
		end

invariant
	url_given: not url.is_empty
	state_known: state >= State_pending and state <= State_failed
	detail_attached: detail /= Void

end
