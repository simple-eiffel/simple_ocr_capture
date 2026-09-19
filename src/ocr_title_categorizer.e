note
	description: "[
		Reads the titles a channel sweep found and files each video
		under a category, using the local model and nothing else. No
		title leaves this machine.

		Two passes, because the two questions are different. The first
		asks the model to READ the channel and name the categories that
		actually fit it - a channel of verse-by-verse studies and a
		channel of debate clips should not be filed under the same
		headings, and a list supplied in advance would force them to be.
		The second asks it to PLACE each title in one of the names it
		just chose, a handful of titles at a time, so a long channel
		does not ride on one enormous reply.

		A title the model does not place, or places somewhere it did not
		itself propose, goes to `Uncategorised'. Guessing is worse than
		saying nothing: a transcript in the wrong category is harder to
		find again than one that was never claimed.

		The model is found rather than configured. When
		`settings.category_model' is empty, Ollama is asked what it
		holds and the first model that is not an OCR or vision one is
		taken - the OCR model this application already runs cannot do
		this job, and asking the user to name a second one before the
		feature works is a setup step for nothing.

		num_ctx is set on every call. Ollama's 4096 default is smaller
		than two hundred titles, and a truncated reply from a language
		model reads exactly like a short one - see the note on
		OCR_SETTINGS.num_ctx for the same trap in the OCR path.

		Thinking is turned OFF on every call, and that is not a
		preference: with it on, the first live run of this class never
		came back. See `generate_body' for the measurement.
	]"

class
	OCR_TITLE_CATEGORIZER

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
		do
			settings := a_settings
			create http.make
			create categories.make (16)
			create last_error.make_empty
			create last_message.make_empty
			create resolved_model.make_empty
		end

feature -- Access

	categories: ARRAYED_LIST [STRING_32]
			-- The headings the model proposed for this channel.

	resolved_model: STRING_8
			-- The model the last call actually ran; empty until one has.

	last_error: STRING_32
			-- Why the last call failed; empty when it did not.

	last_message: STRING_32
			-- What the last call has to say for the status line.

	Uncategorised: STRING_32 = "Uncategorized"
			-- Where a title the model would not place is filed.

	Assign_chunk: INTEGER = 25
			-- Titles per placing call.

feature -- Status report

	has_categories: BOOLEAN
		do
			Result := not categories.is_empty
		end

	is_known_category (a_name: READABLE_STRING_32): BOOLEAN
			-- Is `a_name' one the model proposed, or `Uncategorised'?
		do
			Result := a_name.as_lower.same_string (Uncategorised.as_lower)
			across
				categories as ic
			until
				Result
			loop
				Result := ic.as_lower.same_string (a_name.as_lower)
			end
		end

