note
	description: "[
		M3: the Simple OCR Capture control surface, rebuilt on the pure
		route - an inline-C Win32 window whose every pixel is painted by
		simple_cairo. No Vision2 in this process.

		REAL product machinery wired in, not mocked:
		  OCR_SETTINGS        loaded from the same %APPDATA% file the
		                      classic GUI reads and writes
		  OCR_PREFLIGHT       live Ollama server + model checks on the tick
		  OCR_HOTKEY          the product's own system-wide hotkey class,
		                      polled exactly as the classic GUI polls it
		  capture pipeline    Capture Now (button or hotkey) runs the real
		                      exe in --shot mode: real screen grab, real
		                      OCR through Ollama, output streamed into the
		                      activity log (SIMPLE_ASYNC_PROCESS)

		Deferred to M4, shown disabled WITH THEIR REASON (the
		self-explaining-controls rule): region picker, settings editing,
		auto-run - all Vision2-welded today (EV_SCREEN capture, EV popup
		outlines, the 24-field settings surface).
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
			create preflight.make (settings)
			create hotkey.make
			hotkey_ok := hotkey.register (settings.hotkey_modifiers, settings.hotkey_key)
			resolve_worker_exe

			create log_lines.make (64)
			create hit_rects.make (8)
			log ({STRING_32} "cairo face up %/8212/ settings: " + settings.settings_path)
			if exe_found then
				log ({STRING_32} "worker exe: " + worker_exe)
			else
				log_err ({STRING_32} "worker exe not found; Capture disabled")
			end
			if hotkey_ok then
				log ({STRING_32} "hotkey registered (Ctrl+Alt+G)")
			else
				log_err ({STRING_32} "hotkey unavailable (already taken?)")
			end

			offscreen := cairo.create_surface (Win_w, Win_h)
			ctx := cairo.create_context (offscreen)
			create ev_buf.make (16)
			render

			create ns.make (window_title)
			hwnd := c_create_window (ns.item, Win_w, Win_h)
			if hwnd = default_pointer then
				print ("FAILED to create window%N")
			else
				print ("Simple OCR Capture (cairo face) up. Ctrl+Alt+G or the button captures.%N")
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
							if ev = 2 then
								on_click (ev_buf.read_integer_32 (4), ev_buf.read_integer_32 (8))
							elseif ev = 7 then
								on_tick
							end
							dirty := True
							ev := c_next (ev_buf.item)
						end
						if dirty and not done then
							render
							blit
							if not first_png then
								first_png := True
								if offscreen.write_png ("ocr_cairo_first_frame.png") then
									print ("First frame written to ocr_cairo_first_frame.png%N")
								end
							end
							dirty := False
						end
					end
				end
			end
			shutdown
		end

	shutdown
		do
			hotkey.cleanup
			if attached shot_process as p then
				p.close
			end
			ctx.destroy
			offscreen.destroy
			print ("cairo face closed.%N")
		end

feature {NONE} -- Product machinery (real)

	settings: OCR_SETTINGS
	preflight: OCR_PREFLIGHT
	hotkey: OCR_HOTKEY
	hotkey_ok: BOOLEAN
	did_preflight: BOOLEAN

	worker_exe: STRING_32
		attribute
			create Result.make_empty
		end

	exe_found: BOOLEAN

	resolve_worker_exe
		local
			f: RAW_FILE
			candidates: ARRAY [STRING_32]
			i: INTEGER
		do
			candidates := <<
				{STRING_32} "D:\prod\simple_ocr_capture\EIFGENs\ocr_capture\F_code\simple_ocr_capture.exe",
				{STRING_32} "C:\Program Files\Simple OCR Capture\simple_ocr_capture.exe">>
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

