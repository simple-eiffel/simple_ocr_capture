note
	description: "[
		The settings window on the pure route: SW_WINDOW hosting the
		whole surface as tabs (Capture, Auto-advance, Video, Output,
		Engine, Findings, Maintenance) over one status line. The Video
		tab is a queue: links in, lookups and fetches one per tick
		through `poll_video', one Markdown file per video out. Same public
		contract as the Vision2 OCR_MAIN_WINDOW it succeeds - the
		composition root's agent wiring lands unchanged.

		Dialogs are the toolkit's own drawn modals, so every confirm
		flow is a CONTINUATION: ask, and the OK button carries the
		rest of the work as an agent. Region picks ride
		OCR_SW_SELECTOR (route overlay events here); outlines ride
		OCR_SW_OUTLINES; the preview is an SW_IMAGE over the grab's
		thumbnail surface.

		Every unattended capture - auto-advance, a video's captions -
		passes through `confirm_output_then': the output folder and
		file name are put in front of the user, on a sheet, before a
		single byte is written. The verb button carries the run on as
		a continuation.
	]"

class
	OCR_SW_MAIN_WINDOW

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS; a_cycle: OCR_CYCLE; a_strip: OCR_SW_STRIP; a_queue: OCR_VIDEO_QUEUE)
		local
			root: SW_COLUMN
			bar: SW_MENU_BAR
		do
			settings := a_settings
			cycle := a_cycle
			status_strip := a_strip
			queue := a_queue
			create theme.make_dark
			create window.make ("Simple OCR Capture " + {OCR_VERSION}.Version, 120, 60, 980, 900, theme)
			create findings_rows.make (16)
			create selector.make

			create root.make
			root := root.with_padding (12.0).with_gap (10.0)
			create bar.make
			bar.add_menu ("Help", agent help_menu)
			root.put (bar)
			build_status (root)
			build_tabs (root)
			window.set_root (root)
			load_from_settings
		end

feature -- Access

	window: SW_WINDOW
			-- The window itself; the composition root runs it.

	selector: OCR_SW_SELECTOR
			-- The region picker; overlay events route here while
			-- `selector.is_active'.

feature -- Basic operations

	report (a_message: READABLE_STRING_GENERAL)
			-- Show `a_message' on the status line.
		do
			status_label.set_text (a_message)
			window.request_render
		end

	add_finding (a_severity, a_pages, a_problem, a_remedy: STRING_32)
			-- One finding, newest at the top: during a run the
			-- interesting row is the one that just appeared.
		local
			l_when: DATE_TIME
			stamp, problem: STRING_32
		do
			create l_when.make_now
			create stamp.make (10)
			stamp.append_string_general (two (l_when.hour))
			stamp.append_character (':')
			stamp.append_string_general (two (l_when.minute))
			stamp.append_character (':')
			stamp.append_string_general (two (l_when.second))
			create problem.make (a_problem.count + a_severity.count + 3)
			problem.append_character ('[')
			problem.append (a_severity)
			problem.append_character (']')
			problem.append_character (' ')
			problem.append (a_problem)
			findings_rows.put_front ([stamp, a_pages.twin, problem, a_remedy.twin])
			findings_grid.set_rows (findings_rows)
			window.request_render
		end

	show_preview (a_surface: detachable CAIRO_SURFACE)
			-- The last capture's thumbnail in the preview panel.
		do
			if attached a_surface as s then
				preview.set_surface (s)
			end
			window.request_render
		end

