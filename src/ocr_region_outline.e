note
	description: "[
		A dashed rectangle drawn ON the desktop, showing where one of the
		configured regions actually sits.

		Built from FOUR thin borderless popup windows - one per edge - rather
		than one window with a hole in it. Vision2 exposes no layered-window
		alpha, so a single window covering the rectangle would hide the very
		thing being checked. Four two-pixel strips leave the content visible.

		Deliberately NOT the frozen-desktop approach used by
		OCR_REGION_SELECTOR. That class photographs the screen and shows the
		photograph, which is right for dragging (nothing can scroll mid-drag)
		and wrong for this: an alignment check must be against the LIVE reader,
		with both windows still movable.
	]"
	design: "[
		EV_POPUP_WINDOW for the same two properties the status strip relies on:
		its Windows implementation sets WS_EX_TOPMOST, so the outline sits over
		a full-screen reader, and `disconnect_from_window_manager' stops it
		taking focus. That call MUST precede `show'; it cannot be applied after.

		The dashes are runs of `fill_rectangle' rather than a dashed pen. The
		same choice as the strip's play glyph: a run of segments needs no
		coordinate array and cannot be got subtly wrong.

		Geometry is in PHYSICAL screen pixels. Popup `set_position' and
		`set_size' are faithful there - proven by the status strip, which is
		dragged by the user and whose transport glyphs are laid out from its
		requested width. The 2/3 scaling that OCR_MAIN_WINDOW once documented
		was a DPI-unaware measurement artefact and does not apply.
	]"

class
	OCR_REGION_OUTLINE

create
	make

feature {NONE} -- Initialization

	make (a_colour: EV_COLOR; a_pattern: INTEGER)
			-- An outline drawn in `a_colour' with dash pattern `a_pattern'.
		require
			known_pattern: a_pattern >= Pattern_dash and a_pattern <= Pattern_dash_dot
		do
			colour := a_colour
			pattern := a_pattern
			create edges.make (4)
			create areas.make (4)
			build_edges
		ensure
			colour_set: colour = a_colour
			pattern_set: pattern = a_pattern
			hidden: not is_shown
		end

	build_edges
			-- Create the four edge windows, hidden.
		local
			i: INTEGER
			l_window: EV_POPUP_WINDOW
			l_area: EV_DRAWING_AREA
		do
			from
				i := 1
			until
				i > 4
			loop
				create l_window
					-- Before `show', never after.
				l_window.disconnect_from_window_manager
				create l_area
				l_window.extend (l_area)
					-- `i' closed, the four expose coordinates left open. Writing
					-- `agent on_expose (i)' partially applies nothing and fails
					-- VUAR(1) with "formals 5, actuals 1".
				l_area.expose_actions.extend (agent on_expose (i, ?, ?, ?, ?))
				edges.extend (l_window)
				areas.extend (l_area)
				i := i + 1
			end
		ensure
			four_edges: edges.count = 4 and areas.count = 4
		end

feature -- Access

	colour: EV_COLOR
			-- Colour the dashes are drawn in.

	pattern: INTEGER
			-- Which dash pattern; `Pattern_dash', `Pattern_dot' or
			-- `Pattern_dash_dot'.

	x, y, width, height: INTEGER
			-- The rectangle being outlined, in physical screen pixels.

feature -- Status report

	is_shown: BOOLEAN
			-- Is the outline on screen?

	is_valid: BOOLEAN
			-- Is there a rectangle worth drawing?
		do
			Result := width > 0 and height > 0
		end

	intersects (a_x, a_y, a_width, a_height: INTEGER): BOOLEAN
			-- Does the drawn frame overlap the rectangle (`a_x', `a_y') by
			-- `a_width' x `a_height'?
			--
			-- Asked before a screen capture. An outline drawn around its OWN
			-- region never overlaps it, so the common case answers False and
			-- the outline is left alone. A different region's outline can still
			-- cross the capture rectangle - an advance button hard against the
			-- right edge of the page does exactly that - and only those need
			-- taking down for the shot.
			--
			-- Tested against the frame's bounding box, which includes the hole
			-- in the middle. Conservative: it can hide an outline that would not
			-- quite have been photographed. Erring the other way would put a
			-- dashed line in an archived page image.
		do
			Result := is_valid and then a_width > 0 and then a_height > 0
				and then (x - Thickness) < (a_x + a_width)
				and then (x + width + Thickness) > a_x
				and then (y - Thickness) < (a_y + a_height)
				and then (y + height + Thickness) > a_y
		end