feature {NONE} -- Capture cycle (the real pipeline, product's own worker pattern)

	shot_process: detachable SIMPLE_ASYNC_PROCESS
	shot_t0: REAL_64
	last_shot_ms: REAL_64
	shots_done: INTEGER

	is_shooting: BOOLEAN
		do
			Result := attached shot_process as p and then not p.has_finished
		end

	start_shot (a_source: STRING_32)
		local
			p: SIMPLE_ASYNC_PROCESS
			cmd: STRING_32
		do
			if is_shooting then
				log ({STRING_32} "capture ignored %/8212/ one is already running")
			elseif not exe_found then
				log_err ({STRING_32} "cannot capture: worker exe not found")
			elseif not settings.is_region_valid then
				log_err ({STRING_32} "cannot capture: region not set (use the classic GUI %/8212/ M4 brings the picker here)")
			else
				create cmd.make (128)
				cmd.append_character ('"')
				cmd.append (worker_exe)
				cmd.append_string_general ("%" --shot ")
				cmd.append_string_general (settings.region_x.out)
				cmd.append_character (' ')
				cmd.append_string_general (settings.region_y.out)
				cmd.append_character (' ')
				cmd.append_string_general (settings.region_width.out)
				cmd.append_character (' ')
				cmd.append_string_general (settings.region_height.out)
				create p.make
				p.set_show_window (False)
				p.start (cmd)
				if p.is_started then
					shot_process := p
					shot_t0 := c_now_ms
					log ({STRING_32} "capture (" + a_source + {STRING_32} ") %/8212/ region "
						+ settings.region_width.out.to_string_32 + {STRING_32} "x"
						+ settings.region_height.out.to_string_32 + {STRING_32} " at "
						+ settings.region_x.out.to_string_32 + {STRING_32} ","
						+ settings.region_y.out.to_string_32)
				else
					log_err ({STRING_32} "worker failed to start")
				end
			end
		end

	poll_shot
		local
			lines: LIST [STRING_32]
		do
			if attached shot_process as p and then p.has_finished then
				last_shot_ms := c_now_ms - shot_t0
				shots_done := shots_done + 1
				lines := p.accumulated_output.split ('%N')
				across lines as l loop
					l.prune_all ('%R')
					l.right_adjust
					if not l.is_empty then
						log ({STRING_32} "  " + l)
					end
				end
				if p.exit_code = 0 then
					log ({STRING_32} "capture done in " + ms_str (last_shot_ms) + {STRING_32} " ms")
				else
					log_err ({STRING_32} "capture exited with code " + p.exit_code.out.to_string_32)
				end
				p.close
				shot_process := Void
			end
		end

feature {NONE} -- Tick

	ticks: INTEGER

	on_tick
		do
			ticks := ticks + 1
			if hotkey_ok and then hotkey.taken_presses > 0 then
				start_shot ({STRING_32} "hotkey")
			end
			poll_shot
			if not is_shooting and then (not did_preflight or ticks \\ 12 = 0) then
				preflight.refresh
				did_preflight := True
			end
		end

feature {NONE} -- Clicks

	Act_capture: INTEGER = 1
	Act_open_text: INTEGER = 2
	Act_set_region: INTEGER = 3
	Act_settings: INTEGER = 4

	hit_rects: ARRAYED_LIST [TUPLE [x, y, w: REAL_64; id: INTEGER]]

	remember_hit (a_x, a_y, a_w: REAL_64; a_id: INTEGER)
		do
			hit_rects.extend ([a_x, a_y, a_w, a_id])
		end

	on_click (a_x, a_y: INTEGER)
		local
			ns: NATIVE_STRING
		do
			across hit_rects as r loop
				if a_x >= r.x and a_x <= r.x + r.w and a_y >= r.y and a_y <= r.y + 28.0 then
					if r.id = Act_capture then
						start_shot ({STRING_32} "button")
					elseif r.id = Act_open_text then
						create ns.make (settings.text_file_path)
						if c_shell_open (ns.item) = 1 then
							log ({STRING_32} "opened " + settings.text_file_path)
						else
							log_err ({STRING_32} "could not open " + settings.text_file_path)
						end
					elseif r.id = Act_set_region then
						log ({STRING_32} "Set Region is M4: the picker is a full-screen Vision2 window today %/8212/ use the classic GUI meanwhile")
					elseif r.id = Act_settings then
						log ({STRING_32} "Settings editing is M4: 24 fields await the toolkit%/8217/s input widgets %/8212/ classic GUI meanwhile")
					end
				end
			end
		end

feature {NONE} -- Activity log

	log_lines: ARRAYED_LIST [STRING_32]

	log (a_s: STRING_32)
		do
			log_lines.extend ({STRING_32} "%/183/ " + a_s)
			if log_lines.count > 200 then
				log_lines.start
				log_lines.remove
			end
		end

	log_err (a_s: STRING_32)
		do
			log_lines.extend ({STRING_32} "! " + a_s)
			if log_lines.count > 200 then
				log_lines.start
				log_lines.remove
			end
		end

feature {NONE} -- Rendering

	render
		local
			y: REAL_64
		do
			hit_rects.wipe_out
			ctx.set_color_hex (C_bg).paint.do_nothing
			draw_toolbar
			y := draw_region_card (58.0)
			y := draw_output_card (y + 10.0)
			y := draw_engine_card (y + 10.0)
			draw_activity_card
			draw_actions
			draw_strip
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
			txt (x, 28.0, {STRING_32} "1.7.0 %/183/ cairo face M3 %/183/ pure Win32", C_dim)

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
			else
				x := chip_r (x, 13.0, {STRING_32} "CHECKING%/8230/", C_amber, C_amber_wash, C_amber) - 8.0
			end
			if hotkey_ok then
				x := chip_r (x, 13.0, {STRING_32} "CTRL+ALT+G", C_blue, C_blue_wash, C_blue) - 8.0
			else
				x := chip_r (x, 13.0, {STRING_32} "HOTKEY TAKEN", C_signal, C_signal_wash, C_signal) - 8.0
			end
		end

	draw_region_card (a_y: REAL_64): REAL_64
		local
			h: REAL_64
		do
			h := 96.0
			card (Left_x, a_y, Left_w, h, C_blue)
			head (Left_x, a_y, {STRING_32} "CAPTURE REGION")
			if settings.is_region_valid then
				chip (Left_x + 150.0, a_y + 12.0, {STRING_32} "SET", C_green, C_green_wash, C_green).do_nothing
			else
				chip (Left_x + 150.0, a_y + 12.0, {STRING_32} "NOT SET", C_signal, C_signal_wash, C_signal).do_nothing
			end
			row (Left_x, a_y + 52.0, {STRING_32} "origin",
				settings.region_x.out.to_string_32 + {STRING_32} ", " + settings.region_y.out.to_string_32)
			row (Left_x, a_y + 74.0, {STRING_32} "size",
				settings.region_width.out.to_string_32 + {STRING_32} " x " + settings.region_height.out.to_string_32)
			Result := a_y + h
		end

	draw_output_card (a_y: REAL_64): REAL_64
		local
			h, bx: REAL_64
		do
			h := 148.0
			card (Left_x, a_y, Left_w, h, C_green)
			head (Left_x, a_y, {STRING_32} "OUTPUT")
			row (Left_x, a_y + 52.0, {STRING_32} "folder", elide (settings.output_folder, 236.0))
			row (Left_x, a_y + 74.0, {STRING_32} "file", elide (settings.text_file_name, 236.0))
			bx := Left_x + 14.0
			if settings.save_text then
				bx := chip (bx, a_y + 90.0, {STRING_32} "TEXT", C_green, C_green_wash, C_green) + 6.0
			end
			if settings.save_image then
				bx := chip (bx, a_y + 90.0, {STRING_32} "IMAGES", C_blue, C_blue_wash, C_blue) + 6.0
			end
			if settings.add_separators then
				bx := chip (bx, a_y + 90.0, {STRING_32} "SEPARATORS", C_dim, C_bar, C_line) + 6.0
			end
			remember_hit (Left_x + 14.0, a_y + 114.0,
				button (Left_x + 14.0, a_y + 114.0, {STRING_32} "Open Text File", True), Act_open_text)
			Result := a_y + h
		end

	draw_engine_card (a_y: REAL_64): REAL_64
		local
			h: REAL_64
		do
			h := 118.0
			card (Left_x, a_y, Left_w, h, C_amber)
			head (Left_x, a_y, {STRING_32} "ENGINE")
			row (Left_x, a_y + 52.0, {STRING_32} "model", elide (settings.model.to_string_32, 236.0))
			row (Left_x, a_y + 74.0, {STRING_32} "endpoint", elide (settings.endpoint.to_string_32, 236.0))
			row (Left_x, a_y + 96.0, {STRING_32} "timeout",
				settings.ocr_timeout_seconds.out.to_string_32 + {STRING_32} " s %/183/ ctx " + settings.num_ctx.out.to_string_32)
			Result := a_y + h
		end

	draw_activity_card
		local
			y0, y, h: REAL_64
			i, first: INTEGER
			s: STRING_32
		do
			y0 := 58.0
			h := Strip_y - 58.0 - 56.0
			card (Right_x, y0, Right_w, h, C_line)
			head (Right_x, y0, {STRING_32} "ACTIVITY")
			if is_shooting and attached shot_process as p then
				chip_r (Right_x + Right_w - 14.0, y0 + 12.0,
					{STRING_32} "CAPTURING %/8230/ " + p.elapsed_seconds.out.to_string_32 + {STRING_32} "s",
					C_amber, C_amber_wash, C_amber).do_nothing
			elseif shots_done > 0 then
				chip_r (Right_x + Right_w - 14.0, y0 + 12.0,
					{STRING_32} "LAST " + ms_str (last_shot_ms) + {STRING_32} " MS",
					C_green, C_green_wash, C_green).do_nothing
			end
			set_font (f_mono, 10.5, False)
			first := (log_lines.count - Log_visible + 1).max (1)
			y := y0 + 52.0
			from
				i := first
			until
				i > log_lines.count
			loop
				s := log_lines [i]
				if not s.is_empty and then s [1] = '!' then
					txt (Right_x + 14.0, y, elide (s, Right_w - 28.0), C_signal)
				else
					txt (Right_x + 14.0, y, elide (s, Right_w - 28.0), C_ink)
				end
				y := y + 18.0
				i := i + 1
			end
		end

	draw_actions
		local
			x, y: REAL_64
		do
			y := Strip_y - 44.0
			x := Right_x
			remember_hit (x, y, button (x, y, {STRING_32} "Capture Now  (Ctrl+Alt+G)", True), Act_capture)
			x := x + last_button_w + 10.0
			remember_hit (x, y, button_disabled (x, y, {STRING_32} "Set Region %/8212/ M4"), Act_set_region)
			x := x + last_button_w + 10.0
			remember_hit (x, y, button_disabled (x, y, {STRING_32} "Settings %/8212/ M4"), Act_settings)
		end

	draw_strip
		local
			s: STRING_32
		do
			ctx.set_color_hex (C_bar).fill_rect (0.0, Strip_y, Win_w, 30.0).do_nothing
			ctx.set_color_hex (C_line).fill_rect (0.0, Strip_y, Win_w, 1.0).do_nothing
			set_font (f_mono, 10.0, False)
			if did_preflight then
				if preflight.is_runtime_reachable and preflight.is_model_present then
					s := {STRING_32} "ready %/8212/ server reachable, model present"
				elseif preflight.is_runtime_reachable then
					s := {STRING_32} "server up, model missing %/8212/ pull it from the classic GUI"
				else
					s := {STRING_32} "Ollama unreachable at " + settings.endpoint.to_string_32
				end
			else
				s := {STRING_32} "first health check pending%/8230/"
			end
			txt (14.0, Strip_y + 19.0, elide (s, 700.0), C_dim)
			s := {STRING_32} "shots " + shots_done.out.to_string_32 + {STRING_32} " %/183/ M3 %/183/ simple_cairo"
			txt (Win_w - 14.0 - adv (s), Strip_y + 19.0, s, C_dim)
		end

feature {NONE} -- Card kit (spike-proven style)

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

	row (a_x, a_y: REAL_64; a_label, a_value: STRING_32)
		do
			set_font (f_mono, 10.5, False)
			txt (a_x + 14.0, a_y, a_label, C_dim)
			txt (a_x + 90.0, a_y, a_value, C_ink)
		end

	last_button_w: REAL_64

	button (a_x, a_y: REAL_64; a_label: STRING_32; a_primary: BOOLEAN): REAL_64
		local
			fg, bg, bd: NATURAL_32
		do
			set_font (f_display, 11.5, False)
			last_button_w := 22.0 + adv (a_label)
			if a_primary then
				fg := C_blue
				bg := C_blue_wash
				bd := C_blue
			else
				fg := C_ink
				bg := C_panel
				bd := C_line
			end
			ctx.set_color_hex (bg).rounded_rectangle (a_x, a_y, last_button_w, 28.0, 3.0).fill_preserve.do_nothing
			ctx.set_color_hex (bd).set_line_width (1.0).stroke.do_nothing
			txt (a_x + 11.0, a_y + 18.5, a_label, fg)
			Result := last_button_w
		end

	button_disabled (a_x, a_y: REAL_64; a_label: STRING_32): REAL_64
		do
			set_font (f_display, 11.5, False)
			last_button_w := 22.0 + adv (a_label)
			ctx.set_color_hex (C_bar).rounded_rectangle (a_x, a_y, last_button_w, 28.0, 3.0).fill_preserve.do_nothing
			ctx.set_color_hex (C_line).set_line_width (1.0).stroke.do_nothing
			txt (a_x + 11.0, a_y + 18.5, a_label, C_dim)
			Result := last_button_w
		end

	chip (a_x, a_y: REAL_64; a_label: STRING_32; a_fg, a_bg, a_bd: NATURAL_32): REAL_64
		local
			w: REAL_64
		do
			set_font (f_mono, 9.5, False)
			w := 12.0
			across a_label as c loop
				w := w + adv (one_char (c)) + 0.6
			end
			ctx.set_color_hex (a_bg).rounded_rectangle (a_x, a_y, w, 18.0, 2.0).fill_preserve.do_nothing
			ctx.set_color_hex (a_bd).set_line_width (1.0).stroke.do_nothing
			tracked (a_x + 6.0, a_y + 13.0, a_label, a_fg, 0.6).do_nothing
			Result := a_x + w
		end

	chip_r (a_right, a_y: REAL_64; a_label: STRING_32; a_fg, a_bg, a_bd: NATURAL_32): REAL_64
			-- Right-aligned chip; returns its LEFT edge.
		local
			w: REAL_64
		do
			set_font (f_mono, 9.5, False)
			w := 12.0
			across a_label as c loop
				w := w + adv (one_char (c)) + 0.6
			end
			Result := a_right - w
			chip (Result, a_y, a_label, a_fg, a_bg, a_bd).do_nothing
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
			Result := {STRING_32} "Simple OCR Capture %/8212/ cairo face (M3)"
		end

	Win_w: INTEGER = 1180
	Win_h: INTEGER = 660
	Left_x: REAL_64 = 16.0
	Left_w: REAL_64 = 360.0
	Right_x: REAL_64 = 392.0
	Right_w: REAL_64 = 772.0
	Strip_y: REAL_64 = 630.0
	Log_visible: INTEGER = 24

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

feature {NONE} -- C Externals (window scaffolding)

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

end
