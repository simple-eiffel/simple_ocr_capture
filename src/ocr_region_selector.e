note
	description: "[
		Snipping-Tool style region picker: drag a rectangle over a frozen image
		of the desktop.

		The desktop is captured ONCE and shown full-screen in a borderless
		topmost window, rather than made transparent. Two reasons: Vision2
		exposes no layered-window alpha, and freezing means the page cannot
		scroll or a tooltip pop up midway through the drag, so what you select
		is exactly what gets captured.

		The rubber band is drawn in XOR mode, so erasing it is just drawing it
		again. Repainting a 3840x2160 pixmap on every pointer motion would move
		tens of megabytes per frame and crawl.
	]"

class
	OCR_REGION_SELECTOR

create
	make

feature {NONE} -- Initialization

	make
			-- Prepare a selector.
		do
			create last_error.make_empty
		end

feature -- Access

	last_error: STRING_32
			-- Reason `start' could not run; empty when it could.

feature -- Basic operations

	start (a_on_done: PROCEDURE [detachable EV_RECTANGLE])
			-- Freeze the desktop, show it full-screen and let the user drag a
			-- rectangle. Calls `a_on_done' with the chosen rectangle in SCREEN
			-- coordinates, or with Void if cancelled with Escape or right-click.
		local
			l_capture: OCR_CAPTURE
			l_screen: EV_SCREEN
			l_window: EV_POPUP_WINDOW
		do
			last_error.wipe_out
			on_done := a_on_done

			create l_screen
			origin_x := l_screen.virtual_x
			origin_y := l_screen.virtual_y
			span_width := l_screen.virtual_width
			span_height := l_screen.virtual_height

			create l_capture.make
			frozen_desktop := l_capture.capture (origin_x, origin_y, span_width, span_height)

			if frozen_desktop = Void then
				last_error := {STRING_32} "Could not capture the desktop: "
				last_error.append (l_capture.last_error)
				a_on_done.call ([Void])
			else
				create area
				area.set_minimum_size (span_width, span_height)

				create l_window
				l_window.extend (area)
				l_window.set_size (span_width, span_height)
				l_window.set_position (origin_x, origin_y)
				window := l_window

				area.expose_actions.extend (agent on_expose)
				area.pointer_button_press_actions.extend (agent on_press)
				area.pointer_motion_actions.extend (agent on_motion)
				area.pointer_button_release_actions.extend (agent on_release)
				area.key_press_actions.extend (agent on_key)

				l_window.show
				area.set_focus
			end
		end

feature {NONE} -- Events

	on_expose (a_x, a_y, a_width, a_height: INTEGER)
			-- Paint the frozen desktop and the instruction banner.
		do
			if attached frozen_desktop as al_desktop then
				area.set_copy_mode
				area.draw_pixmap (0, 0, al_desktop)

				area.set_foreground_color (banner_background)
				area.fill_rectangle (0, 0, span_width, Banner_height)
				area.set_foreground_color (banner_text)
				area.draw_text (16, Banner_height - 9,
					{STRING_32} "Drag to select the capture region    |    Esc or right-click to cancel")
			end
		end

	on_press (a_x, a_y, a_button: INTEGER; a_x_tilt, a_y_tilt, a_pressure: DOUBLE; a_screen_x, a_screen_y: INTEGER)
			-- Anchor the rubber band, or cancel on right-click.
		do
			if a_button = 3 then
				finish (Void)
			elseif a_button = 1 then
				anchor_x := a_x
				anchor_y := a_y
				current_x := a_x
				current_y := a_y
				is_dragging := True
				has_band := False
				area.set_xor_mode
				area.set_foreground_color (band_colour)
			end
		end

	on_motion (a_x, a_y: INTEGER; a_x_tilt, a_y_tilt, a_pressure: DOUBLE; a_screen_x, a_screen_y: INTEGER)
			-- Move the rubber band.
		do
			if is_dragging then
				erase_band
				current_x := a_x
				current_y := a_y
				draw_band
			end
		end

	on_release (a_x, a_y, a_button: INTEGER; a_x_tilt, a_y_tilt, a_pressure: DOUBLE; a_screen_x, a_screen_y: INTEGER)
			-- Complete the selection.
		local
			l_rect: EV_RECTANGLE
		do
			if is_dragging and a_button = 1 then
				erase_band
				is_dragging := False
				current_x := a_x
				current_y := a_y
				area.set_copy_mode

				if band_width >= Minimum_extent and band_height >= Minimum_extent then
						-- Back to screen coordinates: the window sits at the
						-- virtual desktop origin, which is negative on a
						-- multi-monitor layout extending left of or above the
						-- primary display.
					create l_rect.make (origin_x + band_left, origin_y + band_top, band_width, band_height)
					finish (l_rect)
				else
						-- A stray click, not a drag.
					finish (Void)
				end
			end
		end

	on_key (a_key: EV_KEY)
			-- Cancel on Escape.
		do
			if a_key.code = {EV_KEY_CONSTANTS}.key_escape then
				finish (Void)
			end
		end

