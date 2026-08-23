note
	description: "[
		The three region outlines on the pure route: SHELL_OUTLINES
		frame windows - click-through, topmost, never activated -
		one slot per region. Same public contract as the Vision2
		OCR_OUTLINE_SET it succeeds: kinds, live-from-settings
		rectangles, and the shutter's suspend/resume pair.

		Colour still separates the three (cyan capture, amber
		advance, green label), and WALL THICKNESS separates them
		again for eyes that cannot separate the colours - the old
		set used dash patterns for the same duty; frame regions do
		not dash, so the walls grow instead: 2, 4 and 6 pixels.
	]"

class
	OCR_SW_OUTLINES

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
		do
			settings := a_settings
			create shown.make_filled (False, 1, 3)
			create suspended.make_filled (False, 1, 3)
		ensure
			nothing_shown: not is_any_shown
		end

feature -- Status report

	is_any_shown: BOOLEAN
		do
			Result := shown [1] or shown [2] or shown [3]
		end

	is_shown (a_kind: INTEGER): BOOLEAN
		require
			known: is_known_kind (a_kind)
		do
			if a_kind = Kind_all then
				Result := shown [1] and shown [2] and shown [3]
			else
				Result := shown [a_kind]
			end
		end

	is_known_kind (a_kind: INTEGER): BOOLEAN
			-- Is `a_kind' one of the three regions, or `Kind_all'?
		do
			Result := a_kind >= Kind_capture and a_kind <= Kind_all
		end

	is_configured (a_kind: INTEGER): BOOLEAN
			-- Does the settings object hold a usable rectangle for
			-- `a_kind' right now? Read live, never cached: the whole
			-- purpose of an outline is to check what is CURRENT.
		require
			known: is_known_kind (a_kind) and a_kind /= Kind_all
		do
			inspect a_kind
			when Kind_capture then
				Result := settings.is_region_valid
			when Kind_advance then
				Result := settings.is_advance_region_valid
			else
				Result := settings.is_page_label_region_valid
			end
		end

feature -- Basic operations

	show (a_kind: INTEGER)
			-- Show `a_kind' (or all three) at the rectangles the
			-- settings hold RIGHT NOW; an unconfigured region simply
			-- stays down.
		require
			known: is_known_kind (a_kind)
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
		require
			known: is_known_kind (a_kind)
		do
			if a_kind = Kind_all then
				hide_one (Kind_capture)
				hide_one (Kind_advance)
				hide_one (Kind_label)
			else
				hide_one (a_kind)
			end
		end

	suspend
			-- Take every shown outline off the screen for the
			-- shutter's instant, remembering which they were.
		local
			k: INTEGER
		do
			from
				k := 1
			until
				k > 3
			loop
				suspended [k] := shown [k]
				if shown [k] then
					hide_one (k)
				end
				k := k + 1
			end
		ensure
			all_down: not is_any_shown
		end

	resume
			-- Put back whatever `suspend' took down.
		local
			k: INTEGER
		do
			from
				k := 1
			until
				k > 3
			loop
				if suspended [k] then
					show_one (k)
					suspended [k] := False
				end
				k := k + 1
			end
		end

feature -- Constants

	Kind_capture: INTEGER = 1
	Kind_advance: INTEGER = 2
	Kind_label: INTEGER = 3
	Kind_all: INTEGER = 4

feature {NONE} -- Implementation

	settings: OCR_SETTINGS

	shown: ARRAY [BOOLEAN]

	suspended: ARRAY [BOOLEAN]
			-- Which outlines `suspend' took down, for `resume'.

	frames: SHELL_OUTLINES
		once
			create Result
		end

	show_one (a_kind: INTEGER)
		require
			single: a_kind >= Kind_capture and a_kind <= Kind_label
		local
			rx, ry, rw, rh: INTEGER
		do
			if is_configured (a_kind) then
				inspect a_kind
				when Kind_capture then
					rx := settings.region_x
					ry := settings.region_y
					rw := settings.region_width
					rh := settings.region_height
				when Kind_advance then
					rx := settings.advance_x
					ry := settings.advance_y
					rw := settings.advance_width
					rh := settings.advance_height
				else
					rx := settings.page_label_x
					ry := settings.page_label_y
					rw := settings.page_label_width
					rh := settings.page_label_height
				end
					-- the frame sits OUTSIDE the region, so the walls
					-- never cover a pixel the shutter would capture
				frames.show (a_kind - 1,
					rx - wall_of (a_kind), ry - wall_of (a_kind),
					rw + 2 * wall_of (a_kind), rh + 2 * wall_of (a_kind),
					wall_of (a_kind), colour_of (a_kind))
				shown [a_kind] := True
			end
		end

	hide_one (a_kind: INTEGER)
		require
			single: a_kind >= Kind_capture and a_kind <= Kind_label
		do
			frames.hide (a_kind - 1)
			shown [a_kind] := False
		end

	wall_of (a_kind: INTEGER): INTEGER
			-- 2, 4, 6: pattern-duty reassigned to thickness.
		do
			Result := a_kind * 2
		end

	colour_of (a_kind: INTEGER): NATURAL_32
			-- Cyan capture, amber advance, green label - the old
			-- set's exact colours.
		do
			inspect a_kind
			when Kind_capture then
				Result := 0x00DCFF
			when Kind_advance then
				Result := 0xFFAA28
			else
				Result := 0x78F08C
			end
		end

invariant
	three_tracked: shown.count = 3 and suspended.count = 3

end
