note
	description: "[
		The three configured regions, drawable on the desktop as dashed
		outlines: the capture region, the advance button, and the page
		indicator.

		Each has its own colour AND its own dash pattern. Colour alone is not
		enough - all three can be shown together, over a page that may be any
		colour, and a reader who cannot separate them has learned nothing.
	]"
	design: "[
		Rectangles are re-read from `settings' every time an outline is shown,
		never cached at creation. The whole purpose of the feature is to check
		a region that has just been dragged, so showing the value it had when
		the window opened would answer the wrong question.
	]"

class
	OCR_OUTLINE_SET

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
			-- Prepare outlines over `a_settings'.
		do
			settings := a_settings
			create capture_outline.make (colour_capture, {OCR_REGION_OUTLINE}.Pattern_dash)
			create advance_outline.make (colour_advance, {OCR_REGION_OUTLINE}.Pattern_dot)
			create label_outline.make (colour_label, {OCR_REGION_OUTLINE}.Pattern_dash_dot)
		ensure
			nothing_shown: not is_any_shown
		end

feature -- Status report

	is_any_shown: BOOLEAN
			-- Is at least one outline on screen?
		do
			Result := capture_outline.is_shown or advance_outline.is_shown
				or label_outline.is_shown
		end

	is_shown (a_kind: INTEGER): BOOLEAN
			-- Is the outline for `a_kind' on screen?
		require
			known_kind: is_known_kind (a_kind)
		do
			Result := outline_for (a_kind).is_shown
		end

	is_known_kind (a_kind: INTEGER): BOOLEAN
			-- Is `a_kind' one of the three regions, or `Kind_all'?
		do
			Result := a_kind >= Kind_capture and a_kind <= Kind_all
		end

	is_configured (a_kind: INTEGER): BOOLEAN
			-- Has `a_kind' actually been set up?
		require
			known_kind: is_known_kind (a_kind)
		do
			inspect a_kind
			when Kind_capture then Result := settings.is_region_valid
			when Kind_advance then Result := settings.is_advance_region_valid
			when Kind_label then Result := settings.is_page_label_region_valid
			else
				Result := settings.is_region_valid or settings.is_advance_region_valid
					or settings.is_page_label_region_valid
			end
		end

feature -- Basic operations

	show (a_kind: INTEGER)
			-- Put the outline(s) for `a_kind' on screen, re-reading the
			-- rectangle from settings first.
		require
			known_kind: is_known_kind (a_kind)
		do
			if a_kind = Kind_all then
				show_one (Kind_capture)
				show_one (Kind_advance)
				show_one (Kind_label)
			else
				show_one (a_kind)
			end
		end

	hide (a_kind: INTEGER)
			-- Take the outline(s) for `a_kind' off screen.
		require
			known_kind: is_known_kind (a_kind)
		do
			if a_kind = Kind_all then
				hide_all
			else
				outline_for (a_kind).hide
			end
		end

	hide_all
			-- Take every outline off screen.
			--
			-- The unconditional escape hatch. Twelve topmost windows with no
			-- obvious way to clear them would be a bad thing to leave behind if
			-- a release event is ever missed, so several paths call this.
		do
			capture_outline.hide
			advance_outline.hide
			label_outline.hide
		ensure
			nothing_shown: not is_any_shown
		end

	suspend
			-- Hide every outline for the instant of a screen capture,
			-- remembering which were up.
			--
			-- These are real windows sitting ON the edges of the rectangle being
			-- photographed, so one left visible is baked into the PNG and sent
			-- to the OCR model. Hiding them for the whole run would be the
			-- simpler rule and the wrong one: the outlines are most useful
			-- DURING a run, when pages are turning and misalignment finally
			-- shows itself. A capture takes milliseconds and they come back
			-- straight after, so what the user sees is a flicker once a page.
			--
			-- Only the ones that actually CROSS the capture rectangle come
			-- down. Since each outline is drawn just outside its own region, the
			-- capture region's own outline never overlaps it and is left alone -
			-- so in the ordinary layout nothing flickers at all. An advance
			-- button hard against the edge of the page is the case this exists
			-- for.
		do
			was_capture_shown := capture_outline.is_shown and then overlaps_capture (capture_outline)
			was_advance_shown := advance_outline.is_shown and then overlaps_capture (advance_outline)
			was_label_shown := label_outline.is_shown and then overlaps_capture (label_outline)

			if was_capture_shown then
				capture_outline.hide
			end
			if was_advance_shown then
				advance_outline.hide
			end
			if was_label_shown then
				label_outline.hide
			end
		end

	overlaps_capture (a_outline: OCR_REGION_OUTLINE): BOOLEAN
			-- Would `a_outline' be photographed by a capture?
		do
			Result := a_outline.intersects (settings.region_x, settings.region_y,
				settings.region_width, settings.region_height)
		end

	resume
			-- Put back whatever `suspend' took down.
		do
			if was_capture_shown then
				show_one (Kind_capture)
			end
			if was_advance_shown then
				show_one (Kind_advance)
			end
			if was_label_shown then
				show_one (Kind_label)
			end
		end

	advance_phase
			-- March the dashes on whatever is visible.
			--
			-- Cheap when nothing is shown, which is almost always, so this can
			-- sit on the main timer without a guard at the call site.
		do
			if capture_outline.is_shown then
				capture_outline.advance_phase
			end
			if advance_outline.is_shown then
				advance_outline.advance_phase
			end
			if label_outline.is_shown then
				label_outline.advance_phase
			end
		end

feature -- Access

	description (a_kind: INTEGER): STRING_32
			-- What `a_kind' is called, for the status line.
		require
			known_kind: is_known_kind (a_kind)
		do
			inspect a_kind
			when Kind_capture then Result := {STRING_32} "capture region"
			when Kind_advance then Result := {STRING_32} "advance button"
			when Kind_label then Result := {STRING_32} "page indicator"
			else Result := {STRING_32} "all three regions"
			end
		end

