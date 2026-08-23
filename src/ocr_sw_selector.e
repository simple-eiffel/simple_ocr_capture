note
	description: "[
		Snipping-style region picker on the pure route. The desktop
		is grabbed ONCE (SW_SCREEN - the page cannot scroll or a
		tooltip pop mid-drag; what you see frozen is what you get),
		shown on SHELL_OVERLAY across the whole virtual screen, and
		painted with a full SW_PAINTER through the overlay's DC:
		the frozen image, a dim wash, the chosen band re-lit and
		stroked, and the instruction banner.

		Events arrive as overlay types (31 move / 32 down / 33 up /
		34 cancel / 35 expose) through the host window's
		set_on_shell_event seam - feed them to `handle_event'.
		Successor to the Vision2 OCR_REGION_SELECTOR.
	]"

class
	OCR_SW_SELECTOR

create
	make

feature {NONE} -- Initialization

	make
		do
			create last_error.make_empty
		end

feature -- Access

	last_error: STRING_32
			-- Reason `start' could not run; empty when it could.

	is_active: BOOLEAN
			-- Is the overlay up and listening?

feature -- Basic operations

	start (a_on_done: PROCEDURE [TUPLE [detachable TUPLE [x, y, w, h: INTEGER]]])
			-- Freeze the desktop and let the user drag. Calls
			-- `a_on_done' with the rectangle in SCREEN coordinates,
			-- or with Void on Escape / right-click / a dragless tap.
		require
			idle: not is_active
		local
			sc: SW_SCREEN
		do
			last_error.wipe_out
			on_done := a_on_done
			create sc
			origin_x := sc.virtual_x
			origin_y := sc.virtual_y
			span_w := sc.virtual_width
			span_h := sc.virtual_height
			snapshot := sc.grab (origin_x, origin_y, span_w, span_h)
			if snapshot = Void then
				last_error := {STRING_32} "Could not capture the desktop (locked session?)."
				a_on_done.call ([Void])
			else
				is_dragging := False
				overlay.show
				is_active := True
				paint
			end
		end

	handle_event (a_type, a_x, a_y: INTEGER)
			-- One overlay event from the shared queue (client
			-- coordinates). Call for types 31..35 while `is_active'.
		require
			active: is_active
		do
			inspect a_type
			when 32 then
				is_dragging := True
				anchor_x := a_x
				anchor_y := a_y
				cur_x := a_x
				cur_y := a_y
				paint
			when 31 then
				if is_dragging then
					cur_x := a_x
					cur_y := a_y
					paint
				end
			when 33 then
				if is_dragging then
					cur_x := a_x
					cur_y := a_y
					finish
				end
			when 34 then
				cancel
			when 35 then
				paint
			else
			end
		end

	cancel
			-- Take the overlay down and report nothing chosen.
		do
			if is_active then
				teardown
				if attached on_done as d then
					d.call ([Void])
				end
			end
		ensure
			idle: not is_active
		end

feature -- Measurement (the pure band law, assaultable headless)

	band_x: INTEGER
		do
			Result := anchor_x.min (cur_x)
		end

	band_y: INTEGER
		do
			Result := anchor_y.min (cur_y)
		end

	band_w: INTEGER
		do
			Result := (anchor_x - cur_x).abs
		end

	band_h: INTEGER
		do
			Result := (anchor_y - cur_y).abs
		end

	is_band_usable: BOOLEAN
			-- A dragless tap is a cancel, not a 1x1 region.
		do
			Result := band_w >= Min_side and band_h >= Min_side
		end

	Min_side: INTEGER = 3

	normalized_band (a_ax, a_ay, a_cx, a_cy: INTEGER): TUPLE [x, y, w, h: INTEGER]
			-- The rectangle a drag from (a_ax, a_ay) to (a_cx, a_cy)
			-- names, whichever way the hand moved. Pure - the
			-- assault drives it with bare numbers.
		do
			Result := [a_ax.min (a_cx), a_ay.min (a_cy),
				(a_ax - a_cx).abs, (a_ay - a_cy).abs]
		ensure
			positive: Result.w >= 0 and Result.h >= 0
		end

	is_usable_band (a_w, a_h: INTEGER): BOOLEAN
			-- The tap-is-cancel law, stated purely.
		do
			Result := a_w >= Min_side and a_h >= Min_side
		end

feature {NONE} -- Implementation

	finish
			-- Accept the band: screen coordinates out, overlay down.
		local
			rx, ry, rw, rh: INTEGER
		do
			rx := band_x + origin_x
			ry := band_y + origin_y
			rw := band_w
			rh := band_h
			if is_band_usable then
				teardown
				if attached on_done as d then
					d.call ([[rx, ry, rw, rh]])
				end
			else
				cancel
			end
		ensure
			idle: not is_active
		end

	teardown
		do
			overlay.hide
			if attached snapshot as fz then
				fz.destroy
				snapshot := Void
			end
			is_active := False
			is_dragging := False
		ensure
			idle: not is_active
		end

	paint
			-- The frozen desktop, a dim wash, the band re-lit and
			-- stroked, the banner - all through the overlay's DC.
		local
			dc: POINTER
			ws: CAIRO_SURFACE
			ctx: CAIRO_CONTEXT
			p: SW_PAINTER
			th: SW_THEME
			msg: STRING_32
			mw: REAL_64
		do
			dc := overlay.dc
			if dc /= default_pointer then
				create ws.make_for_dc (dc)
				if ws.is_valid and attached snapshot as fz then
					create ctx.make (ws)
					create th.make_dark
					create p.make (ctx, th)
					ctx.set_source_surface (fz, 0.0, 0.0).paint.do_nothing
					p.set_color_alpha (0x000000, 0.35)
					p.fill_rect (0.0, 0.0, span_w, span_h)
					if is_dragging and then band_w > 0 and then band_h > 0 then
							-- the band re-lit: the frozen image again,
							-- clipped to the choice
						p.push_clip (band_x, band_y, band_w, band_h)
						ctx.set_source_surface (fz, 0.0, 0.0).paint.do_nothing
						p.pop_clip
						p.set_color (th.accent)
						p.set_line_width (2.0)
						p.rrect_stroke (band_x - 1.0, band_y - 1.0, band_w + 2.0, band_h + 2.0, 1.0)
						p.set_line_width (1.0)
					end
					create msg.make_from_string_general ("Drag a rectangle; Esc or right-click cancels.")
					p.font ({SW_PAINTER}.Role_ui, 14.0, True)
					mw := p.advance (msg) + 28.0
					p.set_color_alpha (0x000000, 0.72)
					p.rrect_fill ((span_w - mw) / 2.0, 18.0, mw, 34.0, 6.0)
					p.set_color (0xFFFFFF)
					p.text ((span_w - mw) / 2.0 + 14.0, 41.0, msg)
					ctx.destroy
				end
				ws.destroy
				overlay.release_dc (dc)
			end
		end

	overlay: SHELL_OVERLAY
		once
			create Result
		end

	on_done: detachable PROCEDURE [TUPLE [detachable TUPLE [x, y, w, h: INTEGER]]]

	snapshot: detachable CAIRO_SURFACE

	origin_x, origin_y, span_w, span_h: INTEGER

	is_dragging: BOOLEAN

	anchor_x, anchor_y, cur_x, cur_y: INTEGER

end