feature {NONE} -- Rubber band

	draw_band
			-- Draw the band in XOR mode.
		do
			if band_width > 0 and band_height > 0 then
				area.draw_rectangle (band_left, band_top, band_width, band_height)
				has_band := True
			end
		end

	erase_band
			-- Undraw the band. XOR is its own inverse, so this is the same call.
		do
			if has_band then
				area.draw_rectangle (band_left, band_top, band_width, band_height)
				has_band := False
			end
		end

	band_left: INTEGER
			-- Left edge, whichever way the drag went.
		do
			Result := anchor_x.min (current_x)
		end

	band_top: INTEGER
			-- Top edge, whichever way the drag went.
		do
			Result := anchor_y.min (current_y)
		end

	band_width: INTEGER
		do
			Result := (current_x - anchor_x).abs
		end

	band_height: INTEGER
		do
			Result := (current_y - anchor_y).abs
		end

feature {NONE} -- Implementation

	finish (a_rect: detachable EV_RECTANGLE)
			-- Tear down and report `a_rect'.
		do
			if attached window as al_window then
				al_window.hide
				al_window.destroy
			end
			frozen_desktop := Void
			if attached on_done as al_done then
				al_done.call ([a_rect])
			end
		end

	window: detachable EV_POPUP_WINDOW
			-- Full-screen host for the frozen desktop.

	area: EV_DRAWING_AREA
			-- Canvas showing the frozen desktop.
		attribute
			create Result
		end

	frozen_desktop: detachable EV_PIXMAP
			-- Snapshot of the desktop taken when selection began.

	on_done: detachable PROCEDURE [detachable EV_RECTANGLE]
			-- Continuation invoked with the result.

	origin_x, origin_y: INTEGER
			-- Top-left of the virtual desktop; negative on some layouts.

	span_width, span_height: INTEGER
			-- Size of the virtual desktop.

	anchor_x, anchor_y: INTEGER
			-- Where the drag started.

	current_x, current_y: INTEGER
			-- Where the pointer is now.

	is_dragging: BOOLEAN
			-- Is a drag in progress?

	has_band: BOOLEAN
			-- Is a band currently drawn (and therefore erasable)?

feature {NONE} -- Constants

	Minimum_extent: INTEGER = 8
			-- Below this a drag is treated as a stray click.

	Banner_height: INTEGER = 30

	band_colour: EV_COLOR
		once
			create Result.make_with_8_bit_rgb (255, 255, 255)
		end

	banner_background: EV_COLOR
		once
			create Result.make_with_8_bit_rgb (20, 22, 28)
		end

	banner_text: EV_COLOR
		once
			create Result.make_with_8_bit_rgb (235, 237, 242)
		end

invariant
	error_attached: last_error /= Void

end
