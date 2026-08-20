note
	description: "[
		Always-on-top progress strip showing where a capture cycle has got to.

		Built on EV_POPUP_WINDOW for two properties the ordinary window class
		does not offer: its Windows implementation sets WS_EX_TOPMOST, so the
		strip stays visible over a full-screen PDF reader, and it is borderless
		and absent from the taskbar.

		`disconnect_from_window_manager' is essential, not cosmetic: without it
		the strip takes focus when shown, which would pull focus away from the
		document being read on every single capture.
	]"

class
	OCR_STATUS_STRIP

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
			-- Build the strip, positioned per `a_settings'.
		do
			settings := a_settings
			stage := Stage_idle
			show_thumbnail := a_settings.show_thumbnail
			create message.make_from_string ("READY")

			create window
				-- Must precede `show'; cannot be called afterwards.
			window.disconnect_from_window_manager

			create area
			area.set_minimum_size (Strip_width, Strip_height)
			window.extend (area)
			window.set_size (Strip_width, Strip_height)
			window.set_position (a_settings.strip_x, a_settings.strip_y)

			area.expose_actions.extend (agent on_expose)
			area.pointer_button_press_actions.extend (agent on_press)
			area.pointer_motion_actions.extend (agent on_motion)
			area.pointer_button_release_actions.extend (agent on_release)
		end

feature -- Access

	stage: INTEGER
			-- Current cycle stage, `Stage_idle' through `Stage_ready'.

	message: STRING_32
			-- Caption shown beside the lights.

feature -- Status report

	is_displayed: BOOLEAN
			-- Is the strip on screen?
		do
			Result := window.is_displayed
		end