feature -- Element change

	seed (a_names: LIST [STRING_32])
			-- Adopt categories that are already in use.
			--
			-- A channel harvested a second time should file its new
			-- videos under the headings the first harvest chose, not
			-- under a fresh set that means the same things in different
			-- words. `propose' is then not called at all, which also
			-- makes the common re-run - a handful of new videos - a good
			-- deal quicker.
		do
			categories.wipe_out
			across
				a_names as ic
			loop
				if not ic.is_empty and then not ic.as_lower.same_string (Uncategorised.as_lower)
					and then not holds_category (ic) and then categories.count < Category_limit
				then
					categories.extend (ic.twin)
				end
			end
		end

feature -- Basic operations

	propose (a_videos: LIST [OCR_CHANNEL_VIDEO]; a_channel: READABLE_STRING_32): BOOLEAN
			-- Ask the model to name the categories that fit `a_videos'.
		require
			something_to_read: not a_videos.is_empty
		do
			categories.wipe_out
			last_error.wipe_out
			if not ensure_model then
					-- `last_error' already says why
			elseif not ask (propose_prompt (a_videos, a_channel), Propose_ctx) then
					-- `last_error' already says why
			else
				read_categories (last_reply)
				if categories.is_empty then
					last_error := {STRING_32} "The model proposed no categories it could use. Its reply was: "
					last_error.append (clipped (last_reply))
				else
					create last_message.make (80)
					last_message.append_string_general ("The model proposed ")
					last_message.append_string_general (categories.count.out)
					last_message.append_string_general (" categories for this channel.")
					Result := True
				end
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			categories_on_success: Result implies has_categories
		end

	place (a_chunk: LIST [OCR_CHANNEL_VIDEO]): BOOLEAN
			-- File each video of `a_chunk' under one of `categories'.
			-- Every video comes out categorised: one the model would not
			-- place is filed under `Uncategorised'.
		require
			proposed: has_categories
			something_to_place: not a_chunk.is_empty
			small_enough: a_chunk.count <= Assign_chunk
		local
			l_placed: INTEGER
		do
			last_error.wipe_out
			if not ensure_model then
					-- `last_error' already says why
			elseif not ask (assign_prompt (a_chunk), Assign_ctx) then
					-- `last_error' already says why
			else
				l_placed := apply_placings (last_reply, a_chunk)
					-- Whatever the model left out is still filed, just not
					-- by it: the harvest must never stall on a title.
				across
					a_chunk as ic
				loop
					if not ic.is_categorised then
						ic.set_category (Uncategorised)
					end
				end
				create last_message.make (80)
				last_message.append_string_general ("Filed ")
				last_message.append_string_general (l_placed.out)
				last_message.append_string_general (" of ")
				last_message.append_string_general (a_chunk.count.out)
				last_message.append_string_general (" titles.")
				Result := True
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			all_filed: Result implies across a_chunk as ic all ic.is_categorised end
		end

feature -- Conversion

	read_categories (a_reply: READABLE_STRING_32)
			-- Take one category per line out of `a_reply', dropping the
			-- numbering, bullets and quotes a model likes to add, and
			-- anything too long to be a folder name.
		local
			l_lines: LIST [STRING_32]
			l_name: STRING_32
		do
			categories.wipe_out
			l_lines := thought_removed (a_reply).split ('%N')
			across
				l_lines as ic
			loop
				l_name := bare_name (ic)
				if l_name.count >= 2 and then l_name.count <= Category_cap
					and then not holds_category (l_name) and then categories.count < Category_limit
				then
					categories.extend (l_name)
				end
			end
		end

	bare_name (a_line: READABLE_STRING_32): STRING_32
			-- `a_line' with a leading number, bullet or dash removed and
			-- the characters a folder name cannot carry dropped.
		local
			i: INTEGER
			c: CHARACTER_32
			l_seen_text: BOOLEAN
		do
			create Result.make (a_line.count)
			from
				i := 1
			until
				i > a_line.count
			loop
				c := a_line.item (i)
				if not l_seen_text and then (c.is_digit or c = '-' or c = '*' or c = '.'
					or c = ')' or c = '#' or c = '%'' or c = '%"' or c.is_space)
				then
						-- still in the decoration before the name
				else
					l_seen_text := True
					if c.natural_32_code >= 32 and then not Name_reserved.has (c) then
						Result.append_character (c)
					end
				end
				i := i + 1
			end
			Result.right_adjust
			Result.left_adjust
		end

	holds_category (a_name: READABLE_STRING_32): BOOLEAN
		do
			across
				categories as ic
			until
				Result
			loop
				Result := ic.as_lower.same_string (a_name.as_lower)
			end
		end

	Name_reserved: STRING_32 = "\/:*?%"<>|"

	Category_cap: INTEGER = 48
			-- Longer than this is a sentence, not a folder name.

	Category_limit: INTEGER = 20

feature {NONE} -- Prompts

	propose_prompt (a_videos: LIST [OCR_CHANNEL_VIDEO]; a_channel: READABLE_STRING_32): STRING_32
			-- Ask for the headings this channel wants.
		local
			l_step, i, l_taken: INTEGER
		do
			create Result.make (4000)
			Result.append_string_general ("These are video titles from the YouTube channel %"")
			Result.append (a_channel)
			Result.append_string_general ("%".%N%N")
			Result.append_string_general ("Read them and decide what this channel is actually about. Then name between 6 and 14 categories that together cover these videos, so that each video could be filed under exactly one of them.%N%N")
			Result.append_string_general ("Rules for your answer:%N")
			Result.append_string_general ("- One category name per line, and nothing else. No numbering, no bullets, no explanation, no preamble.%N")
			Result.append_string_general ("- Two to four words each, in Title Case.%N")
			Result.append_string_general ("- They must be folder names, so no slashes, colons or quotes.%N")
			Result.append_string_general ("- Name what THIS channel covers. Do not use generic headings like %"Miscellaneous%" or %"Other%".%N%N")
			Result.append_string_general ("Titles:%N")
				-- Sampled evenly rather than taken from the top: the newest
				-- videos of a channel are often one series, and a list of
				-- categories drawn from them alone would not fit the rest.
			if a_videos.count > Propose_sample then
				l_step := a_videos.count // Propose_sample
			else
				l_step := 1
			end
			from
				i := 1
			until
				i > a_videos.count or l_taken >= Propose_sample
			loop
				Result.append (a_videos.i_th (i).title)
				Result.append_character ('%N')
				l_taken := l_taken + 1
				i := i + l_step
			end
		end

	assign_prompt (a_chunk: LIST [OCR_CHANNEL_VIDEO]): STRING_32
			-- Ask where each of these titles belongs.
		local
			i: INTEGER
		do
			create Result.make (2000)
			Result.append_string_general ("File each numbered video title under exactly one of these categories:%N%N")
			across
				categories as ic
			loop
				Result.append (ic)
				Result.append_character ('%N')
			end
			Result.append (Uncategorised)
			Result.append_string_general ("%N%NAnswer with one line per title, in this exact form:%N")
			Result.append_string_general ("<number>|<category name>%N%N")
			Result.append_string_general ("Copy the category name exactly as it is spelled above. Use ")
			Result.append (Uncategorised)
			Result.append_string_general (" when none of the others fits. Give no other text.%N%NTitles:%N")
			from
				i := 1
			until
				i > a_chunk.count
			loop
				Result.append_string_general (i.out)
				Result.append_string_general (". ")
				Result.append (a_chunk.i_th (i).title)
				Result.append_character ('%N')
				i := i + 1
			end
		end

	Propose_sample: INTEGER = 200
			-- Titles shown when asking for categories.

	Propose_ctx: INTEGER = 32768

	Assign_ctx: INTEGER = 16384

feature {NONE} -- Reading the reply

	apply_placings (a_reply: READABLE_STRING_32; a_chunk: LIST [OCR_CHANNEL_VIDEO]): INTEGER
			-- Set the category of each video `a_reply' names; the count
			-- placed is returned. A number out of range, or a category
			-- the model did not itself propose, is ignored.
		local
			l_lines: LIST [STRING_32]
			l_bar, l_index: INTEGER
			l_head, l_name: STRING_32
		do
			l_lines := thought_removed (a_reply).split ('%N')
			across
				l_lines as ic
			loop
				l_bar := ic.index_of ('|', 1)
				if l_bar > 1 then
					l_head := ic.substring (1, l_bar - 1)
					l_head.left_adjust
					l_head.right_adjust
					l_name := bare_name (ic.substring (l_bar + 1, ic.count))
					if l_head.is_integer then
						l_index := l_head.to_integer
						if l_index >= 1 and then l_index <= a_chunk.count
							and then not l_name.is_empty and then is_known_category (l_name)
							and then not a_chunk.i_th (l_index).is_categorised
						then
							a_chunk.i_th (l_index).set_category (matching_category (l_name))
							Result := Result + 1
						end
					end
				end
			end
		ensure
			within_the_chunk: Result >= 0 and Result <= a_chunk.count
		end

	matching_category (a_name: READABLE_STRING_32): STRING_32
			-- The proposed category `a_name' names, spelled the way it
			-- was proposed, so two spellings cannot become two folders.
		require
			known: is_known_category (a_name)
		do
			Result := Uncategorised.twin
			across
				categories as ic
			until
				not Result.same_string (Uncategorised)
			loop
				if ic.as_lower.same_string (a_name.as_lower) then
					Result := ic.twin
				end
			end
		ensure
			never_empty: not Result.is_empty
		end

	thought_removed (a_reply: READABLE_STRING_32): STRING_32
			-- `a_reply' without the reasoning a thinking model emits
			-- before its answer. Qwen and its kin wrap it in <think>
			-- tags; everything up to the last closing tag is dropped.
		local
			i: INTEGER
		do
			create Result.make_from_string (a_reply.to_string_32)
			i := last_index_of_substring (Result, Think_close)
			if i > 0 then
				Result := Result.substring (i + Think_close.count, Result.count)
			end
			Result.left_adjust
		end

	last_index_of_substring (a_text: READABLE_STRING_32; a_mark: READABLE_STRING_32): INTEGER
			-- Where `a_mark' last starts in `a_text'; 0 when absent.
		local
			i: INTEGER
		do
			from
				i := a_text.substring_index (a_mark, 1)
			until
				i = 0
			loop
				Result := i
				i := a_text.substring_index (a_mark, i + 1)
			end
		end

	Think_close: STRING_32 = "</think>"

	clipped (a_text: READABLE_STRING_32): STRING_32
			-- The first `Clip' characters of `a_text', for an error line.
		do
			Result := a_text.substring (1, Clip.min (a_text.count)).to_string_32
		end

	Clip: INTEGER = 200

