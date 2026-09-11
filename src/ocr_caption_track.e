note
	description: "[
		Fetches a YouTube video's caption track the way the player does,
		with no browser, no yt-dlp and no Python: one POST to the
		player endpoint answers with the title, channel, length,
		playability and the list of caption tracks; one GET on a track's
		URL, asked for json3, returns the cues.

		The player is asked as the Android client. Measured 2026-09-11:
		the web client's track URLs answer HTTP 200 with an EMPTY body
		(YouTube wants a proof-of-origin token from that client), while
		the Android client's URLs return the full 391 KB json3 track for
		a 23:40 video - 1434 events, 4465 words, the same count yt-dlp
		reports. The Android URL carries fmt=srv3, which must be replaced,
		not appended to: a second fmt is ignored.

		Members-only videos answer UNPLAYABLE with a reason naming the
		channel membership; the title, channel and length still arrive.
		That is reported, not worked around: the signed-in route is a
		separate feature.

		Everything here is WinHTTP (OCR_HTTP) and simple_json.
	]"

class
	OCR_CAPTION_TRACK

create
	make

feature {NONE} -- Initialization

	make
		do
			create http.make
			create video_id.make_empty
			create title.make_empty
			create channel.make_empty
			create status.make_empty
			create status_reason.make_empty
			create last_error.make_empty
			create last_json3.make_empty
			create tracks.make (2)
		end

feature -- Access

	video_id: STRING_8
			-- The id the last `probe' looked up.

	title: STRING_32
			-- Video title from the last `probe'; empty when unknown.

	channel: STRING_32
			-- Channel name from the last `probe'.

	length_seconds: INTEGER
			-- Video length from the last `probe'; 0 when unknown.

	status: STRING_32
			-- The player's playability status: "OK", "UNPLAYABLE",
			-- "LOGIN_REQUIRED", "ERROR"; empty before a probe.

	status_reason: STRING_32
			-- The player's own words when `status' is not "OK".

	tracks: ARRAYED_LIST [TUPLE [language, kind, name, base_url: STRING_32]]
			-- Caption tracks on offer. `kind' is "asr" for automatic
			-- captions and empty for uploaded ones.

	last_error: STRING_32
			-- Why the last operation failed; empty when it succeeded.

	last_json3: STRING_32
			-- The track text the last `fetch_json3' brought back.

	is_probed: BOOLEAN
			-- Has `probe' answered for `video_id'?

feature -- Status report

	is_playable: BOOLEAN
			-- Did the player say the video plays for an anonymous viewer?
		do
			Result := status.same_string_general ("OK")
		end

	is_members_only: BOOLEAN
			-- Is the video gated behind a channel membership?
		local
			l_reason: STRING_32
		do
			l_reason := status_reason.as_lower
			Result := not is_playable and then
				(l_reason.has_substring ({STRING_32} "member") or l_reason.has_substring ({STRING_32} "join this channel"))
		end

	needs_login: BOOLEAN
			-- Did the player ask for a signed-in viewer (age gate, private)?
		do
			Result := status.same_string_general ("LOGIN_REQUIRED")
		end

	has_captions: BOOLEAN
		do
			Result := not tracks.is_empty
		end

	preferred_track: INTEGER
			-- The track to read: an uploaded English track over an
			-- automatic one, English over anything else, uploaded over
			-- automatic; 0 when there are none.
		local
			i, l_best_score, l_score: INTEGER
		do
			from
				i := 1
			until
				i > tracks.count
			loop
				l_score := 1
				if tracks.i_th (i).kind.is_empty then
					l_score := l_score + 2
				end
				if tracks.i_th (i).language.as_lower.starts_with ({STRING_32} "en") then
					l_score := l_score + 4
				end
				if l_score > l_best_score then
					l_best_score := l_score
					Result := i
				end
				i := i + 1
			end
		ensure
			none_when_empty: tracks.is_empty implies Result = 0
			in_range: not tracks.is_empty implies (Result >= 1 and Result <= tracks.count)
		end

	track_caption (a_index: INTEGER): STRING_32
			-- How the track reads in a header line: its name, or its
			-- language with "(auto-generated)" for automatic captions.
		require
			in_range: a_index >= 1 and a_index <= tracks.count
		do
			if not tracks.i_th (a_index).name.is_empty then
				Result := tracks.i_th (a_index).name.twin
			else
				Result := tracks.i_th (a_index).language.twin
				if not tracks.i_th (a_index).kind.is_empty then
					Result.append_string_general (" (auto-generated)")
				end
			end
		end