feature -- Basic operations

	show
			-- Display the strip.
		do
			window.show
		end

	hide
			-- Remove the strip from the screen.
		do
			window.hide
		end

	set_stage (a_stage: INTEGER; a_message: READABLE_STRING_GENERAL)
			-- Advance to `a_stage', captioned `a_message', and repaint.
		require
			in_range: a_stage >= Stage_idle and a_stage <= Stage_ready
		do
			stage := a_stage
			create message.make_from_string_general (a_message)
			refresh
		ensure
			stage_set: stage = a_stage
		end

	set_thumbnail (a_pixmap: detachable EV_PIXMAP)
			-- Show `a_pixmap' beneath the lights, resizing to fit it.
			-- Void clears the panel.
		do
			thumbnail := a_pixmap
			resize_to_content
			refresh
		end

	set_thumbnail_visible (a_flag: BOOLEAN)
			-- Show or hide the thumbnail panel.
		do
			show_thumbnail := a_flag
			resize_to_content
			refresh
		ensure
			set: show_thumbnail = a_flag
		end

	ensure_visible
			-- Put the strip back on screen if it has gone, without moving it
			-- unless its position is unusable.
			--
			-- Called from the timer. The strip went missing during a live run
			-- and could not be recovered from the interface at all - the
			-- checkbox still said it was on, and it was not. The cause was never
			-- identified, so this does not try to address one: it simply checks
			-- the invariant "the strip should be showing" and repairs it.
			--
			-- Cheap enough to poll: `is_displayed' is a field read.
		local
			l_screen: EV_SCREEN
			l_x, l_y: INTEGER
		do
			create l_screen
			l_x := window.x_position
			l_y := window.y_position

				-- A position outside the desktop is "shown" and invisible, which
				-- looks exactly like the window having vanished. A monitor
				-- unplugged or a resolution change is enough to cause it.
			if l_x < l_screen.virtual_x
				or l_x > l_screen.virtual_x + l_screen.virtual_width - Recovery_margin
				or l_y < l_screen.virtual_y
				or l_y > l_screen.virtual_y + l_screen.virtual_height - Recovery_margin
			then
				l_x := l_screen.virtual_x + Recovery_inset
				l_y := l_screen.virtual_y + Recovery_inset
				window.set_position (l_x, l_y)
				settings.set_strip_position (l_x, l_y)
			end

			if not window.is_displayed then
				window.show
				refresh
			end
		end

	restore_to_default
			-- Force the strip back to a known-good place and show it.
			--
			-- The deliberate "I cannot find it" recovery. Unlike `ensure_visible'
			-- this always MOVES the strip, because a user pressing this button
			-- has already failed to find it where it was.
		local
			l_screen: EV_SCREEN
			l_x, l_y: INTEGER
		do
			create l_screen
			l_x := l_screen.virtual_x + Recovery_inset
			l_y := l_screen.virtual_y + Recovery_inset
			resize_to_content
			window.set_position (l_x, l_y)
			if not window.is_displayed then
				window.show
			end
			settings.set_strip_position (l_x, l_y)
			settings.store
			refresh
		ensure
			on_screen: is_displayed
		end

	refresh
			-- Repaint immediately.
		do
			if window.is_displayed then
				on_expose (0, 0, current_width, current_height)
			end
		end

feature -- Page caption

	page_caption: STRING_32
			-- Which page the thumbnail shows; empty when unknown.
		attribute
			create Result.make_empty
		end

	set_page_caption (a_text: READABLE_STRING_GENERAL)
			-- Show `a_text' beneath the thumbnail.
		do
			create page_caption.make_from_string_general (a_text)
				-- Resizes as well as repaints: the caption adds a line the strip
				-- has no room for until it is asked to grow.
			resize_to_content
			refresh
		ensure
			set: page_caption.same_string_general (a_text)
		end

	metrics_caption: STRING_32
			-- Rate and ETA for the run in progress; empty when there is none.
		attribute
			create Result.make_empty
		end

	set_metrics_caption (a_text: READABLE_STRING_GENERAL)
			-- Show `a_text' beneath the page caption.
			--
			-- On the strip rather than only in the settings window, because the
			-- settings window is behind the reader for the whole of an
			-- unattended run. The strip is the only thing actually on screen,
			-- so it is where a progress figure has to be to be read at all.
		do
			create metrics_caption.make_from_string_general (a_text)
			resize_to_content
			refresh
		ensure
			set: metrics_caption.same_string_general (a_text)
		end

feature -- Auto-advance transport

	set_transport_action (a_agent: PROCEDURE [INTEGER])
			-- Call `a_agent' with `Transport_play', `Transport_pause' or
			-- `Transport_stop' when the matching glyph is pressed.
		do
			on_transport_agent := a_agent
		end

	set_transport_state (a_running, a_paused: BOOLEAN)
			-- Show whether an unattended run is going, so the glyphs read as
			-- state and not merely as buttons.
		do
			is_auto_running := a_running
			is_auto_paused := a_paused
			refresh
		ensure
			running_set: is_auto_running = a_running
			paused_set: is_auto_paused = a_paused
		end

	is_auto_running: BOOLEAN
			-- Is an unattended run in progress?

	is_auto_paused: BOOLEAN
			-- Is an unattended run suspended?

