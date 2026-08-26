note
	description: "[
		The rebuild's own battery: the selector's pure band law with
		bare numbers, and the outline set's lifecycle with REAL
		click-through frame windows parked far offscreen.
	]"

class
	SW_REBUILD_TESTS

inherit
	TEST_SET_BASE

feature -- Selector band law

	test_band_normalizes_any_drag_direction
		local
			s: OCR_SW_SELECTOR
			b: TUPLE [x, y, w, h: INTEGER]
		do
			create s.make
			b := s.normalized_band (10, 10, 110, 60)
			assert_integers_equal ("east-south x", 10, b.x)
			assert_integers_equal ("east-south w", 100, b.w)
			b := s.normalized_band (110, 60, 10, 10)
			assert_integers_equal ("west-north drag names the SAME box x", 10, b.x)
			assert_integers_equal ("and the same w", 100, b.w)
			assert_integers_equal ("and the same h", 50, b.h)
			assert ("a real drag is usable", s.is_usable_band (100, 50))
			assert ("a tap is a cancel, not a 1x1 region", not s.is_usable_band (1, 1))
			assert ("the fence is exact", s.is_usable_band (3, 3) and not s.is_usable_band (2, 3))
		end

feature -- Selector handle law (adjust mode, bare numbers)

	test_handle_index_answers_every_grab_point
			-- The box (100, 100, 200, 100): corners outrank middles,
			-- handles outrank the interior, outside answers nothing.
		local
			s: OCR_SW_SELECTOR
		do
			create s.make
			assert_integers_equal ("top-left corner", 1, s.handle_index_at (100, 100, 100, 100, 200, 100))
			assert_integers_equal ("top-right corner", 3, s.handle_index_at (300, 100, 100, 100, 200, 100))
			assert_integers_equal ("bottom-right corner", 5, s.handle_index_at (300, 200, 100, 100, 200, 100))
			assert_integers_equal ("bottom-left corner", 7, s.handle_index_at (100, 200, 100, 100, 200, 100))
			assert_integers_equal ("top middle", 2, s.handle_index_at (200, 100, 100, 100, 200, 100))
			assert_integers_equal ("right middle", 4, s.handle_index_at (300, 150, 100, 100, 200, 100))
			assert_integers_equal ("bottom middle", 6, s.handle_index_at (200, 200, 100, 100, 200, 100))
			assert_integers_equal ("left middle", 8, s.handle_index_at (100, 150, 100, 100, 200, 100))
			assert_integers_equal ("the interior moves the box", 9, s.handle_index_at (180, 160, 100, 100, 200, 100))
			assert_integers_equal ("outside answers nothing", 0, s.handle_index_at (50, 50, 100, 100, 200, 100))
			assert_integers_equal ("the catch square is generous",
				1, s.handle_index_at (100 + s.Handle_grasp, 100 + s.Handle_grasp, 100, 100, 200, 100))
			assert_integers_equal ("but exactly bounded",
				9, s.handle_index_at (100 + s.Handle_grasp + 1, 100 + s.Handle_grasp + 1, 100, 100, 200, 100))
		end

	test_adjusted_band_moves_the_right_edges
		local
			s: OCR_SW_SELECTOR
			b: TUPLE [x, y, w, h: INTEGER]
		do
			create s.make
				-- bottom-right corner: grows both dimensions
			b := s.adjusted_band (5, 100, 100, 200, 100, 10, 5)
			assert_integers_equal ("BR leaves x", 100, b.x)
			assert_integers_equal ("BR grows w", 210, b.w)
			assert_integers_equal ("BR grows h", 105, b.h)
				-- top-left corner: moves origin, shrinks size
			b := s.adjusted_band (1, 100, 100, 200, 100, 10, 5)
			assert_integers_equal ("TL moves x", 110, b.x)
			assert_integers_equal ("TL shrinks w", 190, b.w)
			assert_integers_equal ("TL shrinks h", 95, b.h)
				-- a middle moves ONE edge only
			b := s.adjusted_band (4, 100, 100, 200, 100, -20, 999)
			assert_integers_equal ("right middle ignores dy on y", 100, b.y)
			assert_integers_equal ("right middle ignores dy on h", 100, b.h)
			assert_integers_equal ("and pulls only w", 180, b.w)
				-- the interior carries the whole box unchanged in size
			b := s.adjusted_band (9, 100, 100, 200, 100, -7, 3)
			assert_integers_equal ("move x", 93, b.x)
			assert_integers_equal ("move y", 103, b.y)
			assert_integers_equal ("move keeps w", 200, b.w)
			assert_integers_equal ("move keeps h", 100, b.h)
		end

	test_adjusted_band_clamps_at_min_side
			-- Pulling an edge across its opposite cannot destroy the
			-- box: the pull clamps at Min_side.
		local
			s: OCR_SW_SELECTOR
			b: TUPLE [x, y, w, h: INTEGER]
		do
			create s.make
			b := s.adjusted_band (8, 100, 100, 200, 100, 500, 0)
			assert_integers_equal ("left edge stops Min_side short", s.Min_side, b.w)
			assert_integers_equal ("pinned to the right edge", 300 - s.Min_side, b.x)
			b := s.adjusted_band (2, 100, 100, 200, 100, 0, 500)
			assert_integers_equal ("top edge likewise", s.Min_side, b.h)
			b := s.adjusted_band (5, 100, 100, 200, 100, -500, -500)
			assert_integers_equal ("BR pulled through TL clamps w", s.Min_side, b.w)
			assert_integers_equal ("and h", s.Min_side, b.h)
			assert_integers_equal ("without moving the origin", 100, b.x)
		end