feature {NONE} -- Talking to the model

	settings: OCR_SETTINGS

	http: OCR_HTTP

	last_reply: STRING_32
			-- What the model said to the last `ask'.
		attribute
			create Result.make_empty
		end

	ask (a_prompt: READABLE_STRING_32; a_ctx: INTEGER): BOOLEAN
			-- Run `a_prompt'; `last_reply' then holds the model's words.
		require
			prompt_given: not a_prompt.is_empty
			model_found: not resolved_model.is_empty
		local
			l_quick: SIMPLE_JSON_QUICK
			l_retried: BOOLEAN
		do
			last_reply.wipe_out
			if not l_retried then
				if not http.post_json (settings.endpoint, generate_body (a_prompt, a_ctx), Timeout_seconds) then
					last_error := http.last_error.twin
				elseif http.last_body.is_empty then
					last_error := {STRING_32} "The model returned an empty body."
				else
					create l_quick.make
					if attached l_quick.parse_object (http.last_body) as al_obj then
						if attached al_obj.string_item ({STRING_32} "response") as al_text then
							last_reply := (create {OCR_JSON_UTIL}).utf8_repaired (al_text)
							Result := True
						elseif attached al_obj.string_item ({STRING_32} "error") as al_err then
							last_error := {STRING_32} "Model error: "
							last_error.append (al_err)
						else
							last_error := {STRING_32} "The model's reply had no %"response%" field."
						end
					else
						last_error := {STRING_32} "The model's reply was not JSON."
					end
				end
			else
				last_error := {STRING_32} "The categorising request raised an exception."
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
		rescue
			l_retried := True
			retry
		end

	generate_body (a_prompt: READABLE_STRING_32; a_ctx: INTEGER): STRING_8
			-- The Ollama /api/generate payload for a text question.
		local
			u: OCR_JSON_UTIL
		do
			create u
			create Result.make (a_prompt.count * 2 + 256)
			Result.append ("{%"model%":")
			Result.append (u.quoted (resolved_model))
			Result.append (",%"prompt%":")
			Result.append (u.quoted (a_prompt))
			Result.append (",%"stream%":false")
				-- think:false is the difference between this feature working
				-- and this feature timing out. Measured 2026-09-19 on
				-- Qwen3 8B, asking for categories over 105 titles: with
				-- thinking left on the call had not returned after FIVE
				-- MINUTES and died on the socket timeout; with it off the
				-- same call answered in 6 seconds with the same kind of
				-- answer. A non-thinking model accepts the flag and ignores
				-- it (checked against the OCR model), so it is sent to
				-- whatever model is found rather than guessed about.
			Result.append (",%"think%":false")
			Result.append (",%"options%":{%"temperature%":0,%"num_ctx%":")
			Result.append (a_ctx.out)
			Result.append ("}}")
		end

	Timeout_seconds: INTEGER = 180
			-- Long enough for a cold 19 GB model to load and answer
			-- (22 s measured, load included), short enough that a model
			-- that will never answer does not hold the window for the
			-- five minutes it used to.