feature -- Outlines (the shutter's contract)

	outlines: OCR_SW_OUTLINES
		once
			create Result.make (settings)
		end

	suspend_outlines
			-- Momentary duck around the shutter; boxes stay ticked.
		do
			outlines.suspend
		end

	resume_outlines
		do
			outlines.resume
		end

	animate_outlines
			-- The Vision2 outlines marched their dashes; frame
			-- regions are solid and this is deliberately nothing.
		do
		end

feature -- Output folder readiness

	is_output_folder_ready: BOOLEAN
			-- Quiet form for the hotkey tick: exists now, or not.
			-- The asking form is `ensure_output_folder_then'.
		do
			store_to_settings
			if settings.output_folder.is_empty then
				report ("No output folder set - choose one before capturing.")
			else
				Result := settings.output_folder_exists
				if not Result then
					report ("The output folder does not exist - use Test Capture or Browse to create/choose it.")
				end
			end
		end

	ensure_output_folder_then (a_then: PROCEDURE)
			-- Run `a_then' once the output folder exists - asking
			-- before creating: a mistyped path must never silently
			-- become a directory a whole book scans into.
		local
			d: SW_DIALOG
		do
			store_to_settings
			if settings.output_folder.is_empty then
				report ("No output folder set - choose one before capturing.")
			elseif settings.output_folder_exists then
				a_then.call
			else
				create d.make ({SW_DIALOG}.Kind_warning, "Output folder",
					{STRING_32} "This output folder does not exist:%N%N" + settings.output_folder
					+ {STRING_32} "%N%NCreate it?")
				d.add_button ("Cancel", False, agent report ("Not created. Change the output folder before capturing - nothing has been written."))
				d.add_button ("Create", True, agent create_folder_then (a_then))
				window.show_dialog (d)
			end
		end

feature -- Output confirmation (before any unattended run)

	confirm_output_then (a_verb: READABLE_STRING_GENERAL; a_suggested_name: detachable READABLE_STRING_GENERAL; a_then: PROCEDURE)
			-- Put the output folder and file name in front of the user
			-- on a sheet whose primary button reads `a_verb'; when it is
			-- pressed with both present, the folder exists (created if
			-- it did not) and both are stored, then `a_then' runs.
			-- `a_suggested_name', when given, replaces the stored file
			-- name in the box - a video is named after its title.
		require
			verb_given: not a_verb.is_empty
		do
			confirm_output_explaining ("Check both before the run starts: everything it reads is appended to this one file. Browse picks the folder; the name is yours to change.",
				a_verb, a_suggested_name, a_then)
		ensure
			asking: output_prompt /= Void
		end

	confirm_output_explaining (a_explanation, a_verb: READABLE_STRING_GENERAL; a_suggested_name: detachable READABLE_STRING_GENERAL; a_then: PROCEDURE)
			-- `confirm_output_then' with the sheet's own words.
		require
			verb_given: not a_verb.is_empty
		local
			l_prompt: OCR_SW_OUTPUT_PROMPT
			l_name: STRING_32
		do
			store_to_settings
			if attached a_suggested_name as al_name and then not al_name.is_empty then
				create l_name.make_from_string_general (al_name)
			else
				l_name := settings.text_file_name.twin
			end
			create l_prompt.make_prompt ("Where does the text go?", a_explanation,
				settings.output_folder, l_name, a_verb)
			l_prompt.set_on_browse (agent prompt_browse)
			l_prompt.set_on_cancel (agent prompt_cancelled)
			l_prompt.set_on_accept (agent prompt_accepted (?, ?, a_then))
			output_prompt := l_prompt
			window.show_sheet (l_prompt, 680.0)
		ensure
			asking: output_prompt /= Void
		end

feature {NONE} -- Output confirmation internals

	output_prompt: detachable OCR_SW_OUTPUT_PROMPT
			-- The sheet up right now, if any; kept so the Browse round
			-- trip can put it back after the folder picker.

	prompt_browse
			-- Swap the prompt for the folder picker; the pick (or its
			-- cancel) brings the prompt back.
		local
			fd: SW_FILE_DIALOG
			start_dir: STRING_32
		do
			if attached output_prompt as al_prompt then
				start_dir := al_prompt.folder
				if start_dir.is_empty or else not (create {DIRECTORY}.make (start_dir)).exists then
					create start_dir.make_from_string_general ("C:\")
				end
				create fd.make_open (start_dir)
				fd.set_on_accept (agent prompt_folder_picked)
				fd.set_on_cancel (agent prompt_reshow)
				window.show_sheet (fd, 640.0)
			end
		end

	prompt_folder_picked (a_path: STRING_32)
			-- The picker names files; the folder of the pick - or the
			-- path itself when it is a directory - goes in the box.
		local
			dir: STRING_32
			i: INTEGER
		do
			dir := a_path.twin
			if not (create {DIRECTORY}.make (dir)).exists then
				i := dir.last_index_of ('\', dir.count)
				if i > 1 then
					dir.keep_head (i - 1)
				end
			end
			if attached output_prompt as al_prompt then
				al_prompt.set_folder (dir)
			end
			prompt_reshow
		end

	prompt_reshow
		do
			window.close_sheet
			if attached output_prompt as al_prompt then
				window.show_sheet (al_prompt, 680.0)
			end
			window.request_render
		end

	prompt_cancelled
		do
			window.close_sheet
			output_prompt := Void
			report ("Not started - nothing has been written.")
			window.request_render
		end

	prompt_accepted (a_folder, a_name: STRING_32; a_then: PROCEDURE)
			-- Both present: make the folder real, store both values
			-- where every writer reads them, then run.
		do
			window.close_sheet
			output_prompt := Void
			if created_folder (a_folder) then
				is_loading := True
				field_folder.set_text (a_folder)
				field_text_name.set_text (a_name)
				is_loading := False
				store_to_settings
				settings.store
				window.request_render
				a_then.call
			else
				report ({STRING_32} "Could not create " + a_folder + {STRING_32} " - check the path for a typo or a drive that is not there. Nothing has been written.")
			end
		end

feature -- Auto-advance state

	show_auto_state (a_running, a_paused: BOOLEAN)
		do
			button_auto_start.set_enabled (not a_running or a_paused)
			button_auto_pause.set_enabled (a_running and not a_paused)
			button_auto_stop.set_enabled (a_running or a_paused)
			if a_running and not a_paused then
				auto_hint.set_text ("Running - the strip's square also stops it.")
			elseif a_paused then
				auto_hint.set_text ("Paused - Start resumes.")
			else
				auto_hint.set_text ("Set both regions above, then Start.")
			end
			window.request_render
		end

feature -- Element change (the composition root's wiring points)

	set_hotkey_changed_action (a_agent: PROCEDURE)
		do
			on_hotkey_changed := a_agent
		end

	set_quit_action (a_agent: PROCEDURE)
		do
			on_quit := a_agent
		end

	set_check_setup_action (a_agent: PROCEDURE)
		do
			on_check_setup_agent := a_agent
		end

	set_auto_start_action (a_agent: PROCEDURE)
		do
			on_auto_start_agent := a_agent
		end

	set_auto_pause_action (a_agent: PROCEDURE)
		do
			on_auto_pause_agent := a_agent
		end

	set_auto_stop_action (a_agent: PROCEDURE)
		do
			on_auto_stop_agent := a_agent
		end

feature -- Settings round trip

	load_from_settings
			-- Fill every control from `settings'.
		do
			is_loading := True
			field_x.set_value (settings.region_x)
			field_y.set_value (settings.region_y)
			field_w.set_value (settings.region_width)
			field_h.set_value (settings.region_height)
			field_folder.set_text (settings.output_folder)
			field_move_drive.set_text (settings.move_to_drive)
			field_text_name.set_text (settings.text_file_name)
			field_endpoint.set_text (settings.endpoint)
			field_model.set_text (settings.model)
			field_timeout.set_value (settings.ocr_timeout_seconds)
			field_num_ctx.set_value (settings.num_ctx)
			field_advance_x.set_value (settings.advance_x)
			field_advance_y.set_value (settings.advance_y)
			field_advance_w.set_value (settings.advance_width)
			field_advance_h.set_value (settings.advance_height)
			field_label_x.set_value (settings.page_label_x)
			field_label_y.set_value (settings.page_label_y)
			field_label_w.set_value (settings.page_label_width)
			field_label_h.set_value (settings.page_label_height)
			field_advance_delay.set_value (settings.advance_delay_ms)
			check_save_text.set_checked (settings.save_text)
			check_save_image.set_checked (settings.save_image)
			check_separators.set_checked (settings.add_separators)
			check_markdown.set_checked (settings.markdown_output)
			check_figures.set_checked (settings.extract_figures)
			check_show_strip.set_checked (settings.show_strip)
			check_show_thumb.set_checked (settings.show_thumbnail)
			check_browser_session.set_checked (settings.use_browser_session)
			check_ctrl.set_checked (settings.hotkey_modifiers.bit_and ({OCR_HOTKEY}.Mod_control) /= 0)
			check_alt.set_checked (settings.hotkey_modifiers.bit_and ({OCR_HOTKEY}.Mod_alt) /= 0)
			check_shift.set_checked (settings.hotkey_modifiers.bit_and ({OCR_HOTKEY}.Mod_shift) /= 0)
			select_text (combo_format, settings.image_format.to_string_32)
			select_text (combo_key, key_name_for (settings.hotkey_key))
			show_auto_state (False, False)
			is_loading := False
		end

	store_to_settings
			-- Push every control back into `settings'. Guarded
			-- values (region extents, file name) refuse emptiness.
		local
			l_mods: NATURAL_32
		do
			if not is_loading then
				if field_w.value > 0 and field_h.value > 0 then
					settings.set_region (field_x.value, field_y.value, field_w.value, field_h.value)
				end
				if field_advance_w.value > 0 and field_advance_h.value > 0 then
					settings.set_advance_region (field_advance_x.value, field_advance_y.value,
						field_advance_w.value, field_advance_h.value)
				end
				if field_label_w.value > 0 and field_label_h.value > 0 then
					settings.set_page_label_region (field_label_x.value, field_label_y.value,
						field_label_w.value, field_label_h.value)
				end
				settings.set_advance_delay_ms (field_advance_delay.value)
				settings.set_output_folder (field_folder.text)
					-- stored even when empty: an empty box that left the
					-- old drive stored would move a book to a destination
					-- the window is no longer showing
				settings.set_move_to_drive (field_move_drive.text)
				if not field_text_name.text.is_empty then
					settings.set_text_file_name (field_text_name.text)
				end
				settings.set_save_text (check_save_text.is_checked)
				settings.set_save_image (check_save_image.is_checked)
				settings.set_add_separators (check_separators.is_checked)
				settings.set_markdown_output (check_markdown.is_checked)
				settings.set_extract_figures (check_figures.is_checked)
				settings.set_show_strip (check_show_strip.is_checked)
				settings.set_show_thumbnail (check_show_thumb.is_checked)
				settings.set_use_browser_session (check_browser_session.is_checked)
				if not field_endpoint.text.is_empty then
					settings.set_endpoint (narrowed (field_endpoint.text))
				end
				if not field_model.text.is_empty then
					settings.set_model (narrowed (field_model.text))
				end
				settings.set_ocr_timeout_seconds (field_timeout.value)
				settings.set_num_ctx (field_num_ctx.value)
				settings.set_image_format (narrowed (combo_format.selected_text))
				l_mods := 0
				if check_ctrl.is_checked then
					l_mods := l_mods | {OCR_HOTKEY}.Mod_control
				end
				if check_alt.is_checked then
					l_mods := l_mods | {OCR_HOTKEY}.Mod_alt
				end
				if check_shift.is_checked then
					l_mods := l_mods | {OCR_HOTKEY}.Mod_shift
				end
				settings.set_hotkey (l_mods, key_code_for (combo_key.selected_text))
			end
		end

feature {NONE} -- Building

	theme: SW_THEME

	build_status (a_root: SW_COLUMN)
		local
			card: SW_CARD
		do
			create card.make_striped (theme.accent)
			create status_label.make_ui ("Ready.")
			card.put (status_label)
			a_root.put (card)
		end

	build_tabs (a_root: SW_COLUMN)
		local
			tabs: SW_TABS
		do
			create tabs.make
			tabs.add_page ("Capture", capture_page)
			tabs.add_page ("Auto-advance", auto_page)
			tabs.add_page ("Video", video_page)
			tabs.add_page ("Output", output_page)
			tabs.add_page ("Engine", engine_page)
			tabs.add_page ("Findings", findings_page)
			tabs.add_page ("Maintenance", maintenance_page)
			a_root.put (tabs)
		end

	capture_page: SW_COLUMN
		local
			row: SW_ROW
		do
			create Result.make
			Result := Result.with_gap (10.0)
			Result.put ((create {SW_LABEL}.make_ui ("The rectangle each hotkey press transcribes.")).as_muted)
			create field_x.make (0, -20000, 20000, agent on_number_edited)
			create field_y.make (0, -20000, 20000, agent on_number_edited)
			create field_w.make (800, 0, 20000, agent on_number_edited)
			create field_h.make (600, 0, 20000, agent on_number_edited)
			Result.put (coordinate_row ("X", field_x, "Y", field_y))
			Result.put (coordinate_row ("W", field_w, "H", field_h))
			create row.make
			row := row.add (create {SW_BUTTON}.make ("Set Region by Dragging...", agent on_set_region))
				.add (create {SW_BUTTON}.make ("Test Capture", agent on_test_capture))
				.add (create {SW_BUTTON}.make ("Capture Now", agent on_capture_now))
			Result.put (row)
			create check_outline_capture.make ("Show this region on screen", False, Void)
			check_outline_capture.set_on_change (agent on_outline_toggle)
			Result.put (check_outline_capture)
			create preview.make_from_surface (create {CAIRO_SURFACE}.make (4, 3))
			preview.set_grow (1.0)
			Result.put (preview)
		end

	auto_page: SW_COLUMN
		local
			row: SW_ROW
		do
			create Result.make
			Result := Result.with_gap (10.0)
			Result.put ((create {SW_LABEL}.make_ui ("Given the next-page button and the page indicator, it reads the book itself.")).as_muted)
			create field_advance_x.make (0, -20000, 20000, agent on_number_edited)
			create field_advance_y.make (0, -20000, 20000, agent on_number_edited)
			create field_advance_w.make (0, 0, 20000, agent on_number_edited)
			create field_advance_h.make (0, 0, 20000, agent on_number_edited)
			Result.put ((create {SW_LABEL}.make_ui ("Advance button")).as_muted)
			Result.put (coordinate_row ("X", field_advance_x, "Y", field_advance_y))
			Result.put (coordinate_row ("W", field_advance_w, "H", field_advance_h))
			Result.put (create {SW_BUTTON}.make ("Set Advance Button by Dragging...", agent on_set_advance_region))
			create field_label_x.make (0, -20000, 20000, agent on_number_edited)
			create field_label_y.make (0, -20000, 20000, agent on_number_edited)
			create field_label_w.make (0, 0, 20000, agent on_number_edited)
			create field_label_h.make (0, 0, 20000, agent on_number_edited)
			Result.put ((create {SW_LABEL}.make_ui ("Page indicator")).as_muted)
			Result.put (coordinate_row ("X", field_label_x, "Y", field_label_y))
			Result.put (coordinate_row ("W", field_label_w, "H", field_label_h))
			Result.put (create {SW_BUTTON}.make ("Set Page Indicator by Dragging...", agent on_set_label_region))
			create field_advance_delay.make (1200, 500, 60000, agent on_number_edited)
			Result.put (labelled ("Min. settle (ms)", field_advance_delay))
			create check_outline_advance.make ("Show advance region", False, Void)
			check_outline_advance.set_on_change (agent on_outline_toggle)
			create check_outline_label.make ("Show indicator region", False, Void)
			check_outline_label.set_on_change (agent on_outline_toggle)
			create row.make
			row := row.add (check_outline_advance).add (check_outline_label)
			Result.put (row)
			create button_auto_start.make ("Start", agent on_auto_start)
			create button_auto_pause.make ("Pause", agent on_auto_pause)
			create button_auto_stop.make ("Stop", agent on_auto_stop)
			button_auto_start.set_kind ({SW_BUTTON}.Kind_primary)
			create row.make
			row := row.add (button_auto_start).add (button_auto_pause).add (button_auto_stop)
			Result.put (row)
			create auto_hint.make_ui ("Set both regions above, then Start.")
			auto_hint := auto_hint.as_muted
			Result.put (auto_hint)
		end

	video_page: SW_COLUMN
		local
			row: SW_ROW
		do
			create Result.make
			Result := Result.with_gap (10.0)
			Result.put ((create {SW_LABEL}.make_ui ("Paste YouTube links, one or many. Each is looked up as it lands; Fetch writes every ready one to its own Markdown file. Nothing but the two requests the player itself makes leaves this machine.")).as_muted.with_wrap)
			create field_video_url.make_single_line ("")
			field_video_url.set_spellcheck (False)
			field_video_url.set_grow (1.0)
			create row.make
			row := row.add (labelled ("Links", field_video_url))
			row.children.first.set_grow (1.0)
			row := row.add (create {SW_BUTTON}.make ("Add", agent on_video_add))
			Result.put (row)
			create video_grid.make (200.0)
			video_grid.add_column (create {SW_GRID_COLUMN [OCR_VIDEO_ITEM]}.make ("Title", 250.0, agent (v: OCR_VIDEO_ITEM): STRING_32 do Result := v.title end))
			video_grid.add_column (create {SW_GRID_COLUMN [OCR_VIDEO_ITEM]}.make ("Channel", 140.0, agent (v: OCR_VIDEO_ITEM): STRING_32 do Result := v.channel end))
			video_grid.add_column (create {SW_GRID_COLUMN [OCR_VIDEO_ITEM]}.make ("Length", 60.0, agent (v: OCR_VIDEO_ITEM): STRING_32 do Result := v.length_caption end))
			video_grid.add_column (create {SW_GRID_COLUMN [OCR_VIDEO_ITEM]}.make ("Captions", 150.0, agent (v: OCR_VIDEO_ITEM): STRING_32 do Result := v.captions_caption end))
			video_grid.add_column (create {SW_GRID_COLUMN [OCR_VIDEO_ITEM]}.make ("File", 200.0, agent (v: OCR_VIDEO_ITEM): STRING_32 do Result := v.file_name end))
			video_grid.add_column (create {SW_GRID_COLUMN [OCR_VIDEO_ITEM]}.make ("Status", 260.0, agent (v: OCR_VIDEO_ITEM): STRING_32 do Result := v.status_caption end))
			video_grid.set_on_select (agent on_video_selected)
			video_grid.set_rows (queue.items)
			Result.put (video_grid)
			create field_video_name.make_single_line ("")
			field_video_name.set_spellcheck (False)
			field_video_name.set_grow (1.0)
			create row.make
			row := row.add (labelled ("File name", field_video_name))
			row.children.first.set_grow (1.0)
			row := row.add (create {SW_BUTTON}.make ("Rename", agent on_video_rename))
			Result.put (row)
			create button_video_fetch.make ("Fetch All...", agent on_video_fetch_all)
			button_video_fetch.set_kind ({SW_BUTTON}.Kind_primary)
			create row.make
			row := row.add (button_video_fetch)
				.add (create {SW_BUTTON}.make ("Fetch Selected...", agent on_video_fetch_selected))
				.add (create {SW_BUTTON}.make ("Remove", agent on_video_remove))
				.add (create {SW_BUTTON}.make ("Clear Finished", agent on_video_clear_finished))
			Result.put (row)
			create row.make
			row := row.add (create {SW_BUTTON}.make ("Fetch via My Browser Session...", agent on_video_session))
			Result.put (row)
			create video_hint.make_ui ("Fetch All asks once where the files go; each video is written to its own .md file, named from its title (edit the name above). Fetch Selected asks for that one video alone. Fetch via My Browser Session opens a signed-in YouTube window and works for members-only videos.")
			video_hint := video_hint.as_muted.with_wrap
			Result.put (video_hint)
			create video_preview.make (220.0)
			video_preview.set_grow (1.0)
			Result.put (video_preview)
		end

	output_page: SW_COLUMN
		local
			row, folder_row: SW_ROW
		do
			create Result.make
			Result := Result.with_gap (10.0)
			create field_folder.make_single_line ("")
			field_folder.set_on_change (agent on_field_changed)
			field_folder.set_grow (1.0)
			create folder_row.make
			folder_row := folder_row.add (labelled ("Folder", field_folder))
			folder_row.children.first.set_grow (1.0)
			folder_row := folder_row.add (create {SW_BUTTON}.make ("Browse...", agent on_browse))
			Result.put (folder_row)
			create field_text_name.make_single_line ("")
			field_text_name.set_on_change (agent on_field_changed)
			Result.put (labelled ("Text file", field_text_name))
			create check_save_text.make ("Append OCR text to the file above", True, Void)
			check_save_text.set_on_change (agent on_field_changed)
			create check_save_image.make ("Also keep the captured image", True, Void)
			check_save_image.set_on_change (agent on_field_changed)
			create check_separators.make ("Write a header line before each capture", False, Void)
			check_separators.set_on_change (agent on_field_changed)
			Result.put (check_save_text)
			Result.put (check_save_image)
			Result.put (check_separators)
			create check_markdown.make ("Write the transcript as Markdown (.md)", False, Void)
			check_markdown.set_on_change (agent on_markdown_toggle)
			create check_figures.make ("Extract figures with AI into the Markdown transcript", False, Void)
			check_figures.set_on_change (agent on_figures_toggle)
			Result.put (check_markdown)
			Result.put (check_figures)
			Result.put ((create {SW_LABEL}.make_ui ("Figures: prose pages cost nothing extra; each detected figure adds a few seconds. Off unless this book has them.")).as_muted)
			create combo_format.make
			combo_format.add_option ("png")
			combo_format.add_option ("bmp")
			combo_format.set_on_change (agent on_field_changed)
			Result.put (labelled ("Image format", combo_format))
			create check_show_strip.make ("Show progress strip", True, Void)
			check_show_strip.set_on_change (agent on_strip_toggle)
			create check_show_thumb.make ("Show last capture on the strip", True, Void)
			check_show_thumb.set_on_change (agent on_thumb_toggle)
			Result.put (check_show_strip)
			Result.put (check_show_thumb)
			Result.put (create {SW_BUTTON}.make ("Save Settings", agent on_save_settings))
		end

	engine_page: SW_COLUMN
		do
			create Result.make
			Result := Result.with_gap (10.0)
			Result.put ((create {SW_LABEL}.make_ui ("The local model that does the reading. Nothing leaves this machine.")).as_muted)
			create field_endpoint.make_single_line ("")
			field_endpoint.set_on_change (agent on_field_changed)
			Result.put (labelled ("Endpoint", field_endpoint))
			create field_model.make_single_line ("")
			field_model.set_on_change (agent on_field_changed)
			Result.put (labelled ("Model", field_model))
			create field_timeout.make (240, 5, 3600, agent on_number_edited)
			Result.put (labelled ("Timeout (s)", field_timeout))
			create field_num_ctx.make (8192, 512, 131072, agent on_number_edited)
			Result.put (labelled ("Context tokens", field_num_ctx))
			Result.put (create {SW_BUTTON}.make ("Check Setup / Install Model", agent on_check_setup))
			Result.put (create {SW_SEPARATOR}.make_labeled ("YouTube session (members-only videos)"))
			create check_browser_session.make ("Use my browser login for members-only videos", False, Void)
			check_browser_session.set_on_change (agent on_field_changed)
			Result.put (check_browser_session)
			Result.put ((create {SW_LABEL}.make_ui ("When on, a video a channel membership gates opens a signed-in YouTube window (WebView2) and its captions are fetched from your own session. The window appears only when needed; sign in once and it is remembered. Nothing but YouTube's own requests leaves this machine.")).as_muted.with_wrap)
				-- trigger lives with the engine page: both are
				-- set-once machinery
			Result.put ((create {SW_LABEL}.make_ui ("Trigger")).as_muted)
			create check_ctrl.make ("Ctrl", True, Void)
			check_ctrl.set_on_change (agent on_hotkey_edited)
			create check_alt.make ("Alt", True, Void)
			check_alt.set_on_change (agent on_hotkey_edited)
			create check_shift.make ("Shift", False, Void)
			check_shift.set_on_change (agent on_hotkey_edited)
			create combo_key.make
			fill_key_combo
			combo_key.set_on_change (agent on_hotkey_edited)
			Result.put ((create {SW_ROW}.make).add (check_ctrl).add (check_alt).add (check_shift).add (combo_key))
		end

	findings_page: SW_COLUMN
		local
			row: SW_ROW
		do
			create Result.make
			Result := Result.with_gap (10.0)
			Result.put ((create {SW_LABEL}.make_ui ("Problems the run noticed itself, newest first, each with its remedy.")).as_muted)
			create findings_grid.make (420.0)
			findings_grid.add_column (create {SW_GRID_COLUMN [TUPLE [stamp, pages, problem, remedy: STRING_32]]}.make ("When", 70.0, agent (r: TUPLE [stamp, pages, problem, remedy: STRING_32]): STRING_32 do Result := r.stamp end))
			findings_grid.add_column (create {SW_GRID_COLUMN [TUPLE [stamp, pages, problem, remedy: STRING_32]]}.make ("Pages", 90.0, agent (r: TUPLE [stamp, pages, problem, remedy: STRING_32]): STRING_32 do Result := r.pages end))
			findings_grid.add_column (create {SW_GRID_COLUMN [TUPLE [stamp, pages, problem, remedy: STRING_32]]}.make ("Problem", 380.0, agent (r: TUPLE [stamp, pages, problem, remedy: STRING_32]): STRING_32 do Result := r.problem end))
			findings_grid.add_column (create {SW_GRID_COLUMN [TUPLE [stamp, pages, problem, remedy: STRING_32]]}.make ("Remedy", 360.0, agent (r: TUPLE [stamp, pages, problem, remedy: STRING_32]): STRING_32 do Result := r.remedy end))
			findings_grid.set_grow (1.0)
			Result.put (findings_grid)
			create row.make
			row := row.add (create {SW_BUTTON}.make ("Run Audit", agent on_run_audit))
				.add (create {SW_BUTTON}.make ("Clear List", agent on_clear_findings))
			Result.put (row)
		end

	maintenance_page: SW_COLUMN
		local
			row: SW_ROW
		do
			create Result.make
			Result := Result.with_gap (10.0)
			Result.put ((create {SW_LABEL}.make_ui ("Between books: the images, the log, and the fields that change per book.")).as_muted)
			create field_move_drive.make_single_line ("")
			field_move_drive.set_on_change (agent on_field_changed)
			Result.put (labelled ("Move to drive", field_move_drive))
			create row.make
			row := row.add (create {SW_BUTTON}.make ("Delete Images...", agent on_delete_images))
				.add (create {SW_BUTTON}.make ("Move Images...", agent on_move_images))
			Result.put (row)
			Result.put ((create {SW_LABEL}.make_ui ("ocr_*.png and ocr_*.bmp only; nothing already at the destination is overwritten.")).as_muted)
			create row.make
			row := row.add (create {SW_BUTTON}.make ("Open Log", agent on_open_log))
				.add (create {SW_BUTTON}.make ("Clear Log", agent on_clear_log))
				.add (create {SW_BUTTON}.make ("Clear All...", agent on_clear_all))
			Result.put (row)
			Result.put ((create {SW_BUTTON}.make ("Quit", agent on_quit_pressed)).as_kind ({SW_BUTTON}.Kind_danger))
		end

feature {NONE} -- Actions

	on_field_changed
		do
			store_to_settings
		end

	on_number_edited (a_value: INTEGER)
			-- Any number box: the value is already clamped; store.
		do
			store_to_settings
		end

	on_hotkey_edited
		do
			store_to_settings
			if attached on_hotkey_changed as a then
				a.call
			end
		end

	on_strip_toggle
		do
			store_to_settings
			if settings.show_strip then
				status_strip.show
			else
				status_strip.hide
			end
		end

	on_thumb_toggle
		do
			store_to_settings
			status_strip.set_thumbnail_visible (settings.show_thumbnail)
		end

	help_menu: SW_MENU
			-- Help's dropdown, built fresh on every open as menu
			-- builders are.
		do
			create Result.make
			Result.add_item ("About Simple OCR Capture...", "", True, agent on_about)
		end

	on_about
			-- The running build as a composed panel: identity, the AI
			-- models in play, substrate, and the picker's escape
			-- hatch. A centered sheet - truly modal; its close X or
			-- Escape dismisses it.
		local
			col: SW_COLUMN
		do
			create col.make
			col := col.with_padding (6.0).with_gap (10.0)
			col.put (create {SW_LABEL}.make ("Simple OCR Capture", {SW_PAINTER}.Role_ui, 20.0, True))
			col.put ((create {SW_LABEL}.make_ui ("Version " + {OCR_VERSION}.Version + " - built " + {OCR_VERSION}.Built)).as_muted)
			col.put (create {SW_LABEL}.make_body ("Reads a book through your screen: capture a region, OCR it through a local model, append the text to one file. Nothing leaves the machine."))
			col.put (create {SW_SEPARATOR}.make_labeled ("AI models"))
			col.put (labelled ("OCR model", create {SW_LABEL}.make_mono (settings.model)))
			col.put (labelled ("Endpoint", create {SW_LABEL}.make_mono (settings.endpoint)))
			col.put (labelled ("Page labels", create {SW_LABEL}.make_mono ("the OCR model (indicator prompt)")))
			col.put (labelled ("Figure detect", create {SW_LABEL}.make_mono ("Windows OCR text mask + model confirm")))
			col.put (labelled ("Video captions", create {SW_LABEL}.make_mono ("YouTube caption track over WinHTTP - no model, no browser")))
			col.put (create {SW_SEPARATOR}.make_labeled ("Built on"))
			col.put (create {SW_LABEL}.make_body ("simple_widgets over simple_shell and cairo - pure Eiffel and Win32: no Vision2, no runtime, no redistributable."))
			col.put (create {SW_SEPARATOR}.make_labeled ("If the region picker is ever stuck"))
			col.put (create {SW_LABEL}.make_body ("Esc, right-click or Alt+F4 cancels a drag. Held for five seconds, Esc quits the application itself - the picker can never take the session with it."))
			col.put ((create {SW_LABEL}.make_ui ("github.com/simple-eiffel/simple_ocr_capture")).as_muted)
			window.show_sheet (col, 600.0)
		end

	on_markdown_toggle
			-- Markdown off takes figures with it: they have nowhere
			-- to embed without it.
		do
			if not is_loading then
				if not check_markdown.is_checked and then check_figures.is_checked then
					is_loading := True
					check_figures.set_checked (False)
					is_loading := False
				end
				store_to_settings
				report ({STRING_32} "Transcript file: " + settings.transcript_file_name)
			end
		end

	on_figures_toggle
			-- Ticking figures is a deliberate act and gets a
			-- deliberate confirm: the box unticks until the dialog's
			-- Yes re-ticks it (with Markdown alongside). Unticking
			-- needs no ceremony.
		local
			d: SW_DIALOG
		do
			if not is_loading then
				if check_figures.is_checked then
					is_loading := True
					check_figures.set_checked (False)
					is_loading := False
					create d.make ({SW_DIALOG}.Kind_warning, "Extract figures from this book?",
						{STRING_32} "Most books need no figure extraction - leave this OFF unless this book carries photographs, charts, maps or illustrations you want captured.%N%NWhat it costs: pages of plain prose add nothing (detection rides under the OCR you already wait for); each detected figure adds a few seconds for its confirmation.%N%NWhat you get: figures saved as PNG files in an images folder beside the transcript, embedded in the Markdown where they occurred.%N%NThe Markdown transcript is required and will be switched on with it.")
					d.add_button ("No, leave it off", False, Void)
					d.add_button ("Yes, extract figures", True, agent confirm_figures_on)
					window.show_dialog (d)
				else
					store_to_settings
				end
			end
		end

	confirm_figures_on
			-- The dialog's Yes: figures on, Markdown with it.
		do
			is_loading := True
			check_markdown.set_checked (True)
			check_figures.set_checked (True)
			is_loading := False
			store_to_settings
			report ({STRING_32} "Figure extraction ON - transcript: " + settings.transcript_file_name)
		end

	on_video_add
			-- Every link in the box becomes a row; lookups follow on
			-- the tick.
		local
			l_added: INTEGER
			l_report: STRING_32
		do
			l_added := queue.add_links (field_video_url.text)
			create l_report.make (80)
			l_report.append_string_general (l_added.out)
			l_report.append_string_general (" added")
			if queue.last_duplicates > 0 then
				l_report.append_string_general (", ")
				l_report.append_string_general (queue.last_duplicates.out)
				l_report.append_string_general (" already listed")
			end
			if queue.last_rejected > 0 then
				l_report.append_string_general (", ")
				l_report.append_string_general (queue.last_rejected.out)
				l_report.append_string_general (" not a video link")
			end
			if l_added > 0 then
				field_video_url.set_text ("")
				l_report.append_string_general (". Looking them up...")
			elseif queue.last_rejected = 0 and queue.last_duplicates = 0 then
				l_report := {STRING_32} "Paste one or more YouTube links first."
			end
			report (l_report)
			refresh_video_grid
		end

feature -- Video queue (the composition root's tick calls this)

	poll_video
			-- The tick's share of the queue: one lookup, or one fetch,
			-- never both, so the window breathes between network calls.
		do
			if queue.has_pending_lookup then
				queue.look_up_next
				report (queue.last_message)
				note_video_refusals
				refresh_video_grid
				if not queue.has_pending_lookup then
					report ({STRING_32} "Lookups done: " + queue.ready_count.out + {STRING_32} " ready, "
						+ queue.refused_count.out + {STRING_32} " refused. Fetch All writes the ready ones.")
				end
			elseif queue.is_fetching then
				queue.fetch_next
				report (queue.last_message)
				refresh_video_grid
				if not queue.is_fetching then
					report ({STRING_32} "Fetch done: " + queue.saved_count.out + {STRING_32} " transcript(s) in " + queue.folder)
					add_finding ({STRING_32} "info", {STRING_32} "video",
						{STRING_32} "Fetch pass finished: " + queue.saved_count.out + {STRING_32} " saved, " + queue.refused_count.out + {STRING_32} " refused",
						{STRING_32} "The files are in " + queue.folder)
					show_video_preview
					offer_session_fallback
				end
			elseif queue.is_session_active then
				queue.poll_session
				if not queue.is_session_active then
					report (queue.last_message)
					refresh_video_grid
					note_video_refusals
					show_video_preview
					add_finding ({STRING_32} "info", {STRING_32} "video", queue.last_message,
						{STRING_32} "Members-only transcripts are marked as such in their header")
				end
			end
		end

	offer_session_fallback
			-- After a normal fetch, if some rows were gated and the user
			-- has enabled the browser session, run it for those rows.
		do
			if settings.use_browser_session and then queue.session_available
				and then queue.members_refused_count > 0 and then not queue.is_session_active
			then
				report ({STRING_32} "Some videos are members-only; opening your browser session for "
					+ queue.members_refused_count.out + {STRING_32} " of them.")
				queue.start_session (settings.output_folder, True)
				refresh_video_grid
			end
		end

	on_video_session
			-- Explicit: fetch every not-yet-saved row through the signed-in
			-- browser window (works for public and members-only alike).
		do
			if queue.is_busy then
				report ("Still working - wait for the current pass to finish.")
			elseif not queue.session_available then
				report ("The sign-in helper (ocr_yt_session.exe) is not next to the application.")
			elseif queue.session_candidates (False).is_empty then
				report ("Nothing to fetch: every row is already saved or has no video id.")
			else
				confirm_output_then ("Fetch", first_ready_name, agent video_session_confirmed)
			end
		end

	video_session_confirmed
		do
			if not settings.text_file_name.is_empty then
					-- honour a name the prompt set, for the first candidate
				if attached first_session_candidate as al then
					al.set_file_name (settings.text_file_name)
					al.set_file_name (queue.distinct_name (al.file_name, al))
				end
			end
			queue.start_session (settings.output_folder, False)
			refresh_video_grid
			report (queue.last_message)
		end

	first_session_candidate: detachable OCR_VIDEO_ITEM
		do
			across queue.session_candidates (False) as ic until attached Result loop
				Result := ic
			end
		end

feature {NONE} -- Video queue internals

	note_video_refusals
			-- A findings row for each refusal not yet noted.
		do
			across
				queue.items as ic
			loop
				if ic.is_refused and then not ic.is_queued and then not noted_refusals.has (ic) then
					noted_refusals.extend (ic)
					add_finding ({STRING_32} "warn", {STRING_32} "video", ic.title + {STRING_32} ": " + ic.detail,
						{STRING_32} "Members-only needs the signed-in route (planned); a video with no captions has nothing to fetch")
				end
			end
		end

	noted_refusals: ARRAYED_LIST [OCR_VIDEO_ITEM]
		attribute
			create Result.make (4)
		end

	refresh_video_grid
		do
			video_grid.set_rows (queue.items)
			window.request_render
		end

	on_video_selected (a_index: INTEGER)
			-- The row's file name goes in the box; its text, if it has
			-- any, in the preview.
		do
			if a_index >= 1 and a_index <= queue.items.count then
				field_video_name.set_text (queue.items.i_th (a_index).file_name)
			end
			show_video_preview
		end

	selected_video: detachable OCR_VIDEO_ITEM
		do
			Result := video_grid.selected_object
		end

	show_video_preview
			-- The selected row's paragraphs, or the last saved row's.
		local
			l_item: detachable OCR_VIDEO_ITEM
		do
			l_item := selected_video
			if l_item = Void or else not l_item.run.text.is_loaded then
				across
					queue.items as ic
				loop
					if ic.run.text.is_loaded then
						l_item := ic
					end
				end
			end
			video_preview.wipe_out
			if attached l_item as al_item and then al_item.run.text.is_loaded then
				across
					al_item.run.text.paragraphs as ic
				loop
					video_preview.add (ic)
				end
			end
			window.request_render
		end

	on_video_rename
		local
			l_name: STRING_32
		do
			l_name := field_video_name.text.twin
			l_name.left_adjust
			l_name.right_adjust
			if video_grid.selected_model < 1 then
				report ("Select a row to rename.")
			elseif l_name.is_empty then
				report ("Type a file name first.")
			else
				queue.rename_item (video_grid.selected_model, l_name)
				field_video_name.set_text (queue.items.i_th (video_grid.selected_model).file_name)
				report ({STRING_32} "File name: " + queue.items.i_th (video_grid.selected_model).file_name)
				refresh_video_grid
			end
		end

	on_video_fetch_all
			-- One prompt for the folder; the file name shown is the
			-- first ready row's and applies to it.
		do
			if queue.is_busy then
				report ("Still working - wait for the lookups or the current fetch to finish.")
			elseif queue.ready_count = 0 then
				report ("Nothing is ready to fetch. Add links, or wait for their lookups.")
			else
				confirm_output_explaining ({STRING_32} "Every ready video (" + queue.ready_count.out
					+ {STRING_32} ") is written to its own file in this folder, named as the queue shows. The name below is the first video's; change it here or rename rows in the queue.",
					"Fetch", first_ready_name, agent video_fetch_all_confirmed)
			end
		end

	first_ready_name: STRING_32
		do
			create Result.make_empty
			across
				queue.items as ic
			until
				not Result.is_empty
			loop
				if ic.is_ready then
					Result := ic.file_name.twin
				end
			end
		end

	video_fetch_all_confirmed
			-- The prompt stored the folder and the first name; the pass
			-- walks the ready rows on the tick.
		local
			l_first: BOOLEAN
		do
			across
				queue.items as ic
			until
				l_first
			loop
				if ic.is_ready then
					l_first := True
					if not settings.text_file_name.is_empty then
						ic.set_file_name (settings.text_file_name)
						ic.set_file_name (queue.distinct_name (ic.file_name, ic))
					end
				end
			end
			queue.start_fetch_all (settings.output_folder)
			refresh_video_grid
			report ({STRING_32} "Fetching " + queue.queued_count.out + {STRING_32} " transcript(s) into " + queue.folder + {STRING_32} " ...")
		end

	on_video_fetch_selected
		do
			if queue.is_busy then
				report ("Still working - wait for the lookups or the current fetch to finish.")
			elseif not attached selected_video as al_item then
				report ("Select a row first.")
			elseif not al_item.is_ready then
				report ({STRING_32} "That row is not ready: " + al_item.status_caption)
			else
				confirm_output_explaining ({STRING_32} "This one video, " + al_item.title
					+ {STRING_32} ", is written to the file below in this folder. A file that already exists is appended to.",
					"Fetch", al_item.file_name, agent video_fetch_one_confirmed (video_grid.selected_model))
			end
		end

	video_fetch_one_confirmed (a_index: INTEGER)
		do
			if a_index >= 1 and a_index <= queue.items.count and then queue.items.i_th (a_index).is_ready then
				if not settings.text_file_name.is_empty then
					queue.rename_item (a_index, settings.text_file_name)
				end
				queue.start_fetch_one (a_index, settings.output_folder)
				refresh_video_grid
				report ({STRING_32} "Fetching " + queue.items.i_th (a_index).title + {STRING_32} " ...")
			end
		end

	on_video_remove
		do
			if video_grid.selected_model < 1 then
				report ("Select a row to remove.")
			elseif queue.is_busy then
				report ("Wait for the queue to finish before removing rows.")
			else
				queue.remove (video_grid.selected_model)
				video_grid.select_model_row (0)
				field_video_name.set_text ("")
				refresh_video_grid
				report ("Row removed.")
			end
		end

	on_video_clear_finished
		do
			if queue.is_busy then
				report ("Wait for the queue to finish first.")
			else
				queue.clear_finished
				noted_refusals.wipe_out
				video_grid.select_model_row (0)
				field_video_name.set_text ("")
				refresh_video_grid
				report ("Saved, refused and failed rows cleared; the files stay where they were written.")
			end
		end

	on_set_region
		do
			if settings.is_region_valid then
				report ("Adjust the box by its handles - or drag outside it to draw anew. Enter accepts.")
				selector.start_adjusting (settings.region_x, settings.region_y,
					settings.region_width, settings.region_height, agent on_region_chosen)
			else
				report ("Drag a rectangle; Esc or right-click cancels.")
				selector.start (agent on_region_chosen)
			end
		end

	on_region_chosen (a_rect: detachable TUPLE [x, y, w, h: INTEGER])
		do
			if attached a_rect as r then
				is_loading := True
				field_x.set_value (r.x)
				field_y.set_value (r.y)
				field_w.set_value (r.w)
				field_h.set_value (r.h)
				is_loading := False
				store_to_settings
				check_outline_capture.set_checked (True)
				outlines.show (outlines.Kind_capture)
				report ("Region set to " + r.w.out + " x " + r.h.out + " at (" + r.x.out + ", " + r.y.out + "). Outlined on screen.")
			else
				report ("Region selection cancelled.")
			end
			window.request_render
		end

	on_set_advance_region
		do
			if settings.is_advance_region_valid then
				report ("Adjust the box by its handles - or drag outside it to draw anew. Enter accepts.")
				selector.start_adjusting (settings.advance_x, settings.advance_y,
					settings.advance_width, settings.advance_height, agent on_advance_region_chosen)
			else
				report ("Drag a box around the NEXT PAGE button; Esc or right-click cancels.")
				selector.start (agent on_advance_region_chosen)
			end
		end

	on_advance_region_chosen (a_rect: detachable TUPLE [x, y, w, h: INTEGER])
		do
			if attached a_rect as r then
				is_loading := True
				field_advance_x.set_value (r.x)
				field_advance_y.set_value (r.y)
				field_advance_w.set_value (r.w)
				field_advance_h.set_value (r.h)
				is_loading := False
				store_to_settings
				check_outline_advance.set_checked (True)
				outlines.show (outlines.Kind_advance)
				report ("Advance button set. Its middle - (" + (r.x + r.w // 2).out + ", " + (r.y + r.h // 2).out + ") - is where the click lands.")
			else
				report ("Advance button selection cancelled.")
			end
			window.request_render
		end

	on_set_label_region
		do
			if settings.is_page_label_region_valid then
				report ("Adjust the box by its handles - or drag outside it to draw anew. Enter accepts.")
				selector.start_adjusting (settings.page_label_x, settings.page_label_y,
					settings.page_label_width, settings.page_label_height, agent on_label_region_chosen)
			else
				report ("Drag a box around the PAGE INDICATOR; Esc or right-click cancels.")
				selector.start (agent on_label_region_chosen)
			end
		end

	on_label_region_chosen (a_rect: detachable TUPLE [x, y, w, h: INTEGER])
		do
			if attached a_rect as r then
				is_loading := True
				field_label_x.set_value (r.x)
				field_label_y.set_value (r.y)
				field_label_w.set_value (r.w)
				field_label_h.set_value (r.h)
				is_loading := False
				store_to_settings
				check_outline_label.set_checked (True)
				outlines.show (outlines.Kind_label)
				report ("Page indicator set to " + r.w.out + " x " + r.h.out + ".")
			else
				report ("Page indicator selection cancelled.")
			end
			window.request_render
		end

	on_outline_toggle
			-- Any outline box: show or hide per the boxes' state.
		do
			sync_outline (check_outline_capture, outlines.Kind_capture)
			sync_outline (check_outline_advance, outlines.Kind_advance)
			sync_outline (check_outline_label, outlines.Kind_label)
		end

	sync_outline (a_box: SW_CHECK_BOX; a_kind: INTEGER)
		do
			if a_box.is_checked then
				if outlines.is_configured (a_kind) then
					outlines.show (a_kind)
				else
					a_box.set_checked (False)
					report ("That region is not set yet - drag it first.")
				end
			else
				outlines.hide (a_kind)
			end
		end

	on_test_capture
			-- Capture the region and show it in the preview.
		local
			g: OCR_GRAB
		do
			store_to_settings
			if not settings.is_region_valid then
				report ("No capture region set - press %"Set Region by Dragging...%" first.")
			else
				suspend_outlines
				create g.make
				if attached g.capture (settings.region_x, settings.region_y,
					settings.region_width, settings.region_height) as shot
				then
					show_preview (g.last_thumbnail)
					shot.destroy
					report ("Captured " + settings.region_width.out + " x " + settings.region_height.out + ". This is what the model will see.")
				else
					report (g.last_error)
				end
				resume_outlines
			end
		end

	on_capture_now
			-- One full cycle, exactly as the hotkey would.
		do
			ensure_output_folder_then (agent cycle.trigger)
		end

	on_browse
		local
			fd: SW_FILE_DIALOG
			start_dir: STRING_32
		do
			start_dir := field_folder.text.twin
			if start_dir.is_empty or else not (create {DIRECTORY}.make (start_dir)).exists then
				create start_dir.make_from_string_general ("C:\")
			end
			create fd.make_open (start_dir)
			fd.set_on_accept (agent on_folder_picked)
			window.show_sheet (fd, 640.0)
		end

	on_folder_picked (a_path: STRING_32)
			-- The dialog picks FILES; the folder of the choice - or
			-- the path itself when it IS a directory - is the answer.
		local
			dir: STRING_32
			i: INTEGER
		do
			window.close_sheet
			if (create {DIRECTORY}.make (a_path)).exists then
				dir := a_path.twin
			else
				dir := a_path.twin
				i := dir.last_index_of ('\', dir.count)
				if i > 1 then
					dir.keep_head (i - 1)
				end
			end
			field_folder.set_text (dir)
			store_to_settings
			report ("Folder changed - set a text file name for this book.")
			window.request_render
		end

	on_save_settings
		do
			store_to_settings
			settings.store
			report ("Settings saved.")
		end

	on_check_setup
		do
			if attached on_check_setup_agent as a then
				a.call
			end
		end

	on_auto_start
		do
			if attached on_auto_start_agent as a then
				a.call
			end
		end

	on_auto_pause
		do
			if attached on_auto_pause_agent as a then
				a.call
			end
		end

	on_auto_stop
		do
			if attached on_auto_stop_agent as a then
				a.call
			end
		end

	on_quit_pressed
		do
			if attached on_quit as a then
				a.call
			end
		end

	on_run_audit
		local
			l_audit: OCR_AUDIT
		do
			store_to_settings
			if settings.output_folder.is_empty or else settings.text_file_name.is_empty then
				report ("Set the output folder and text file first - there is nothing to audit.")
			else
				report ("Auditing " + narrowed (settings.text_file_name) + " ...")
				create l_audit.make (settings)
				l_audit.findings.set_notify (agent add_finding)
				l_audit.run (settings.text_file_path)
				if l_audit.finding_count = 0 then
					add_finding ({STRING_32} "info", {STRING_32} "",
						{STRING_32} "Nothing wrong found in this transcript",
						{STRING_32} "Gaps, repeats, jumps, failed and truncated captures were all checked")
				end
				report ("Audit finished: " + l_audit.finding_count.out + " finding(s).")
			end
		end

	on_clear_findings
		do
			findings_rows.wipe_out
			findings_grid.set_rows (findings_rows)
			report ("Findings list cleared (the findings file on disk is untouched).")
			window.request_render
		end

	on_open_log
		local
			l_log: OCR_LOG_FILE
		do
			create l_log
			if not l_log.exists then
				report ("There is no log file yet - it appears after the first capture.")
			elseif l_log.open_externally then
				report ("Opened " + narrowed (l_log.path))
			else
				report ("Could not open the log. It is at " + narrowed (l_log.path))
			end
		end

	on_clear_log
		local
			l_log: OCR_LOG_FILE
			d: SW_DIALOG
		do
			create l_log
			if not l_log.exists then
				report ("There is no log file to clear.")
			else
				create d.make ({SW_DIALOG}.Kind_warning, "Clear Log",
					{STRING_32} "Clear the diagnostic log?%N%NIt currently holds "
					+ (l_log.byte_count // 1024).out
					+ {STRING_32} " KB. This is the only record of what unattended runs did. Your transcripts and images are not affected.")
				d.add_button ("Cancel", False, Void)
				d.add_button ("Clear", True, agent clear_log_confirmed)
				window.show_dialog (d)
			end
		end

	clear_log_confirmed
		local
			l_log: OCR_LOG_FILE
		do
			create l_log
			l_log.clear
			report ("Log cleared.")
		end

	on_clear_all
		local
			d: SW_DIALOG
		do
			create d.make ({SW_DIALOG}.Kind_warning, "Clear All",
				"Clear the capture region, advance button, page indicator, output folder and text file name?%N%NYour hotkey, model, endpoint, context size and prompt are NOT affected. Captured images and transcripts already written are not touched.")
			d.add_button ("Cancel", False, Void)
			d.add_button ("Clear", True, agent clear_all_confirmed)
			window.show_dialog (d)
		end

	clear_all_confirmed
			-- On `settings' directly, then reload: store_to_settings
			-- deliberately refuses zero extents and empty names, so
			-- routing a clear through it silently kept old values on
			-- disk - the first shipped version had to be found by hand.
		do
			settings.clear_region
			settings.clear_advance_region
			settings.clear_page_label_region
			settings.set_output_folder ("")
			settings.store
			outlines.hide (outlines.Kind_all)
			check_outline_capture.set_checked (False)
			check_outline_advance.set_checked (False)
			check_outline_label.set_checked (False)
			load_from_settings
			report ("Cleared. Set the region and folder for the next book.")
			window.request_render
		end

	on_delete_images
		local
			d: SW_DIALOG
		do
			store_to_settings
			if cycle.is_busy then
				report ("A capture is in progress - try again when it finishes.")
			elseif not image_store.folder_exists then
				report ("The output folder does not exist - nothing to delete.")
			elseif not image_store.has_images then
				report ("No ocr_*.png or ocr_*.bmp images in " + narrowed (settings.output_folder))
			else
				create d.make ({SW_DIALOG}.Kind_danger, "Delete Images",
					{STRING_32} "Delete " + image_store.image_count.out
					+ {STRING_32} " ocr-related image(s) (" + image_store.size_caption
					+ {STRING_32} ") from%N%N" + settings.output_folder
					+ {STRING_32} "%N%NThis cannot be undone. Your transcript and the findings file are NOT affected - only ocr_*.png and ocr_*.bmp are removed.")
				d.add_button ("Cancel", False, Void)
				d.add_button ("Delete", True, agent delete_images_confirmed)
				window.show_dialog (d)
			end
		end

	delete_images_confirmed
		do
			image_store.delete_all
			report (outcome_report ("deleted"))
		end

	on_move_images
		local
			d: SW_DIALOG
		do
			store_to_settings
			if cycle.is_busy then
				report ("A capture is in progress - try again when it finishes.")
			elseif not image_store.folder_exists then
				report ("The output folder does not exist - nothing to move.")
			elseif not image_store.has_usable_leaf then
				report ("Set a text file name first - it names the destination folder.")
			elseif not image_store.has_images then
				report ("No ocr_*.png or ocr_*.bmp images in " + narrowed (settings.output_folder))
			elseif settings.move_to_drive.is_empty then
				report ("Set 'Move to drive' first (a drive letter, like E).")
			else
				create d.make ({SW_DIALOG}.Kind_warning, "Move Images",
					{STRING_32} "Move " + image_store.image_count.out
					+ {STRING_32} " image(s) (" + image_store.size_caption
					+ {STRING_32} ") to%N%N" + image_store.destination_folder (settings.move_to_drive)
					+ {STRING_32} "%N%NNothing already at the destination is overwritten; collisions are skipped and reported.")
				d.add_button ("Cancel", False, Void)
				d.add_button ("Move", True, agent move_images_confirmed)
				window.show_dialog (d)
			end
		end

	move_images_confirmed
		do
			image_store.move_all_to (settings.move_to_drive)
			report (outcome_report ("moved"))
		end

	outcome_report (a_verb: READABLE_STRING_GENERAL): STRING_32
			-- Skipped and failed appear only when non-zero: a clean
			-- run reads "214 moved." and nothing more.
		do
			create Result.make (100)
			if not image_store.last_error.is_empty then
				Result.append (image_store.last_error)
			else
				Result.append_string_general (image_store.last_done.out)
				Result.append_character (' ')
				Result.append_string_general (a_verb)
				Result.append_character ('.')
				if image_store.last_skipped > 0 then
					Result.append_string_general (" Skipped ")
					Result.append_string_general (image_store.last_skipped.out)
					Result.append_string_general (" (already at destination).")
				end
				if image_store.last_failed > 0 then
					Result.append_string_general (" FAILED ")
					Result.append_string_general (image_store.last_failed.out)
					Result.append_character ('.')
				end
			end
		end

	create_folder_then (a_then: PROCEDURE)
		do
			if created_folder (settings.output_folder) then
				report ("Created " + narrowed (settings.output_folder))
				a_then.call
			else
				report ("Could not create that folder. Check the path for a typo or a drive that is not there.")
			end
		end

	created_folder (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Make `a_path' with any missing parents; True when it
			-- exists afterwards.
		local
			d: DIRECTORY
		do
			create d.make (a_path)
			if not d.exists then
				d.recursive_create_dir
			end
			Result := d.exists
		rescue
			Result := False
			retry
		end

feature {NONE} -- Helpers

	labelled (a_caption: READABLE_STRING_GENERAL; a_widget: SW_WIDGET): SW_ROW
		do
			create Result.make
			Result := Result.add ((create {SW_LABEL}.make_ui (a_caption)).as_muted).add (a_widget)
		end

	coordinate_row (a_c1: READABLE_STRING_GENERAL; a_f1: SW_NUMBER_BOX;
			a_c2: READABLE_STRING_GENERAL; a_f2: SW_NUMBER_BOX): SW_ROW
		do
			create Result.make
			Result := Result.add ((create {SW_LABEL}.make_ui (a_c1)).as_muted).add (a_f1)
				.add ((create {SW_LABEL}.make_ui (a_c2)).as_muted).add (a_f2)
		end

	fill_key_combo
		local
			c: CHARACTER_8
			i: INTEGER
		do
			from
				c := 'A'
			until
				c > 'Z'
			loop
				combo_key.add_option (c.out)
				c := c.next
			end
			from
				i := 1
			until
				i > 12
			loop
				combo_key.add_option ("F" + i.out)
				i := i + 1
			end
		end

	select_text (a_select: SW_SELECT; a_text: READABLE_STRING_GENERAL)
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > a_select.options.count
			loop
				if a_select.options.i_th (i).same_string_general (a_text) then
					a_select.select_index (i)
				end
				i := i + 1
			end
		end

	key_name_for (a_code: NATURAL_32): STRING_32
		do
			if a_code >= 0x41 and a_code <= 0x5A then
				create Result.make_from_string_general (a_code.to_integer_32.to_character_8.out)
			elseif a_code >= 0x70 and a_code <= 0x7B then
				create Result.make_from_string_general ("F" + (a_code.to_integer_32 - 0x70 + 1).out)
			else
				create Result.make_from_string_general ("G")
			end
		end

	key_code_for (a_name: READABLE_STRING_GENERAL): NATURAL_32
		local
			l_name: STRING_8
		do
			l_name := narrowed (a_name)
			l_name.to_upper
			if l_name.count = 1 and then l_name.item (1) >= 'A' and l_name.item (1) <= 'Z' then
				Result := l_name.item (1).code.to_natural_32
			elseif l_name.count >= 2 and then l_name.item (1) = 'F'
				and then l_name.substring (2, l_name.count).is_integer
			then
				Result := (0x70 + l_name.substring (2, l_name.count).to_integer - 1).to_natural_32
			else
				Result := {OCR_HOTKEY}.Vk_g
			end
		ensure
			non_zero: Result /= 0
		end

	two (a_value: INTEGER): STRING_8
		do
			if a_value < 10 then
				Result := "0" + a_value.out
			else
				Result := a_value.out
			end
		end

	narrowed (a_text: READABLE_STRING_GENERAL): STRING_8
		do
			Result := a_text.to_string_8
		end

	image_store: OCR_IMAGE_STORE
		once
			create Result.make (settings)
		end

feature {NONE} -- State

	settings: OCR_SETTINGS
	cycle: OCR_CYCLE
	status_strip: OCR_SW_STRIP
	queue: OCR_VIDEO_QUEUE
	is_loading: BOOLEAN

	on_hotkey_changed: detachable PROCEDURE
	on_quit: detachable PROCEDURE
	on_check_setup_agent: detachable PROCEDURE
	on_auto_start_agent: detachable PROCEDURE
	on_auto_pause_agent: detachable PROCEDURE
	on_auto_stop_agent: detachable PROCEDURE

	status_label: SW_LABEL attribute create Result.make_ui ("Ready.") end
	auto_hint: SW_LABEL attribute create Result.make_ui ("") end
	preview: SW_IMAGE attribute create Result.make_from_surface (create {CAIRO_SURFACE}.make (4, 3)) end
	findings_grid: SW_DATA_GRID [TUPLE [stamp, pages, problem, remedy: STRING_32]]
		attribute create Result.make (420.0) end
	findings_rows: ARRAYED_LIST [TUPLE [stamp, pages, problem, remedy: STRING_32]]

	field_x: SW_NUMBER_BOX attribute create Result.make (0, -20000, 20000, Void) end
	field_y: SW_NUMBER_BOX attribute create Result.make (0, -20000, 20000, Void) end
	field_w: SW_NUMBER_BOX attribute create Result.make (0, 0, 20000, Void) end
	field_h: SW_NUMBER_BOX attribute create Result.make (0, 0, 20000, Void) end
	field_advance_x: SW_NUMBER_BOX attribute create Result.make (0, -20000, 20000, Void) end
	field_advance_y: SW_NUMBER_BOX attribute create Result.make (0, -20000, 20000, Void) end
	field_advance_w: SW_NUMBER_BOX attribute create Result.make (0, 0, 20000, Void) end
	field_advance_h: SW_NUMBER_BOX attribute create Result.make (0, 0, 20000, Void) end
	field_label_x: SW_NUMBER_BOX attribute create Result.make (0, -20000, 20000, Void) end
	field_label_y: SW_NUMBER_BOX attribute create Result.make (0, -20000, 20000, Void) end
	field_label_w: SW_NUMBER_BOX attribute create Result.make (0, 0, 20000, Void) end
	field_label_h: SW_NUMBER_BOX attribute create Result.make (0, 0, 20000, Void) end
	field_advance_delay: SW_NUMBER_BOX attribute create Result.make (1200, 500, 60000, Void) end
	field_timeout: SW_NUMBER_BOX attribute create Result.make (240, 5, 3600, Void) end
	field_num_ctx: SW_NUMBER_BOX attribute create Result.make (8192, 512, 131072, Void) end
	field_folder: SW_TEXT_BOX attribute create Result.make_single_line ("") end
	field_video_url: SW_TEXT_BOX attribute create Result.make_single_line ("") end
	field_video_name: SW_TEXT_BOX attribute create Result.make_single_line ("") end
	video_hint: SW_LABEL attribute create Result.make_ui ("") end
	video_preview: SW_PARAGRAPH_LIST attribute create Result.make (220.0) end
	video_grid: SW_DATA_GRID [OCR_VIDEO_ITEM] attribute create Result.make (200.0) end
	button_video_fetch: SW_BUTTON attribute create Result.make ("Fetch All...", Void) end
	field_move_drive: SW_TEXT_BOX attribute create Result.make_single_line ("") end
	field_text_name: SW_TEXT_BOX attribute create Result.make_single_line ("") end
	field_endpoint: SW_TEXT_BOX attribute create Result.make_single_line ("") end
	field_model: SW_TEXT_BOX attribute create Result.make_single_line ("") end
	check_save_text: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	check_save_image: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	check_separators: SW_CHECK_BOX attribute create Result.make ("", False, Void) end

	check_markdown: SW_CHECK_BOX attribute create Result.make ("", False, Void) end

	check_figures: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	check_show_strip: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	check_show_thumb: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	check_ctrl: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	check_browser_session: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	check_alt: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	check_shift: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	check_outline_capture: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	check_outline_advance: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	check_outline_label: SW_CHECK_BOX attribute create Result.make ("", False, Void) end
	combo_format: SW_SELECT attribute create Result.make end
	combo_key: SW_SELECT attribute create Result.make end
	button_auto_start: SW_BUTTON attribute create Result.make ("Start", Void) end
	button_auto_pause: SW_BUTTON attribute create Result.make ("Pause", Void) end
	button_auto_stop: SW_BUTTON attribute create Result.make ("Stop", Void) end

end
