note
	description: "[
		Snipping-style region picker on the pure route. The desktop
		is grabbed ONCE (SW_SCREEN - the page cannot scroll or a
		tooltip pop mid-drag; what you see frozen is what you get),
		shown on SHELL_OVERLAY across the whole virtual screen, and
		painted with a full SW_PAINTER through the overlay's DC:
		the frozen image, a dim wash, the chosen band re-lit and
		stroked, and the instruction banner.

		A drag does not commit any more - it opens ADJUST mode: the
		band grows eight handles (corners and edge middles), its
		interior drags the whole box, arrows nudge by a pixel
		(Shift+arrows resize), and Enter or the Apply button
		accepts. `start_adjusting' opens straight onto an existing
		box, so micro-adjusting a set region never needs the long
		redraw that motivated all of this. A drag begun outside the
		box replaces it - unless it turns out a mis-tap, which
		restores the box instead of losing it.

		Events arrive as overlay types (31 move / 32 down / 33 up /
		34 cancel / 35 expose / 36 accept / 37 arrow) through the
		host window's set_on_shell_event seam - feed them to
		`handle_event'. Successor to the Vision2 OCR_REGION_SELECTOR.
	]"

class
	OCR_SW_SELECTOR

create
	make

feature {NONE} -- Initialization

	make
		do
			create last_error.make_empty
			create keys
		end

feature -- Access

	last_error: STRING_32
			-- Reason `start' could not run; empty when it could.

	is_active: BOOLEAN
			-- Is the overlay up and listening?

	is_adjusting: BOOLEAN
			-- Is a band up with its handles, awaiting Enter/Apply?

feature -- Basic operations

	start (a_on_done: PROCEDURE [TUPLE [detachable TUPLE [x, y, w, h: INTEGER]]])
			-- Freeze the desktop and let the user drag a fresh box.
			-- Calls `a_on_done' with the rectangle in SCREEN
			-- coordinates, or with Void on Escape / right-click / a
			-- dragless tap.
		require
			idle: not is_active
		do
			if open_overlay (a_on_done) then
				paint
			end
		end

	start_adjusting (a_x, a_y, a_w, a_h: INTEGER;
			a_on_done: PROCEDURE [TUPLE [detachable TUPLE [x, y, w, h: INTEGER]]])
			-- Freeze the desktop with an existing SCREEN-coordinate
			-- box already up in adjust mode - handles, nudges, Enter.
			-- The long redraw of a big region becomes a nudge.
		require
			idle: not is_active
			usable: a_w >= Min_side and a_h >= Min_side
		do
			if open_overlay (a_on_done) then
				adj_x := a_x - origin_x
				adj_y := a_y - origin_y
				adj_w := a_w.min (span_w)
				adj_h := a_h.min (span_h)
				clamp_adjust_to_span
				is_adjusting := True
				paint
			end
		ensure
			adjusting_when_up: is_active implies is_adjusting
		end

	handle_event (a_type, a_x, a_y: INTEGER)
			-- One overlay event from the shared queue (client
			-- coordinates). Call for types 31..37 while `is_active'.
		require
			active: is_active
		do
			inspect a_type
			when 32 then
				on_down (a_x, a_y)
			when 31 then
				on_move (a_x, a_y)
			when 33 then
				on_up (a_x, a_y)
			when 34 then
				cancel
			when 36 then
				if is_adjusting then
					finish_adjusted
				end
			when 37 then
				if is_adjusting then
					nudge (a_x)
				end
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

feature -- Measurement (the pure handle law, assaultable headless)

	Handle_grasp: INTEGER = 10
			-- Half-width of a grab point's catch area.

	handle_index_at (a_px, a_py, a_bx, a_by, a_bw, a_bh: INTEGER): INTEGER
			-- Which grab point of the box (a_bx, a_by, a_bw, a_bh) is
			-- under (a_px, a_py): corners 1 TL, 3 TR, 5 BR, 7 BL;
			-- edge middles 2 top, 4 right, 6 bottom, 8 left;
			-- 9 inside (move the whole box); 0 none. Corners outrank
			-- middles, handles outrank the interior. Pure.
		do
			if near (a_px, a_py, a_bx, a_by) then
				Result := 1
			elseif near (a_px, a_py, a_bx + a_bw, a_by) then
				Result := 3
			elseif near (a_px, a_py, a_bx + a_bw, a_by + a_bh) then
				Result := 5
			elseif near (a_px, a_py, a_bx, a_by + a_bh) then
				Result := 7
			elseif near (a_px, a_py, a_bx + a_bw // 2, a_by) then
				Result := 2
			elseif near (a_px, a_py, a_bx + a_bw, a_by + a_bh // 2) then
				Result := 4
			elseif near (a_px, a_py, a_bx + a_bw // 2, a_by + a_bh) then
				Result := 6
			elseif near (a_px, a_py, a_bx, a_by + a_bh // 2) then
				Result := 8
			elseif a_px >= a_bx and a_px <= a_bx + a_bw
				and a_py >= a_by and a_py <= a_by + a_bh
			then
				Result := 9
			end
		ensure
			known: Result >= 0 and Result <= 9
		end

	adjusted_band (a_handle, a_bx, a_by, a_bw, a_bh, a_dx, a_dy: INTEGER): TUPLE [x, y, w, h: INTEGER]
			-- The box after grab point `a_handle' moves by
			-- (a_dx, a_dy): corners move their two edges, middles
			-- their one, 9 carries the whole box. An edge can never
			-- cross to within Min_side of its opposite - the pull
			-- clamps, so micro-adjustment cannot destroy the box. Pure.
		require
			a_grab_point: a_handle >= 1 and a_handle <= 9
			a_box: a_bw >= Min_side and a_bh >= Min_side
		local
			l, t, r, b: INTEGER
		do
			l := a_bx
			t := a_by
			r := a_bx + a_bw
			b := a_by + a_bh
			if a_handle = 9 then
				Result := [l + a_dx, t + a_dy, a_bw, a_bh]
			else
				if a_handle = 1 or a_handle = 7 or a_handle = 8 then
					l := (l + a_dx).min (r - Min_side)
				end
				if a_handle = 3 or a_handle = 4 or a_handle = 5 then
					r := (r + a_dx).max (l + Min_side)
				end
				if a_handle = 1 or a_handle = 2 or a_handle = 3 then
					t := (t + a_dy).min (b - Min_side)
				end
				if a_handle = 5 or a_handle = 6 or a_handle = 7 then
					b := (b + a_dy).max (t + Min_side)
				end
				Result := [l, t, r - l, b - t]
			end
		ensure
			never_degenerate: Result.w >= Min_side and Result.h >= Min_side
			move_preserves_size: a_handle = 9 implies
				(Result.w = a_bw and Result.h = a_bh)
		end

