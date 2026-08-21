note
	description: "[
		The Simple OCR Capture main window, rebuilt at FUNCTIONAL PARITY
		on the pure route - an inline-C Win32 window, every pixel painted
		by simple_cairo. No Vision2 in this process.

		Parity with the classic window, group by group:
		  Capture region   editable X/Y/W/H + Set Region by Dragging on a
		                   frozen-desktop overlay (pure BitBlt, replaces
		                   EV_SCREEN) + Test Capture with in-window thumbnail
		  Auto-advance     editable advance/indicator regions + settle, both
		                   drag-setters live; Start/Pause/Stop deferred with
		                   reason (the auto-run engine drives EV outlines)
		  Output           folder/file/drive editable, append/image/header
		                   checkboxes, png-bmp format cycle
		  Trigger          Ctrl/Alt/Shift + key, re-registered live
		  OCR engine       endpoint/model/timeout/ctx editable, Check Setup
		                   (OCR_HEALTH.run_quick) and Install Model
		                   (runtime.pull_command, async) wired
		  Findings         OCR_AUDIT.run over the real text file, report
		                   shown in the table area
		  Bottom rows      Capture Now (real --shot pipeline), Save Settings
		                   (OCR_SETTINGS.store), strip/thumbnail checkboxes
		                   bound to the shared settings

		Every field edits with a real caret (click to place, arrows, Home,
		End, Delete, Backspace) - the spike's editing engine, single-line.
		Every log/status line is mirrored to stdout so a session leaves a
		record.
	]"
	author: "Larry Rix"
	date: "$Date$"
	revision: "$Revision$"

class
	OCR_CAIRO_GUI

create
	make

feature {NONE} -- Initialization

	make
		local
			ns: NATIVE_STRING
			hwnd: POINTER
			done, dirty, first_png: BOOLEAN
			ev: INTEGER
		do
			create cairo.make
			f_display := {STRING_32} "Segoe UI"
			f_body := {STRING_32} "Georgia"
			f_mono := {STRING_32} "Consolas"
			load_private_fonts

			create settings
			settings.load
			create runtime.make (settings)
			runtime.prepare
			create preflight.make (settings)
			create health.make (settings, runtime, preflight)
			create audit.make (settings)
			create hotkey.make
			hotkey_ok := hotkey.register (settings.hotkey_modifiers, settings.hotkey_key)
			resolve_worker_exe
			create page_position
			create clicker.make
			create namer
			create dots.make (6)

			create findings_lines.make (16)
			create field_rects.make (24)
			create check_rects.make (12)
			create btn_rects.make (24)
			create edit_buf.make_empty
			set_status ({STRING_32} "loaded " + settings.settings_path)
			if winocr_found then
				log_line ({STRING_32} "label OCR: Windows OCR (fast path)")
			else
				log_line ({STRING_32} "label OCR: model worker (winocr_label.ps1 not found)")
			end

			offscreen := cairo.create_surface (Win_w, Win_h)
			ctx := cairo.create_context (offscreen)
			create ev_buf.make (16)
			render

			create ns.make (window_title)
			hwnd := c_create_window (ns.item, Win_w, Win_h)
			if hwnd = default_pointer then
				log_line ({STRING_32} "FAILED to create window")
			else
				log_line ({STRING_32} "cairo face up")
				if settings.show_strip then
					show_strip_win
				end
				from
				until
					done
				loop
					if c_pump = 0 then
						done := True
					else
						from
							ev := c_next (ev_buf.item)
						until
							ev = 0
						loop
							dispatch (ev, ev_buf.read_integer_32 (4), ev_buf.read_integer_32 (8))
							ev := c_next (ev_buf.item)
						end
						if overlay_mode > 0 then
							render_overlay
						elseif not done then
							render
							blit
							if not first_png then
								first_png := True
								if offscreen.write_png ("ocr_cairo_first_frame.png") then
									log_line ({STRING_32} "first frame written")
								end
							end
						end
						dirty := False
					end
				end
			end
			shutdown
		end

	dispatch (a_ev, a_a, a_b: INTEGER)
		do
			if a_ev = 2 then
				on_click (a_a, a_b)
			elseif a_ev = 3 then
				on_char (a_a)
			elseif a_ev = 4 then
				on_key (a_a)
			elseif a_ev = 7 then
				on_tick
			elseif a_ev = 12 then
				on_overlay_move (a_a, a_b)
			elseif a_ev = 13 then
				on_overlay_down (a_a, a_b)
			elseif a_ev = 14 then
				on_overlay_up (a_a, a_b)
			elseif a_ev = 15 then
				cancel_overlay
			elseif a_ev = 21 then
				on_strip_click (a_a, a_b)
			elseif a_ev = 22 then
				on_strip_moved (a_a, a_b)
			elseif a_ev = 23 then
				blit_strip
			end
		end

	shutdown
		do
			hotkey.cleanup
			hide_strip_win
			if attached worker_p as p then
				p.close
			end
			if attached label_p as p then
				p.close
			end
			if attached pull_process as p then
				p.close
			end
			ctx.destroy
			offscreen.destroy
			log_line ({STRING_32} "session closed")
		end

feature {NONE} -- Product machinery

	settings: OCR_SETTINGS
	runtime: OCR_RUNTIME
	preflight: OCR_PREFLIGHT
	health: OCR_HEALTH
	audit: OCR_AUDIT
	hotkey: OCR_HOTKEY
	hotkey_ok: BOOLEAN
	did_preflight: BOOLEAN

	worker_exe: STRING_32
		attribute
			create Result.make_empty
		end

	exe_found: BOOLEAN

	winocr_script: STRING_32
		attribute
			create Result.make_empty
		end

	winocr_found: BOOLEAN

	resolve_worker_exe
		local
			f: RAW_FILE
			candidates: ARRAY [STRING_32]
			i: INTEGER
		do
			candidates := <<
				{STRING_32} "D:\prod\simple_ocr_capture\EIFGENs\ocr_capture\F_code\simple_ocr_capture.exe",
				{STRING_32} "C:\Program Files\Simple OCR Capture\simple_ocr_capture.exe">>
			winocr_script := {STRING_32} "D:\prod\simple_ocr_capture\ocr_cairo\winocr_label.ps1"
			create f.make_with_name (winocr_script)
			winocr_found := f.exists
			from
				i := candidates.lower
			until
				i > candidates.upper or exe_found
			loop
				create f.make_with_name (candidates [i])
				if f.exists then
					worker_exe := candidates [i]
					exe_found := True
				end
				i := i + 1
			end
		end

feature {NONE} -- Status line (mirrored to stdout)

	status_msg: STRING_32
		attribute
			create Result.make_empty
		end

	status_is_error: BOOLEAN

	set_status (a_s: STRING_32)
		do
			status_msg := a_s
			status_is_error := False
			log_line (a_s)
		end

	set_error (a_s: STRING_32)
		do
			status_msg := a_s
			status_is_error := True
			log_line ({STRING_32} "! " + a_s)
		end

	log_line (a_s: STRING_32)
			-- Append to the session log. NEVER print: in a GUI-subsystem
			-- Eiffel program the runtime allocates a console on the first
			-- console write - that was Larry's mystery DOS window.
		local
			f: PLAIN_TEXT_FILE
		do
			create f.make_with_name ("ocr_cairo_session.log")
			if f.exists then
				f.open_append
			else
				f.open_write
			end
			if f.is_open_write then
				f.put_string (a_s.to_string_8)
				f.put_new_line
				f.close
			end
		end

