note
	description: "[
		Settings window. Everything the capture loop reads is editable here and
		persists to disk.

		Values are pushed into OCR_SETTINGS as they change rather than on an OK
		button, because the hotkey can fire a capture while this window is open
		and the cycle must see current values.
	]"

class
	OCR_MAIN_WINDOW

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS; a_cycle: OCR_CYCLE; a_strip: OCR_STATUS_STRIP)
			-- Build the window over `a_settings'.
		do
			settings := a_settings
			cycle := a_cycle
			status_strip := a_strip

			window.set_title ("Simple OCR Capture")

			root_box.set_border_width (Group_border)
			root_box.set_padding (Gap)

			window.extend (root_box)

			build_region_group
			build_auto_group
			build_output_group
			build_trigger_group
			build_ocr_group
			build_outline_group
			build_findings_group
			build_maintenance_row
			build_action_row

			status_label.set_text ("Ready.")
			root_box.extend (status_label)
			root_box.disable_item_expand (status_label)

			load_from_settings

			window.set_size (Window_width, Window_height)

			window.close_request_actions.extend (agent on_close)
		end

feature -- Access

	window: EV_TITLED_WINDOW
			-- The settings window itself.
		attribute
			create Result
		end

feature -- Basic operations

	show
			-- Display the window.
		do
			window.show
			window.set_size (Window_width, Window_height)
		end

	report (a_message: READABLE_STRING_GENERAL)
			-- Show `a_message' on the status line.
		do
			status_label.set_text (a_message)
		end

	add_finding (a_severity, a_pages, a_problem, a_remedy: STRING_32)
			-- Show one finding in the list, newest at the top.
			--
			-- Newest first because during a run the interesting row is the one
			-- that just appeared, and a list that grows downwards puts it out of
			-- sight exactly when it matters.
		local
			l_row: EV_MULTI_COLUMN_LIST_ROW
			l_when: DATE_TIME
			l_stamp: STRING_32
		do
			create l_when.make_now
			create l_stamp.make (10)
			l_stamp.append_string_general (two (l_when.hour))
			l_stamp.append_character (':')
			l_stamp.append_string_general (two (l_when.minute))
			l_stamp.append_character (':')
			l_stamp.append_string_general (two (l_when.second))

			create l_row
			l_row.extend (l_stamp)
			l_row.extend (a_pages)
				-- Severity in front of the problem rather than in a column of
				-- its own: it is one word, and a column for it would cost width
				-- the remedy needs more.
			l_row.extend ({STRING_32} "[" + a_severity + "] " + a_problem)
			l_row.extend (a_remedy)
			findings_list.put_front (l_row)
		end

	animate_outlines
			-- March the dashes on any visible region outline.
			--
			-- Driven from the application's existing timer rather than a timer
			-- of its own. An animated outline is unmistakable against static
			-- page content; a still one can be read as part of the document.
		do
			outlines.advance_phase
		end

	suspend_outlines
			-- Take any outline that would be photographed out of the frame,
			-- leaving its checkbox ticked.
			--
			-- Paired with `resume_outlines' around the shutter. The checkboxes
			-- are deliberately NOT cleared: this is a momentary duck, not the
			-- user turning something off, and a box that unticked itself once a
			-- page would be maddening.
		do
			outlines.suspend
		end

	resume_outlines
			-- Put back whatever `suspend_outlines' took down.
		do
			outlines.resume
		end

	hide_outlines
			-- Take every region outline off the desktop, and untick the boxes.
		do
			outlines.hide_all
			is_syncing := True
			set_check (check_outline_capture, False)
			set_check (check_outline_advance, False)
			set_check (check_outline_label, False)
			set_check (check_outline_all, False)
			is_syncing := False
		end