feature {NONE} -- Finding a model

	ensure_model: BOOLEAN
			-- Settle which model does the filing.
		do
			if not resolved_model.is_empty then
				Result := True
			elseif not settings.category_model.is_empty then
				resolved_model := settings.category_model.twin
				Result := True
			else
				Result := find_model
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
			named_on_success: Result implies not resolved_model.is_empty
		end

	find_model: BOOLEAN
			-- Ask Ollama what it holds and take the first model that is
			-- not an OCR or vision one.
		local
			l_names: LIST [STRING_8]
		do
			if not http.get (tags_url, Tags_timeout_seconds) then
				last_error := {STRING_32} "Could not ask Ollama what models it has: "
				last_error.append (http.last_error)
			else
				l_names := model_names (http.last_body)
				across
					l_names as ic
				until
					not resolved_model.is_empty
				loop
					if not is_vision_model (ic) then
						resolved_model := ic.twin
					end
				end
				if resolved_model.is_empty then
					last_error := {STRING_32} "Ollama has no text model for filing titles. Pull one, for example %"ollama pull qwen3:8b%", or name one in settings.json as %"category_model%"."
				else
					Result := True
				end
			end
		ensure
			error_on_failure: not Result implies not last_error.is_empty
		end

	is_vision_model (a_name: READABLE_STRING_8): BOOLEAN
			-- Is `a_name' an OCR or vision model, which cannot do this?
		local
			l_lower: STRING_8
		do
			create l_lower.make_from_string (a_name)
			l_lower.to_lower
			Result := l_lower.has_substring ("ocr") or l_lower.has_substring ("vision")
				or l_lower.has_substring ("llava") or l_lower.has_substring ("clip")
				or l_lower.has_substring ("embed")
		end

	model_names (a_body: STRING_8): LIST [STRING_8]
			-- Every model tag the /api/tags reply lists, in its order.
		local
			i, l_end: INTEGER
			l_list: ARRAYED_LIST [STRING_8]
		do
			create l_list.make (8)
			from
				i := a_body.substring_index (Name_marker, 1)
			until
				i = 0
			loop
				i := i + Name_marker.count
				l_end := a_body.index_of ('%"', i)
				if l_end > i then
					l_list.extend (a_body.substring (i, l_end - 1))
					i := a_body.substring_index (Name_marker, l_end)
				else
					i := 0
				end
			end
			Result := l_list
		end

	Name_marker: STRING_8 = "%"name%":%""

	tags_url: STRING_8
			-- The /api/tags of whatever host `settings.endpoint' names.
		local
			i: INTEGER
		do
			create Result.make_from_string (settings.endpoint)
			i := Result.substring_index ("/api/", 1)
			if i > 0 then
				Result := Result.substring (1, i - 1)
			end
			Result.append ("/api/tags")
		ensure
			asks_tags: Result.ends_with ("/api/tags")
		end

	Tags_timeout_seconds: INTEGER = 15

invariant
	parts_attached: settings /= Void and http /= Void and categories /= Void
		and last_error /= Void and last_message /= Void and resolved_model /= Void

end