feature {NONE} -- The mouse in adjust mode

	on_down (a_x, a_y: INTEGER)
		local
			k: INTEGER
		do
			if is_adjusting then
				if in_button (a_x, a_y, apply_bx, apply_by, apply_bw) then
					finish_adjusted
				elseif in_button (a_x, a_y, cancel_bx, cancel_by, cancel_bw) then
					cancel
				else
					k := handle_index_at (a_x, a_y, adj_x, adj_y, adj_w, adj_h)
					if k > 0 then
						active_handle := k
						grab_x := a_x
						grab_y := a_y
					else
							-- outside the box: begin a replacing drag,
							-- but remember the box - a mis-tap must
							-- restore it, not lose it
						saved_x := adj_x
						saved_y := adj_y
						saved_w := adj_w
						saved_h := adj_h
						has_saved := True
						is_adjusting := False
						begin_drag (a_x, a_y)
					end
				end
			else
				begin_drag (a_x, a_y)
			end
		end

	on_move (a_x, a_y: INTEGER)
		local
			nb: TUPLE [x, y, w, h: INTEGER]
		do
			if is_adjusting and active_handle > 0 then
				nb := adjusted_band (active_handle, adj_x, adj_y, adj_w, adj_h,
					a_x - grab_x, a_y - grab_y)
				adj_x := nb.x
				adj_y := nb.y
				adj_w := nb.w
				adj_h := nb.h
				clamp_adjust_to_span
				grab_x := a_x
				grab_y := a_y
				paint
			elseif is_dragging then
				cur_x := a_x
				cur_y := a_y
				paint
			end
		end

	on_up (a_x, a_y: INTEGER)
		do
			if is_adjusting and active_handle > 0 then
				active_handle := 0
				paint
			elseif is_dragging then
				cur_x := a_x
				cur_y := a_y
				is_dragging := False
				if is_band_usable then
					adj_x := band_x
					adj_y := band_y
					adj_w := band_w
					adj_h := band_h
					has_saved := False
					is_adjusting := True
					paint
				elseif has_saved then
						-- the drag was a mis-tap: the box comes back
					adj_x := saved_x
					adj_y := saved_y
					adj_w := saved_w
					adj_h := saved_h
					has_saved := False
					is_adjusting := True
					paint
				else
					cancel
				end
			end
		end

	begin_drag (a_x, a_y: INTEGER)
		do
			is_dragging := True
			anchor_x := a_x
			anchor_y := a_y
			cur_x := a_x
			cur_y := a_y
			paint
		end

	nudge (a_vk: INTEGER)
			-- One arrow key: a pixel of movement, or with Shift held
			-- a pixel of size on the bottom-right corner. The same
			-- pure law the mouse uses.
		local
			dx, dy: INTEGER
			nb: TUPLE [x, y, w, h: INTEGER]
		do
			inspect a_vk
			when 37 then
				dx := -1
			when 39 then
				dx := 1
			when 38 then
				dy := -1
			when 40 then
				dy := 1
			else
			end
			if dx /= 0 or dy /= 0 then
				if keys.shift_down then
					nb := adjusted_band (5, adj_x, adj_y, adj_w, adj_h, dx, dy)
				else
					nb := adjusted_band (9, adj_x, adj_y, adj_w, adj_h, dx, dy)
				end
				adj_x := nb.x
				adj_y := nb.y
				adj_w := nb.w
				adj_h := nb.h
				clamp_adjust_to_span
				paint
			end
		end