feature -- Outline lifecycle (real frame windows, offscreen)

	test_outlines_show_suspend_resume
		local
			o: OCR_SW_OUTLINES
			st: OCR_SETTINGS
		do
			create st
			st.set_region (-3000, -3000, 80, 50)
			create o.make (st)
			assert ("capture region configured", o.is_configured (o.Kind_capture))
			assert ("advance is not", not o.is_configured (o.Kind_advance))
			o.show (o.Kind_capture)
			assert ("shown", o.is_shown (o.Kind_capture))
			o.show (o.Kind_advance)
			assert ("an unconfigured region stays down", not o.is_shown (o.Kind_advance))
			o.suspend
			assert ("the shutter takes everything down", not o.is_any_shown)
			o.resume
			assert ("and resume restores exactly what was up", o.is_shown (o.Kind_capture))
			assert ("but never what was not", not o.is_shown (o.Kind_advance))
			o.hide (o.Kind_all)
			assert ("hidden", not o.is_any_shown)
		end

feature -- Strip laws (sizing measured, transport zoned)

	test_strip_sizing_and_transport_zone
		local
			s: OCR_SW_STRIP
			st: OCR_SETTINGS
		do
			create st
			create s.make (st)
			assert_integers_equal ("minimum width stands", 320, s.current_width)
			assert_integers_equal ("minimum height stands", 34, s.current_height)
			s.set_page_caption ("Page 90-92 of 139")
			assert ("a caption line grows the height", s.current_height >= 34 + 17)
			s.set_metrics_caption ("2.1 pages/min%N ETA 25m")
			assert ("two metrics lines grow it again", s.current_height >= 34 + 3 * 17)
			assert ("the play glyph answers in the corner",
				s.transport_at (s.transport_left (s.Transport_play) + 6, 17) = s.Transport_play)
			assert ("stop too",
				s.transport_at (s.transport_left (s.Transport_stop) + 6, 17) = s.Transport_stop)
			assert ("the body is not a button", s.transport_at (30, 17) = 0)
			assert ("the transport lives inside the C no-drag corner",
				s.transport_left (s.Transport_play) >= s.current_width - 90)
		end

end
