note
	description: "[
		The members-only helper: a standalone console exe that hosts one
		WebView2 window carrying the user's own YouTube login, walks a
		list of watch URLs, and writes each video's caption track to a
		json3 file the GUI then turns into a transcript.

		Why a separate process. The WebView2 event loop is blocking and
		owns its own window; the OCR application runs its own 50 ms pump.
		Isolating the browser in a spawned exe - the pattern the OCR
		worker already uses for the model call - keeps the two loops
		apart and keeps WebView2 out of the main binary.

		Why intercept rather than fetch. A direct fetch of the caption
		URL returns an empty body even from inside the signed-in page
		(YouTube's proof-of-origin gate). So the injected script instead
		captures the player's OWN caption request, which carries the
		session and the token, by patching fetch and XMLHttpRequest, and
		nudges the player to make that request (mute, play, skip the ad,
		turn English captions on). Proven end to end on 2026-09-12.

		Sign-in. The window is visible the whole run. A members-only
		video the user is not yet signed in for answers UNPLAYABLE; the
		helper re-navigates to it a few times so the user can sign in in
		the same window. The WebView2 profile is per-exe and persists, so
		the sign-in is a one-time act; later runs fetch without it.

		Usage: ocr_yt_session.exe <urls-file> <out-dir>
	]"

class
	OCR_YT_SESSION

create
	make

feature {NONE} -- Initialization

	make
		local
			l_args: ARGUMENTS_32
		do
			create l_args
			create out_dir.make_empty
			create urls.make (8)
			create ids.make (8)
			create browser.make
			if l_args.argument_count < 2 then
				io.error.put_string ("usage: ocr_yt_session <urls-file> <out-dir>%N")
			else
				read_urls (l_args.argument (1))
				create out_dir.make_from_string_general (l_args.argument (2))
				if urls.is_empty then
					io.error.put_string ("no usable YouTube links in the list%N")
					write_done
				elseif browser.is_valid then
					browser.set_title ("Simple OCR Capture - sign in to YouTube for members-only videos")
					browser.set_size (1120, 820)
					browser.on_call ("ocr_deliver", agent on_deliver)
					browser.inject (fetch_script)
					current_index := 1
					attempts := 0
					start_current
					browser.run
				else
					io.error.put_string ("Could not create the browser window. Is the WebView2 runtime installed?%N")
					write_done
				end
			end
		end

feature {NONE} -- The walk over the list

	current_index: INTEGER

	attempts: INTEGER

	Max_attempts: INTEGER = 5

	start_current
		require
			in_range: current_index >= 1 and current_index <= urls.count
		do
			attempts := attempts + 1
			print ("[" + current_index.out + "/" + urls.count.out + "] " + ids.i_th (current_index)
				+ " (try " + attempts.out + ")%N")
			browser.navigate_to (urls.i_th (current_index))
		end

	advance
		do
			current_index := current_index + 1
			attempts := 0
			if current_index > urls.count then
				write_done
				browser.close
			else
				start_current
			end
		end