feature {NONE} -- Implementation

	open_overlay (a_on_done: PROCEDURE [TUPLE [detachable TUPLE [x, y, w, h: INTEGER]]]): BOOLEAN
			-- Grab the desktop and raise the overlay; on failure set
			-- `last_error' and report Void at once.
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
				is_adjusting := False
				active_handle := 0
				has_saved := False
				overlay.show
				is_active := True
				Result := True
			end
		ensure
			up_iff: Result = is_active
		end

	finish_adjusted
			-- Accept the adjusted box: screen coordinates out,
			-- overlay down.
		require
			adjusting: is_adjusting
		local
			rx, ry, rw, rh: INTEGER
		do
			rx := adj_x + origin_x
			ry := adj_y + origin_y
			rw := adj_w
			rh := adj_h
			teardown
			if attached on_done as d then
				d.call ([[rx, ry, rw, rh]])
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
			is_adjusting := False
			active_handle := 0
			has_saved := False
		ensure
			idle: not is_active
		end

	near (a_px, a_py, a_hx, a_hy: INTEGER): BOOLEAN
			-- Within a grab point's catch square centred on
			-- (a_hx, a_hy)?
		do
			Result := (a_px - a_hx).abs <= Handle_grasp
				and (a_py - a_hy).abs <= Handle_grasp
		end

	in_button (a_px, a_py, a_bx, a_by, a_bw: INTEGER): BOOLEAN
			-- Inside a banner button laid out at (a_bx, a_by) with
			-- width a_bw? Zero width - not yet painted - catches
			-- nothing.
		do
			Result := a_bw > 0 and then a_px >= a_bx and then a_px <= a_bx + a_bw
				and then a_py >= a_by and then a_py <= a_by + Button_h
		end

	clamp_adjust_to_span
			-- Keep the adjusted box on the frozen screen.
		do
			adj_w := adj_w.min (span_w)
			adj_h := adj_h.min (span_h)
			adj_x := adj_x.max (0).min (span_w - adj_w)
			adj_y := adj_y.max (0).min (span_h - adj_h)
		ensure
			on_screen: adj_x >= 0 and adj_y >= 0
				and adj_x + adj_w <= span_w and adj_y + adj_h <= span_h
		end

	paint
			-- The frozen desktop, a dim wash, the band re-lit and
			-- stroked - with its handles, dimensions and the
			-- Apply/Cancel pair while adjusting - and the banner.
		local
			dc: POINTER
			ws: CAIRO_SURFACE
			ctx: CAIRO_CONTEXT
			p: SW_PAINTER
			th: SW_THEME
			msg, dims: STRING_32
			mw, bx0, by0, aw, cw: REAL_64
			rx, ry, rw, rh: INTEGER
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
					if is_adjusting then
						rx := adj_x
						ry := adj_y
						rw := adj_w
						rh := adj_h
					else
						rx := band_x
						ry := band_y
						rw := band_w
						rh := band_h
					end
					if (is_adjusting or is_dragging) and then rw > 0 and then rh > 0 then
							-- the band re-lit: the frozen image again,
							-- clipped to the choice
						p.push_clip (rx, ry, rw, rh)
						ctx.set_source_surface (fz, 0.0, 0.0).paint.do_nothing
						p.pop_clip
						p.set_color (th.accent)
						p.set_line_width (2.0)
						p.rrect_stroke (rx - 1.0, ry - 1.0, rw + 2.0, rh + 2.0, 1.0)
						p.set_line_width (1.0)
					end
					if is_adjusting then
						draw_handles (p, th, rx, ry, rw, rh)
						create dims.make (16)
						dims.append_string_general (rw.out)
						dims.append_string_general (" x ")
						dims.append_string_general (rh.out)
						p.font ({SW_PAINTER}.Role_mono, 12.0, False)
						mw := p.advance (dims) + 16.0
						p.set_color_alpha (0x000000, 0.72)
						p.rrect_fill (rx + 4.0, ry + 4.0, mw, 22.0, 4.0)
						p.set_color (0xFFFFFF)
						p.text (rx + 12.0, ry + 20.0, dims)
						create msg.make_from_string_general (
							"Drag the handles or the box; arrows nudge, Shift+arrows resize; Enter accepts, Esc cancels.")
					else
						create msg.make_from_string_general (
							"Drag a rectangle; Esc or right-click cancels.")
					end
					p.font ({SW_PAINTER}.Role_ui, 14.0, True)
					mw := p.advance (msg) + 28.0
					p.set_color_alpha (0x000000, 0.72)
					p.rrect_fill ((span_w - mw) / 2.0, 18.0, mw, 34.0, 6.0)
					p.set_color (0xFFFFFF)
					p.text ((span_w - mw) / 2.0 + 14.0, 41.0, msg)
					if is_adjusting then
							-- the mouse-only path: Apply and Cancel
							-- under the banner
						p.font ({SW_PAINTER}.Role_ui, 13.0, True)
						aw := p.advance ("Apply") + 28.0
						cw := p.advance ("Cancel") + 28.0
						bx0 := (span_w - (aw + 10.0 + cw)) / 2.0
						by0 := 60.0
						p.set_color (th.accent)
						p.rrect_fill (bx0, by0, aw, Button_h, 6.0)
						p.set_color (0xFFFFFF)
						p.text (bx0 + 14.0, by0 + 20.0, "Apply")
						apply_bx := bx0.truncated_to_integer
						apply_by := by0.truncated_to_integer
						apply_bw := aw.truncated_to_integer
						p.set_color_alpha (0x000000, 0.72)
						p.rrect_fill (bx0 + aw + 10.0, by0, cw, Button_h, 6.0)
						p.set_color (0xFFFFFF)
						p.text (bx0 + aw + 10.0 + 14.0, by0 + 20.0, "Cancel")
						cancel_bx := (bx0 + aw + 10.0).truncated_to_integer
						cancel_by := by0.truncated_to_integer
						cancel_bw := cw.truncated_to_integer
					else
						apply_bw := 0
						cancel_bw := 0
					end
					ctx.destroy
				end
				ws.destroy
				overlay.release_dc (dc)
			end
		end

	draw_handles (a_p: SW_PAINTER; a_th: SW_THEME; a_rx, a_ry, a_rw, a_rh: INTEGER)
			-- Eight grab squares: corners and edge middles.
		local
			i: INTEGER
			hx, hy: REAL_64
		do
			from
				i := 1
			until
				i > 8
			loop
				inspect i
				when 1 then
					hx := a_rx
					hy := a_ry
				when 2 then
					hx := a_rx + a_rw / 2.0
					hy := a_ry
				when 3 then
					hx := a_rx + a_rw
					hy := a_ry
				when 4 then
					hx := a_rx + a_rw
					hy := a_ry + a_rh / 2.0
				when 5 then
					hx := a_rx + a_rw
					hy := a_ry + a_rh
				when 6 then
					hx := a_rx + a_rw / 2.0
					hy := a_ry + a_rh
				when 7 then
					hx := a_rx
					hy := a_ry + a_rh
				else
					hx := a_rx
					hy := a_ry + a_rh / 2.0
				end
				a_p.set_color (0x000000)
				a_p.fill_rect (hx - Handle_half - 1.0, hy - Handle_half - 1.0,
					2.0 * Handle_half + 2.0, 2.0 * Handle_half + 2.0)
				a_p.set_color (a_th.accent)
				a_p.fill_rect (hx - Handle_half, hy - Handle_half,
					2.0 * Handle_half, 2.0 * Handle_half)
				i := i + 1
			end
		end

	Handle_half: REAL_64 = 6.0
			-- Half the drawn side of a grab square.

	Button_h: INTEGER = 28
			-- Banner button height, drawing and hit-testing alike.

	overlay: SHELL_OVERLAY
		once
			create Result
		end

	keys: SHELL_KEYS
			-- Physical modifier state at nudge time.

	on_done: detachable PROCEDURE [TUPLE [detachable TUPLE [x, y, w, h: INTEGER]]]

	snapshot: detachable CAIRO_SURFACE

	origin_x, origin_y, span_w, span_h: INTEGER

	is_dragging: BOOLEAN

	anchor_x, anchor_y, cur_x, cur_y: INTEGER

	adj_x, adj_y, adj_w, adj_h: INTEGER
			-- The box under adjustment, client coordinates.

	active_handle: INTEGER
			-- The grab point being dragged: 1..8 a handle, 9 the
			-- interior, 0 none.

	grab_x, grab_y: INTEGER
			-- Where the active grab last was.

	saved_x, saved_y, saved_w, saved_h: INTEGER
	has_saved: BOOLEAN
			-- The box remembered across a replacing drag, so a
			-- mis-tap restores instead of destroying.

	apply_bx, apply_by, apply_bw: INTEGER
	cancel_bx, cancel_by, cancel_bw: INTEGER
			-- The banner buttons as last painted; width 0 = not up.

end