feature {NONE} -- Construction

	build_region_group
			-- Capture-region controls.
		local
			l_frame: EV_FRAME
			l_box, l_row: EV_HORIZONTAL_BOX
			l_col: EV_VERTICAL_BOX
			l_set: EV_BUTTON
			l_test: EV_BUTTON
		do
			create l_frame.make_with_text ("Capture region")
			create l_col
			l_col.set_border_width (Group_border)
			l_col.set_padding (Gap)

			create l_set.make_with_text ("Set Region by Dragging...")
			l_set.select_actions.extend (agent on_set_region)
			l_col.extend (left_aligned (l_set))
			l_col.disable_item_expand (l_col.last)

			create field_x
			create field_y
			create field_w
			create field_h
			create l_box
			l_box := coordinate_row (field_x, field_y, field_w, field_h)
			l_col.extend (l_box)
			l_col.disable_item_expand (l_box)

			create l_row
			l_row.set_padding (Gap)
			create l_test.make_with_text ("Test Capture")
			l_test.select_actions.extend (agent on_test_capture)
			l_row.extend (l_test)
			l_row.disable_item_expand (l_test)
			create screen_label.make_with_text ("")
			l_row.extend (screen_label)
			l_col.extend (l_row)
			l_col.disable_item_expand (l_row)

				-- Fixed rather than expanding. As the only growable item in the
				-- group it soaked up every spare pixel of window height, which is
				-- what made the window look mostly empty: a blank panel roughly
				-- 150 pixels tall sat under a region that had never been tested.
			create preview
			preview.set_minimum_size (Preview_width, Preview_height)
			l_col.extend (preview)
			l_col.disable_item_expand (preview)

			l_frame.extend (l_col)
			root_box.extend (l_frame)
		end

	build_auto_group
			-- Auto-advance: the two rectangles, the settle delay, and transport.
		local
			l_frame: EV_FRAME
			l_box: EV_HORIZONTAL_BOX
			l_col: EV_VERTICAL_BOX
			l_set_advance, l_set_label: EV_BUTTON
			l_transport: EV_HORIZONTAL_BOX
		do
			create l_frame.make_with_text ("Auto-advance")
			create l_col
			l_col.set_border_width (Group_border)
			l_col.set_padding (Gap)

			create l_set_advance.make_with_text ("Set Advance Button by Dragging...")
			l_set_advance.select_actions.extend (agent on_set_advance_region)
			l_col.extend (left_aligned (l_set_advance))
			l_col.disable_item_expand (l_col.last)

			create field_advance_x
			create field_advance_y
			create field_advance_w
			create field_advance_h
			create l_box
			l_box := coordinate_row (field_advance_x, field_advance_y,
				field_advance_w, field_advance_h)
			l_col.extend (l_box)
			l_col.disable_item_expand (l_box)

			create l_set_label.make_with_text ("Set Page Indicator by Dragging...")
			l_set_label.select_actions.extend (agent on_set_label_region)
			l_col.extend (left_aligned (l_set_label))
			l_col.disable_item_expand (l_col.last)

			create field_label_x
			create field_label_y
			create field_label_w
			create field_label_h
			create l_box
			l_box := coordinate_row (field_label_x, field_label_y,
				field_label_w, field_label_h)
			l_col.extend (l_box)
			l_col.disable_item_expand (l_box)

			create field_advance_delay
			l_col.extend (labelled_number ("Min. settle (ms)", field_advance_delay))
			l_col.disable_item_expand (l_col.last)

			create auto_hint.make_with_text (
				"Turns the page as soon as the shot is taken. Stops when a capture comes back the same as the one before it.")
			l_col.extend (auto_hint)
			l_col.disable_item_expand (auto_hint)

			create l_transport
			l_transport.set_padding (Gap)
			create button_auto_start.make_with_text ("Start")
			button_auto_start.select_actions.extend (agent on_auto_start)
			create button_auto_pause.make_with_text ("Pause")
			button_auto_pause.select_actions.extend (agent on_auto_pause)
			create button_auto_stop.make_with_text ("Stop")
			button_auto_stop.select_actions.extend (agent on_auto_stop)
			l_transport.extend (button_auto_start)
			l_transport.extend (button_auto_pause)
			l_transport.extend (button_auto_stop)
			l_transport.disable_item_expand (button_auto_start)
			l_transport.disable_item_expand (button_auto_pause)
			l_transport.disable_item_expand (button_auto_stop)
			l_transport.extend (create {EV_CELL})
			l_col.extend (l_transport)
			l_col.disable_item_expand (l_transport)

			l_frame.extend (l_col)
			root_box.extend (l_frame)
		end

	build_output_group
			-- Where results are written.
		local
			l_frame: EV_FRAME
			l_col: EV_VERTICAL_BOX
			l_row: EV_HORIZONTAL_BOX
			l_browse: EV_BUTTON
		do
			create l_frame.make_with_text ("Output")
			create l_col
			l_col.set_border_width (Group_border)
			l_col.set_padding (Gap)

			create l_row
			l_row.set_padding (Gap)
			create field_folder
			l_row.extend (labelled ("Folder", field_folder))
			create l_browse.make_with_text ("Browse...")
			l_browse.select_actions.extend (agent on_browse)
			l_row.extend (l_browse)
			l_row.disable_item_expand (l_browse)
			l_col.extend (l_row)
			l_col.disable_item_expand (l_row)

			create field_text_name
			l_col.extend (labelled ("Text file", field_text_name))
			l_col.disable_item_expand (l_col.last)

			create check_save_text.make_with_text ("Append OCR text to the file above")
			create check_save_image.make_with_text ("Also keep the captured image")
			create check_separators.make_with_text ("Write a header line before each capture")
			l_col.extend (check_save_text)
			l_col.extend (check_save_image)
			l_col.extend (check_separators)
			l_col.disable_item_expand (check_save_text)
			l_col.disable_item_expand (check_save_image)
			l_col.disable_item_expand (check_separators)

			create combo_format
			combo_format.extend (list_item ("png"))
			combo_format.extend (list_item ("bmp"))
			combo_format.disable_edit
			combo_format.set_minimum_width (Number_field_width)
			l_row := captioned ("Image format", combo_format, Label_width)
			l_row.disable_item_expand (combo_format)
			l_row.extend (create {EV_CELL})
			l_col.extend (l_row)
			l_col.disable_item_expand (l_row)

			l_frame.extend (l_col)
			root_box.extend (l_frame)
		end

	build_trigger_group
			-- Hotkey selection.
		local
			l_frame: EV_FRAME
			l_col: EV_VERTICAL_BOX
			l_row: EV_HORIZONTAL_BOX
		do
			create l_frame.make_with_text ("Trigger")
			create l_col
			l_col.set_border_width (Group_border)
			l_col.set_padding (Gap)

			create l_row
			l_row.set_padding (Gap)
			create check_ctrl.make_with_text ("Ctrl")
			create check_alt.make_with_text ("Alt")
			create check_shift.make_with_text ("Shift")
			l_row.extend (check_ctrl)
			l_row.extend (check_alt)
			l_row.extend (check_shift)
				-- Without this the three checkboxes share the row equally and
				-- push the key dropdown off the right edge, leaving no way to
				-- see or change which key is bound.
			l_row.disable_item_expand (check_ctrl)
			l_row.disable_item_expand (check_alt)
			l_row.disable_item_expand (check_shift)

			create combo_key
			populate_key_combo
			combo_key.disable_edit
			l_row.extend (combo_key)
			l_col.extend (l_row)
			l_col.disable_item_expand (l_row)

				-- No second line here. There was a `hotkey_label' that was created
				-- empty and never written to by anything, so it reserved a blank
				-- row for the life of the window. What it looked like it was for -
				-- "Hotkey active: Ctrl+Alt+G" - goes to the status line instead,
				-- via `register_hotkey'.

			l_frame.extend (l_col)
			root_box.extend (l_frame)
		end

	build_ocr_group
			-- Model and endpoint.
		local
			l_frame: EV_FRAME
			l_col: EV_VERTICAL_BOX
			l_check: EV_BUTTON
		do
			create l_frame.make_with_text ("OCR engine")
			create l_col
			l_col.set_border_width (Group_border)
			l_col.set_padding (Gap)

				-- Endpoint and model stay full width: they hold a URL and a
				-- registry tag, and truncating either hides the part that
				-- differs. The two numbers beside them do not.
			create field_endpoint
			create field_model
			create field_timeout
			create field_num_ctx
			l_col.extend (labelled ("Endpoint", field_endpoint))
			l_col.disable_item_expand (l_col.last)
			l_col.extend (labelled ("Model", field_model))
			l_col.disable_item_expand (l_col.last)
			l_col.extend (labelled_number ("Timeout (s)", field_timeout))
			l_col.disable_item_expand (l_col.last)
			l_col.extend (labelled_number ("Context tokens", field_num_ctx))
			l_col.disable_item_expand (l_col.last)

			create context_hint.make_with_text (
				"Image + text share this window. Too low silently truncates long pages.")
			l_col.extend (context_hint)
			l_col.disable_item_expand (context_hint)

			create l_check.make_with_text ("Check Setup / Install Model")
			l_check.select_actions.extend (agent on_check_setup)
			l_col.extend (left_aligned (l_check))
			l_col.disable_item_expand (l_col.last)

			l_frame.extend (l_col)
			root_box.extend (l_frame)
		end

	build_outline_group
			-- Checkboxes that draw each configured region on the DESKTOP.
			--
			-- Checkboxes rather than the click-and-hold buttons first sketched.
			-- A hold gesture buys only "glance without leaving it on", and costs
			-- a real failure mode: if a release event is ever swallowed, twelve
			-- topmost windows stay on screen with no obvious way to clear them.
			-- A checkbox cannot get stuck.
		local
			l_frame: EV_FRAME
			l_col: EV_VERTICAL_BOX
			l_row: EV_HORIZONTAL_BOX
			l_hint: EV_LABEL
		do
			create l_frame.make_with_text ("Show regions on screen")
			create l_col
			l_col.set_border_width (Group_border)
			l_col.set_padding (Gap)

			create l_row
			l_row.set_padding (Gap)
			create check_outline_capture.make_with_text ("Capture region")
			check_outline_capture.select_actions.extend (
				agent on_outline_toggle ({OCR_OUTLINE_SET}.Kind_capture))
			create check_outline_advance.make_with_text ("Advance button")
			check_outline_advance.select_actions.extend (
				agent on_outline_toggle ({OCR_OUTLINE_SET}.Kind_advance))
			create check_outline_label.make_with_text ("Page indicator")
			check_outline_label.select_actions.extend (
				agent on_outline_toggle ({OCR_OUTLINE_SET}.Kind_label))
			create check_outline_all.make_with_text ("All three")
			check_outline_all.select_actions.extend (
				agent on_outline_toggle ({OCR_OUTLINE_SET}.Kind_all))

			l_row.extend (check_outline_capture)
			l_row.extend (check_outline_advance)
			l_row.extend (check_outline_label)
			l_row.extend (check_outline_all)
			l_row.disable_item_expand (check_outline_capture)
			l_row.disable_item_expand (check_outline_advance)
			l_row.disable_item_expand (check_outline_label)
			l_row.disable_item_expand (check_outline_all)
			l_row.extend (create {EV_CELL})
			l_col.extend (l_row)
			l_col.disable_item_expand (l_row)

			create l_hint.make_with_text (
				"Drawn on the desktop over your reader, not in this window. Move this window clear of the reader to see them.")
			l_col.extend (l_hint)
			l_col.disable_item_expand (l_hint)

			l_frame.extend (l_col)
			root_box.extend (l_frame)
		end

	build_findings_group
			-- The list of problems worth a human's attention.
			--
			-- On the main window rather than in a dialog, because the failures
			-- this exists for were all noticed HOURS after they happened: a
			-- reader that jumped 209 pages, an indicator that stopped reading
			-- for eleven captures, a book re-scanned from the cover. Every one
			-- was visible in the data at the time and nothing said so.
		local
			l_frame: EV_FRAME
			l_col: EV_VERTICAL_BOX
			l_row: EV_HORIZONTAL_BOX
			l_audit, l_clear: EV_BUTTON
			l_hint: EV_LABEL
		do
			create l_frame.make_with_text ("Findings")
			create l_col
			l_col.set_border_width (Group_border)
			l_col.set_padding (Gap)

				-- No `set_column_count': the list grows to fit the titles given,
				-- and there is no such feature to call.
			findings_list.set_column_titles (<<"When", "Where", "Problem", "What to do">>)
			findings_list.set_column_widths (<<70, 150, 330, 380>>)
			findings_list.set_minimum_height (Findings_height)
			l_col.extend (findings_list)

			create l_row
			l_row.set_padding (Gap)
			create l_audit.make_with_text ("Run Audit")
			l_audit.select_actions.extend (agent on_run_audit)
			create l_clear.make_with_text ("Clear List")
			l_clear.select_actions.extend (agent on_clear_findings)
			l_row.extend (l_audit)
			l_row.extend (l_clear)
			l_row.disable_item_expand (l_audit)
			l_row.disable_item_expand (l_clear)
			create l_hint.make_with_text (
				"Problems appear here as they happen. Run Audit checks the finished transcript for gaps, repeats and jumps.")
			l_row.extend (l_hint)
			l_col.extend (l_row)
			l_col.disable_item_expand (l_row)

			l_frame.extend (l_col)
			root_box.extend (l_frame)
		end

	build_maintenance_row
			-- Between-books housekeeping: reset the per-book settings, and read
			-- or empty the log.
			--
			-- Kept off the main action row deliberately. "Capture Now" is what
			-- you press constantly; "Clear All" is what you press once a book
			-- and must never be hit by accident reaching for its neighbour.
		local
			l_row: EV_HORIZONTAL_BOX
			l_clear, l_open_log, l_clear_log, l_show_strip: EV_BUTTON
		do
			create l_row
			l_row.set_padding (Gap)

			create l_clear.make_with_text ("Clear All")
			l_clear.select_actions.extend (agent on_clear_all)
			create l_open_log.make_with_text ("Open Log")
			l_open_log.select_actions.extend (agent on_open_log)
			create l_clear_log.make_with_text ("Clear Log")
			l_clear_log.select_actions.extend (agent on_clear_log)
			create l_show_strip.make_with_text ("Show Strip")
			l_show_strip.select_actions.extend (agent on_restore_strip)

			l_row.extend (l_clear)
			l_row.extend (l_open_log)
			l_row.extend (l_clear_log)
			l_row.extend (l_show_strip)
			l_row.disable_item_expand (l_clear)
			l_row.disable_item_expand (l_open_log)
			l_row.disable_item_expand (l_clear_log)
			l_row.disable_item_expand (l_show_strip)
			l_row.extend (create {EV_CELL})

			root_box.extend (l_row)
			root_box.disable_item_expand (l_row)
		end

	build_action_row
			-- Capture button and strip toggle.
		local
			l_row: EV_HORIZONTAL_BOX
			l_capture, l_apply: EV_BUTTON
		do
			create l_row
			l_row.set_padding (Gap)

			create l_capture.make_with_text ("Capture Now")
			l_capture.select_actions.extend (agent on_capture_now)
			l_row.extend (l_capture)

			create l_apply.make_with_text ("Save Settings")
			l_apply.select_actions.extend (agent on_apply)
			l_row.extend (l_apply)

			create check_show_strip.make_with_text ("Show progress strip")
			check_show_strip.select_actions.extend (agent on_toggle_strip)
			l_row.extend (check_show_strip)

			create check_show_thumb.make_with_text ("Show last capture")
			check_show_thumb.select_actions.extend (agent on_toggle_thumbnail)
			l_row.extend (check_show_thumb)

			root_box.extend (l_row)
			root_box.disable_item_expand (l_row)
		end

feature {NONE} -- Settings transfer

	is_loading: BOOLEAN
			-- Is `load_from_settings' currently populating the controls?
			--
			-- EV_CHECK_BUTTON.enable_select FIRES select_actions. Populating a
			-- checkbox therefore runs its change handler, which calls
			-- `store_to_settings', which reads EVERY control - including the
			-- ones load has not reached yet - and writes their empty state to
			-- disk. Loading the strip checkbox wrote show_thumbnail=false from
			-- the not-yet-loaded thumbnail checkbox, and the next line then
			-- loaded that false straight back. Same shape as the bug that
			-- turned Ctrl+Alt+G into a bare "A".

	load_from_settings
			-- Fill every control from `settings'.
		do
			is_loading := True
			field_x.set_text (settings.region_x.out)
			field_y.set_text (settings.region_y.out)
			field_w.set_text (settings.region_width.out)
			field_h.set_text (settings.region_height.out)
			field_folder.set_text (settings.output_folder)
			field_text_name.set_text (settings.text_file_name)
			field_endpoint.set_text (settings.endpoint)
			field_model.set_text (settings.model)
			field_timeout.set_text (settings.ocr_timeout_seconds.out)
			field_num_ctx.set_text (settings.num_ctx.out)

			field_advance_x.set_text (settings.advance_x.out)
			field_advance_y.set_text (settings.advance_y.out)
			field_advance_w.set_text (settings.advance_width.out)
			field_advance_h.set_text (settings.advance_height.out)
			field_label_x.set_text (settings.page_label_x.out)
			field_label_y.set_text (settings.page_label_y.out)
			field_label_w.set_text (settings.page_label_width.out)
			field_label_h.set_text (settings.page_label_height.out)
			field_advance_delay.set_text (settings.advance_delay_ms.out)
			show_auto_state (False, False)

			set_check (check_save_text, settings.save_text)
			set_check (check_save_image, settings.save_image)
			set_check (check_separators, settings.add_separators)
			set_check (check_show_strip, settings.show_strip)
			set_check (check_show_thumb, settings.show_thumbnail)

			select_in_combo (combo_format, settings.image_format)

			set_check (check_ctrl, (settings.hotkey_modifiers & {OCR_HOTKEY}.Mod_control) /= 0)
			set_check (check_alt, (settings.hotkey_modifiers & {OCR_HOTKEY}.Mod_alt) /= 0)
			set_check (check_shift, (settings.hotkey_modifiers & {OCR_HOTKEY}.Mod_shift) /= 0)
			select_in_combo (combo_key, key_name_for (settings.hotkey_key))

			update_screen_label
			is_loading := False
		ensure
			not_loading: not is_loading
		end

	store_to_settings
			-- Push every control back into `settings'.
		local
			l_mods: NATURAL_32
		do
			if is_loading then
					-- Reached via a change handler fired by load itself. The
					-- controls are half-populated, so writing them would
					-- overwrite good stored values with empty ones.
			else
			if field_w.text.is_integer and field_h.text.is_integer
				and then field_w.text.to_integer > 0 and field_h.text.to_integer > 0
			then
				settings.set_region (integer_of (field_x), integer_of (field_y),
					field_w.text.to_integer, field_h.text.to_integer)
			end

			settings.set_output_folder (field_folder.text)
			if not field_text_name.text.is_empty then
				settings.set_text_file_name (field_text_name.text)
			end
			settings.set_save_text (check_save_text.is_selected)
			settings.set_save_image (check_save_image.is_selected)
			settings.set_add_separators (check_separators.is_selected)
			settings.set_show_strip (check_show_strip.is_selected)
			settings.set_show_thumbnail (check_show_thumb.is_selected)

			if combo_format.text.same_string_general ("bmp") then
				settings.set_image_format ("bmp")
			else
				settings.set_image_format ("png")
			end

			if not field_endpoint.text.is_empty then
				settings.set_endpoint (narrowed (field_endpoint.text))
			end
			if not field_model.text.is_empty then
				settings.set_model (narrowed (field_model.text))
			end
			if field_timeout.text.is_integer and then field_timeout.text.to_integer > 0 then
				settings.set_ocr_timeout_seconds (field_timeout.text.to_integer)
			end
				-- Floor of 4096: anything less and a screenshot can fill the
				-- window on its own, truncating every capture without saying so.
			if field_num_ctx.text.is_integer and then field_num_ctx.text.to_integer >= 4096 then
				settings.set_num_ctx (field_num_ctx.text.to_integer)
			end

				-- Both rectangles are written only when they have real extent.
				-- A half-typed width would otherwise zero the stored box, and a
				-- zero-extent advance box is precisely what stops any clicking.
			if integer_of (field_advance_w) > 0 and integer_of (field_advance_h) > 0 then
				settings.set_advance_region (integer_of (field_advance_x), integer_of (field_advance_y),
					integer_of (field_advance_w), integer_of (field_advance_h))
			end
			if integer_of (field_label_w) > 0 and integer_of (field_label_h) > 0 then
				settings.set_page_label_region (integer_of (field_label_x), integer_of (field_label_y),
					integer_of (field_label_w), integer_of (field_label_h))
			end
			if field_advance_delay.text.is_integer then
				settings.set_advance_delay_ms (field_advance_delay.text.to_integer)
			end

			l_mods := 0
			if check_ctrl.is_selected then l_mods := l_mods | {OCR_HOTKEY}.Mod_control end
			if check_alt.is_selected then l_mods := l_mods | {OCR_HOTKEY}.Mod_alt end
			if check_shift.is_selected then l_mods := l_mods | {OCR_HOTKEY}.Mod_shift end

				-- Only overwrite a stored hotkey with a USABLE one. Writing
				-- whatever the widgets happen to hold is how a working
				-- Ctrl+Alt+G silently became a bare "A": merely opening and
				-- closing this window replaced it. A combination with no
				-- modifier is never what the user meant, so keep what is stored
				-- rather than destroy it.
			if l_mods /= 0 then
					settings.set_hotkey (l_mods, key_code_for (combo_key.text))
				end

				settings.store
			end
		end

feature {NONE} -- Events

	on_set_region
			-- Launch the drag-select overlay.
		do
			report ("Drag a rectangle; Esc or right-click cancels.")
			create region_selector.make
			if attached region_selector as al_selector then
				al_selector.start (agent on_region_chosen)
			end
		end

	on_region_chosen (a_rect: detachable EV_RECTANGLE)
			-- Receive the dragged rectangle.
		do
			if attached a_rect as al_rect then
				field_x.set_text (al_rect.x.out)
				field_y.set_text (al_rect.y.out)
				field_w.set_text (al_rect.width.out)
				field_h.set_text (al_rect.height.out)
				store_to_settings
				reveal_region ({OCR_OUTLINE_SET}.Kind_capture)
				report ("Region set to " + al_rect.width.out + " x " + al_rect.height.out
					+ " at (" + al_rect.x.out + ", " + al_rect.y.out
					+ "). Outlined on screen - untick 'Capture region' to hide it.")
			else
				report ("Region selection cancelled.")
			end
			region_selector := Void
		end

	on_set_advance_region
			-- Drag a box around the reader's next-page control.
		do
			report ("Drag a box around the NEXT PAGE button; Esc or right-click cancels.")
			create region_selector.make
			if attached region_selector as al_selector then
				al_selector.start (agent on_advance_region_chosen)
			end
		end

	on_advance_region_chosen (a_rect: detachable EV_RECTANGLE)
			-- Receive the advance button rectangle.
		do
			if attached a_rect as al_rect and then al_rect.width > 0 and then al_rect.height > 0 then
				field_advance_x.set_text (al_rect.x.out)
				field_advance_y.set_text (al_rect.y.out)
				field_advance_w.set_text (al_rect.width.out)
				field_advance_h.set_text (al_rect.height.out)
				store_to_settings
				reveal_region ({OCR_OUTLINE_SET}.Kind_advance)
				report ("Advance button set. Its middle - (" +
					(al_rect.x + al_rect.width // 2).out + ", " +
					(al_rect.y + al_rect.height // 2).out
					+ ") - is what gets clicked. Outlined on screen.")
				warn_if_regions_collide
			else
				report ("Advance button selection cancelled.")
			end
			region_selector := Void
		end

	on_set_label_region
			-- Drag a box around the reader's page indicator.
		do
			report ("Drag a box around the PAGE NUMBER indicator; Esc or right-click cancels.")
			create region_selector.make
			if attached region_selector as al_selector then
				al_selector.start (agent on_label_region_chosen)
			end
		end

	on_label_region_chosen (a_rect: detachable EV_RECTANGLE)
			-- Receive the page indicator rectangle.
		do
			if attached a_rect as al_rect and then al_rect.width > 0 and then al_rect.height > 0 then
				field_label_x.set_text (al_rect.x.out)
				field_label_y.set_text (al_rect.y.out)
				field_label_w.set_text (al_rect.width.out)
				field_label_h.set_text (al_rect.height.out)
				store_to_settings
				reveal_region ({OCR_OUTLINE_SET}.Kind_label)
				report ("Page indicator set to " + al_rect.width.out + " x " + al_rect.height.out
					+ ". Outlined on screen - untick 'Page indicator' to hide it.")
				warn_if_regions_collide
			else
				report ("Page indicator selection cancelled.")
			end
			region_selector := Void
		end

	on_auto_start
			-- Ask the driver to begin or resume an unattended run.
		do
			store_to_settings
			if attached on_auto_start_agent as al_agent then
				al_agent.call
			end
		end

	on_auto_pause
			-- Ask the driver to pause.
		do
			if attached on_auto_pause_agent as al_agent then
				al_agent.call
			end
		end

	on_auto_stop
			-- Ask the driver to stop.
		do
			if attached on_auto_stop_agent as al_agent then
				al_agent.call
			end
		end

	on_test_capture
			-- Capture the region and show it in the preview.
		local
			l_capture: OCR_CAPTURE
		do
			store_to_settings
				-- `OCR_CAPTURE.capture' REQUIRES a positive extent, and with
				-- assertions baked into the shipped binary a zero rectangle does
				-- not fail politely - it aborts the application.
				--
				-- This became reachable when Clear All shipped. Before that, a
				-- rectangle could only arrive from a drag (always positive) or
				-- from stored settings (always positive), so no caller had ever
				-- had to consider zero. A new way to reach a state obliges every
				-- consumer of that state to be re-checked; this was the one that
				-- had not been.
			if not settings.is_region_valid then
				report ("No capture region set - press %"Set Region by Dragging...%" first.")
			else
					-- This path calls OCR_CAPTURE directly rather than going
					-- through the cycle, so it has to work the shutter itself.
				suspend_outlines
				create l_capture.make
				if attached l_capture.capture (settings.region_x, settings.region_y,
					settings.region_width, settings.region_height) as al_pixmap
				then
					show_preview (al_pixmap)
					report ("Captured " + l_capture.last_width.out + " x " + l_capture.last_height.out + ".")
				else
					report (l_capture.last_error)
				end
				resume_outlines
			end
		end

	on_browse
			-- Choose the output folder.
		local
			l_dialog: EV_DIRECTORY_DIALOG
			l_current: STRING_32
		do
			create l_dialog
			l_current := field_folder.text
				-- `set_start_directory' REQUIRES the directory to exist:
				--     a_path_exists: (create {DIRECTORY}.make (a_path)).exists
				-- Assertions are baked into the shipped binary, so an empty or
				-- deleted path does not degrade - it takes the application down
				-- with a precondition violation. Clear All empties this field,
				-- so the very next Browse did exactly that.
			if not l_current.is_empty
				and then (create {DIRECTORY}.make (l_current)).exists
			then
				l_dialog.set_start_directory (l_current)
			end
			l_dialog.show_modal_to_window (window)

			if not l_dialog.directory.is_empty
				and then not l_dialog.directory.same_string_general (l_current)
			then
				field_folder.set_text (l_dialog.directory)
					-- A new folder means a new book, and the previous book's file
					-- name is the one name that must NOT be reused: keeping it
					-- appends the new book silently onto the old transcript.
					--
					-- Written straight to `settings' rather than left to
					-- `store_to_settings', which skips an empty name by design.
					-- Going through it cleared the BOX while leaving the old name
					-- stored - so the next capture would still have written to the
					-- previous book's file, which is the exact bug this prevents.
				field_text_name.set_text ({OCR_SETTINGS}.Default_text_file_name)
				store_to_settings
				report ("Folder changed - set a text file name for this book.")
			end
		end

	on_clear_all
			-- Reset what changes from book to book, and nothing else.
		local
			l_question: EV_CONFIRMATION_DIALOG
		do
			create l_question.make_with_text (
				"Clear the capture region, advance button, page indicator, output folder and text file name?%N%N" +
				"Your hotkey, model, endpoint, context size and prompt are NOT affected.%N%N" +
				"Captured images and transcripts already written are not touched.")
			l_question.set_title ("Simple OCR Capture - Clear All")
			l_question.show_modal_to_window (window)

			if attached l_question.selected_button as al_button
				and then al_button.same_string_general ("OK")
			then
					-- Cleared on `settings' directly, then the controls reloaded
					-- from it. NOT by blanking the fields and calling
					-- `store_to_settings': that routine deliberately refuses to
					-- store a zero-extent rectangle or an empty file name, so a
					-- Clear All routed through it emptied the SCREEN while
					-- leaving the old region and file name on disk. It looked
					-- like it worked and silently did not - the first version of
					-- this feature shipped that way and had to be found by hand.
				settings.clear_region
				settings.clear_advance_region
				settings.clear_page_label_region
				settings.set_output_folder ("")
				settings.set_text_file_name ({OCR_SETTINGS}.Default_text_file_name)
				settings.store

				load_from_settings
				report ("Cleared. Set the folder, file name and capture region for the next book.")
			end
		end

	on_outline_toggle (a_kind: INTEGER)
			-- Show or hide the outline for `a_kind' on the desktop.
			--
			-- Guarded by `is_syncing' because ticking "All three" sets the other
			-- three boxes, and `enable_select'/`disable_select' FIRE their own
			-- select_actions - so each would re-enter here and drive the others
			-- again. Same hazard the settings loader documents.
		require
			known_kind: outlines.is_known_kind (a_kind)
		local
			l_on: BOOLEAN
		do
			if not is_syncing then
				is_syncing := True

				l_on := outline_check (a_kind).is_selected
				if l_on then
					outlines.show (a_kind)
				else
					outlines.hide (a_kind)
				end

				if a_kind = {OCR_OUTLINE_SET}.Kind_all then
					set_check (check_outline_capture, l_on)
					set_check (check_outline_advance, l_on)
					set_check (check_outline_label, l_on)
				else
						-- "All three" reflects reality rather than leading it: it
						-- goes off the moment any single one is turned off.
					sync_outline_all
				end

				is_syncing := False
				report_outline_state (a_kind, l_on)
			end
		end

	reveal_region (a_kind: INTEGER)
			-- Tick `a_kind''s box and draw it, right after it has been dragged.
			--
			-- So a drag ends with the box you just drew still on screen, against
			-- the reader, where you can see whether it landed where you meant.
			-- Until now the only way to check was Test Capture, which answers a
			-- page later and only for the capture region.
			--
			-- Not left to the checkbox's own action: `enable_select' on a box
			-- that is ALREADY ticked fires nothing, so re-dragging a region
			-- whose outline was showing would have left the old rectangle drawn.
			-- `show' re-reads settings, so this always reflects the new drag.
		require
			single_kind: a_kind >= {OCR_OUTLINE_SET}.Kind_capture
				and a_kind <= {OCR_OUTLINE_SET}.Kind_label
		do
			is_syncing := True
			set_check (outline_check (a_kind), True)
			sync_outline_all
			is_syncing := False
			outlines.show (a_kind)
		end

	warn_if_regions_collide
			-- Say so, loudly, when the page indicator and the advance button
			-- have ended up on the same spot.
			--
			-- Called AFTER the success message so it wins the status line: the
			-- reassuring "Page indicator set to 91 x 474" is exactly what made
			-- the last collision look fine.
		do
			if settings.is_label_over_advance then
				report ("WARNING: the page indicator and the advance button are on the same spot. "
					+ "One is text to read, the other a button to click - check both boxes.")
			end
		end

	sync_outline_all
			-- Make "All three" agree with the three individual boxes.
		do
			set_check (check_outline_all,
				check_outline_capture.is_selected
				and check_outline_advance.is_selected
				and check_outline_label.is_selected)
		end

	report_outline_state (a_kind: INTEGER; a_on: BOOLEAN)
			-- Say what happened, including the case that draws nothing.
		require
			known_kind: outlines.is_known_kind (a_kind)
		local
			l_message: STRING_32
		do
			if not a_on then
				create l_message.make_from_string_general ("Hid the ")
				l_message.append (outlines.description (a_kind))
				l_message.append_character ('.')
			elseif not outlines.is_configured (a_kind) then
					-- Said out loud rather than left as an empty screen: an
					-- unset region draws nothing, which is indistinguishable
					-- from the feature being broken.
				create l_message.make_from_string_general ("Nothing to show - the ")
				l_message.append (outlines.description (a_kind))
				l_message.append_string_general (" has not been set yet.")
			else
				create l_message.make_from_string_general ("Showing the ")
				l_message.append (outlines.description (a_kind))
				l_message.append_string_general (" on the desktop. Move this window if it is in the way.")
			end
			report (l_message)
		end

	outline_check (a_kind: INTEGER): EV_CHECK_BUTTON
			-- The checkbox controlling `a_kind'.
		require
			known_kind: outlines.is_known_kind (a_kind)
		do
			inspect a_kind
			when {OCR_OUTLINE_SET}.Kind_capture then Result := check_outline_capture
			when {OCR_OUTLINE_SET}.Kind_advance then Result := check_outline_advance
			when {OCR_OUTLINE_SET}.Kind_label then Result := check_outline_label
			else Result := check_outline_all
			end
		end