feature {NONE} -- Run engine (the product cycle, pure)

	Run_idle: INTEGER = 0
	Run_single: INTEGER = 1
	Run_auto: INTEGER = 2

	run_mode: INTEGER
	run_paused: BOOLEAN
	cyc_working: BOOLEAN
	cyc_settling: BOOLEAN

	equal_strikes: INTEGER
			-- Consecutive unchanged re-grabs; the book is only declared
			-- finished on the second, so a slow page render is not
			-- mistaken for the back cover.

	grab_cur: detachable CAIRO_SURFACE
	grab_prev: detachable CAIRO_SURFACE
	worker_p: detachable SIMPLE_ASYNC_PROCESS
	label_p: detachable SIMPLE_ASYNC_PROCESS

	page_position: OCR_PAGE_POSITION
	clicker: OCR_CLICKER
	namer: OCR_IMAGE_NAME

	last_label: STRING_32
		attribute
			create Result.make_empty
		end

	dots: ARRAYED_LIST [INTEGER]
			-- Last outcomes: 1 ok, 2 failed.

	pages_done: INTEGER
	shots_done: INTEGER
	t_settle: REAL_64
	t_run_start: REAL_64
	last_shot_ms: REAL_64
	t_page_start: REAL_64

	is_engine_busy: BOOLEAN
		do
			Result := run_mode /= Run_idle
		end

	state_word: STRING_32
		do
			if run_mode = Run_idle then
				Result := {STRING_32} "READY"
			elseif run_paused then
				Result := {STRING_32} "PAUSED"
			elseif cyc_working then
				Result := {STRING_32} "READING"
			elseif cyc_settling then
				Result := {STRING_32} "TURNING"
			else
				Result := {STRING_32} "RUNNING"
			end
		end

	grab_region_surface: detachable CAIRO_SURFACE
			-- Fresh grab of the capture region, or Void on failure.
		local
			s: CAIRO_SURFACE
		do
			s := cairo.create_surface (settings.region_width, settings.region_height)
			if c_grab_screen (settings.region_x, settings.region_y,
				settings.region_width, settings.region_height, s.data, s.stride) = 1
			then
				s.mark_dirty.do_nothing
				Result := s
			else
				s.destroy
			end
		end

	begin_single
		do
			if is_engine_busy then
				set_status ({STRING_32} "busy %/8212/ a capture cycle is already running")
			elseif not exe_found then
				set_error ({STRING_32} "cannot capture: worker exe not found")
			elseif not settings.is_region_valid then
				set_error ({STRING_32} "cannot capture: region not set")
			else
				grab_cur := grab_region_surface
				if grab_cur = Void then
					set_error ({STRING_32} "screen grab failed")
				else
					run_mode := Run_single
					kick_capture
				end
			end
		end

	start_run
		do
			if is_engine_busy then
				set_status ({STRING_32} "already running")
			elseif not exe_found then
				set_error ({STRING_32} "cannot start: worker exe not found")
			elseif not settings.is_region_valid then
				set_error ({STRING_32} "cannot start: capture region not set")
			elseif not settings.is_advance_region_valid then
				set_error ({STRING_32} "cannot start: advance button not set %/8212/ drag it in Auto-advance")
			else
				grab_cur := grab_region_surface
				if grab_cur = Void then
					set_error ({STRING_32} "screen grab failed")
				else
					run_mode := Run_auto
					run_paused := False
					pages_done := 0
					dots.wipe_out
					t_run_start := c_now_ms
					if not strip_visible then
						show_strip_win
					end
					set_status ({STRING_32} "auto-run started %/8212/ watch the strip; Pause or Stop any time")
					kick_capture
				end
			end
		end

	pause_resume
		do
			if run_mode = Run_auto then
				run_paused := not run_paused
				if run_paused then
					set_status ({STRING_32} "paused %/8212/ finishing the page in flight, then holding")
				else
					set_status ({STRING_32} "resumed")
					if cyc_settling then
						t_settle := c_now_ms
					end
				end
			else
				set_status ({STRING_32} "nothing to pause %/8212/ start a run first")
			end
		end

	stop_run (a_reason: STRING_32)
		do
			if attached worker_p as w then
				w.close
			end
			worker_p := Void
			if attached label_p as l then
				l.close
			end
			label_p := Void
			run_mode := Run_idle
			run_paused := False
			cyc_working := False
			cyc_settling := False
			equal_strikes := 0
			set_status (a_reason)
		end

	kick_capture
			-- Save the current grab, send it to the real worker (append
			-- pipeline), and start the page-indicator read when configured.
		local
			img: STRING_32
			cmd: STRING_32
			w: SIMPLE_ASYNC_PROCESS
		do
			if attached grab_cur as g then
				t_page_start := c_now_ms
				img := settings.output_folder.twin
				img.append_character ('\')
				img.append (namer.stem (last_label, settings.capture_index))
				img.append_string_general (".png")
				settings.bump_capture_index
				if g.write_png (img) then
					create cmd.make (160)
					cmd.append_character ('%"')
					cmd.append (worker_exe)
					cmd.append_string_general ("%" --worker %"")
					cmd.append (img)
					cmd.append_string_general ("%" %"")
					cmd.append (settings.text_file_path)
					cmd.append_character ('%"')
					create w.make
					w.set_show_window (False)
					w.start (cmd)
					if w.is_started then
						worker_p := w
						cyc_working := True
						cyc_settling := False
						shots_done := shots_done + 1
						set_status ({STRING_32} "page " + (pages_done + 1).out.to_string_32
							+ {STRING_32} ": OCR in flight %/8230/")
						start_label_read
					else
						stop_run ({STRING_32} "worker failed to start")
					end
				else
					stop_run ({STRING_32} "could not write " + img)
				end
			end
		end

	label_img_path: STRING_32
		do
			Result := settings.output_folder.twin
			Result.append_string_general ("\\ocr_label_probe.png")
		end

	label_txt_path: STRING_32
		do
			Result := settings.output_folder.twin
			Result.append_string_general ("\\ocr_label_probe.txt")
		end

	start_label_read
			-- Grab the page-indicator region and OCR it via the label worker.
		local
			s: CAIRO_SURFACE
			cmd: STRING_32
			l: SIMPLE_ASYNC_PROCESS
		do
			if settings.is_page_label_region_valid and label_p = Void then
				s := cairo.create_surface (settings.page_label_width, settings.page_label_height)
				if c_grab_screen (settings.page_label_x, settings.page_label_y,
					settings.page_label_width, settings.page_label_height, s.data, s.stride) = 1
				then
					s.mark_dirty.do_nothing
					if s.write_png (label_img_path) then
						create cmd.make (200)
						if winocr_found then
								-- Windows OCR: ~0.3 s for a five-word label vs
								-- seconds for the 7B model. Cannon retired;
								-- flyswatter deployed.
							cmd.append_string_general ("powershell.exe -NoProfile -ExecutionPolicy Bypass -File %"")
							cmd.append (winocr_script)
							cmd.append_string_general ("%" %"")
							cmd.append (label_img_path)
							cmd.append_string_general ("%" %"")
							cmd.append (label_txt_path)
							cmd.append_character ('%"')
						else
							cmd.append_character ('%"')
							cmd.append (worker_exe)
							cmd.append_string_general ("%" --label-worker %"")
							cmd.append (label_img_path)
							cmd.append_string_general ("%" %"")
							cmd.append (label_txt_path)
							cmd.append_character ('%"')
						end
						create l.make
						l.set_show_window (False)
						l.start (cmd)
						if l.is_started then
							label_p := l
						else
							log_line ({STRING_32} "label spawn FAILED: " + cmd)
						end
					end
				end
				s.destroy
			end
		end

	read_label_file: STRING_32
		local
			f: PLAIN_TEXT_FILE
		do
			create Result.make_empty
			create f.make_with_name (label_txt_path)
			if f.exists and then f.is_readable then
				f.open_read
				if f.count > 0 then
					f.read_stream (f.count.min (200))
					Result := f.last_string.to_string_32
				end
				f.close
			end
			Result.prune_all ('%R')
			if Result.has ('%N') then
					-- first line only: the worker parks failure reasons on line 2
				Result.keep_head (Result.index_of ('%N', 1) - 1)
			end
		end

	engine_tick
		local
			ok: BOOLEAN
			n: detachable CAIRO_SURFACE
		do
			if attached label_p as l and then l.has_finished then
				log_line ({STRING_32} "label worker exit " + l.exit_code.out)
				l.close
				label_p := Void
				last_label := read_label_file
				if last_label.is_empty then
					log_line ({STRING_32} "label read: EMPTY")
				else
					log_line ({STRING_32} "label read: " + last_label)
					page_position.set_from (last_label)
					log_line ({STRING_32} "label parsed: pos " + page_position.position.out
						+ " total " + page_position.total.out)
				end
			end
			if cyc_working and then attached worker_p as w and then w.has_finished then
				ok := w.exit_code = 0
				w.close
				worker_p := Void
				cyc_working := False
				last_shot_ms := c_now_ms - t_page_start
				if ok then
					pages_done := pages_done + 1
					push_dot (1)
				else
					push_dot (2)
				end
				if not ok then
					stop_run ({STRING_32} "OCR worker failed %/8212/ run stopped")
				elseif run_mode = Run_single then
					run_mode := Run_idle
					set_status ({STRING_32} "captured and appended in " + ms_str (last_shot_ms)
						+ {STRING_32} " ms %/8212/ " + settings.text_file_name)
				else
					if clicker.click_centre_of (settings.advance_x, settings.advance_y,
						settings.advance_width, settings.advance_height)
					then
						cyc_settling := True
						t_settle := c_now_ms
					else
						stop_run ({STRING_32} "could not click the advance button %/8212/ run stopped")
					end
				end
			end
			if cyc_settling and then not run_paused
				and then c_now_ms - t_settle >= settings.advance_delay_ms.max (100)
			then
				cyc_settling := False
				n := grab_region_surface
				if n = Void then
					stop_run ({STRING_32} "screen grab failed %/8212/ run stopped")
				elseif attached grab_cur as g and then surfaces_equal (g, n) then
					n.destroy
					if equal_strikes = 0 then
							-- one more settle period, then a second look:
							-- a slow render must not read as end-of-book
						equal_strikes := 1
						cyc_settling := True
						t_settle := c_now_ms
						log_line ({STRING_32} "page unchanged %/8212/ waiting to confirm end")
					else
						stop_run ({STRING_32} "page stopped changing %/8212/ book finished after "
							+ pages_done.out.to_string_32 + {STRING_32} " pages")
					end
				else
					equal_strikes := 0
					if attached grab_prev as gp then
						gp.destroy
					end
					grab_prev := grab_cur
					grab_cur := n
					kick_capture
				end
			end
		end

	surfaces_equal (a, b: CAIRO_SURFACE): BOOLEAN
		do
			a.flush.do_nothing
			b.flush.do_nothing
			Result := a.width = b.width and then a.height = b.height
				and then c_bufs_equal (a.data, b.data, a.stride * a.height) = 1
		end

	push_dot (a_kind: INTEGER)
		do
			dots.extend (a_kind)
			if dots.count > 6 then
				dots.start
				dots.remove
			end
		end

feature {NONE} -- Status strip window (parity with the classic strip)

	strip_visible: BOOLEAN
	strip_surface: detachable CAIRO_SURFACE
	strip_ctx: detachable CAIRO_CONTEXT

	Strip_w: INTEGER = 320
	Strip_h: INTEGER = 430

	toggle_strip
		do
			if strip_visible then
				hide_strip_win
			else
				show_strip_win
			end
		end

	show_strip_win
		local
			s: CAIRO_SURFACE
		do
			if strip_surface = Void then
				s := cairo.create_surface (Strip_w, Strip_h)
				strip_surface := s
				strip_ctx := cairo.create_context (s)
			end
			if c_show_strip (settings.strip_x, settings.strip_y, Strip_w, Strip_h) /= default_pointer then
				strip_visible := True
				render_strip
				blit_strip
			end
		end

	hide_strip_win
		do
			c_hide_strip
			strip_visible := False
		end

	on_strip_click (a_x, a_y: INTEGER)
		do
			if a_y < 26 and a_x > Strip_w - 90 then
				if a_x > Strip_w - 90 and a_x <= Strip_w - 62 then
					if run_mode = Run_idle then
						start_run
					elseif run_paused then
						pause_resume
					end
				elseif a_x > Strip_w - 62 and a_x <= Strip_w - 34 then
					pause_resume
				else
					stop_run ({STRING_32} "stopped from the strip")
				end
			end
		end

	on_strip_moved (a_x, a_y: INTEGER)
		do
			settings.set_strip_position (a_x, a_y)
		end

	render_strip
		local
			c: CAIRO_CONTEXT
			i, x: INTEGER
			y, sc, sw, sh: REAL_64
			s: STRING_32
		do
			if attached strip_ctx as sctx then
				c := sctx
				c.set_color_hex (0x14181F).paint.do_nothing
				-- dots
				from
					i := 1
				until
					i > 6
				loop
					if i <= dots.count then
						if dots [i] = 1 then
							c.set_color_hex (0x35C46F).do_nothing
						else
							c.set_color_hex (0xE0563A).do_nothing
						end
					else
						c.set_color_hex (0x3A4250).do_nothing
					end
					c.fill_circle (16.0 + (i - 1) * 16.0, 14.0, 5.0).do_nothing
					i := i + 1
				end
				-- state word
				strip_font (14.0, True)
				strip_txt (c, 118.0, 19.0, state_word, 0xE8ECF2)
				-- transport: play / pause / stop
				c.set_color_hex (0xB9C2CE).do_nothing
				c.move_to (Strip_w - 84.0, 8.0).line_to (Strip_w - 84.0, 20.0)
					.line_to (Strip_w - 73.0, 14.0).close_path.fill.do_nothing
				c.fill_rect (Strip_w - 58.0, 8.0, 4.0, 12.0)
					.fill_rect (Strip_w - 50.0, 8.0, 4.0, 12.0).do_nothing
				c.fill_rect (Strip_w - 30.0, 8.0, 12.0, 12.0).do_nothing
				-- thumbnail
				if settings.show_thumbnail and attached grab_cur as g then
					sc := (250.0 / g.height).min (288.0 / g.width)
					sw := g.width * sc
					sh := g.height * sc
					c.set_color_hex (0xFFFFFF)
						.fill_rect (16.0 + (288.0 - sw) / 2.0 - 3.0, 34.0 + (250.0 - sh) / 2.0 - 3.0, sw + 6.0, sh + 6.0).do_nothing
					c.save.translate (16.0 + (288.0 - sw) / 2.0, 34.0 + (250.0 - sh) / 2.0)
						.scale (sc, sc).set_source_surface (g, 0.0, 0.0).paint.do_nothing
					c.restore.do_nothing
				else
					strip_font (10.0, False)
					strip_txt (c, 70.0, 160.0, {STRING_32} "no capture yet", 0x8A93A0)
				end
				-- stats
				y := 306.0
				strip_font (13.0, False)
				if page_position.has_position and page_position.has_total then
					s := {STRING_32} "Page " + page_position.position.out.to_string_32
						+ {STRING_32} " of " + page_position.total.out.to_string_32
						+ {STRING_32} "   " + pct_str + {STRING_32} "%%"
				else
					s := {STRING_32} "Pages this run: " + pages_done.out.to_string_32
				end
				strip_txt (c, 16.0, y, s, 0xE8ECF2)
				y := y + 24.0
				strip_txt (c, 16.0, y, rate_line, 0x58D08A)
				y := y + 24.0
				strip_txt (c, 16.0, y, eta_line, 0x6FC7E8)
				y := y + 24.0
				strip_txt (c, 16.0, y, finish_line, 0xE8D06A)
				x := 0
			end
		end

	strip_font (a_size: REAL_64; a_bold: BOOLEAN)
		do
			if attached strip_ctx as c then
				if a_bold then
					c.select_font (f_mono, c.Slant_normal, c.Weight_bold).do_nothing
				else
					c.select_font (f_mono, c.Slant_normal, c.Weight_normal).do_nothing
				end
				c.set_font_size (a_size).do_nothing
			end
		end

	strip_txt (a_c: CAIRO_CONTEXT; a_x, a_y: REAL_64; a_s: STRING_32; a_color: NATURAL_32)
		do
			a_c.set_color_hex (a_color).move_to (a_x, a_y).show_text (a_s).do_nothing
		end

	run_minutes: REAL_64
		do
			if t_run_start > 0.0 then
				Result := (c_now_ms - t_run_start) / 60000.0
			end
		end

	pages_per_min: REAL_64
		do
			if run_minutes > 0.05 and pages_done > 0 then
				Result := pages_done / run_minutes
			end
		end

	pct_str: STRING_32
		local
			pc: INTEGER
		do
			if page_position.total > 0 then
				pc := page_position.position * 100 // page_position.total
			end
			Result := pc.out.to_string_32
		end

	rate_line: STRING_32
		do
			if pages_per_min > 0.0 then
				Result := ms_str (pages_per_min) + {STRING_32} " pg/min   last "
					+ ms_str (last_shot_ms / 1000.0) + {STRING_32} " s"
			else
				Result := {STRING_32} "measuring rate %/8230/"
			end
		end

	eta_minutes: INTEGER
		do
			if pages_per_min > 0.0 and page_position.has_total and page_position.has_position
				and page_position.total > page_position.position
			then
				Result := (((page_position.total - page_position.position) / pages_per_min) + 0.5).truncated_to_integer
			end
		end

	eta_line: STRING_32
		do
			if eta_minutes > 0 then
				Result := {STRING_32} "ETA " + eta_minutes.out.to_string_32
					+ {STRING_32} " min   ("
					+ (page_position.total - page_position.position).out.to_string_32
					+ {STRING_32} " pages left)"
			else
				Result := {STRING_32} "ETA %/8212/"
			end
		end

	finish_line: STRING_32
		local
			m, h: INTEGER
			ampm: STRING_32
		do
			if eta_minutes > 0 then
				m := (c_minutes_of_day + eta_minutes) \\ 1440
				h := m // 60
				if h >= 12 then
					ampm := {STRING_32} " PM"
				else
					ampm := {STRING_32} " AM"
				end
				if h = 0 then
					h := 12
				elseif h > 12 then
					h := h - 12
				end
				Result := {STRING_32} "finishing about " + h.out.to_string_32
					+ {STRING_32} ":" + two_digits (m \\ 60) + ampm
			else
				create Result.make_empty
			end
		end

	two_digits (a_n: INTEGER): STRING_32
		do
			create Result.make (2)
			if a_n < 10 then
				Result.append_character ('0')
			end
			Result.append_string_general (a_n.out)
		end

	blit_strip
		local
			hdc: POINTER
			ws: CAIRO_SURFACE
			c2: CAIRO_CONTEXT
		do
			if strip_visible and attached strip_surface as ss then
				ss.flush.do_nothing
				hdc := c_strip_dc
				if hdc /= default_pointer then
					create ws.make_for_dc (hdc)
					if ws.is_valid then
						create c2.make (ws)
						c2.set_source_surface (ss, 0.0, 0.0).paint.do_nothing
						c2.destroy
					end
					ws.destroy
					c_strip_release (hdc)
				end
			end
		end

feature {NONE} -- Model install (real, async)

	pull_process: detachable SIMPLE_ASYNC_PROCESS
	pull_ticks: INTEGER

	is_pulling: BOOLEAN
		do
			Result := attached pull_process as p and then not p.has_finished
		end

	start_pull
		local
			p: SIMPLE_ASYNC_PROCESS
		do
			if is_pulling then
				set_status ({STRING_32} "a model download is already running")
			elseif not runtime.is_executable_found then
				set_error ({STRING_32} "ollama executable not located; is Ollama installed?")
			else
				create p.make
				p.set_show_window (False)
				p.start (runtime.pull_command (settings.model))
				if p.is_started then
					pull_process := p
					pull_ticks := 0
					set_status ({STRING_32} "downloading model %/8230/ the window stays usable")
				else
					set_error ({STRING_32} "could not start ollama pull")
				end
			end
		end

	poll_pull
		do
			if attached pull_process as p then
				if p.has_finished then
					p.close
					pull_process := Void
					preflight.refresh
					if preflight.is_model_present then
						set_status ({STRING_32} "model installed %/8212/ ready to capture")
					else
						set_error ({STRING_32} "download finished but the model is not listed; check Ollama logs")
					end
				else
					pull_ticks := pull_ticks + 1
					if pull_ticks \\ 2 = 0 then
						set_status ({STRING_32} "downloading model %/8230/ "
							+ (pull_ticks // 2).out.to_string_32 + {STRING_32} "s")
					end
				end
			end
		end

feature {NONE} -- Tick

	ticks: INTEGER
	blink_on: BOOLEAN

	on_tick
		do
			ticks := ticks + 1
			blink_on := not blink_on
			if hotkey_ok and then hotkey.taken_presses > 0 then
				begin_single
			end
			engine_tick
			poll_pull
			if not is_engine_busy and not is_pulling
				and then (not did_preflight or ticks \\ 24 = 0)
			then
				preflight.refresh
				did_preflight := True
			end
			if strip_visible then
				render_strip
				blit_strip
			end
		end

feature {NONE} -- Field editing engine (the spike's editor, single-line)

	focused_id: INTEGER
	edit_buf: STRING_32
	edit_caret: INTEGER

	field_value (a_id: INTEGER): STRING_32
			-- Current display value of field `a_id' from the model.
		do
			inspect a_id
			when 1 then Result := settings.region_x.out.to_string_32
			when 2 then Result := settings.region_y.out.to_string_32
			when 3 then Result := settings.region_width.out.to_string_32
			when 4 then Result := settings.region_height.out.to_string_32
			when 5 then Result := settings.advance_x.out.to_string_32
			when 6 then Result := settings.advance_y.out.to_string_32
			when 7 then Result := settings.advance_width.out.to_string_32
			when 8 then Result := settings.advance_height.out.to_string_32
			when 9 then Result := settings.page_label_x.out.to_string_32
			when 10 then Result := settings.page_label_y.out.to_string_32
			when 11 then Result := settings.page_label_width.out.to_string_32
			when 12 then Result := settings.page_label_height.out.to_string_32
			when 13 then Result := settings.advance_delay_ms.out.to_string_32
			when 14 then Result := settings.output_folder.twin
			when 15 then Result := settings.text_file_name.twin
			when 16 then Result := settings.move_to_drive.twin
			when 17 then Result := key_name (settings.hotkey_key)
			when 18 then Result := settings.endpoint.to_string_32
			when 19 then Result := settings.model.to_string_32
			when 20 then Result := settings.ocr_timeout_seconds.out.to_string_32
			when 21 then Result := settings.num_ctx.out.to_string_32
			else
				create Result.make_empty
			end
		end

	focus_field (a_id: INTEGER; a_click_x: REAL_64; a_fx: REAL_64)
		local
			i: INTEGER
			x: REAL_64
		do
			commit_focused
			focused_id := a_id
			edit_buf := field_value (a_id)
			set_font (f_mono, 10.5, False)
			edit_caret := edit_buf.count
			x := 0.0
			from
				i := 1
			until
				i > edit_buf.count
			loop
				x := x + adv (one_char (edit_buf [i]))
				if a_fx + 8.0 + x - (adv (one_char (edit_buf [i])) / 2.0) > a_click_x then
					edit_caret := i - 1
					i := edit_buf.count -- exit
				end
				i := i + 1
			end
			blink_on := True
		end

	commit_focused
		local
			v: INTEGER
			ok: BOOLEAN
		do
			if focused_id > 0 then
				ok := True
				inspect focused_id
				when 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 20, 21 then
					if edit_buf.is_integer then
						v := edit_buf.to_integer
						inspect focused_id
						when 1 then settings.set_region (v, settings.region_y, settings.region_width, settings.region_height)
						when 2 then settings.set_region (settings.region_x, v, settings.region_width, settings.region_height)
						when 3 then
							if v > 0 then
								settings.set_region (settings.region_x, settings.region_y, v, settings.region_height)
							else
								ok := False
							end
						when 4 then
							if v > 0 then
								settings.set_region (settings.region_x, settings.region_y, settings.region_width, v)
							else
								ok := False
							end
						when 5 then settings.set_advance_region (v, settings.advance_y, settings.advance_width, settings.advance_height)
						when 6 then settings.set_advance_region (settings.advance_x, v, settings.advance_width, settings.advance_height)
						when 7 then settings.set_advance_region (settings.advance_x, settings.advance_y, v, settings.advance_height)
						when 8 then settings.set_advance_region (settings.advance_x, settings.advance_y, settings.advance_width, v)
						when 9 then settings.set_page_label_region (v, settings.page_label_y, settings.page_label_width, settings.page_label_height)
						when 10 then settings.set_page_label_region (settings.page_label_x, v, settings.page_label_width, settings.page_label_height)
						when 11 then settings.set_page_label_region (settings.page_label_x, settings.page_label_y, v, settings.page_label_height)
						when 12 then settings.set_page_label_region (settings.page_label_x, settings.page_label_y, settings.page_label_width, v)
						when 13 then
							if v >= 0 then
								settings.set_advance_delay_ms (v)
							else
								ok := False
							end
						when 20 then
							if v > 0 then
								settings.set_ocr_timeout_seconds (v)
							else
								ok := False
							end
						when 21 then
							if v > 0 then
								settings.set_num_ctx (v)
							else
								ok := False
							end
						else
						end
					else
						ok := False
					end
					if not ok then
						set_error ({STRING_32} "not applied: %"" + edit_buf + {STRING_32} "%" is not a valid number here")
					end
				when 14 then
					settings.set_output_folder (edit_buf)
				when 15 then
					if edit_buf.is_empty then
						set_error ({STRING_32} "text file name cannot be empty")
					else
						settings.set_text_file_name (edit_buf)
					end
				when 16 then
					settings.set_move_to_drive (edit_buf)
				when 17 then
					apply_key_name
				when 18 then
					if edit_buf.is_empty then
						set_error ({STRING_32} "endpoint cannot be empty")
					else
						settings.set_endpoint (edit_buf.to_string_8)
					end
				when 19 then
					if edit_buf.is_empty then
						set_error ({STRING_32} "model cannot be empty")
					else
						settings.set_model (edit_buf.to_string_8)
					end
				else
				end
				focused_id := 0
			end
		end

	key_name (a_vk: NATURAL_32): STRING_32
		do
			create Result.make (1)
			if a_vk >= 0x41 and a_vk <= 0x5A then
				Result.extend (a_vk.to_character_32)
			elseif a_vk >= 0x30 and a_vk <= 0x39 then
				Result.extend (a_vk.to_character_32)
			elseif a_vk >= 0x70 and a_vk <= 0x7B then
				Result.append_character ('F')
				Result.append_string_general ((a_vk - 0x6F).out)
			else
				Result.append_string_general ("0x")
				Result.append_string_general (a_vk.to_hex_string)
			end
		end

	apply_key_name
		local
			c: CHARACTER_32
			vk: NATURAL_32
		do
			if edit_buf.count = 1 then
				c := edit_buf [1].as_upper
				if (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') then
					vk := c.natural_32_code
					settings.set_hotkey (settings.hotkey_modifiers, vk)
					reregister_hotkey
				else
					set_error ({STRING_32} "trigger key must be a letter or digit")
				end
			else
				set_error ({STRING_32} "trigger key must be one character")
			end
		end

	reregister_hotkey
		do
			hotkey.unregister
			hotkey_ok := hotkey.register (settings.hotkey_modifiers, settings.hotkey_key)
			if hotkey_ok then
				set_status ({STRING_32} "hotkey registered: " + hotkey_text)
			else
				set_error ({STRING_32} "hotkey unavailable: " + hotkey_text)
			end
		end

	hotkey_text: STRING_32
		do
			create Result.make (16)
			if settings.hotkey_modifiers.bit_and (2) /= 0 then
				Result.append_string_general ("Ctrl+")
			end
			if settings.hotkey_modifiers.bit_and (1) /= 0 then
				Result.append_string_general ("Alt+")
			end
			if settings.hotkey_modifiers.bit_and (4) /= 0 then
				Result.append_string_general ("Shift+")
			end
			Result.append (key_name (settings.hotkey_key))
		end

	on_char (a_code: INTEGER)
		do
			if focused_id > 0 then
				if a_code = 13 then
					commit_focused
				elseif a_code = 27 then
					focused_id := 0
				elseif a_code = 8 then
					if edit_caret > 0 then
						edit_buf.remove (edit_caret)
						edit_caret := edit_caret - 1
					end
				elseif a_code >= 32 then
					edit_buf.insert_character (a_code.to_character_32, edit_caret + 1)
					edit_caret := edit_caret + 1
				end
				blink_on := True
			end
		end

	on_key (a_vk: INTEGER)
		do
			if focused_id > 0 then
				if a_vk = 37 and edit_caret > 0 then
					edit_caret := edit_caret - 1
				elseif a_vk = 39 and edit_caret < edit_buf.count then
					edit_caret := edit_caret + 1
				elseif a_vk = 36 then
					edit_caret := 0
				elseif a_vk = 35 then
					edit_caret := edit_buf.count
				elseif a_vk = 46 and edit_caret < edit_buf.count then
					edit_buf.remove (edit_caret + 1)
				end
				blink_on := True
			end
		end

feature {NONE} -- Drag overlay (pure-route region picker)

	overlay_mode: INTEGER
			-- 0 none | 1 capture region | 2 advance button | 3 page indicator

	overlay_frozen: detachable CAIRO_SURFACE
	drag_active: BOOLEAN
	drag_x0, drag_y0, drag_x1, drag_y1: INTEGER

	begin_overlay (a_mode: INTEGER)
		local
			s: CAIRO_SURFACE
			vw, vh: INTEGER
		do
			commit_focused
			vw := c_screen_w
			vh := c_screen_h
			s := cairo.create_surface (vw, vh)
			if c_grab_screen (c_screen_x, c_screen_y, vw, vh, s.data, s.stride) = 1 then
				s.mark_dirty.do_nothing
				overlay_frozen := s
				overlay_mode := a_mode
				drag_active := False
				if c_show_overlay = default_pointer then
					set_error ({STRING_32} "overlay window failed")
					overlay_mode := 0
					s.destroy
					overlay_frozen := Void
				else
					render_overlay
				end
			else
				s.destroy
				set_error ({STRING_32} "screen grab failed")
			end
		end

	on_overlay_down (a_x, a_y: INTEGER)
		do
			drag_active := True
			drag_x0 := a_x
			drag_y0 := a_y
			drag_x1 := a_x
			drag_y1 := a_y
		end

	on_overlay_move (a_x, a_y: INTEGER)
		do
			if drag_active then
				drag_x1 := a_x
				drag_y1 := a_y
				render_overlay
			end
		end

	on_overlay_up (a_x, a_y: INTEGER)
		local
			x, y, w, h: INTEGER
		do
			if drag_active then
				drag_x1 := a_x
				drag_y1 := a_y
				x := drag_x0.min (drag_x1) + c_screen_x
				y := drag_y0.min (drag_y1) + c_screen_y
				w := (drag_x1 - drag_x0).abs
				h := (drag_y1 - drag_y0).abs
				if w < 4 or h < 4 then
					set_error ({STRING_32} "selection too small %/8212/ nothing changed")
				else
					inspect overlay_mode
					when 1 then
						settings.set_region (x, y, w, h)
						set_status ({STRING_32} "capture region set to " + w.out.to_string_32
							+ {STRING_32} " x " + h.out.to_string_32
							+ {STRING_32} " %/8212/ Save Settings to persist")
					when 2 then
						settings.set_advance_region (x, y, w, h)
						set_status ({STRING_32} "advance button set %/8212/ Save Settings to persist")
					when 3 then
						settings.set_page_label_region (x, y, w, h)
						set_status ({STRING_32} "page indicator set %/8212/ Save Settings to persist")
					else
					end
				end
			end
			cancel_overlay
		end

	cancel_overlay
		do
			c_hide_overlay
			overlay_mode := 0
			drag_active := False
			if attached overlay_frozen as s then
				s.destroy
			end
			overlay_frozen := Void
			render
			blit
		end

	render_overlay
		local
			hdc: POINTER
			ws: CAIRO_SURFACE
			c2: CAIRO_CONTEXT
			x, y, w, h: REAL_64
		do
			hdc := c_overlay_dc
			if hdc /= default_pointer and then attached overlay_frozen as fz then
				create ws.make_for_dc (hdc)
				if ws.is_valid then
					create c2.make (ws)
					c2.set_source_surface (fz, 0.0, 0.0).paint.do_nothing
					c2.set_color_rgba (0.0, 0.0, 0.0, 0.25).paint.do_nothing
					if drag_active then
						x := drag_x0.min (drag_x1)
						y := drag_y0.min (drag_y1)
						w := (drag_x1 - drag_x0).abs
						h := (drag_y1 - drag_y0).abs
						if w > 0.0 and h > 0.0 then
							c2.save.clip_rectangle (x, y, w.max (1.0), h.max (1.0)).do_nothing
							c2.set_source_surface (fz, 0.0, 0.0).paint.do_nothing
							c2.restore.do_nothing
							c2.set_color_hex (0xAF3A22).set_line_width (2.0)
								.rectangle (x, y, w, h).stroke.do_nothing
						end
					end
					c2.destroy
				end
				ws.destroy
				c_overlay_release (hdc)
			end
		end

feature {NONE} -- Test capture (pure grab, in-window thumbnail)

	thumb: detachable CAIRO_SURFACE
	thumb_w, thumb_h: INTEGER

	do_test_capture
		local
			s: CAIRO_SURFACE
		do
			commit_focused
			if not settings.is_region_valid then
				set_error ({STRING_32} "region not set")
			else
				s := cairo.create_surface (settings.region_width, settings.region_height)
				if c_grab_screen (settings.region_x, settings.region_y,
					settings.region_width, settings.region_height, s.data, s.stride) = 1
				then
					s.mark_dirty.do_nothing
					if attached thumb as old_t then
						old_t.destroy
					end
					thumb := s
					thumb_w := settings.region_width
					thumb_h := settings.region_height
					set_status ({STRING_32} "test capture: " + thumb_w.out.to_string_32
						+ {STRING_32} " x " + thumb_h.out.to_string_32
						+ {STRING_32} " grabbed (pure BitBlt %/8212/ no Vision2)")
				else
					s.destroy
					set_error ({STRING_32} "screen grab failed")
				end
			end
		end

feature {NONE} -- Health / audit / findings

	findings_lines: ARRAYED_LIST [STRING_32]

	findings_source: STRING_32
		attribute
			Result := {STRING_32} "FINDINGS %/8212/ problems appear here; Run Audit checks the transcript"
		end

	fill_findings_from (a_report: STRING_32; a_source: STRING_32)
		local
			lines: LIST [STRING_32]
			shown: INTEGER
		do
			findings_lines.wipe_out
			findings_source := a_source
			lines := a_report.split ('%N')
			across lines as l loop
				l.prune_all ('%R')
				l.right_adjust
				if not l.is_empty and shown < Findings_visible then
					findings_lines.extend (l.twin)
					shown := shown + 1
				end
			end
		end

	do_check_setup
		do
			commit_focused
			set_status ({STRING_32} "running setup checks %/8230/")
			health.run_quick
			fill_findings_from (health.report, {STRING_32} "SETUP CHECK (OCR_HEALTH)")
			if health.is_healthy then
				set_status ({STRING_32} "setup checks passed")
			else
				set_error ({STRING_32} "setup problems %/8212/ details below: " + health.failure_summary)
			end
		end

	do_audit
		do
			commit_focused
			set_status ({STRING_32} "auditing transcript %/8230/")
			audit.run (settings.text_file_path)
			fill_findings_from (audit.report,
				{STRING_32} "AUDIT %/8212/ " + audit.finding_count.out.to_string_32 + {STRING_32} " finding(s)")
			set_status ({STRING_32} "audit done: " + audit.finding_count.out.to_string_32
				+ {STRING_32} " finding(s)")
		end

feature {NONE} -- Click routing

	field_rects: ARRAYED_LIST [TUPLE [id: INTEGER; x, y, w: REAL_64]]
	check_rects: ARRAYED_LIST [TUPLE [id: INTEGER; x, y: REAL_64]]
	btn_rects: ARRAYED_LIST [TUPLE [id: INTEGER; x, y, w: REAL_64]]

	on_click (a_x, a_y: INTEGER)
		local
			handled: BOOLEAN
		do
			across btn_rects as r loop
				if not handled and then a_x >= r.x and a_x <= r.x + r.w and a_y >= r.y and a_y <= r.y + 26.0 then
					handled := True
					commit_focused
					run_button (r.id)
				end
			end
			across check_rects as r loop
				if not handled and then a_x >= r.x and a_x <= r.x + 15.0 and a_y >= r.y and a_y <= r.y + 15.0 then
					handled := True
					commit_focused
					toggle_check (r.id)
				end
			end
			across field_rects as r loop
				if not handled and then a_x >= r.x and a_x <= r.x + r.w and a_y >= r.y and a_y <= r.y + 22.0 then
					handled := True
					focus_field (r.id, a_x, r.x)
				end
			end
			if not handled then
				commit_focused
			end
		end

	toggle_check (a_id: INTEGER)
		do
			inspect a_id
			when 31 then settings.set_save_text (not settings.save_text)
			when 32 then settings.set_save_image (not settings.save_image)
			when 33 then settings.set_add_separators (not settings.add_separators)
			when 34 then
				settings.set_hotkey (settings.hotkey_modifiers.bit_xor (2), settings.hotkey_key)
				reregister_hotkey
			when 35 then
				settings.set_hotkey (settings.hotkey_modifiers.bit_xor (1), settings.hotkey_key)
				reregister_hotkey
			when 36 then
				settings.set_hotkey (settings.hotkey_modifiers.bit_xor (4), settings.hotkey_key)
				reregister_hotkey
			when 37 then
				settings.set_show_strip (not settings.show_strip)
				toggle_strip
			when 38 then
				settings.set_show_thumbnail (not settings.show_thumbnail)
			else
			end
		end

	run_button (a_id: INTEGER)
		do
			inspect a_id
			when 51 then begin_overlay (1)
			when 52 then do_test_capture
			when 53 then begin_overlay (2)
			when 54 then begin_overlay (3)
			when 55 then
				start_run
			when 56 then
				pause_resume
			when 57 then
				stop_run ({STRING_32} "stopped")
			when 58 then
				set_status ({STRING_32} "Browse is M4 %/8212/ the folder field is directly editable meanwhile")
			when 59 then
				if settings.image_format.same_string ("png") then
					settings.set_image_format ("bmp")
				else
					settings.set_image_format ("png")
				end
			when 60 then do_check_setup
			when 61 then start_pull
			when 62 then do_audit
			when 63 then
				findings_lines.wipe_out
				findings_source := {STRING_32} "FINDINGS %/8212/ cleared"
			when 64 then
				findings_lines.wipe_out
				findings_source := {STRING_32} "FINDINGS"
				set_status ({STRING_32} "cleared")
			when 65 then
				set_status ({STRING_32} "Open Log is M4 %/8212/ the classic GUI owns the log window today")
			when 66 then
				set_status ({STRING_32} "Clear Log is M4")
			when 67 then
				toggle_strip
			when 68, 69 then
				set_status ({STRING_32} "image housekeeping is M4 here %/8212/ classic GUI or 'simple_ocr_capture --images' meanwhile")
			when 70 then begin_single
			when 71 then do_save
			else
			end
		end

	do_save
		do
			commit_focused
			settings.store
			set_status ({STRING_32} "settings saved to " + settings.settings_path)
		end

feature {NONE} -- Rendering

	render
		local
			y: REAL_64
		do
			field_rects.wipe_out
			check_rects.wipe_out
			btn_rects.wipe_out
			ctx.set_color_hex (C_bg).paint.do_nothing
			draw_toolbar
			y := draw_region_group (56.0)
			y := draw_advance_group (y + 8.0)
			y := draw_output_group (y + 8.0)
			y := draw_trigger_group (y + 8.0)
			y := draw_engine_group (y + 8.0)
			y := draw_findings_group (y + 8.0)
			y := draw_bottom_rows (y + 8.0)
			draw_status_line
		end

	draw_toolbar
		local
			x: REAL_64
		do
			ctx.set_color_hex (C_bar).fill_rect (0.0, 0.0, Win_w, 44.0).do_nothing
			ctx.set_color_hex (C_line).fill_rect (0.0, 44.0, Win_w, 1.0).do_nothing
			set_font (f_display, 14.0, True)
			txt (16.0, 28.0, {STRING_32} "Simple OCR Capture", C_ink)
			x := 16.0 + adv ({STRING_32} "Simple OCR Capture") + 10.0
			set_font (f_mono, 10.5, False)
			txt (x, 28.0, {STRING_32} "cairo face %/183/ functional parity %/183/ pure Win32", C_dim)
			x := Win_w - 16.0
			if did_preflight then
				if preflight.is_model_present then
					x := chip_r (x, 13.0, {STRING_32} "MODEL OK", C_green, C_green_wash, C_green) - 8.0
				else
					x := chip_r (x, 13.0, {STRING_32} "MODEL MISSING", C_signal, C_signal_wash, C_signal) - 8.0
				end
				if preflight.is_runtime_reachable then
					x := chip_r (x, 13.0, {STRING_32} "OLLAMA UP", C_green, C_green_wash, C_green) - 8.0
				else
					x := chip_r (x, 13.0, {STRING_32} "OLLAMA DOWN", C_signal, C_signal_wash, C_signal) - 8.0
				end
			end
			if hotkey_ok then
				x := chip_r (x, 13.0, hotkey_text.as_upper, C_blue, C_blue_wash, C_blue) - 8.0
			else
				x := chip_r (x, 13.0, {STRING_32} "HOTKEY TAKEN", C_signal, C_signal_wash, C_signal) - 8.0
			end
		end

	draw_region_group (a_y: REAL_64): REAL_64
		local
			h, x, ty: REAL_64
			sw, sh, sc: REAL_64
		do
			h := 196.0
			card (Gx, a_y, Gw, h, C_blue)
			head (Gx, a_y, {STRING_32} "CAPTURE REGION")
			ty := a_y + 40.0
			x := Gx + 14.0
			x := do_button (x, ty, {STRING_32} "Set Region by Dragging%/8230/", 51, True) + 14.0
			x := labeled_field (x, ty, {STRING_32} "X", 1, 60.0) + 8.0
			x := labeled_field (x, ty, {STRING_32} "Y", 2, 60.0) + 8.0
			x := labeled_field (x, ty, {STRING_32} "W", 3, 60.0) + 8.0
			x := labeled_field (x, ty, {STRING_32} "H", 4, 60.0) + 20.0
			x := do_button (x, ty, {STRING_32} "Test Capture", 52, False) + 16.0
			set_font (f_mono, 10.5, False)
			txt (x, ty + 16.0, {STRING_32} "Screen: " + c_screen_w.out.to_string_32
				+ {STRING_32} " x " + c_screen_h.out.to_string_32, C_dim)
			-- thumbnail strip
			ty := a_y + 76.0
			ctx.set_color_hex (C_bar).fill_rect (Gx + 14.0, ty, Gw - 28.0, 106.0).do_nothing
			ctx.set_color_hex (C_line).set_line_width (1.0)
				.rectangle (Gx + 14.0, ty, Gw - 28.0, 106.0).stroke.do_nothing
			if attached thumb as t then
				sc := (106.0 / thumb_h).min ((Gw - 28.0) / thumb_w)
				sw := thumb_w * sc
				sh := thumb_h * sc
				ctx.save.do_nothing
				ctx.translate (Gx + 14.0 + ((Gw - 28.0) - sw) / 2.0, ty + (106.0 - sh) / 2.0)
					.scale (sc, sc).set_source_surface (t, 0.0, 0.0).paint.do_nothing
				ctx.restore.do_nothing
			else
				set_font (f_mono, 10.0, False)
				txt (Gx + 24.0, ty + 58.0,
					{STRING_32} "Test Capture grabs the region with a pure BitBlt and shows it here",
					C_dim)
			end
			Result := a_y + h
		end

	draw_advance_group (a_y: REAL_64): REAL_64
		local
			h, x, ty: REAL_64
		do
			h := 148.0
			card (Gx, a_y, Gw, h, C_amber)
			head (Gx, a_y, {STRING_32} "AUTO-ADVANCE")
			ty := a_y + 40.0
			x := Gx + 14.0
			x := do_button (x, ty, {STRING_32} "Set Advance Button by Dragging%/8230/", 53, False) + 14.0
			x := labeled_field (x, ty, {STRING_32} "X", 5, 56.0) + 8.0
			x := labeled_field (x, ty, {STRING_32} "Y", 6, 56.0) + 8.0
			x := labeled_field (x, ty, {STRING_32} "W", 7, 48.0) + 8.0
			x := labeled_field (x, ty, {STRING_32} "H", 8, 48.0)
			ty := ty + 34.0
			x := Gx + 14.0
			x := do_button (x, ty, {STRING_32} "Set Page Indicator by Dragging%/8230/", 54, False) + 14.0
			x := labeled_field (x, ty, {STRING_32} "X", 9, 56.0) + 8.0
			x := labeled_field (x, ty, {STRING_32} "Y", 10, 56.0) + 8.0
			x := labeled_field (x, ty, {STRING_32} "W", 11, 48.0) + 8.0
			x := labeled_field (x, ty, {STRING_32} "H", 12, 48.0) + 20.0
			x := labeled_field (x, ty, {STRING_32} "Min. settle (ms)", 13, 60.0)
			ty := ty + 34.0
			x := Gx + 14.0
			x := do_button (x, ty, {STRING_32} "Start", 55, True) + 6.0
			x := do_button (x, ty, {STRING_32} "Pause", 56, False) + 6.0
			x := do_button (x, ty, {STRING_32} "Stop", 57, False) + 16.0
			set_font (f_mono, 10.0, False)
			txt (x, ty + 16.0,
				{STRING_32} "captures, clicks the advance button, waits the settle, stops when the page stops changing",
				C_dim)
			Result := a_y + h
		end

	draw_output_group (a_y: REAL_64): REAL_64
		local
			h, x, ty: REAL_64
		do
			h := 150.0
			card (Gx, a_y, Gw, h, C_green)
			head (Gx, a_y, {STRING_32} "OUTPUT")
			ty := a_y + 40.0
			x := Gx + 14.0
			x := labeled_field (x, ty, {STRING_32} "Folder", 14, 560.0) + 10.0
			x := do_button (x, ty, {STRING_32} "Browse%/8230/", 58, False)
			ty := ty + 32.0
			x := Gx + 14.0
			x := labeled_field (x, ty, {STRING_32} "Text file", 15, 400.0) + 24.0
			x := labeled_field (x, ty, {STRING_32} "Move to drive", 16, 50.0) + 24.0
			set_font (f_mono, 10.5, False)
			txt (x, ty + 16.0, {STRING_32} "Image format:", C_dim)
			x := x + adv ({STRING_32} "Image format:") + 8.0
			x := do_button (x, ty, settings.image_format.to_string_32.as_upper, 59, False)
			ty := ty + 34.0
			x := Gx + 14.0
			x := checkbox (x, ty, {STRING_32} "Append OCR text to the file above", 31, settings.save_text) + 24.0
			x := checkbox (x, ty, {STRING_32} "Also keep the captured image", 32, settings.save_image) + 24.0
			x := checkbox (x, ty, {STRING_32} "Write a header line before each capture", 33, settings.add_separators)
			Result := a_y + h
		end

	draw_trigger_group (a_y: REAL_64): REAL_64
		local
			h, x, ty: REAL_64
		do
			h := 72.0
			card (Gx, a_y, Gw, h, C_blue)
			head (Gx, a_y, {STRING_32} "TRIGGER")
			ty := a_y + 38.0
			x := Gx + 14.0
			x := checkbox (x, ty, {STRING_32} "Ctrl", 34, settings.hotkey_modifiers.bit_and (2) /= 0) + 18.0
			x := checkbox (x, ty, {STRING_32} "Alt", 35, settings.hotkey_modifiers.bit_and (1) /= 0) + 18.0
			x := checkbox (x, ty, {STRING_32} "Shift", 36, settings.hotkey_modifiers.bit_and (4) /= 0) + 24.0
			x := labeled_field (x, ty, {STRING_32} "Key", 17, 50.0) + 24.0
			set_font (f_mono, 10.5, False)
			txt (x, ty + 16.0, {STRING_32} "changes re-register immediately %/8212/ " + hotkey_text, C_dim)
			Result := a_y + h
		end

	draw_engine_group (a_y: REAL_64): REAL_64
		local
			h, x, ty: REAL_64
		do
			h := 150.0
			card (Gx, a_y, Gw, h, C_amber)
			head (Gx, a_y, {STRING_32} "OCR ENGINE")
			ty := a_y + 40.0
			x := Gx + 14.0
			x := labeled_field (x, ty, {STRING_32} "Endpoint", 18, 380.0) + 24.0
			x := labeled_field (x, ty, {STRING_32} "Model", 19, 320.0)
			ty := ty + 32.0
			x := Gx + 14.0
			x := labeled_field (x, ty, {STRING_32} "Timeout (s)", 20, 60.0) + 24.0
			x := labeled_field (x, ty, {STRING_32} "Context tokens", 21, 80.0) + 24.0
			set_font (f_mono, 10.0, False)
			txt (x, ty + 16.0, {STRING_32} "image + text share this window; too low silently truncates long pages", C_dim)
			ty := ty + 34.0
			x := Gx + 14.0
			x := do_button (x, ty, {STRING_32} "Check Setup", 60, True) + 8.0
			x := do_button (x, ty, {STRING_32} "Install Model", 61, False)
			Result := a_y + h
		end

	draw_findings_group (a_y: REAL_64): REAL_64
		local
			h, x, y: REAL_64
			i: INTEGER
		do
			h := 66.0 + Findings_visible * 17.0 + 40.0
			card (Gx, a_y, Gw, h, C_signal)
			set_font (f_mono, 9.5, False)
			tracked (Gx + 14.0, a_y + 24.0, findings_source, C_dim, 1.0).do_nothing
			y := a_y + 46.0
			set_font (f_mono, 10.0, False)
			if findings_lines.is_empty then
				txt (Gx + 14.0, y, {STRING_32} "(nothing to report)", C_dim)
			else
				from
					i := 1
				until
					i > findings_lines.count
				loop
					txt (Gx + 14.0, y, elide (findings_lines [i], Gw - 28.0), C_ink)
					y := y + 17.0
					i := i + 1
				end
			end
			y := a_y + h - 34.0
			x := Gx + 14.0
			x := do_button (x, y, {STRING_32} "Run Audit", 62, False) + 8.0
			x := do_button (x, y, {STRING_32} "Clear List", 63, False) + 16.0
			set_font (f_mono, 10.0, False)
			txt (x, y + 16.0, {STRING_32} "Run Audit checks the finished transcript for gaps, repeats and jumps", C_dim)
			Result := a_y + h
		end

	draw_bottom_rows (a_y: REAL_64): REAL_64
		local
			x, ty: REAL_64
		do
			ty := a_y
			x := Gx
			x := do_button (x, ty, {STRING_32} "Clear All", 64, False) + 6.0
			x := do_button (x, ty, {STRING_32} "Open Log", 65, False) + 6.0
			x := do_button (x, ty, {STRING_32} "Clear Log", 66, False) + 6.0
			x := do_button (x, ty, {STRING_32} "Show Strip", 67, False) + 16.0
			x := do_button (x, ty, {STRING_32} "Delete Images%/8230/", 68, False) + 6.0
			x := do_button (x, ty, {STRING_32} "Move Images%/8230/", 69, False) + 12.0
			set_font (f_mono, 10.0, False)
			txt (x, ty + 16.0, {STRING_32} "ocr_*.png and ocr_*.bmp only", C_dim)
			ty := ty + 36.0
			x := Gx
			x := do_button (x, ty, {STRING_32} "Capture Now  (" + hotkey_text + {STRING_32} ")", 70, True) + 10.0
			x := do_button (x, ty, {STRING_32} "Save Settings", 71, True) + 24.0
			x := checkbox (x, ty + 4.0, {STRING_32} "Show progress strip", 37, settings.show_strip) + 24.0
			x := checkbox (x, ty + 4.0, {STRING_32} "Show last capture", 38, settings.show_thumbnail)
			Result := ty + 34.0
		end

	draw_status_line
		local
			s: STRING_32
		do
			ctx.set_color_hex (C_bar).fill_rect (0.0, Win_h - 28.0, Win_w, 28.0).do_nothing
			ctx.set_color_hex (C_line).fill_rect (0.0, Win_h - 28.0, Win_w, 1.0).do_nothing
			set_font (f_mono, 10.0, False)
			if status_is_error then
				txt (14.0, Win_h - 10.0, elide (status_msg, Win_w - 260.0), C_signal)
			else
				txt (14.0, Win_h - 10.0, elide (status_msg, Win_w - 260.0), C_dim)
			end
			s := {STRING_32} "pages " + pages_done.out.to_string_32 + {STRING_32} " %/183/ shots " + shots_done.out.to_string_32 + {STRING_32} " %/183/ " + state_word
			txt (Win_w - 14.0 - adv (s), Win_h - 10.0, s, C_dim)
		end

feature {NONE} -- Widget kit

	card (a_x, a_y, a_w, a_h: REAL_64; a_stripe: NATURAL_32)
		do
			ctx.set_color_hex (C_panel).rounded_rectangle (a_x, a_y, a_w, a_h, 3.0).fill_preserve.do_nothing
			ctx.set_color_hex (C_line).set_line_width (1.0).stroke.do_nothing
			ctx.save.clip_rectangle (a_x, a_y, 5.0, a_h).do_nothing
			ctx.set_color_hex (a_stripe).rounded_rectangle (a_x, a_y, a_w, a_h, 3.0).fill.do_nothing
			ctx.restore.do_nothing
		end

	head (a_x, a_y: REAL_64; a_title: STRING_32)
		do
			set_font (f_mono, 9.5, False)
			tracked (a_x + 14.0, a_y + 24.0, a_title, C_dim, 1.2).do_nothing
		end

	labeled_field (a_x, a_y: REAL_64; a_label: STRING_32; a_id: INTEGER; a_w: REAL_64): REAL_64
			-- Label + editable field box; returns the right edge.
		local
			x: REAL_64
			v: STRING_32
			cx: REAL_64
			i: INTEGER
		do
			set_font (f_mono, 10.5, False)
			x := a_x
			if not a_label.is_empty then
				txt (x, a_y + 16.0, a_label, C_dim)
				x := x + adv (a_label) + 6.0
			end
			if focused_id = a_id then
				ctx.set_color_hex (C_panel).rectangle (x, a_y, a_w, 22.0).fill_preserve.do_nothing
				ctx.set_color_hex (C_blue).set_line_width (1.6).stroke.do_nothing
				v := edit_buf
			else
				ctx.set_color_hex (C_panel).rectangle (x, a_y, a_w, 22.0).fill_preserve.do_nothing
				ctx.set_color_hex (C_line).set_line_width (1.0).stroke.do_nothing
				v := field_value (a_id)
			end
			txt (x + 6.0, a_y + 16.0, elide (v, a_w - 12.0), C_ink)
			if focused_id = a_id and blink_on then
				cx := x + 6.0
				from
					i := 1
				until
					i > edit_caret
				loop
					cx := cx + adv (one_char (v [i]))
					i := i + 1
				end
				ctx.set_color_hex (C_signal).fill_rect (cx, a_y + 3.0, 1.8, 16.0).do_nothing
			end
			field_rects.extend ([a_id, x, a_y, a_w])
			Result := x + a_w
		end

	checkbox (a_x, a_y: REAL_64; a_label: STRING_32; a_id: INTEGER; a_on: BOOLEAN): REAL_64
		do
			ctx.set_color_hex (C_panel).rectangle (a_x, a_y + 2.0, 15.0, 15.0).fill_preserve.do_nothing
			ctx.set_color_hex (C_line).set_line_width (1.2).stroke.do_nothing
			if a_on then
				ctx.set_color_hex (C_blue).set_line_width (2.0)
					.move_to (a_x + 3.0, a_y + 9.5).line_to (a_x + 6.5, a_y + 13.0)
					.line_to (a_x + 12.0, a_y + 5.0).stroke.do_nothing
			end
			set_font (f_display, 11.0, False)
			txt (a_x + 21.0, a_y + 14.0, a_label, C_ink)
			check_rects.extend ([a_id, a_x, a_y + 2.0])
			Result := a_x + 21.0 + adv (a_label)
		end

	do_button (a_x, a_y: REAL_64; a_label: STRING_32; a_id: INTEGER; a_primary: BOOLEAN): REAL_64
		local
			w: REAL_64
			fg, bg, bd: NATURAL_32
		do
			set_font (f_display, 11.0, False)
			w := 20.0 + adv (a_label)
			if a_primary then
				fg := C_blue
				bg := C_blue_wash
				bd := C_blue
			else
				fg := C_ink
				bg := C_panel
				bd := C_line
			end
			ctx.set_color_hex (bg).rounded_rectangle (a_x, a_y, w, 26.0, 3.0).fill_preserve.do_nothing
			ctx.set_color_hex (bd).set_line_width (1.0).stroke.do_nothing
			txt (a_x + 10.0, a_y + 17.0, a_label, fg)
			btn_rects.extend ([a_id, a_x, a_y, w])
			Result := a_x + w
		end

	chip_r (a_right, a_y: REAL_64; a_label: STRING_32; a_fg, a_bg, a_bd: NATURAL_32): REAL_64
		local
			w, x0: REAL_64
		do
			set_font (f_mono, 9.5, False)
			w := 12.0
			across a_label as c loop
				w := w + adv (one_char (c)) + 0.6
			end
			x0 := a_right - w
			ctx.set_color_hex (a_bg).rounded_rectangle (x0, a_y, w, 18.0, 2.0).fill_preserve.do_nothing
			ctx.set_color_hex (a_bd).set_line_width (1.0).stroke.do_nothing
			tracked (x0 + 6.0, a_y + 13.0, a_label, a_fg, 0.6).do_nothing
			Result := x0
		end

feature {NONE} -- Text kit

	one_char (c: CHARACTER_32): STRING_32
		do
			create Result.make (1)
			Result.extend (c)
		end

	adv (a_s: STRING_32): REAL_64
		do
			Result := ctx.text_extents (a_s).x_advance
		end

	txt (a_x, a_y: REAL_64; a_s: STRING_32; a_color: NATURAL_32)
		do
			ctx.set_color_hex (a_color).move_to (a_x, a_y).show_text (a_s).do_nothing
		end

	tracked (a_x, a_y: REAL_64; a_s: STRING_32; a_color: NATURAL_32; a_tr: REAL_64): REAL_64
		local
			x: REAL_64
		do
			x := a_x
			ctx.set_color_hex (a_color).do_nothing
			across a_s as c loop
				ctx.move_to (x, a_y).show_text (one_char (c)).do_nothing
				x := x + adv (one_char (c)) + a_tr
			end
			Result := x
		end

	elide (a_s: STRING_32; a_maxw: REAL_64): STRING_32
		local
			i: INTEGER
			x: REAL_64
		do
			if adv (a_s) <= a_maxw then
				Result := a_s
			else
				create Result.make (a_s.count)
				from
					i := 1
				until
					i > a_s.count or x > a_maxw - 12.0
				loop
					Result.extend (a_s [i])
					x := x + adv (one_char (a_s [i]))
					i := i + 1
				end
				Result.append_character ('%/8230/')
			end
		end

	set_font (a_family: STRING_32; a_size: REAL_64; a_bold: BOOLEAN)
		do
			if a_bold then
				ctx.select_font (a_family, ctx.Slant_normal, ctx.Weight_bold).do_nothing
			else
				ctx.select_font (a_family, ctx.Slant_normal, ctx.Weight_normal).do_nothing
			end
			ctx.set_font_size (a_size).do_nothing
		end

	ms_str (a_ms: REAL_64): STRING_32
		local
			r10: INTEGER
		do
			r10 := (a_ms * 10.0).rounded
			create Result.make (8)
			Result.append_string_general ((r10 // 10).out)
			Result.append_character ('.')
			Result.append_string_general ((r10 \\ 10).out)
		end

	load_private_fonts
		local
			dir: STRING_32
			n: INTEGER
		do
			dir := {STRING_32} "D:\prod\simple_narrate\docs\_artwork\src\_fonts\"
			if add_font (dir + {STRING_32} "Archivo.ttf") then
				n := n + 1
			end
			if add_font (dir + {STRING_32} "Literata.ttf") then
				n := n + 1
			end
			if add_font (dir + {STRING_32} "IBMPlexMono.ttf") then
				n := n + 1
			end
			if n = 3 then
				f_display := {STRING_32} "Archivo"
				f_body := {STRING_32} "Literata"
				f_mono := {STRING_32} "IBM Plex Mono"
			end
		end

	add_font (a_path: STRING_32): BOOLEAN
		local
			f: RAW_FILE
			ns: NATIVE_STRING
		do
			create f.make_with_name (a_path)
			if f.exists then
				create ns.make (a_path)
				Result := c_add_font (ns.item) > 0
			end
		end

feature {NONE} -- Blit

	blit
		local
			hdc: POINTER
			ws: CAIRO_SURFACE
			c2: CAIRO_CONTEXT
		do
			hdc := c_get_dc
			if hdc /= default_pointer then
				create ws.make_for_dc (hdc)
				if ws.is_valid then
					create c2.make (ws)
					c2.set_source_surface (offscreen, 0.0, 0.0).paint.do_nothing
					c2.destroy
				end
				ws.destroy
				c_release_dc (hdc)
			end
		end

feature {NONE} -- Canvas state

	cairo: SIMPLE_CAIRO
	offscreen: CAIRO_SURFACE
	ctx: CAIRO_CONTEXT
	ev_buf: MANAGED_POINTER

	f_display: STRING_32
	f_body: STRING_32
	f_mono: STRING_32

feature {NONE} -- Geometry & palette

	window_title: STRING_32
		once
			Result := {STRING_32} "Simple OCR Capture %/8212/ cairo face (parity)"
		end

	Win_w: INTEGER = 1120
	Win_h: INTEGER = 1210
	Gx: REAL_64 = 16.0
	Gw: REAL_64 = 1088.0
	Findings_visible: INTEGER = 7

	C_bg: NATURAL_32 = 0xE9ECF1
	C_panel: NATURAL_32 = 0xFFFFFF
	C_bar: NATURAL_32 = 0xF5F7FA
	C_line: NATURAL_32 = 0xD3DAE3
	C_ink: NATURAL_32 = 0x1A2029
	C_dim: NATURAL_32 = 0x5A6573
	C_blue: NATURAL_32 = 0x1F5FA8
	C_blue_wash: NATURAL_32 = 0xC7DAF1
	C_green: NATURAL_32 = 0x1D6B52
	C_green_wash: NATURAL_32 = 0xE0F0E9
	C_amber: NATURAL_32 = 0x8A5A0B
	C_amber_wash: NATURAL_32 = 0xFAF1DD
	C_signal: NATURAL_32 = 0xAF3A22
	C_signal_wash: NATURAL_32 = 0xF8E7E2

feature {NONE} -- C Externals

	c_create_window (a_title: POINTER; a_w, a_h: INTEGER): POINTER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_create_window((const wchar_t*)$a_title, $a_w, $a_h);"
		end

	c_pump: INTEGER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_pump();"
		end

	c_next (a_buf: POINTER): INTEGER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_next_event((int*)$a_buf);"
		end

	c_get_dc: POINTER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_get_dc();"
		end

	c_release_dc (a_dc: POINTER)
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"ocw_release_dc($a_dc);"
		end

	c_now_ms: REAL_64
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_now_ms();"
		end

	c_shell_open (a_path: POINTER): INTEGER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_shell_open((const wchar_t*)$a_path);"
		end

	c_add_font (a_path: POINTER): INTEGER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return (int)AddFontResourceExW((LPCWSTR)$a_path, FR_PRIVATE, 0);"
		end

	c_show_strip (a_x, a_y, a_w, a_h: INTEGER): POINTER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_show_strip($a_x, $a_y, $a_w, $a_h);"
		end

	c_hide_strip
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"ocw_hide_strip();"
		end

	c_strip_dc: POINTER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_strip_dc();"
		end

	c_strip_release (a_dc: POINTER)
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"ocw_strip_release($a_dc);"
		end

	c_bufs_equal (a_a, a_b: POINTER; a_len: INTEGER): INTEGER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_buffers_equal($a_a, $a_b, $a_len);"
		end

	c_minutes_of_day: INTEGER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_minutes_of_day();"
		end

	c_screen_x: INTEGER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_screen_x();"
		end

	c_screen_y: INTEGER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_screen_y();"
		end

	c_screen_w: INTEGER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_screen_w();"
		end

	c_screen_h: INTEGER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_screen_h();"
		end

	c_grab_screen (a_x, a_y, a_w, a_h: INTEGER; a_bits: POINTER; a_stride: INTEGER): INTEGER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_grab_screen($a_x, $a_y, $a_w, $a_h, $a_bits, $a_stride);"
		end

	c_show_overlay: POINTER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_show_overlay();"
		end

	c_hide_overlay
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"ocw_hide_overlay();"
		end

	c_overlay_dc: POINTER
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"return ocw_overlay_dc();"
		end

	c_overlay_release (a_dc: POINTER)
		external
			"C inline use %"ocr_cairo_win.h%""
		alias
			"ocw_overlay_release($a_dc);"
		end

end
