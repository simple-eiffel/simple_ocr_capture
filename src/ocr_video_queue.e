note
	description: "[
		The Video tab's queue: links go in, one at a time or a pasted
		batch; each is looked up on the tick and named after its
		title; a fetch pass then writes each ready row to its own file
		in one folder, again one row per tick, so the window stays
		alive between the network calls (each is about a second).

		Duplicates are folded by video id, not by the spelling of the
		link: youtu.be and watch?v= forms of one video are one row.
		File names within the queue are kept distinct with a numeric
		suffix, so a batch never writes two videos to one file.
	]"

class
	OCR_VIDEO_QUEUE

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
		do
			settings := a_settings
			create items.make (16)
			create folder.make_empty
			create last_message.make_empty
		end

feature -- Access

	items: ARRAYED_LIST [OCR_VIDEO_ITEM]
			-- The rows, in the order added.

	folder: STRING_32
			-- Where the current (or last) fetch pass writes.

	last_message: STRING_32
			-- What the last step had to say.

	last_added: INTEGER
			-- Rows the last `add_links' created.

	last_rejected: INTEGER
			-- Pieces of the last `add_links' that were not video links.

	last_duplicates: INTEGER
			-- Pieces of the last `add_links' already in the queue.

	item_of_id (a_id: READABLE_STRING_8): detachable OCR_VIDEO_ITEM
			-- The row for video `a_id', if any.
		do
			across
				items as ic
			until
				attached Result
			loop
				if ic.video_id.same_string (a_id) then
					Result := ic
				end
			end
		end

feature -- Measurement

	count: INTEGER
		do
			Result := items.count
		end

	pending_count: INTEGER
		do
			across items as ic loop
				if ic.is_pending then
					Result := Result + 1
				end
			end
		end

	ready_count: INTEGER
		do
			across items as ic loop
				if ic.is_ready then
					Result := Result + 1
				end
			end
		end

	queued_count: INTEGER
			-- Rows still waiting in the fetch pass.
		do
			across items as ic loop
				if ic.is_queued and ic.is_ready then
					Result := Result + 1
				end
			end
		end

	saved_count: INTEGER
		do
			across items as ic loop
				if ic.is_saved then
					Result := Result + 1
				end
			end
		end

	refused_count: INTEGER
		do
			across items as ic loop
				if ic.is_refused then
					Result := Result + 1
				end
			end
		end

feature -- Status report

	has_pending_lookup: BOOLEAN
		do
			Result := pending_count > 0
		end

	is_fetching: BOOLEAN
			-- Is a fetch pass under way?
		do
			Result := queued_count > 0
		end

	is_busy: BOOLEAN
		do
			Result := has_pending_lookup or is_fetching
		end

	has_file_name (a_name: READABLE_STRING_32; a_except: detachable OCR_VIDEO_ITEM): BOOLEAN
			-- Does a row other than `a_except' already use `a_name'?
		do
			across
				items as ic
			until
				Result
			loop
				Result := ic /= a_except and then ic.file_name.is_case_insensitive_equal (a_name)
			end
		end

feature -- Element change

	add_links (a_text: READABLE_STRING_GENERAL): INTEGER
			-- Add every video link in `a_text' (one per line, or
			-- separated by spaces); the count added is returned and
			-- kept in `last_added', with `last_rejected' and
			-- `last_duplicates' saying what was left out.
		local
			l_pieces: LIST [STRING_32]
			l_piece: STRING_32
			l_ids: OCR_VIDEO_ID
			l_id: STRING_8
			l_item: OCR_VIDEO_ITEM
		do
			last_added := 0
			last_rejected := 0
			last_duplicates := 0
			create l_ids
			l_pieces := pieces_of (a_text)
			across
				l_pieces as ic
			loop
				l_piece := ic.twin
				l_piece.left_adjust
				l_piece.right_adjust
				if not l_piece.is_empty then
					l_id := l_ids.video_id_of (l_piece)
					if l_id.is_empty then
						last_rejected := last_rejected + 1
					elseif attached item_of_id (l_id) then
						last_duplicates := last_duplicates + 1
					else
						create l_item.make (l_piece, settings)
						items.extend (l_item)
						last_added := last_added + 1
					end
				end
			end
			Result := last_added
		ensure
			grew: items.count = old items.count + Result
			counted: Result = last_added
		end

	remove (a_index: INTEGER)
		require
			in_range: a_index >= 1 and a_index <= items.count
		do
			items.go_i_th (a_index)
			items.remove
		ensure
			shrank: items.count = old items.count - 1
		end

	clear_finished
			-- Drop every saved, refused and failed row.
		do
			from
				items.start
			until
				items.after
			loop
				if items.item.is_finished then
					items.remove
				else
					items.forth
				end
			end
		ensure
			none_finished: across items as ic all not ic.is_finished end
		end

	rename_item (a_index: INTEGER; a_name: READABLE_STRING_GENERAL)
			-- Give row `a_index' the file name `a_name', made distinct
			-- within the queue.
		require
			in_range: a_index >= 1 and a_index <= items.count
			named: not a_name.is_empty
		do
			items.i_th (a_index).set_file_name (a_name)
			items.i_th (a_index).set_file_name (distinct_name (items.i_th (a_index).file_name, items.i_th (a_index)))
		ensure
			distinct: not has_file_name (items.i_th (a_index).file_name, items.i_th (a_index))
		end