feature {NONE} -- Implementation

	show_one (a_kind: INTEGER)
			-- Re-read `a_kind' from settings and show it if it is set.
		require
			single_kind: a_kind >= Kind_capture and a_kind <= Kind_label
		do
			inspect a_kind
			when Kind_capture then
				capture_outline.set_rectangle (settings.region_x, settings.region_y,
					settings.region_width, settings.region_height)
			when Kind_advance then
				advance_outline.set_rectangle (settings.advance_x, settings.advance_y,
					settings.advance_width, settings.advance_height)
			else
				label_outline.set_rectangle (settings.page_label_x, settings.page_label_y,
					settings.page_label_width, settings.page_label_height)
			end
				-- `show' declines a zero-extent rectangle by itself, so an unset
				-- region simply does not appear.
			outline_for (a_kind).show
		end

	outline_for (a_kind: INTEGER): OCR_REGION_OUTLINE
			-- The outline object for `a_kind'.
		require
			single_kind: a_kind >= Kind_capture and a_kind <= Kind_label
		do
			inspect a_kind
			when Kind_capture then Result := capture_outline
			when Kind_advance then Result := advance_outline
			else Result := label_outline
			end
		end

	was_capture_shown, was_advance_shown, was_label_shown: BOOLEAN
			-- Which outlines `suspend' took down, for `resume' to restore.

	settings: OCR_SETTINGS
	capture_outline: OCR_REGION_OUTLINE
	advance_outline: OCR_REGION_OUTLINE
	label_outline: OCR_REGION_OUTLINE

feature {NONE} -- Colours

	colour_capture: EV_COLOR
			-- Cyan: the region being transcribed.
		once
			create Result.make_with_8_bit_rgb (0, 220, 255)
		end

	colour_advance: EV_COLOR
			-- Amber: the thing that gets clicked.
		once
			create Result.make_with_8_bit_rgb (255, 170, 40)
		end

	colour_label: EV_COLOR
			-- Green: the page indicator, matching its colour on the strip.
		once
			create Result.make_with_8_bit_rgb (120, 240, 140)
		end

feature -- Constants

	Kind_capture: INTEGER = 1
	Kind_advance: INTEGER = 2
	Kind_label: INTEGER = 3
	Kind_all: INTEGER = 4

end
