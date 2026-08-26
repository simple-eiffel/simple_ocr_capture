note
	description: "[
		Finds figure candidates on a captured page: rectangles that
		are INKY (pixels far from the page background) but carry NO
		TEXT (Windows OCR word boxes mask the prose). Deliberately
		deterministic - no model is ever asked for coordinates,
		because through Ollama a vision model's coordinate space is
		not controllable. The model's only role comes later: a
		one-word FIGURE/TEXT verdict on each crop this class
		proposes.

		The grid laws are pure and assaulted with bare arrays; only
		`find' touches pixels (the already-saved page PNG) and the
		boxes file winocr_boxes.ps1 wrote.
	]"

class
	OCR_FIGURE_FINDER

create
	make

feature {NONE} -- Initialization

	make
		do
		end

feature -- Constants

	Cell: INTEGER = 16
			-- Grid cell side, pixels.

	Min_extent_cells: INTEGER = 4
			-- A candidate must span at least this many cells on EACH
			-- axis (64 px): anything smaller is a drop cap, a dingbat
			-- or noise, not a figure worth extracting.

	Ink_distance: INTEGER = 96
			-- Manhattan RGB distance from the page background beyond
			-- which a pixel counts as ink.

	Ink_percent: INTEGER = 10
			-- A cell is inky when at least this percent of its
			-- sampled pixels are ink.

	Pad_px: INTEGER = 6
			-- Breathing room added around an accepted candidate.

	Fill_percent: INTEGER = 25
			-- A candidate's marked cells must cover at least this
			-- much of its own bounding box. A real figure fills its
			-- box; a page FRAME or a rule line is a thin connected
			-- structure whose bounding box is enormous and nearly
			-- empty - the first real prose page probed produced
			-- exactly that: one near-page-sized "candidate".

	Max_candidates: INTEGER = 6
			-- More than this on one page is detector confusion, not a
			-- picture book; the largest win.

feature -- Pure laws (assaultable with bare arrays)

	dilated (a_cols, a_rows: INTEGER; a_marked: ARRAY [BOOLEAN]): ARRAY [BOOLEAN]
			-- One 8-neighbour dilation step: bridges the small gaps
			-- chart labels punch through a figure's ink.
		require
			sized: a_marked.count = a_cols * a_rows
		local
			r, c, dr, dc: INTEGER
		do
			create Result.make_filled (False, 1, a_cols * a_rows)
			from
				r := 1
			until
				r > a_rows
			loop
				from
					c := 1
				until
					c > a_cols
				loop
					if a_marked [(r - 1) * a_cols + c] then
						from
							dr := -1
						until
							dr > 1
						loop
							from
								dc := -1
							until
								dc > 1
							loop
								if r + dr >= 1 and r + dr <= a_rows
									and c + dc >= 1 and c + dc <= a_cols
								then
									Result [(r + dr - 1) * a_cols + (c + dc)] := True
								end
								dc := dc + 1
							end
							dr := dr + 1
						end
					end
					c := c + 1
				end
				r := r + 1
			end
		ensure
			sized: Result.count = a_cols * a_rows
		end

	components (a_cols, a_rows: INTEGER; a_marked: ARRAY [BOOLEAN]): ARRAYED_LIST [TUPLE [cx, cy, cw, ch, n: INTEGER]]
			-- Bounding boxes (1-based cells) of the 4-connected True
			-- regions of a grid, row-major, each with its cell count
			-- `n' - the fill law's raw material.
		require
			sized: a_marked.count = a_cols * a_rows
		local
			seen: ARRAY [BOOLEAN]
			stack: ARRAYED_LIST [INTEGER]
			r, c, i, cr, cc, lo_r, hi_r, lo_c, hi_c, cnt: INTEGER
		do
			create Result.make (4)
			create seen.make_filled (False, 1, a_cols * a_rows)
			from
				r := 1
			until
				r > a_rows
			loop
				from
					c := 1
				until
					c > a_cols
				loop
					i := (r - 1) * a_cols + c
					if a_marked [i] and then not seen [i] then
						lo_r := r
						hi_r := r
						lo_c := c
						hi_c := c
						cnt := 0
						create stack.make (16)
						stack.extend (i)
						seen [i] := True
						from
						until
							stack.is_empty
						loop
							i := stack.last
							stack.finish
							stack.remove
							cnt := cnt + 1
							cr := (i - 1) // a_cols + 1
							cc := (i - 1) \\ a_cols + 1
							lo_r := lo_r.min (cr)
							hi_r := hi_r.max (cr)
							lo_c := lo_c.min (cc)
							hi_c := hi_c.max (cc)
							if cc > 1 and then a_marked [i - 1] and then not seen [i - 1] then
								seen [i - 1] := True
								stack.extend (i - 1)
							end
							if cc < a_cols and then a_marked [i + 1] and then not seen [i + 1] then
								seen [i + 1] := True
								stack.extend (i + 1)
							end
							if cr > 1 and then a_marked [i - a_cols] and then not seen [i - a_cols] then
								seen [i - a_cols] := True
								stack.extend (i - a_cols)
							end
							if cr < a_rows and then a_marked [i + a_cols] and then not seen [i + a_cols] then
								seen [i + a_cols] := True
								stack.extend (i + a_cols)
							end
						end
						Result.extend ([lo_c, lo_r, hi_c - lo_c + 1, hi_r - lo_r + 1, cnt])
					end
					c := c + 1
				end
				r := r + 1
			end
		end

	candidates_from_grids (a_cols, a_rows: INTEGER; a_ink, a_text: ARRAY [BOOLEAN]): ARRAYED_LIST [TUPLE [x, y, w, h: INTEGER]]
			-- Figure candidates in PIXELS from an ink grid and a text
			-- mask: (ink and not text), dilated once, connected,
			-- filtered to `Min_extent_cells' per axis, largest first,
			-- capped at `Max_candidates'. Pure - the assault drives
			-- it with hand-built grids.
		require
			ink_sized: a_ink.count = a_cols * a_rows
			text_sized: a_text.count = a_cols * a_rows
		local
			marked: ARRAY [BOOLEAN]
			i, j: INTEGER
			comps: ARRAYED_LIST [TUPLE [cx, cy, cw, ch, n: INTEGER]]
			best: INTEGER
		do
			create marked.make_filled (False, 1, a_cols * a_rows)
			from
				i := 1
			until
				i > a_cols * a_rows
			loop
				marked [i] := a_ink [i] and then not a_text [i]
				i := i + 1
			end
			comps := components (a_cols, a_rows, dilated (a_cols, a_rows, marked))
			create Result.make (comps.count)
			from
			until
				comps.is_empty or Result.count >= Max_candidates
			loop
					-- largest area first, selection-style: pages carry a
					-- handful of figures at most, never enough to sort
				best := 1
				from
					j := 2
				until
					j > comps.count
				loop
					if comps.i_th (j).cw * comps.i_th (j).ch
						> comps.i_th (best).cw * comps.i_th (best).ch
					then
						best := j
					end
					j := j + 1
				end
				if comps.i_th (best).cw >= Min_extent_cells
					and comps.i_th (best).ch >= Min_extent_cells
					and comps.i_th (best).n * 100
						>= comps.i_th (best).cw * comps.i_th (best).ch * Fill_percent
				then
					Result.extend ([(comps.i_th (best).cx - 1) * Cell,
						(comps.i_th (best).cy - 1) * Cell,
						comps.i_th (best).cw * Cell,
						comps.i_th (best).ch * Cell])
				end
				comps.go_i_th (best)
				comps.remove
			end
		ensure
			capped: Result.count <= Max_candidates
		end