feature -- Basic operations

	is_output_folder_ready: BOOLEAN
			-- Does the output folder exist, or has the user just agreed to make
			-- it? False means do not capture.
			--
			-- Asked HERE, before anything is captured, rather than in the capture
			-- cycle where it used to be created silently. A mistyped folder then
			-- produced a new directory and a whole book scanned quietly into the
			-- wrong place - the program inventing a destination the user never
			-- chose.
			--
			-- Answering "no" is not an error and is not treated as one: the user
			-- is told to change the folder, and if the next one does not exist
			-- either they are asked about that one too.
		local
			l_question: EV_CONFIRMATION_DIALOG
			l_prompt: STRING_32
		do
			store_to_settings
			if settings.output_folder.is_empty then
				report ("No output folder set - choose one before capturing.")
			elseif settings.output_folder_exists then
				Result := True
			else
				create l_prompt.make_from_string_general ("This output folder does not exist:%N%N")
				l_prompt.append (settings.output_folder)
				l_prompt.append_string_general ("%N%NCreate it?")
				create l_question.make_with_text (l_prompt)
				l_question.set_title ("Simple OCR Capture - Output folder")
				l_question.show_modal_to_window (window)

				if attached l_question.selected_button as al_button
					and then al_button.same_string_general ("OK")
				then
					if created_folder (settings.output_folder) then
						Result := True
						report ("Created " + narrowed (settings.output_folder))
					else
						report ("Could not create that folder. Check the path for a typo or a drive that is not there.")
					end
				else
					report ("Not created. Change the output folder before capturing - nothing has been written.")
				end
			end
		end

	created_folder (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Make `a_path', with any missing parents. True when it exists after.
		local
			l_dir: DIRECTORY
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_dir.make_with_name (a_path)
				l_dir.recursive_create_dir
				Result := l_dir.exists
			end
		rescue
			l_retried := True
			retry
		end

feature {NONE} -- Events

	on_run_audit
			-- Check the current transcript and fill the list with what it finds.
			--
			-- The audit writes to the same findings file the running application
			-- does, and its notify hook is attached first, so rows appear here
			-- as they are found rather than after a silent pause.
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
			-- Empty the list on screen.
			--
			-- The DISPLAY only. The findings file is the record and is never
			-- touched from here - clearing a list must not quietly discard the
			-- history it was showing.
		do
			findings_list.wipe_out
			report ("Findings list cleared. The findings file is untouched.")
		end

	on_restore_strip
			-- Bring the progress strip back, wherever it went.
			--
			-- Always MOVES it to a known-good corner rather than merely showing
			-- it. Someone pressing this has already failed to find it where it
			-- was, so putting it back in the same place would answer nothing.
			--
			-- Also re-ticks "Show progress strip": the strip once vanished while
			-- that box still claimed it was on, and a recovery that leaves the
			-- interface disagreeing with the screen is half a recovery.
		do
			status_strip.restore_to_default
			set_check (check_show_strip, True)
			settings.set_show_strip (True)
			settings.store
			report ("Progress strip restored to the top-left of the screen.")
		end

	on_open_log
			-- Show the diagnostic log in whatever reads .txt here.
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
			-- Empty the diagnostic log, on confirmation.
		local
			l_log: OCR_LOG_FILE
			l_question: EV_CONFIRMATION_DIALOG
			l_prompt: STRING_32
		do
			create l_log
			if not l_log.exists then
				report ("There is no log file to clear.")
			else
				create l_prompt.make_from_string_general ("Clear the diagnostic log?%N%N")
				l_prompt.append_string_general ("It currently holds ")
				l_prompt.append_string_general ((l_log.byte_count // 1024).out)
				l_prompt.append_string_general (" KB.%N%NThis is the only record of what unattended runs did. Your transcripts and images are not affected.")

				create l_question.make_with_text (l_prompt)
				l_question.set_title ("Simple OCR Capture - Clear Log")
				l_question.show_modal_to_window (window)

				if attached l_question.selected_button as al_button
					and then al_button.same_string_general ("OK")
				then
					l_log.clear
					report ("Log cleared.")
				end
			end
		end

	on_capture_now
			-- Fire a cycle from the button.
		do
			store_to_settings
				-- No outline handling here: OCR_CYCLE takes them down around the
				-- shutter itself, so every path that captures is covered rather
				-- than only the ones someone remembered.
			if is_output_folder_ready then
				cycle.trigger
				if not cycle.last_error.is_empty then
					report (cycle.last_error)
				end
			end
		end

	on_apply
			-- Persist settings and report.
		do
			store_to_settings
			report ("Settings saved.")
			if attached on_hotkey_changed as al_agent then
				al_agent.call (Void)
			end
		end

	on_toggle_strip
			-- Show or hide the progress strip.
		do
			if check_show_strip.is_selected then
				status_strip.show
			else
				status_strip.hide
			end
			store_to_settings
		end

	on_toggle_thumbnail
			-- Show or hide the last-capture thumbnail in the strip.
		do
			status_strip.set_thumbnail_visible (check_show_thumb.is_selected)
			store_to_settings
		end

	on_check_setup
			-- Run the runtime and model checks.
		do
			store_to_settings
			if attached on_check_setup_agent as al_agent then
				al_agent.call (Void)
			end
		end

	on_close
			-- Persist and quit.
		do
				-- Before anything else: these are separate topmost windows, and
				-- ones left showing after the application goes would have to be
				-- killed from Task Manager.
			hide_outlines
			store_to_settings
			if attached on_quit as al_agent then
				al_agent.call (Void)
			end
		end

feature -- Element change

	set_hotkey_changed_action (a_agent: PROCEDURE)
			-- Call `a_agent' when the hotkey needs re-registering.
		do
			on_hotkey_changed := a_agent
		end

	set_quit_action (a_agent: PROCEDURE)
			-- Call `a_agent' when the window is closed.
		do
			on_quit := a_agent
		end

	set_check_setup_action (a_agent: PROCEDURE)
			-- Call `a_agent' to verify the runtime and model.
		do
			on_check_setup_agent := a_agent
		end

	set_auto_start_action (a_agent: PROCEDURE)
			-- Call `a_agent' to begin or resume an unattended run.
		do
			on_auto_start_agent := a_agent
		end

	set_auto_pause_action (a_agent: PROCEDURE)
			-- Call `a_agent' to pause an unattended run.
		do
			on_auto_pause_agent := a_agent
		end

	set_auto_stop_action (a_agent: PROCEDURE)
			-- Call `a_agent' to stop an unattended run.
		do
			on_auto_stop_agent := a_agent
		end

	show_auto_state (a_running, a_paused: BOOLEAN)
			-- Reflect the driver's state in the transport buttons.
			--
			-- Start doubles as Resume, so it stays available while paused and
			-- goes dead only while a run is actually in flight.
		do
			button_auto_start.set_text (if a_paused then "Resume" else "Start" end)
			if a_running then
				button_auto_start.disable_sensitive
				button_auto_pause.enable_sensitive
				button_auto_stop.enable_sensitive
			elseif a_paused then
				button_auto_start.enable_sensitive
				button_auto_pause.disable_sensitive
				button_auto_stop.enable_sensitive
			else
				button_auto_start.enable_sensitive
				button_auto_pause.disable_sensitive
				button_auto_stop.disable_sensitive
			end
		end

feature {NONE} -- Helpers

	labelled (a_caption: READABLE_STRING_GENERAL; a_widget: EV_WIDGET): EV_HORIZONTAL_BOX
			-- `a_widget' preceded by a fixed-width caption.
		do
			Result := captioned (a_caption, a_widget, Label_width)
		end

	labelled_number (a_caption: READABLE_STRING_GENERAL; a_field: EV_TEXT_FIELD): EV_HORIZONTAL_BOX
			-- A captioned field sized for a NUMBER rather than stretched across
			-- the window.
			--
			-- "500" and "16384" do not read better in a box a thousand pixels
			-- wide; they only make the window need to be that wide.
		do
			a_field.set_minimum_width (Number_field_width)
			Result := captioned (a_caption, a_field, Label_width)
			Result.disable_item_expand (a_field)
			Result.extend (create {EV_CELL})
		end

	left_aligned (a_widget: EV_WIDGET): EV_HORIZONTAL_BOX
			-- `a_widget' at its natural width, packed to the left.
			--
			-- A widget put straight into a vertical box is stretched to the full
			-- width of the window. A button reading "Test Capture" is no easier
			-- to hit at 1,290 pixels wide, only harder to read, and every one of
			-- them forced the window wider than its content ever needed.
		do
			create Result
			Result.set_padding (Gap)
			Result.extend (a_widget)
			Result.disable_item_expand (a_widget)
			Result.extend (create {EV_CELL})
		end

	coordinate_row (a_x, a_y, a_w, a_h: EV_TEXT_FIELD): EV_HORIZONTAL_BOX
			-- The four rectangle fields on one line, packed left at a width that
			-- suits a screen coordinate.
			--
			-- Replaces three identical hand-built rows. Four coordinates never
			-- need the full width of the window between them, and sharing it
			-- equally gave each of them roughly 300 pixels to hold "166".
		do
			create Result
			Result.set_padding (Gap)
			add_coordinate (Result, "X", a_x)
			add_coordinate (Result, "Y", a_y)
			add_coordinate (Result, "W", a_w)
			add_coordinate (Result, "H", a_h)
			Result.extend (create {EV_CELL})
		end

	add_coordinate (a_row: EV_HORIZONTAL_BOX; a_caption: READABLE_STRING_GENERAL; a_field: EV_TEXT_FIELD)
			-- Append a captioned, fixed-width coordinate field to `a_row'.
		local
			l_cell: EV_HORIZONTAL_BOX
		do
			a_field.set_minimum_width (Coord_field_width)
			l_cell := captioned (a_caption, a_field, Narrow_label_width)
			l_cell.disable_item_expand (a_field)
			a_row.extend (l_cell)
			a_row.disable_item_expand (l_cell)
		end

	captioned (a_caption: READABLE_STRING_GENERAL; a_widget: EV_WIDGET; a_width: INTEGER): EV_HORIZONTAL_BOX
			-- `a_widget' preceded by `a_caption' occupying `a_width' pixels.
		local
			l_label: EV_LABEL
		do
			create Result
			Result.set_padding (Gap)
			create l_label.make_with_text (a_caption)
			l_label.set_minimum_width (a_width)
				-- Left-aligned: EV_LABEL centres by default, so a caption wider
				-- than its box loses characters from BOTH ends ("Image format"
				-- rendered as "nage forma").
			l_label.align_text_left
			Result.extend (l_label)
			Result.disable_item_expand (l_label)
			Result.extend (a_widget)
		end

	list_item (a_text: READABLE_STRING_GENERAL): EV_LIST_ITEM
		do
			create Result.make_with_text (a_text)
		end

	select_in_combo (a_combo: EV_COMBO_BOX; a_text: READABLE_STRING_GENERAL)
			-- Select the entry of `a_combo' whose text is `a_text'.
			--
			-- NOT `a_combo.set_text': on a combo with `disable_edit' that
			-- updates the displayed string without selecting anything, so
			-- reading `text' back later returns the FIRST entry instead. That is
			-- how a stored hotkey of G came back as A - the combo displayed "G"
			-- but reported "A" - and closing the window then persisted the
			-- wrong key.
		local
			i: INTEGER
			l_done: BOOLEAN
		do
			from
				i := 1
			until
				i > a_combo.count or l_done
			loop
				if a_combo.i_th (i).text.same_string_general (a_text) then
					a_combo.i_th (i).enable_select
					l_done := True
				end
				i := i + 1
			end
			if not l_done and then a_combo.count > 0 then
					-- Stored value is not on the list; fall back to the first
					-- entry so the display and the reported value still agree.
				a_combo.i_th (1).enable_select
			end
		end

	set_check (a_button: EV_CHECK_BUTTON; a_value: BOOLEAN)
		do
			if a_value then
				a_button.enable_select
			else
				a_button.disable_select
			end
		end

	integer_of (a_field: EV_TEXT_FIELD): INTEGER
			-- Numeric value of `a_field', 0 when it is not a number.
		do
			if a_field.text.is_integer then
				Result := a_field.text.to_integer
			end
		end

	two (a_value: INTEGER): STRING_8
			-- `a_value' as at least two digits.
		do
			Result := a_value.out
			if Result.count < 2 then
				Result.prepend ("0")
			end
		end

	narrowed (a_text: READABLE_STRING_GENERAL): STRING_8
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
		end

	show_preview (a_pixmap: EV_PIXMAP)
			-- Draw `a_pixmap' scaled into the preview area.
		local
			l_scaled: EV_PIXMAP
			l_w, l_h: INTEGER
			l_ratio: DOUBLE
		do
			l_ratio := (Preview_width / a_pixmap.width).min (Preview_height / a_pixmap.height)
			if l_ratio > 1.0 then
				l_ratio := 1.0
			end
			l_w := (a_pixmap.width * l_ratio).truncated_to_integer.max (1)
			l_h := (a_pixmap.height * l_ratio).truncated_to_integer.max (1)

			l_scaled := a_pixmap.twin
			l_scaled.stretch (l_w, l_h)

			preview.set_background_color (preview_backdrop)
			preview.clear
			preview.draw_pixmap (0, 0, l_scaled)
		end

	update_screen_label
		local
			l_capture: OCR_CAPTURE
		do
			create l_capture.make
			screen_label.set_text ("Screen: " + l_capture.screen_width.out + " x " + l_capture.screen_height.out)
		end

	populate_key_combo
			-- Offer letters and function keys.
		local
			i: INTEGER
		do
			from i := ('A').code until i > ('Z').code loop
				combo_key.extend (list_item (i.to_character_8.out))
				i := i + 1
			end
			from i := 1 until i > 12 loop
				combo_key.extend (list_item ("F" + i.out))
				i := i + 1
			end
		end

	key_name_for (a_code: NATURAL_32): STRING_32
			-- Display name of virtual key `a_code'.
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
			-- Virtual key code for display name `a_name'.
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

	preview_backdrop: EV_COLOR
		once
			create Result.make_with_8_bit_rgb (245, 245, 248)
		end

feature {NONE} -- Constants

		-- Display scaling: these are PHYSICAL pixels, one for one.
		--
		-- An earlier note here claimed Vision2 shrinks a set_size request to two
		-- thirds on a 150% display, and these numbers were inflated to
		-- compensate. That was a measurement error, not a Vision2 behaviour.
		-- The window was measured with a DPI-UNAWARE tool, which reports every
		-- coordinate divided by the scale factor - hence exactly 2/3 at 150%,
		-- "perfectly linear", which should have been the clue.
		--
		-- Measured again with SetProcessDPIAware first: a request of 1350 wide
		-- produced a window 1350 physical pixels wide. What you write here is
		-- what Windows creates. Do not add a scaling fudge.
	Window_width: INTEGER = 1000
	Window_height: INTEGER = 1200

	Label_width: INTEGER = 130
	Narrow_label_width: INTEGER = 16

	Coord_field_width: INTEGER = 74
			-- Enough for a five-digit screen coordinate. These used to share the
			-- window width four ways, giving each about 300 pixels to hold "166".

	Number_field_width: INTEGER = 110
			-- Enough for a timeout, a context size or a settle delay.

	Preview_width: INTEGER = 580
	Preview_height: INTEGER = 76
			-- Shows enough of a test capture to tell whether the region is
			-- aimed right, which is all it is for. It no longer expands, so this
			-- is its actual height rather than its minimum.

	Findings_height: INTEGER = 110
			-- Room for four or five rows. Enough that a problem appearing during
			-- a run is visible without scrolling, small enough that a quiet book
			-- does not pay much for it.

	Group_border: INTEGER = 6
	Gap: INTEGER = 4
			-- Group inset and inter-widget spacing. Were 8 and 6; the group
			-- count multiplies both, so a couple of pixels each is worth tens
			-- of pixels of window height.

feature {NONE} -- Widgets

		-- Declared self-initializing rather than as plain attributes. Void
		-- safety requires every attribute to be set by the end of the creation
		-- procedure, and the compiler cannot see through the build_* routines
		-- that actually create these, so plain declarations raise VEVI.

	root_box: EV_VERTICAL_BOX attribute create Result end
	field_x: EV_TEXT_FIELD attribute create Result end
	field_y: EV_TEXT_FIELD attribute create Result end
	field_w: EV_TEXT_FIELD attribute create Result end
	field_h: EV_TEXT_FIELD attribute create Result end
	field_folder: EV_TEXT_FIELD attribute create Result end
	field_text_name: EV_TEXT_FIELD attribute create Result end
	field_endpoint: EV_TEXT_FIELD attribute create Result end
	field_model: EV_TEXT_FIELD attribute create Result end
	field_timeout: EV_TEXT_FIELD attribute create Result end
	field_num_ctx: EV_TEXT_FIELD attribute create Result end
	context_hint: EV_LABEL attribute create Result end
	check_save_text: EV_CHECK_BUTTON attribute create Result end
	check_save_image: EV_CHECK_BUTTON attribute create Result end
	check_separators: EV_CHECK_BUTTON attribute create Result end
	check_show_strip: EV_CHECK_BUTTON attribute create Result end
	check_show_thumb: EV_CHECK_BUTTON attribute create Result end
	check_ctrl: EV_CHECK_BUTTON attribute create Result end
	check_alt: EV_CHECK_BUTTON attribute create Result end
	check_shift: EV_CHECK_BUTTON attribute create Result end
	combo_format: EV_COMBO_BOX attribute create Result end
	combo_key: EV_COMBO_BOX attribute create Result end
	preview: EV_DRAWING_AREA attribute create Result end
	status_label: EV_LABEL attribute create Result end
	screen_label: EV_LABEL attribute create Result end
	findings_list: EV_MULTI_COLUMN_LIST attribute create Result end
	check_outline_capture: EV_CHECK_BUTTON attribute create Result end
	check_outline_advance: EV_CHECK_BUTTON attribute create Result end
	check_outline_label: EV_CHECK_BUTTON attribute create Result end
	check_outline_all: EV_CHECK_BUTTON attribute create Result end

	is_syncing: BOOLEAN
			-- Are the outline checkboxes being set programmatically?

	outlines: OCR_OUTLINE_SET
			-- The desktop outlines for the three configured regions.
		attribute
			create Result.make (settings)
		end

feature {NONE} -- State

	settings: OCR_SETTINGS
	cycle: OCR_CYCLE
	status_strip: OCR_STATUS_STRIP
	region_selector: detachable OCR_REGION_SELECTOR
	on_hotkey_changed: detachable PROCEDURE
	on_quit: detachable PROCEDURE
	on_check_setup_agent: detachable PROCEDURE
	on_auto_start_agent: detachable PROCEDURE
	on_auto_pause_agent: detachable PROCEDURE
	on_auto_stop_agent: detachable PROCEDURE

	field_advance_x: EV_TEXT_FIELD attribute create Result end
	field_advance_y: EV_TEXT_FIELD attribute create Result end
	field_advance_w: EV_TEXT_FIELD attribute create Result end
	field_advance_h: EV_TEXT_FIELD attribute create Result end
	field_label_x: EV_TEXT_FIELD attribute create Result end
	field_label_y: EV_TEXT_FIELD attribute create Result end
	field_label_w: EV_TEXT_FIELD attribute create Result end
	field_label_h: EV_TEXT_FIELD attribute create Result end
	field_advance_delay: EV_TEXT_FIELD attribute create Result end
	auto_hint: EV_LABEL attribute create Result end
	button_auto_start: EV_BUTTON attribute create Result end
	button_auto_pause: EV_BUTTON attribute create Result end
	button_auto_stop: EV_BUTTON attribute create Result end

end
