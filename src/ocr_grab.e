note
	description: "[
		Screen-region capture on the pure route: SW_SCREEN grabs the
		desktop through simple_shell's BitBlt (the very C this
		application once carried in its own header, returned home as
		a library), cairo writes the PNG, and a forty-line writer
		covers BMP. No Vision2, no EV_APPLICATION - a worker process
		can capture without paying to start a windowing subsystem.

		Successor to OCR_CAPTURE (Vision2), which leaves with the
		old GUI. Same contract shape: capture answers a surface or
		Void with `last_error' set; capture_to_file adds the disk.
	]"

class
	OCR_GRAB

create
	make

feature {NONE} -- Initialization

	make
		do
			create last_error.make_empty
		end

feature -- Access

	last_error: STRING_32
			-- Why the most recent operation failed; empty on success.

	last_width, last_height: INTEGER
			-- Dimensions actually captured.

	last_thumbnail: detachable CAIRO_SURFACE
			-- Scaled-down copy of the most recent capture (longest
			-- side `Thumbnail_side'), for eyeballing the region.
			-- Only the scaled copy is retained: a full-page capture
			-- is megabytes, the thumbnail a few hundred kilobytes.

	Thumbnail_side: INTEGER = 240

feature -- Basic operations

	capture (a_x, a_y, a_width, a_height: INTEGER): detachable CAIRO_SURFACE
			-- The screen rectangle as an ARGB32 surface, or Void
			-- (with `last_error') when the desktop cannot be read.
			-- The caller owns the surface: destroy it when done.
		require
			positive: a_width > 0 and a_height > 0
		local
			sc: SW_SCREEN
		do
			last_error.wipe_out
			create sc
			Result := sc.grab (a_x, a_y, a_width, a_height)
			if attached Result then
				last_width := a_width
				last_height := a_height
				build_thumbnail (Result)
			else
				last_error := {STRING_32} "Could not read the screen (locked session or protected content)."
			end
		ensure
			sized: attached Result implies (last_width = a_width and last_height = a_height)
			explained: Result = Void implies not last_error.is_empty
		end

	capture_to_file (a_x, a_y, a_width, a_height: INTEGER; a_path: READABLE_STRING_GENERAL; a_format: READABLE_STRING_8): BOOLEAN
			-- Capture and write as `a_format' ("png" or "bmp").
		require
			positive: a_width > 0 and a_height > 0
			format_known: a_format.same_string ("png") or a_format.same_string ("bmp")
		do
			if attached capture (a_x, a_y, a_width, a_height) as s then
				if a_format.same_string ("bmp") then
					Result := write_bmp (s, a_path)
				else
					Result := s.write_png (a_path)
					if not Result then
						last_error := {STRING_32} "Could not write the PNG. Is the folder writable?"
					end
				end
				s.destroy
			end
		ensure
			explained: not Result implies not last_error.is_empty
		end

feature -- Measurement

	virtual_x: INTEGER
		local
			sc: SW_SCREEN
		do
			create sc
			Result := sc.virtual_x
		end

	virtual_y: INTEGER
		local
			sc: SW_SCREEN
		do
			create sc
			Result := sc.virtual_y
		end

	virtual_width: INTEGER
		local
			sc: SW_SCREEN
		do
			create sc
			Result := sc.virtual_width
		end

	virtual_height: INTEGER
		local
			sc: SW_SCREEN
		do
			create sc
			Result := sc.virtual_height
		end

feature {NONE} -- Implementation

	build_thumbnail (a_surface: CAIRO_SURFACE)
			-- Scale the capture so its longest side is
			-- `Thumbnail_side' pixels; keep only the copy.
		local
			tw, th: INTEGER
			f: REAL_64
			thumb: CAIRO_SURFACE
			ctx: CAIRO_CONTEXT
		do
			if last_width >= last_height then
				f := Thumbnail_side / last_width
			else
				f := Thumbnail_side / last_height
			end
			if f > 1.0 then
				f := 1.0
			end
			tw := (last_width * f).rounded.max (1)
			th := (last_height * f).rounded.max (1)
			create thumb.make (tw, th)
			create ctx.make (thumb)
			ctx.scale (f, f).set_source_surface (a_surface, 0.0, 0.0).paint.do_nothing
			ctx.destroy
			if attached last_thumbnail as old_thumb then
				old_thumb.destroy
			end
			last_thumbnail := thumb
		ensure
			kept: last_thumbnail /= Void
		end

	write_bmp (a_surface: CAIRO_SURFACE; a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Uncompressed 32-bit top-down BMP straight from the
			-- surface: cairo's ARGB32 is BGRA in little-endian
			-- memory, exactly BMP's 32bpp order - rows copy through,
			-- minus the stride padding.
		local
			f: RAW_FILE
			mp: MANAGED_POINTER
			w, h, stride, row, col, img_bytes: INTEGER
		do
			a_surface.flush.do_nothing
			w := a_surface.width
			h := a_surface.height
			stride := a_surface.stride
			img_bytes := w * h * 4
			create mp.share_from_pointer (a_surface.data, stride * h)
			create f.make_with_name (a_path)
			f.open_write
			if f.is_open_write then
					-- BITMAPFILEHEADER (14) + BITMAPINFOHEADER (40)
				f.put_natural_8 (0x42)                     -- 'B'
				f.put_natural_8 (0x4D)                     -- 'M'
				put_32 (f, 54 + img_bytes)                 -- file size
				put_32 (f, 0)                              -- reserved
				put_32 (f, 54)                             -- pixel offset
				put_32 (f, 40)                             -- info header size
				put_32 (f, w)
				put_32 (f, -h)                             -- top-down
				f.put_natural_16 (1)                       -- planes
				f.put_natural_16 (32)                      -- bpp
				put_32 (f, 0)                              -- BI_RGB
				put_32 (f, img_bytes)
				put_32 (f, 2835)                           -- 72 dpi
				put_32 (f, 2835)
				put_32 (f, 0)
				put_32 (f, 0)
				from
					row := 0
				until
					row >= h
				loop
					from
						col := 0
					until
						col >= w
					loop
						put_32u (f, mp.read_natural_32 (row * stride + col * 4))
						col := col + 1
					end
					row := row + 1
				end
				f.close
				Result := True
			else
				last_error := {STRING_32} "Could not write the BMP. Is the folder writable?"
			end
		end

	put_32 (a_file: RAW_FILE; a_value: INTEGER)
		do
			put_32u (a_file, a_value.to_natural_32)
		end

	put_32u (a_file: RAW_FILE; a_value: NATURAL_32)
			-- Little-endian, byte by byte - independent of any
			-- platform storable format.
		do
			a_file.put_natural_8 ((a_value.bit_and (0xFF)).to_natural_8)
			a_file.put_natural_8 ((a_value.bit_shift_right (8).bit_and (0xFF)).to_natural_8)
			a_file.put_natural_8 ((a_value.bit_shift_right (16).bit_and (0xFF)).to_natural_8)
			a_file.put_natural_8 ((a_value.bit_shift_right (24).bit_and (0xFF)).to_natural_8)
		end

end