feature -- Page analysis

	find (a_png_path, a_boxes_path: READABLE_STRING_GENERAL): ARRAYED_LIST [TUPLE [x, y, w, h: INTEGER]]
			-- Candidate figure rectangles on the page image, in pixels,
			-- padded and clamped. Empty when the page is prose, when
			-- the boxes file is missing or unreadable (no text mask
			-- means no SAFE candidates), or when the image cannot be
			-- loaded.
		local
			words: detachable ARRAYED_LIST [TUPLE [x, y, w, h: INTEGER]]
			page: CAIRO_SURFACE
			cols, rows, i: INTEGER
			ink, text_mask: ARRAY [BOOLEAN]
			raw: ARRAYED_LIST [TUPLE [x, y, w, h: INTEGER]]
			rx, ry, rw, rh: INTEGER
		do
			create Result.make (0)
			words := boxes_from_file (a_boxes_path)
			if words /= Void then
				create page.make_from_png (a_png_path)
				if page.is_valid and then page.width >= Cell and then page.height >= Cell then
					cols := page.width // Cell
					rows := page.height // Cell
					ink := ink_grid (page, cols, rows)
					create text_mask.make_filled (False, 1, cols * rows)
					across
						words as ic_word
					loop
						mask_box (text_mask, cols, rows,
							ic_word.x, ic_word.y, ic_word.w, ic_word.h)
					end
					raw := candidates_from_grids (cols, rows, ink, text_mask)
					from
						i := 1
					until
						i > raw.count
					loop
						rx := (raw.i_th (i).x - Pad_px).max (0)
						ry := (raw.i_th (i).y - Pad_px).max (0)
						rw := (raw.i_th (i).w + 2 * Pad_px).min (page.width - rx)
						rh := (raw.i_th (i).h + 2 * Pad_px).min (page.height - ry)
						Result.extend ([rx, ry, rw, rh])
						i := i + 1
					end
				end
				page.destroy
			end
		ensure
			capped: Result.count <= Max_candidates
		end

	boxes_from_file (a_path: READABLE_STRING_GENERAL): detachable ARRAYED_LIST [TUPLE [x, y, w, h: INTEGER]]
			-- Word rectangles from a winocr_boxes.ps1 output file:
			-- first line "W H" (skipped), then "x y w h" per word.
			-- Void when the file is absent or reports failure (its
			-- first line empty); an EMPTY list is a valid answer - a
			-- page with no readable words at all.
		local
			l_file: RAW_FILE
			l_lines: LIST [STRING_8]
			l_parts: LIST [STRING_8]
			l_clean: STRING_8
			l_first: BOOLEAN
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (a_path)
				if l_file.exists and then l_file.is_readable then
					l_file.open_read
					if l_file.count > 0 then
						l_file.read_stream (l_file.count)
						l_lines := l_file.last_string.split ('%N')
						l_file.close
						if not l_lines.is_empty and then not l_lines.first.is_empty then
							create Result.make (l_lines.count)
							l_first := True
							across
								l_lines as ic_line
							loop
								if l_first then
									l_first := False
								else
										-- PowerShell writes CRLF: the
										-- carriage return would poison
										-- the last field's is_integer
										-- and silently empty the mask
									l_clean := ic_line.twin
									l_clean.prune_all ('%R')
									l_parts := l_clean.split (' ')
									if l_parts.count >= 4
										and then l_parts.i_th (1).is_integer
										and then l_parts.i_th (2).is_integer
										and then l_parts.i_th (3).is_integer
										and then l_parts.i_th (4).is_integer
									then
										Result.extend ([l_parts.i_th (1).to_integer,
											l_parts.i_th (2).to_integer,
											l_parts.i_th (3).to_integer,
											l_parts.i_th (4).to_integer])
									end
								end
							end
						end
					else
						l_file.close
					end
				end
			end
		rescue
			l_retried := True
			retry
		end