feature -- Basic operations

	look_up_next
			-- Look up the first pending row; name it distinctly.
		require
			something_pending: has_pending_lookup
		local
			l_item: detachable OCR_VIDEO_ITEM
		do
			across
				items as ic
			until
				attached l_item
			loop
				if ic.is_pending then
					l_item := ic
				end
			end
			if attached l_item as al_item then
				al_item.look_up
				if not al_item.file_name.is_empty then
					al_item.set_file_name (distinct_name (al_item.file_name, al_item))
				end
				last_message := al_item.title + {STRING_32} " - " + al_item.status_caption
			end
		ensure
			one_fewer_pending: pending_count = old pending_count - 1
		end

	start_fetch_all (a_folder: READABLE_STRING_GENERAL)
			-- Queue every ready row for a fetch pass into `a_folder'.
		require
			folder_given: not a_folder.is_empty
		do
			create folder.make_from_string_general (a_folder)
			across items as ic loop
				ic.set_queued (ic.is_ready)
			end
		ensure
			all_ready_queued: queued_count = ready_count
		end

	start_fetch_one (a_index: INTEGER; a_folder: READABLE_STRING_GENERAL)
			-- Queue row `a_index' alone.
		require
			in_range: a_index >= 1 and a_index <= items.count
			ready: items.i_th (a_index).is_ready
			folder_given: not a_folder.is_empty
		do
			create folder.make_from_string_general (a_folder)
			across items as ic loop
				ic.set_queued (False)
			end
			items.i_th (a_index).set_queued (True)
		ensure
			one_queued: queued_count = 1
		end

	fetch_next
			-- Write the first queued row's transcript.
		require
			fetching: is_fetching
		local
			l_item: detachable OCR_VIDEO_ITEM
		do
			across
				items as ic
			until
				attached l_item
			loop
				if ic.is_queued and ic.is_ready then
					l_item := ic
				end
			end
			if attached l_item as al_item then
				al_item.fetch_into (folder)
				last_message := al_item.status_caption
			end
		ensure
			one_fewer_queued: queued_count = old queued_count - 1
		end

	distinct_name (a_name: READABLE_STRING_32; a_owner: OCR_VIDEO_ITEM): STRING_32
			-- `a_name', or `a_name' with " (2)", " (3)"... before its
			-- extension until no other row uses it.
		require
			named: not a_name.is_empty
		local
			i, l_dot: INTEGER
			l_stem, l_ext: STRING_32
		do
			create Result.make_from_string (a_name)
			if has_file_name (Result, a_owner) then
				l_dot := a_name.last_index_of ('.', a_name.count)
				if l_dot > 1 then
					l_stem := a_name.substring (1, l_dot - 1)
					l_ext := a_name.substring (l_dot, a_name.count)
				else
					l_stem := a_name.twin
					create l_ext.make_empty
				end
				from
					i := 2
				until
					not has_file_name (Result, a_owner)
				loop
					create Result.make (a_name.count + 5)
					Result.append (l_stem)
					Result.append_string_general (" (")
					Result.append_string_general (i.out)
					Result.append_string_general (")")
					Result.append (l_ext)
					i := i + 1
				end
			end
		ensure
			distinct: not has_file_name (Result, a_owner)
		end

feature {NONE} -- Implementation

	settings: OCR_SETTINGS

	pieces_of (a_text: READABLE_STRING_GENERAL): LIST [STRING_32]
			-- `a_text' cut at newlines, tabs, spaces and commas.
		local
			l_current: STRING_32
			i: INTEGER
			c: CHARACTER_32
			l_result: ARRAYED_LIST [STRING_32]
		do
			create l_result.make (4)
			create l_current.make (80)
			from
				i := 1
			until
				i > a_text.count
			loop
				c := a_text.item (i)
				if c = '%N' or c = '%R' or c = '%T' or c = ' ' or c = ',' or c = ';' then
					if not l_current.is_empty then
						l_result.extend (l_current.twin)
						l_current.wipe_out
					end
				else
					l_current.append_character (c)
				end
				i := i + 1
			end
			if not l_current.is_empty then
				l_result.extend (l_current)
			end
			Result := l_result
		end

invariant
	items_attached: items /= Void
	folder_attached: folder /= Void

end
