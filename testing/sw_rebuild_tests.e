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

end