feature -- Basic operations

	probe (a_url: READABLE_STRING_GENERAL): BOOLEAN
			-- Look `a_url' up: title, channel, length, status and tracks.
		local
			l_ids: OCR_VIDEO_ID
		do
			reset
			create l_ids
			video_id := l_ids.video_id_of (a_url)
			if video_id.is_empty then
				last_error := {STRING_32} "That is not a YouTube video link: "
				last_error.append_string_general (a_url)
			elseif http.post (Player_url, "application/json", player_request_body, Timeout_seconds) then
				parse_player (http.last_body)
				is_probed := True
				Result := True
			else
				last_error := {STRING_32} "Could not reach YouTube: "
				last_error.append (http.last_error)
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			probed_on_success: Result implies is_probed
		end

	fetch_json3 (a_index: INTEGER): BOOLEAN
			-- Bring track `a_index' back as json3 into `last_json3'.
		require
			probed: is_probed
			in_range: a_index >= 1 and a_index <= tracks.count
		do
			last_error.wipe_out
			last_json3.wipe_out
			if http.get (json3_url (tracks.i_th (a_index).base_url), Timeout_seconds) then
				last_json3 := decoded (http.last_body)
				if last_json3.is_empty then
					last_error := {STRING_32} "YouTube answered the caption request with an empty track (a client gate, not a network fault)."
				else
					Result := True
				end
			else
				last_error := {STRING_32} "Could not fetch the caption track: "
				last_error.append (http.last_error)
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			text_on_success: Result implies not last_json3.is_empty
		end