feature {NONE} -- Delivery

	on_deliver (a_seq: STRING_8; a_req: STRING_8)
			-- The injected script calls ocr_deliver(kind, base64(payload)),
			-- so `a_req' is a JSON array ["kind","<b64>"] whose two tokens
			-- carry no quotes or newlines and survive the wrapping intact.
			-- kind is "track" (payload is the json3 body) or "refused"
			-- (payload is the reason).
		local
			l_id, l_kind, l_payload, l_reason: STRING_8
			l_members: BOOLEAN
		do
			browser.respond (a_seq, "%"ok%"")
			l_id := ids.i_th (current_index)
			l_kind := nth_token (a_req, 1)
			l_payload := decoded (nth_token (a_req, 2))
			if l_kind.same_string ("track") and then l_payload.count > 50 then
				write_file (l_id + ".json3", l_payload)
				print ("  saved " + l_payload.count.out + " bytes%N")
				advance
			else
				l_reason := l_payload
				l_members := has_token (l_reason, "member") or has_token (l_reason, "Join this channel")
					or has_token (l_reason, "LOGIN_REQUIRED")
					-- A "timeout" is no caption request captured yet - almost
					-- always a long pre-roll ad or a player that had not begun
					-- playing; it retries. A members gate retries too, to give
					-- the user this window to sign in. A real UNPLAYABLE with a
					-- reason (private, removed, no captions) does not.
				if (l_members or has_token (l_reason, "timeout")) and then attempts < Max_attempts then
					print ("  transient (" + l_reason + "); retry%N")
					start_current
				else
					write_file (l_id + ".refused", l_reason)
					print ("  refused: " + l_reason + "%N")
					advance
				end
			end
		end

feature {NONE} -- Files

	out_dir: STRING_32

	urls: ARRAYED_LIST [STRING_32]

	ids: ARRAYED_LIST [STRING_8]

	browser: SIMPLE_BROWSER

	read_urls (a_path: READABLE_STRING_GENERAL)
		local
			l_file: PLAIN_TEXT_FILE
			l_line, l_id: STRING_8
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (a_path)
				if l_file.exists and then l_file.is_readable then
					l_file.open_read
					from
					until
						l_file.end_of_file
					loop
						l_file.read_line
						l_line := l_file.last_string.twin
						l_line.adjust
						if not l_line.is_empty then
							l_id := video_id (l_line)
							if not l_id.is_empty then
								urls.extend (canonical_watch (l_id))
								ids.extend (l_id)
							end
						end
					end
					l_file.close
				end
			end
		rescue
			l_retried := True
			retry
		end

	canonical_watch (a_id: STRING_8): STRING_32
		do
			create Result.make_from_string_general ("https://www.youtube.com/watch?v=")
			Result.append_string_general (a_id)
		end

	video_id (a_line: STRING_8): STRING_8
		do
			create Result.make_empty
			Result := after_marker (a_line, "v=")
			if Result.is_empty then Result := after_marker (a_line, "youtu.be/") end
			if Result.is_empty then Result := after_marker (a_line, "/live/") end
			if Result.is_empty then Result := after_marker (a_line, "/shorts/") end
			if Result.is_empty then Result := after_marker (a_line, "/embed/") end
			if Result.is_empty and then a_line.count = 11 and then run_of_id (a_line, 1).count = 11 then
				Result := a_line.twin
			end
		end

	after_marker (a_line, a_marker: STRING_8): STRING_8
		local
			i: INTEGER
		do
			create Result.make_empty
			i := a_line.substring_index (a_marker, 1)
			if i > 0 then
				Result := run_of_id (a_line, i + a_marker.count)
			end
		end

	run_of_id (a_line: STRING_8; a_start: INTEGER): STRING_8
		local
			i: INTEGER
		do
			create Result.make (11)
			from i := a_start until i > a_line.count or else not is_id_char (a_line.item (i)) loop
				Result.extend (a_line.item (i))
				i := i + 1
			end
			if Result.count /= 11 then
				Result.wipe_out
			end
		end

	is_id_char (c: CHARACTER_8): BOOLEAN
		do
			Result := (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')
				or (c >= '0' and c <= '9') or c = '_' or c = '-'
		end

	write_file (a_name, a_content: STRING_8)
		local
			l_file: RAW_FILE
			l_path: STRING_32
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_path.make_from_string (out_dir)
				if not l_path.is_empty and then l_path.item (l_path.count) /= '\' then
					l_path.append_character ('\')
				end
				l_path.append_string_general (a_name)
				create l_file.make_open_write (l_path)
				l_file.put_string (a_content)
				l_file.close
			end
		rescue
			l_retried := True
			retry
		end

	write_done
		do
			write_file ("session.done", "done")
		end

feature {NONE} -- Payload decode (the arg is ["kind","<base64>"])

	nth_token (a_req: STRING_8; a_n: INTEGER): STRING_8
			-- The `a_n'-th double-quoted token in `a_req'; the tokens hold
			-- only word/base64 characters, so no escaping to undo.
		require
			positive: a_n >= 1
		local
			i, seen, q1: INTEGER
		do
			create Result.make (64)
			from
				i := 1
				seen := 0
			until
				i > a_req.count or seen = a_n
			loop
				if a_req.item (i) = '%"' then
					q1 := i + 1
					from i := q1 until i > a_req.count or else a_req.item (i) = '%"' loop
						i := i + 1
					end
					seen := seen + 1
					if seen = a_n then
						Result := a_req.substring (q1, (i - 1).max (q1 - 1))
						if q1 > i then
							Result.wipe_out
						end
					end
				end
				i := i + 1
			end
		end

	decoded (a_b64: STRING_8): STRING_8
			-- `a_b64' as raw bytes; empty on anything unparseable.
		local
			l_b: SIMPLE_BASE64
			l_clean: STRING_8
			l_retried: BOOLEAN
		do
			if l_retried then
				create Result.make_empty
			else
				create l_b.make
				l_clean := a_b64.twin
				l_clean.prune_all ('%N')
				l_clean.prune_all ('%R')
				Result := l_b.decode_lenient (l_clean)
			end
		rescue
			l_retried := True
			retry
		end

	has_token (a_text, a_token: STRING_8): BOOLEAN
		do
			Result := a_text.substring_index (a_token, 1) > 0
		end

	fetch_script: STRING_8
		once
			Result := "[
(function(){
  var done=false, TARGET='';
  function vid(u){ var m=/[?&]v=([A-Za-z0-9_-]{11})/.exec(u||''); return m?m[1]:''; }
  function isTrack(u){ return u && u.indexOf('timedtext')>=0 && (!TARGET || vid(u)===TARGET); }
  function b64(s){ try{ return btoa(unescape(encodeURIComponent(s||''))); }catch(e){ return ''; } }
  function deliver(kind, payload){ if(done) return; done=true; try{ window.ocr_deliver(kind, b64(payload)); }catch(e){} }
  var of=window.fetch;
  window.fetch=function(input, init){
    var u=(typeof input==='string')?input:(input&&input.url)||'';
    var p=of.apply(this, arguments);
    if(isTrack(u)){ p.then(function(r){return r.clone().text();}).then(function(x){ if(x&&x.length>50) deliver('track', x); }).catch(function(){}); }
    return p;
  };
  var oo=XMLHttpRequest.prototype.open, os=XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open=function(m,u){ this.__u=u; return oo.apply(this,arguments); };
  XMLHttpRequest.prototype.send=function(){ var x=this; if(isTrack(x.__u)){ x.addEventListener('load',function(){ var t=x.responseText||''; if(t&&t.length>50) deliver('track', t); }); } return os.apply(this,arguments); };
  var n=0; var iv=setInterval(function(){
    n++;
    try{
      var pr=window.ytInitialPlayerResponse, st=pr&&pr.playabilityStatus&&pr.playabilityStatus.status;
      if(!TARGET && pr&&pr.videoDetails&&pr.videoDetails.videoId) TARGET=pr.videoDetails.videoId;
      if(st && st!=='OK'){ clearInterval(iv); deliver('refused', st+': '+(pr.playabilityStatus.reason||'')); return; }
      var sk=document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button'); if(sk){ try{sk.click();}catch(e){} }
      var v=document.querySelector('video'); if(v){ v.muted=true; if(v.paused){ try{v.play();}catch(e){} } }
      var mp=document.getElementById('movie_player');
      if(mp&&mp.loadModule){ try{mp.loadModule('captions');}catch(e){} try{mp.setOption('captions','track',{languageCode:'en'});}catch(e){} }
    }catch(e){}
    if(n>90){ clearInterval(iv); if(!done) deliver('refused', 'no caption request captured (timeout)'); }
  },500);
})();
]"
		end

end
