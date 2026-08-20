note
	description: "[
		Screen-region capture. Grabs a rectangle of the live screen and writes
		it to disk.

		Uses Vision2's EV_SCREEN.sub_pixmap, which is BitBlt-backed on Windows,
		so no additional inline C is needed for capture or for PNG encoding.

		An EV_APPLICATION must exist before any feature here is called; Vision2
		objects cannot be created without one. The GUI provides it; headless
		callers must create one themselves (no event loop is required).
	]"

class
	OCR_CAPTURE

create
	make

feature {NONE} -- Initialization

	make
			-- Create a capture agent.
		do
			create last_error.make_empty
			create screen
		end

feature -- Access

	last_error: STRING_32
			-- Reason the most recent operation failed; empty when it succeeded.

	last_width, last_height: INTEGER
			-- Dimensions actually captured.

	last_thumbnail: detachable EV_PIXMAP
			-- Scaled-down copy of the most recent capture, for eyeballing that
			-- the region grabbed the intended content.
			--
			-- Only the SCALED copy is retained. A full-page capture is around
			-- 1369x1847, and holding one of those per cycle would pin about
			-- 10 MB of GDI-backed pixels for the life of the application.

feature -- Measurement

	screen_width: INTEGER
			-- Width of the virtual desktop.
		do
			Result := screen.virtual_width
		end

	screen_height: INTEGER
			-- Height of the virtual desktop.
		do
			Result := screen.virtual_height
		end

feature -- Basic operations

	capture (a_x, a_y, a_width, a_height: INTEGER): detachable EV_PIXMAP
			-- Rectangle of the screen at (`a_x', `a_y'), clamped to the virtual
			-- desktop. Void when the rectangle lies wholly off-screen.
		require
			positive_extent: a_width > 0 and a_height > 0
		local
			l_x, l_y, l_w, l_h: INTEGER
			l_rect: EV_RECTANGLE
			l_retried: BOOLEAN
		do
			if not l_retried then
				last_error.wipe_out

					-- Clamp to the virtual desktop; sub_pixmap on an
					-- out-of-bounds rectangle yields garbage or raises.
				l_x := a_x.max (screen.virtual_x)
				l_y := a_y.max (screen.virtual_y)
				l_w := a_width.min (screen.virtual_x + screen.virtual_width - l_x)
				l_h := a_height.min (screen.virtual_y + screen.virtual_height - l_y)

				if l_w > 0 and l_h > 0 then
					create l_rect.make (l_x, l_y, l_w, l_h)
					Result := screen.sub_pixmap (l_rect)
					last_width := l_w
					last_height := l_h
				else
					last_error := {STRING_32} "Capture region lies outside the screen."
				end
			else
				last_error := {STRING_32} "Screen capture raised an exception."
			end
		ensure
			error_reported: Result = Void implies not last_error.is_empty
			sized_on_success: Result /= Void implies (last_width > 0 and last_height > 0)
		rescue
			l_retried := True
			retry
		end

	capture_to_file (a_x, a_y, a_width, a_height: INTEGER; a_path: READABLE_STRING_GENERAL; a_format: READABLE_STRING_8): BOOLEAN
			-- Capture the rectangle and write it to `a_path' as `a_format'
			-- ("png" or "bmp"). True when the file exists afterwards.
		require
			positive_extent: a_width > 0 and a_height > 0
			path_not_empty: not a_path.is_empty
			format_known: a_format.same_string ("png") or a_format.same_string ("bmp")
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			if not l_retried then
				if attached capture (a_x, a_y, a_width, a_height) as al_pixmap then
					if a_format.same_string ("bmp") then
						al_pixmap.save_to_named_file (create {EV_BMP_FORMAT}, a_path)
					else
						al_pixmap.save_to_named_file (create {EV_PNG_FORMAT}, a_path)
					end
					create l_file.make_with_name (a_path)
					Result := l_file.exists and then l_file.count > 0
					if not Result then
						last_error := {STRING_32} "Image file was not written."
					else
						build_thumbnail (al_pixmap)
					end
				end
			else
				last_error := {STRING_32} "Writing the image raised an exception."
			end
		ensure
			error_reported: not Result implies not last_error.is_empty
		rescue
			l_retried := True
			retry
		end

feature -- Constants

	Thumbnail_max_width: INTEGER = 240
	Thumbnail_max_height: INTEGER = 260
			-- Bounding box for `last_thumbnail'. Tall enough that a portrait
			-- page still reads as a page rather than a smear.

feature {NONE} -- Implementation

	build_thumbnail (a_pixmap: EV_PIXMAP)
			-- Store a scaled copy of `a_pixmap' in `last_thumbnail'.
		require
			pixmap_attached: a_pixmap /= Void
		local
			l_scaled: EV_PIXMAP
			l_ratio: DOUBLE
			l_w, l_h: INTEGER
			l_retried: BOOLEAN
		do
			if not l_retried and then a_pixmap.width > 0 and a_pixmap.height > 0 then
					-- Fit inside the box, never enlarge: a small region should
					-- show at its own size rather than be blown up and blurred.
				l_ratio := (Thumbnail_max_width / a_pixmap.width).min
					(Thumbnail_max_height / a_pixmap.height)
				if l_ratio > 1.0 then
					l_ratio := 1.0
				end
				l_w := (a_pixmap.width * l_ratio).truncated_to_integer.max (1)
				l_h := (a_pixmap.height * l_ratio).truncated_to_integer.max (1)

				l_scaled := a_pixmap.twin
				l_scaled.stretch (l_w, l_h)
				last_thumbnail := l_scaled
			else
				last_thumbnail := Void
			end
		rescue
				-- A missing thumbnail must never cost a capture.
			l_retried := True
			last_thumbnail := Void
			retry
		end

	screen: EV_SCREEN
			-- Drawable representing the whole desktop.

invariant
	error_attached: last_error /= Void

end