feature -- Conversion

	json3_url (a_base_url: READABLE_STRING_32): STRING_8
			-- `a_base_url' asking for json3: any fmt= already there is
			-- removed first, since the server honours the first one.
		local
			i, j: INTEGER
		do
			create Result.make (a_base_url.count + 12)
			Result.append_string_general (a_base_url)
			from
				i := Result.substring_index ("fmt=", 1)
			until
				i = 0
			loop
				if i > 1 and then (Result.item (i - 1) = '&' or Result.item (i - 1) = '?') then
					j := Result.index_of ('&', i)
					if j = 0 then
						j := Result.count + 1
					end
						-- drop "fmt=xxx" and the separator before it when
						-- another parameter follows; keep '?' when it leads
					if Result.item (i - 1) = '&' then
						Result.remove_substring (i - 1, j - 1)
					elseif j <= Result.count then
						Result.remove_substring (i, j)
					else
						Result.remove_substring (i - 1, j - 1)
					end
					i := Result.substring_index ("fmt=", 1)
				else
					i := Result.substring_index ("fmt=", i + 1)
				end
			end
			if Result.has ('?') then
				Result.append ("&fmt=json3")
			else
				Result.append ("?fmt=json3")
			end
		ensure
			asks_json3: Result.ends_with ("fmt=json3")
		end

feature {NONE} -- Implementation

	http: OCR_HTTP

	Player_url: STRING_8 = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"

	Timeout_seconds: INTEGER = 20

	reset
		do
			video_id.wipe_out
			title.wipe_out
			channel.wipe_out
			status.wipe_out
			status_reason.wipe_out
			last_error.wipe_out
			last_json3.wipe_out
			tracks.wipe_out
			length_seconds := 0
			is_probed := False
		end

	player_request_body: STRING_8
			-- The Android client's player request for `video_id'.
		do
			create Result.make (160)
			Result.append ("{%"context%":{%"client%":{%"clientName%":%"ANDROID%",%"clientVersion%":%"20.10.38%",%"androidSdkVersion%":30,%"hl%":%"en%"}},%"videoId%":%"")
			Result.append (video_id)
			Result.append ("%"}")
		end

	parse_player (a_body: STRING_8)
			-- Read status, details and tracks out of the player reply.
		local
			l_json: SIMPLE_JSON
			i: INTEGER
			l_language, l_kind, l_name, l_url: STRING_32
		do
			create l_json
			if a_body.is_empty then
				status := {STRING_32} "ERROR"
				status_reason := {STRING_32} "YouTube sent an empty reply."
			elseif attached l_json.parse (decoded (a_body)) as al_value and then al_value.is_object then
				if attached al_value.as_object.object_item ({STRING_32} "playabilityStatus") as al_status then
					if attached al_status.string_item ({STRING_32} "status") as al_s then
						status := al_s.twin
					end
					if attached al_status.string_item ({STRING_32} "reason") as al_r then
						status_reason := al_r.twin
					end
				end
				if attached al_value.as_object.object_item ({STRING_32} "videoDetails") as al_details then
					if attached al_details.string_item ({STRING_32} "title") as al_t then
						title := al_t.twin
					end
					if attached al_details.string_item ({STRING_32} "author") as al_a then
						channel := al_a.twin
					end
					if attached al_details.string_item ({STRING_32} "lengthSeconds") as al_l and then al_l.is_integer then
						length_seconds := al_l.to_integer
					end
				end
				if attached al_value.as_object.object_item ({STRING_32} "captions") as al_captions
					and then attached al_captions.object_item ({STRING_32} "playerCaptionsTracklistRenderer") as al_renderer
					and then attached al_renderer.array_item ({STRING_32} "captionTracks") as al_tracks
				then
					from
						i := 1
					until
						i > al_tracks.count
					loop
						if attached al_tracks.object_item (i) as al_track
							and then attached al_track.string_item ({STRING_32} "baseUrl") as al_url
						then
							create l_url.make_from_string (al_url)
							create l_language.make_empty
							create l_kind.make_empty
							create l_name.make_empty
							if attached al_track.string_item ({STRING_32} "languageCode") as al_lang then
								l_language := al_lang.twin
							end
							if attached al_track.string_item ({STRING_32} "kind") as al_k then
								l_kind := al_k.twin
							end
							l_name := track_name (al_track)
							tracks.extend ([l_language, l_kind, l_name, l_url])
						end
						i := i + 1
					end
				end
				if status.is_empty then
					status := {STRING_32} "ERROR"
					status_reason := {STRING_32} "The player reply carried no playability status."
				end
			else
				status := {STRING_32} "ERROR"
				status_reason := {STRING_32} "YouTube's reply was not JSON."
			end
		ensure
			status_known: not status.is_empty
		end

	track_name (a_track: SIMPLE_JSON_OBJECT): STRING_32
			-- The display name: name.runs[1].text (Android) or
			-- name.simpleText (web); empty when neither is there.
		do
			create Result.make_empty
			if attached a_track.object_item ({STRING_32} "name") as al_name then
				if attached al_name.string_item ({STRING_32} "simpleText") as al_simple then
					Result := al_simple.twin
				elseif attached al_name.array_item ({STRING_32} "runs") as al_runs and then al_runs.count >= 1
					and then attached al_runs.object_item (1) as al_run
					and then attached al_run.string_item ({STRING_32} "text") as al_text
				then
					Result := al_text.twin
				end
			end
		end

	decoded (a_utf8: STRING_8): STRING_32
			-- `a_utf8' bytes as characters.
		do
			Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_utf8)
		end

invariant
	strings_attached: video_id /= Void and title /= Void and channel /= Void
		and status /= Void and status_reason /= Void and last_error /= Void and last_json3 /= Void
	tracks_attached: tracks /= Void
	length_non_negative: length_seconds >= 0

end