feature -- Element change

	set_rectangle (a_x, a_y, a_width, a_height: INTEGER)
			-- Outline (`a_x', `a_y') by `a_width' x `a_height'.
		do
			x := a_x
			y := a_y
			width := a_width
			height := a_height
			if is_shown then
				lay_out
			end
		ensure
			set: x = a_x and y = a_y and width = a_width and height = a_height
		end

	advance_phase
			-- Move the dashes along one step, for a marching-ants effect.
			--
			-- An animated outline is unmistakable against static page content;
			-- a still one can be read as part of the document.
		do
			phase := (phase + 1) \\ pattern_period
			if is_shown then
				refresh
			end
		end

feature -- Basic operations

	show
			-- Put the outline on screen.
			--
			-- Refuses a zero-extent rectangle rather than drawing four strips
			-- stacked at one point, which would look like a defect and tell the
			-- user nothing.
		do
			if is_valid then
				lay_out
				across edges as ic_edge loop
					ic_edge.show
				end
				is_shown := True
			end
		end

	hide
			-- Take it off screen.
		do
			across edges as ic_edge loop
				ic_edge.hide
			end
			is_shown := False
		ensure
			hidden: not is_shown
		end

	refresh
			-- Repaint every edge.
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > 4
			loop
				if edges.i_th (i).is_displayed then
					on_expose (i, 0, 0, 0, 0)
				end
				i := i + 1
			end
		end

feature {NONE} -- Layout

	lay_out
			-- Position the four edge windows just OUTSIDE the rectangle.
			--
			-- Outside, not on it. Drawn inside the bounds, the frame covers three
			-- pixels of every edge of the very area being photographed - so it
			-- lands in the PNG and goes to the OCR model, and it hides the
			-- content whose alignment is being checked. Sitting outside, the
			-- capture region is untouched and an outline can be left up for a
			-- whole unattended run.
			--
			-- The horizontal strips run the full width plus both corners; the
			-- vertical ones span only the rectangle's own height, so the corners
			-- are drawn once rather than twice. Overlapping strips double the
			-- colour and read as blobs.
		do
			place (Edge_top, x - Thickness, y - Thickness, width + 2 * Thickness, Thickness)
			place (Edge_bottom, x - Thickness, y + height, width + 2 * Thickness, Thickness)
			place (Edge_left, x - Thickness, y, Thickness, height)
			place (Edge_right, x + width, y, Thickness, height)
		end


	place (a_edge, a_x, a_y, a_width, a_height: INTEGER)
			-- Move edge `a_edge' to (`a_x', `a_y') at `a_width' x `a_height'.
		require
			known_edge: a_edge >= Edge_top and a_edge <= Edge_right
		local
			l_w, l_h: INTEGER
		do
			l_w := a_width.max (1)
			l_h := a_height.max (1)
			areas.i_th (a_edge).set_minimum_size (l_w, l_h)
			edges.i_th (a_edge).set_size (l_w, l_h)
			edges.i_th (a_edge).set_position (a_x, a_y)
		end

feature {NONE} -- Painting

	on_expose (a_edge, a_x, a_y, a_width, a_height: INTEGER)
			-- Paint edge `a_edge' with the dash pattern.
		require
			known_edge: a_edge >= Edge_top and a_edge <= Edge_right
		local
			l_area: EV_DRAWING_AREA
			l_horizontal: BOOLEAN
			l_length, l_run, l_at: INTEGER
			l_on: BOOLEAN
			l_step: INTEGER
		do
			l_area := areas.i_th (a_edge)
			l_horizontal := a_edge = Edge_top or a_edge = Edge_bottom
				-- Matches `lay_out': horizontals span the width plus both
				-- corners, verticals span the rectangle's own height.
			if l_horizontal then
				l_length := width + 2 * Thickness
			else
				l_length := height
			end

				-- Backdrop first: the window is otherwise whatever Windows left
				-- in it, which on a dark reader shows as a pale bar.
			l_area.set_background_color (colour_gap)
			l_area.set_foreground_color (colour_gap)
			l_area.fill_rectangle (0, 0, l_length, Thickness)

			l_area.set_foreground_color (colour)
				-- Start part-way into the pattern so the dashes appear to travel
				-- when `advance_phase' bumps it.
			l_at := -phase
			l_step := 0
			from
			until
				l_at >= l_length
			loop
				l_run := run_length (l_step)
				l_on := is_on_run (l_step)
				if l_on and then l_at + l_run > 0 then
					if l_horizontal then
						l_area.fill_rectangle (l_at.max (0), 0,
							(l_run.min (l_length - l_at)).max (1), Thickness)
					else
						l_area.fill_rectangle (0, l_at.max (0), Thickness,
							(l_run.min (l_length - l_at)).max (1))
					end
				end
				l_at := l_at + l_run
				l_step := l_step + 1
			end
		end

	run_length (a_step: INTEGER): INTEGER
			-- Length of run `a_step' in the current pattern.
		do
			inspect pattern
			when Pattern_dot then
				if a_step \\ 2 = 0 then Result := 2 else Result := 5 end
			when Pattern_dash_dot then
					-- dash, gap, dot, gap
				inspect a_step \\ 4
				when 0 then Result := 10
				when 1 then Result := 5
				when 2 then Result := 2
				else Result := 5
				end
			else
					-- Pattern_dash
				if a_step \\ 2 = 0 then Result := 9 else Result := 6 end
			end
		ensure
			positive: Result > 0
		end

	is_on_run (a_step: INTEGER): BOOLEAN
			-- Is run `a_step' drawn rather than skipped?
		do
			inspect pattern
			when Pattern_dash_dot then
				Result := a_step \\ 2 = 0
			else
				Result := a_step \\ 2 = 0
			end
		end

	pattern_period: INTEGER
			-- Length of one full cycle of the pattern, for phase wrapping.
		do
			inspect pattern
			when Pattern_dot then Result := 7
			when Pattern_dash_dot then Result := 22
			else Result := 15
			end
		ensure
			positive: Result > 0
		end

	colour_gap: EV_COLOR
			-- What the un-drawn parts of an edge are filled with.
			--
			-- A dark grey rather than an attempt at transparency: Vision2 gives
			-- no alpha, and against both light and dark readers a thin dark line
			-- reads as a border instead of as damage.
		once
			create Result.make_with_8_bit_rgb (28, 30, 36)
		end

feature {NONE} -- Implementation

	edges: ARRAYED_LIST [EV_POPUP_WINDOW]
			-- Top, bottom, left, right.

	areas: ARRAYED_LIST [EV_DRAWING_AREA]
			-- Canvas of each edge, in the same order.

	phase: INTEGER
			-- How far the dashes have marched.

feature -- Constants

	Pattern_dash: INTEGER = 1
	Pattern_dot: INTEGER = 2
	Pattern_dash_dot: INTEGER = 3

	Edge_top: INTEGER = 1
	Edge_bottom: INTEGER = 2
	Edge_left: INTEGER = 3
	Edge_right: INTEGER = 4

	Thickness: INTEGER = 3
			-- Edge width in pixels. Three rather than one: a single-pixel line
			-- disappears against detailed page content, and these strips also
			-- have to be findable by eye at a glance.

invariant
	four_edges: edges.count = 4
	four_areas: areas.count = 4
	known_pattern: pattern >= Pattern_dash and pattern <= Pattern_dash_dot

end
