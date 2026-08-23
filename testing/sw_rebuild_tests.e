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