feature {NONE} -- Transport painting

	transport_left (a_index: INTEGER): INTEGER
			-- Left edge of glyph `a_index', laid out from the right-hand end.
		require
			in_range: a_index >= 1 and a_index <= 3
		do
			Result := current_width - Transport_margin - 3 * Transport_size - 2 * Transport_gap
				+ (a_index - 1) * (Transport_size + Transport_gap)
		end

	draw_transport
			-- Paint the play, pause and stop glyphs.
		local
			l_left, i, l_bar: INTEGER
		do
				-- Play: a right-pointing triangle built from vertical segments.
				-- Drawn rather than filled as a polygon because a run of segments
				-- needs no coordinate array and cannot be got subtly wrong.
			l_left := transport_left (Transport_play)
			area.set_foreground_color (transport_colour (not is_auto_running))
			from
				i := 0
			until
				i >= Transport_size
			loop
				area.draw_segment (l_left + i, Transport_top + i // 2,
					l_left + i, Transport_top + Transport_size - i // 2)
				i := i + 1
			end

				-- Pause: two upright bars.
			l_left := transport_left (Transport_pause)
			area.set_foreground_color (transport_colour (is_auto_running))
			l_bar := (Transport_size - 4) // 2
			area.fill_rectangle (l_left, Transport_top, l_bar, Transport_size)
			area.fill_rectangle (l_left + l_bar + 4, Transport_top, l_bar, Transport_size)

				-- Stop: a square.
			l_left := transport_left (Transport_stop)
			area.set_foreground_color (transport_colour (is_auto_running or is_auto_paused))
			area.fill_rectangle (l_left, Transport_top, Transport_size, Transport_size)
		end

	transport_colour (a_live: BOOLEAN): EV_COLOR
			-- Bright when the glyph is worth pressing, dim when it is not.
		do
			if a_live then
				create Result.make_with_8_bit_rgb (210, 210, 210)
			else
				create Result.make_with_8_bit_rgb (90, 90, 90)
			end
		end

	on_transport_agent: detachable PROCEDURE [INTEGER]

feature -- Measurement

	current_width: INTEGER
			-- Width the strip needs right now.
			--
			-- The captions are MEASURED, not assumed to fit. The rates line
			-- changes length with the numbers in it, and a fixed width clipped
			-- it: "ETA 25m" rendered as "ETA 25", which does not read as a
			-- truncation - it reads as a different value. A number that silently
			-- loses its unit is worse than one that is not shown.
		do
			Result := Strip_width
			if has_visible_thumbnail and then attached thumbnail as al_thumb then
				Result := Result.max (al_thumb.width + 2 * Thumb_margin)
			end
			Result := Result.max (caption_width (page_caption))
			across metrics_lines as ic_line loop
					-- `ic_line', not `ic_line.item': across binds the ITEM here,
					-- so the cursor form resolves to STRING_32's character-at-index
					-- and fails VUAR(1) complaining about a missing argument.
				Result := Result.max (caption_width (ic_line))
			end
		ensure
			at_least_minimum: Result >= Strip_width
		end

	metrics_lines: LIST [STRING_32]
			-- `metrics_caption' broken into display lines.
			--
			-- Guarded against the empty case: `split' on an empty string yields
			-- a list of ONE empty item, which would reserve a blank row on the
			-- strip for a run that has not started.
		do
			if metrics_caption.is_empty then
				create {ARRAYED_LIST [STRING_32]} Result.make (0)
			else
				Result := metrics_caption.split ('%N')
			end
		ensure
			attached_result: Result /= Void
		end

	caption_width (a_text: READABLE_STRING_32): INTEGER
			-- Width the strip needs to show `a_text' as a caption line.
		do
			if not a_text.is_empty and then not area.font.is_destroyed then
				Result := Caption_left + area.font.string_width (a_text) + Thumb_margin
			end
		ensure
			not_negative: Result >= 0
		end

	current_height: INTEGER
			-- Height the strip needs right now.
			--
			-- The captions are counted OUTSIDE the thumbnail test. They used to
			-- be inside it, so switching the thumbnail off also silently hid the
			-- page number and would now hide the rates - the two things most
			-- worth reading when the picture is turned off to save space.
		do
			Result := Strip_height + thumbnail_extent
			if not page_caption.is_empty then
				Result := Result + Caption_height
			end
			Result := Result + metrics_lines.count * Caption_height
		ensure
			at_least_minimum: Result >= Strip_height
		end

	thumbnail_extent: INTEGER
			-- Vertical space the thumbnail claims, margins included; zero when
			-- there is none or the panel is switched off.
		do
			if has_visible_thumbnail and then attached thumbnail as al_thumb then
				Result := al_thumb.height + 2 * Thumb_margin
			end
		ensure
			not_negative: Result >= 0
		end

	caption_top: INTEGER
			-- Y of the first caption line.
		do
			Result := Strip_height
			if has_visible_thumbnail and then attached thumbnail as al_thumb then
				Result := Result + al_thumb.height
			end
		end

	has_visible_thumbnail: BOOLEAN
			-- Is there a thumbnail, and is the panel switched on?
		do
			Result := show_thumbnail and thumbnail /= Void
		end

feature -- Constants

	Stage_idle: INTEGER = 0
	Stage_started: INTEGER = 1
	Stage_captured: INTEGER = 2
	Stage_ocr: INTEGER = 3
	Stage_written: INTEGER = 4
	Stage_ready: INTEGER = 5

	Strip_width: INTEGER = 320
			-- Wider than the lights and caption need, to make room for the
			-- transport glyphs at the right-hand end.

	Strip_height: INTEGER = 34

	Transport_play: INTEGER = 1
	Transport_pause: INTEGER = 2
	Transport_stop: INTEGER = 3

feature {NONE} -- Painting

	on_expose (a_x, a_y, a_width, a_height: INTEGER)
			-- Repaint the strip.
		local
			i, l_cx: INTEGER
			l_w, l_h: INTEGER
			l_y, l_left: INTEGER
		do
			l_w := current_width
			l_h := current_height

			area.set_background_color (colour_backdrop)
			area.set_foreground_color (colour_backdrop)
			area.fill_rectangle (0, 0, l_w, l_h)

			area.set_foreground_color (colour_border)
			area.draw_rectangle (0, 0, l_w - 1, l_h - 1)

			l_left := Thumb_margin
			if has_visible_thumbnail and then attached thumbnail as al_thumb then
					-- Centred under the lights, with a hairline frame so the
					-- page edge is distinguishable from the strip background.
				l_cx := (l_w - al_thumb.width) // 2
				l_left := l_cx
				area.draw_pixmap (l_cx, Strip_height, al_thumb)
				area.set_foreground_color (colour_border)
				area.draw_rectangle (l_cx - 1, Strip_height - 1,
					al_thumb.width + 1, al_thumb.height + 1)
			end

				-- Which page this picture is, and how fast the run is going,
				-- written directly beneath it. One glance at the strip answers
				-- "what is it working on, and how long left?" without going near
				-- the settings window - which spends an unattended run hidden
				-- behind the reader, where nothing on it can be read.
			l_y := caption_top
			if not page_caption.is_empty then
				area.set_foreground_color (colour_text)
				area.draw_text (Caption_left, l_y + Caption_baseline, page_caption)
				l_y := l_y + Caption_height
			end
			area.set_foreground_color (colour_metrics)
			across metrics_lines as ic_line loop
				area.draw_text (Caption_left, l_y + Caption_baseline, ic_line)
				l_y := l_y + Caption_height
			end

				-- Five lights, filling left to right as the cycle advances.
			from
				i := 1
			until
				i > 5
			loop
				l_cx := Light_left + (i - 1) * Light_pitch
				area.set_foreground_color (colour_for_light (i))
				area.fill_ellipse (l_cx, Light_top, Light_size, Light_size)
				area.set_foreground_color (colour_border)
				area.draw_ellipse (l_cx, Light_top, Light_size, Light_size)
				i := i + 1
			end

			area.set_foreground_color (colour_text)
			area.draw_text (Light_left + 5 * Light_pitch + 8, Strip_height - 11, message)

			draw_transport
		end

	colour_for_light (a_index: INTEGER): EV_COLOR
			-- Colour of light `a_index' at the current stage.
		require
			in_range: a_index >= 1 and a_index <= 5
		do
			if stage = Stage_ready then
				Result := colour_ready
			elseif a_index < stage then
				Result := colour_done
			elseif a_index = stage then
				Result := colour_active
			else
				Result := colour_pending
			end
		ensure
			attached_result: Result /= Void
		end