feature {NONE} -- Pixels

	ink_grid (a_page: CAIRO_SURFACE; a_cols, a_rows: INTEGER): ARRAY [BOOLEAN]
			-- Which cells carry ink: pixels sampled every 4th in both
			-- axes, compared against the page's border-average
			-- background - so dark-mode readers work exactly like
			-- paper-white ones.
		require
			valid: a_page.is_valid
		local
			mp: MANAGED_POINTER
			stride, bg_r, bg_g, bg_b: INTEGER
			r, c, py, px, hits, total, off: INTEGER
			b, g, rr: INTEGER
		do
			a_page.flush.do_nothing
			stride := a_page.stride
			create mp.share_from_pointer (a_page.data, stride * a_page.height)
			background_of (mp, a_page.width, a_page.height, stride)
			bg_r := last_bg_r
			bg_g := last_bg_g
			bg_b := last_bg_b
			create Result.make_filled (False, 1, a_cols * a_rows)
			from
				r := 1
			until
				r > a_rows
			loop
				from
					c := 1
				until
					c > a_cols
				loop
					hits := 0
					total := 0
					from
						py := (r - 1) * Cell
					until
						py >= r * Cell
					loop
						from
							px := (c - 1) * Cell
						until
							px >= c * Cell
						loop
							off := py * stride + px * 4
							b := mp.read_natural_8 (off).to_integer_32
							g := mp.read_natural_8 (off + 1).to_integer_32
							rr := mp.read_natural_8 (off + 2).to_integer_32
							if (rr - bg_r).abs + (g - bg_g).abs + (b - bg_b).abs > Ink_distance then
								hits := hits + 1
							end
							total := total + 1
							px := px + 4
						end
						py := py + 4
					end
					if total > 0 and then hits * 100 >= total * Ink_percent then
						Result [(r - 1) * a_cols + c] := True
					end
					c := c + 1
				end
				r := r + 1
			end
		ensure
			sized: Result.count = a_cols * a_rows
		end

	background_of (a_mp: MANAGED_POINTER; a_w, a_h, a_stride: INTEGER)
			-- Average the page's border pixels into `last_bg_*': the
			-- edges of a captured page are background almost always.
		local
			x, y, n, sr, sg, sb, off: INTEGER
		do
			from
				x := 0
			until
				x >= a_w
			loop
				off := x * 4
				sb := sb + a_mp.read_natural_8 (off).to_integer_32
				sg := sg + a_mp.read_natural_8 (off + 1).to_integer_32
				sr := sr + a_mp.read_natural_8 (off + 2).to_integer_32
				off := (a_h - 1) * a_stride + x * 4
				sb := sb + a_mp.read_natural_8 (off).to_integer_32
				sg := sg + a_mp.read_natural_8 (off + 1).to_integer_32
				sr := sr + a_mp.read_natural_8 (off + 2).to_integer_32
				n := n + 2
				x := x + 8
			end
			from
				y := 0
			until
				y >= a_h
			loop
				off := y * a_stride
				sb := sb + a_mp.read_natural_8 (off).to_integer_32
				sg := sg + a_mp.read_natural_8 (off + 1).to_integer_32
				sr := sr + a_mp.read_natural_8 (off + 2).to_integer_32
				off := y * a_stride + (a_w - 1) * 4
				sb := sb + a_mp.read_natural_8 (off).to_integer_32
				sg := sg + a_mp.read_natural_8 (off + 1).to_integer_32
				sr := sr + a_mp.read_natural_8 (off + 2).to_integer_32
				n := n + 2
				y := y + 8
			end
			if n > 0 then
				last_bg_r := sr // n
				last_bg_g := sg // n
				last_bg_b := sb // n
			end
		end

	mask_box (a_mask: ARRAY [BOOLEAN]; a_cols, a_rows, a_x, a_y, a_w, a_h: INTEGER)
			-- Mark every cell a word box touches, grown by one cell
			-- all round: prose must never survive into candidacy.
		local
			c0, c1, r0, r1, r, c: INTEGER
		do
			c0 := (a_x // Cell).max (0)
			c1 := ((a_x + a_w) // Cell + 1).min (a_cols - 1)
			r0 := (a_y // Cell).max (0)
			r1 := ((a_y + a_h) // Cell + 1).min (a_rows - 1)
			from
				r := r0
			until
				r > r1
			loop
				from
					c := c0
				until
					c > c1
				loop
					a_mask [r * a_cols + c + 1] := True
					c := c + 1
				end
				r := r + 1
			end
		end

	last_bg_r, last_bg_g, last_bg_b: INTEGER
			-- The most recent background sample.

end