feature {NONE} -- Dragging

	on_press (a_x, a_y, a_button: INTEGER; a_x_tilt, a_y_tilt, a_pressure: DOUBLE; a_screen_x, a_screen_y: INTEGER)
			-- Press a transport glyph, or begin dragging the strip.
		local
			l_hit: INTEGER
		do
			if a_button = 1 then
				l_hit := transport_at (a_x, a_y)
					-- Tested before dragging starts: the glyphs sit inside the
					-- same drawing area that moves the window, so a press that
					-- lands on one must not also become a drag.
				if l_hit /= 0 then
					if attached on_transport_agent as al_agent then
						al_agent.call ([l_hit])
					end
				else
					is_dragging := True
						-- Remember the grab offset so the strip does not jump.
					drag_offset_x := a_screen_x - window.x_position
					drag_offset_y := a_screen_y - window.y_position
				end
			end
		end

	transport_at (a_x, a_y: INTEGER): INTEGER
			-- Which transport glyph is at (`a_x', `a_y')? Zero for none.
		local
			i, l_left: INTEGER
		do
			if a_y >= Transport_top and a_y <= Transport_top + Transport_size then
				from
					i := 1
				until
					i > 3 or Result /= 0
				loop
					l_left := transport_left (i)
					if a_x >= l_left and a_x <= l_left + Transport_size then
						Result := i
					end
					i := i + 1
				end
			end
		ensure
			known: Result >= 0 and Result <= 3
		end

	on_motion (a_x, a_y: INTEGER; a_x_tilt, a_y_tilt, a_pressure: DOUBLE; a_screen_x, a_screen_y: INTEGER)
			-- Move the strip with the pointer.
		do
			if is_dragging then
				window.set_position (a_screen_x - drag_offset_x, a_screen_y - drag_offset_y)
			end
		end

	on_release (a_x, a_y, a_button: INTEGER; a_x_tilt, a_y_tilt, a_pressure: DOUBLE; a_screen_x, a_screen_y: INTEGER)
			-- Finish dragging and remember where the strip landed.
		do
			if is_dragging then
				is_dragging := False
				settings.set_strip_position (window.x_position, window.y_position)
				settings.store
			end
		end

	resize_to_content
			-- Grow or shrink the window to fit the lights plus any thumbnail.
		local
			l_w, l_h: INTEGER
		do
			l_w := current_width
			l_h := current_height
			area.set_minimum_size (l_w, l_h)
			window.set_size (l_w, l_h)
		end

	thumbnail: detachable EV_PIXMAP
			-- Scaled image of the most recent capture.

	show_thumbnail: BOOLEAN
			-- Is the thumbnail panel switched on?

	is_dragging: BOOLEAN
			-- Is the user moving the strip?

	drag_offset_x, drag_offset_y: INTEGER
			-- Pointer position within the strip when the drag began.

feature {NONE} -- Colours

	colour_backdrop: EV_COLOR
		once
			create Result.make_with_8_bit_rgb (32, 34, 40)
		end

	colour_border: EV_COLOR
		once
			create Result.make_with_8_bit_rgb (90, 94, 104)
		end

	colour_text: EV_COLOR
		once
			create Result.make_with_8_bit_rgb (228, 230, 236)
		end

	colour_metrics: EV_COLOR
			-- Dimmer than `colour_text': the rates are secondary to the page
			-- number directly above them, and should not compete with it.
		once
			create Result.make_with_8_bit_rgb (150, 200, 165)
		end

	colour_pending: EV_COLOR
		once
			create Result.make_with_8_bit_rgb (60, 63, 72)
		end

	colour_done: EV_COLOR
		once
			create Result.make_with_8_bit_rgb (70, 130, 220)
		end

	colour_active: EV_COLOR
		once
			create Result.make_with_8_bit_rgb (240, 175, 60)
		end

	colour_ready: EV_COLOR
		once
			create Result.make_with_8_bit_rgb (70, 200, 110)
		end

feature {NONE} -- Layout constants

	Transport_size: INTEGER = 12
	Transport_gap: INTEGER = 7
	Transport_margin: INTEGER = 10
	Transport_top: INTEGER = 11

	Light_left: INTEGER = 12
	Light_top: INTEGER = 11
	Light_size: INTEGER = 12
	Light_pitch: INTEGER = 18
	Thumb_margin: INTEGER = 6

	Recovery_inset: INTEGER = 40
			-- Where the strip is put when it has to be rescued: just inside the
			-- top-left of the virtual desktop, which exists on every layout.

	Recovery_margin: INTEGER = 60
			-- How much of the strip must remain on the desktop for its position
			-- to count as usable. Less than this and it is unfindable.

	Caption_left: INTEGER = 8
			-- Left inset of every caption line.
			--
			-- Fixed rather than aligned to the thumbnail. Centring the captions
			-- on the picture made the width they need depend on the width of the
			-- strip, which depends on the width they need.

	Caption_height: INTEGER = 17
			-- Extra strip height claimed by the page caption line.

	Caption_baseline: INTEGER = 18
			-- Text baseline below the bottom of the thumbnail.

feature {NONE} -- Implementation

	window: EV_POPUP_WINDOW
			-- Borderless, topmost, non-focusing host window.

	area: EV_DRAWING_AREA
			-- Canvas the lights are painted on.

	settings: OCR_SETTINGS
			-- Shared configuration; receives the strip position on drop.

invariant
	stage_in_range: stage >= Stage_idle and stage <= Stage_ready
	message_attached: message /= Void

end
