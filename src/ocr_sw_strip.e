note
	description: "[
		The always-on-top progress strip on the pure route:
		SHELL_STRIP (topmost, toolwindow, never activated - the very
		properties the Vision2 original needed disconnect_from_
		window_manager to get), painted with a full SW_PAINTER
		through the strip's DC. Five stage lights, the caption, the
		thumbnail with the page and rates beneath it, and the
		play/pause/stop transport from the drawn-glyph set.

		Dragging is the C side's gift: any press outside the
		transport corner moves the window natively; event 22
		reports where it landed and the position is remembered.
		Same public contract as OCR_STATUS_STRIP, which it succeeds.
	]"

class
	OCR_SW_STRIP

create
	make

feature {NONE} -- Initialization

	make (a_settings: OCR_SETTINGS)
		do
			settings := a_settings
			stage := Stage_idle
			show_thumbnail := a_settings.show_thumbnail
			create message.make_from_string ("READY")
		ensure
			idle: stage = Stage_idle
		end

feature -- Access

	stage: INTEGER
			-- Current cycle stage, `Stage_idle' through `Stage_ready'.

	message: STRING_32
			-- Caption shown beside the lights.

	is_displayed: BOOLEAN
			-- Is the strip on screen?

feature -- Basic operations

	show
		do
			place
			is_displayed := True
			paint
		ensure
			displayed: is_displayed
		end

	hide
		do
			tool_strip.hide
			is_displayed := False
		ensure
			hidden: not is_displayed
		end

	set_stage (a_stage: INTEGER; a_message: READABLE_STRING_GENERAL)
			-- Advance to `a_stage', captioned `a_message', and repaint.
		require
			in_range: a_stage >= Stage_idle and a_stage <= Stage_ready
		do
			stage := a_stage
			create message.make_from_string_general (a_message)
			refresh
		ensure
			stage_set: stage = a_stage
		end

	set_thumbnail (a_surface: detachable CAIRO_SURFACE)
			-- Show `a_surface' beneath the lights, resizing to fit.
			-- Void clears the panel. The surface is the caller's;
			-- the strip only draws it.
		do
			thumbnail := a_surface
			refresh
		end

	set_thumbnail_visible (a_flag: BOOLEAN)
		do
			show_thumbnail := a_flag
			refresh
		ensure
			set: show_thumbnail = a_flag
		end

	ensure_visible
			-- Repair "the strip should be showing": back on the
			-- desktop if its remembered position fell off it, shown
			-- again if it somehow is not. Cheap enough to poll.
		local
			sc: SW_SCREEN
			lx, ly: INTEGER
		do
			if is_displayed then
				create sc
				lx := settings.strip_x
				ly := settings.strip_y
				if lx < sc.virtual_x
					or lx > sc.virtual_x + sc.virtual_width - Recovery_margin
					or ly < sc.virtual_y
					or ly > sc.virtual_y + sc.virtual_height - Recovery_margin
				then
					lx := sc.virtual_x + Recovery_inset
					ly := sc.virtual_y + Recovery_inset
					settings.set_strip_position (lx, ly)
				end
				place
			end
		end

	restore_to_default
			-- Force the strip to a known-good place and show it: the
			-- deliberate "I cannot find it" recovery, which always
			-- MOVES because the user already failed to find it.
		local
			sc: SW_SCREEN
		do
			create sc
			settings.set_strip_position (sc.virtual_x + Recovery_inset, sc.virtual_y + Recovery_inset)
			settings.store
			show
		ensure
			on_screen: is_displayed
		end

	refresh
			-- Re-place (the size may have changed) and repaint.
		do
			if is_displayed then
				place
				paint
			end
		end

feature -- Events (fed from the host window's shell-event seam)

	handle_event (a_type, a_x, a_y: INTEGER)
			-- 21 press (client x/y: transport or drag began),
			-- 22 moved (screen x/y: remember where it landed),
			-- 23 expose (repaint).
		local
			hit: INTEGER
		do
			inspect a_type
			when 21 then
				hit := transport_at (a_x, a_y)
				if hit /= 0 and then attached on_transport_agent as a then
					a.call ([hit])
				end
			when 22 then
				settings.set_strip_position (a_x, a_y)
				settings.store
			when 23 then
				paint
			else
			end
		end

feature -- Page caption

	page_caption: STRING_32
		attribute
			create Result.make_empty
		end

	set_page_caption (a_text: READABLE_STRING_GENERAL)
		do
			create page_caption.make_from_string_general (a_text)
			refresh
		ensure
			set: page_caption.same_string_general (a_text)
		end

	metrics_caption: STRING_32
		attribute
			create Result.make_empty
		end

	set_metrics_caption (a_text: READABLE_STRING_GENERAL)
			-- On the strip because the settings window spends an
			-- unattended run hidden behind the reader; the strip is
			-- the only thing on screen, so it is where a progress
			-- figure has to be to be read at all.
		do
			create metrics_caption.make_from_string_general (a_text)
			refresh
		ensure
			set: metrics_caption.same_string_general (a_text)
		end

feature -- Auto-advance transport

	set_transport_action (a_agent: PROCEDURE [INTEGER])
		do
			on_transport_agent := a_agent
		end

	set_transport_state (a_running, a_paused: BOOLEAN)
		do
			is_auto_running := a_running
			is_auto_paused := a_paused
			refresh
		ensure
			running_set: is_auto_running = a_running
			paused_set: is_auto_paused = a_paused
		end

	is_auto_running: BOOLEAN
	is_auto_paused: BOOLEAN

feature -- Measurement (the strip's own sizing laws, assaultable)

	current_width: INTEGER
			-- Captions are MEASURED, never assumed to fit: a rates
			-- line that loses its unit reads as a different value.
		do
			Result := Strip_width
			if has_visible_thumbnail and then attached thumbnail as th then
				Result := Result.max (th.width + 2 * Thumb_margin)
			end
			Result := Result.max (caption_width (page_caption))
			across
				metrics_lines as line
			loop
				Result := Result.max (caption_width (line))
			end
		ensure
			at_least_minimum: Result >= Strip_width
		end

	current_height: INTEGER
			-- Captions count OUTSIDE the thumbnail test: switching
			-- the picture off must not hide the page and the rates.
		do
			Result := Strip_height + thumbnail_extent
			if not page_caption.is_empty then
				Result := Result + Caption_height
			end
			Result := Result + metrics_lines.count * Caption_height
		ensure
			at_least_minimum: Result >= Strip_height
		end

	metrics_lines: LIST [STRING_32]
			-- Guarded: split on an empty string yields ONE empty
			-- item, which would reserve a blank row for a run that
			-- has not started.
		do
			if metrics_caption.is_empty then
				create {ARRAYED_LIST [STRING_32]} Result.make (0)
			else
				Result := metrics_caption.split ('%N')
			end
		end

	transport_at (a_x, a_y: INTEGER): INTEGER
			-- Which transport glyph is at the client point; 0 none.
		local
			i, l_left: INTEGER
		do
			if a_y >= Transport_top - 3 and a_y <= Transport_top + Transport_size + 3 then
				from
					i := 1
				until
					i > 3 or Result /= 0
				loop
					l_left := transport_left (i)
					if a_x >= l_left - 3 and a_x <= l_left + Transport_size + 3 then
						Result := i
					end
					i := i + 1
				end
			end
		ensure
			known: Result >= 0 and Result <= 3
		end

	transport_left (a_index: INTEGER): INTEGER
			-- Laid out from the right-hand end, inside the C side's
			-- no-drag corner (right 90px of the top 26px).
		require
			in_range: a_index >= 1 and a_index <= 3
		do
			Result := current_width - Transport_margin - 3 * Transport_size - 2 * Transport_gap
				+ (a_index - 1) * (Transport_size + Transport_gap)
		end

feature -- Constants

	Stage_idle: INTEGER = 0
	Stage_started: INTEGER = 1
	Stage_captured: INTEGER = 2
	Stage_ocr: INTEGER = 3
	Stage_written: INTEGER = 4
	Stage_ready: INTEGER = 5

	Strip_width: INTEGER = 320
	Strip_height: INTEGER = 34

	Transport_play: INTEGER = 1
	Transport_pause: INTEGER = 2
	Transport_stop: INTEGER = 3

feature {NONE} -- Painting

	paint
			-- The whole strip through its DC: panel, lights, message,
			-- thumbnail, captions, transport glyphs.
		local
			dc: POINTER
			ws: CAIRO_SURFACE
			ctx: CAIRO_CONTEXT
			p: SW_PAINTER
			w, h, i, cx: INTEGER
			ly: REAL_64
		do
			dc := tool_strip.dc
			if dc /= default_pointer then
				create ws.make_for_dc (dc)
				if ws.is_valid then
					create ctx.make (ws)
					p := painter_for (ctx)
					w := current_width
					h := current_height
					p.set_color (0x202228)
					p.fill_rect (0.0, 0.0, w, h)
					p.set_color (0x5A5E68)
					p.rrect_stroke (0.5, 0.5, w - 1.0, h - 1.0, 1.0)
						-- five lights, filling left to right
					from
						i := 1
					until
						i > 5
					loop
						cx := Light_left + (i - 1) * Light_pitch
						p.set_color (light_colour (i))
						p.circle_fill (cx + Light_size / 2.0, Light_top + Light_size / 2.0, Light_size / 2.0)
						p.set_color (0x5A5E68)
						p.circle_stroke (cx + Light_size / 2.0, Light_top + Light_size / 2.0, Light_size / 2.0)
						i := i + 1
					end
					p.font ({SW_PAINTER}.Role_ui, 12.0, True)
					p.set_color (0xE4E6EC)
					p.text (Light_left + 5 * Light_pitch + 8.0, Strip_height - 11.0, message)
						-- thumbnail, centred, hairline-framed
					if has_visible_thumbnail and then attached thumbnail as th then
						cx := (w - th.width) // 2
						p.draw_image (th, cx, Strip_height, th.width, th.height)
						p.set_color (0x5A5E68)
						p.rrect_stroke (cx - 1.0, Strip_height - 1.0, th.width + 2.0, th.height + 2.0, 1.0)
					end
						-- page and rates beneath: the one glance that
						-- answers "what is it on, how long left?"
					ly := caption_top
					p.font ({SW_PAINTER}.Role_ui, 12.0, False)
					if not page_caption.is_empty then
						p.set_color (0xE4E6EC)
						p.text (Caption_left, ly + Caption_baseline, page_caption)
						ly := ly + Caption_height
					end
					p.set_color (0x96C8A5)
					across
						metrics_lines as line
					loop
						p.text (Caption_left, ly + Caption_baseline, line)
						ly := ly + Caption_height
					end
						-- transport, from the drawn-glyph set: bright
						-- when worth pressing, dim when not
					p.set_color (transport_colour (not is_auto_running))
					p.glyph ({SW_PAINTER}.Glyph_play,
						transport_left (Transport_play) + Transport_size / 2.0,
						Transport_top + Transport_size / 2.0, Transport_size)
					p.set_color (transport_colour (is_auto_running))
					p.glyph ({SW_PAINTER}.Glyph_pause,
						transport_left (Transport_pause) + Transport_size / 2.0,
						Transport_top + Transport_size / 2.0, Transport_size)
					p.set_color (transport_colour (is_auto_running or is_auto_paused))
					p.glyph ({SW_PAINTER}.Glyph_stop,
						transport_left (Transport_stop) + Transport_size / 2.0,
						Transport_top + Transport_size / 2.0, Transport_size)
					ctx.destroy
				end
				ws.destroy
				tool_strip.release_dc (dc)
			end
		end

	light_colour (a_index: INTEGER): NATURAL_32
			-- The old strip's exact stage palette.
		require
			in_range: a_index >= 1 and a_index <= 5
		do
			if stage = Stage_ready then
				Result := 0x46C86E
			elseif a_index < stage then
				Result := 0x4682DC
			elseif a_index = stage then
				Result := 0xF0AF3C
			else
				Result := 0x3C3F48
			end
		end

	transport_colour (a_live: BOOLEAN): NATURAL_32
		do
			if a_live then
				Result := 0xD2D2D2
			else
				Result := 0x5A5A5A
			end
		end

	caption_top: INTEGER
		do
			Result := Strip_height
			if has_visible_thumbnail and then attached thumbnail as th then
				Result := Result + th.height
			end
		end

	has_visible_thumbnail: BOOLEAN
		do
			Result := show_thumbnail and thumbnail /= Void
		end

	thumbnail_extent: INTEGER
			-- Vertical space the thumbnail claims, margins included;
			-- zero when there is none or the panel is off.
		do
			if has_visible_thumbnail and then attached thumbnail as th then
				Result := th.height + 2 * Thumb_margin
			end
		ensure
			not_negative: Result >= 0
		end

	caption_width (a_text: READABLE_STRING_32): INTEGER
		do
			if not a_text.is_empty then
				measure_painter.font ({SW_PAINTER}.Role_ui, 12.0, False)
				Result := Caption_left + measure_painter.advance (a_text).rounded + Thumb_margin
			end
		ensure
			not_negative: Result >= 0
		end

	place
			-- Show (or re-show) at the remembered position, at the
			-- size the content needs right now.
		do
			tool_strip.show (settings.strip_x, settings.strip_y, current_width, current_height)
		end

	tool_strip: SHELL_STRIP
		once
			create Result
		end

	measure_painter: SW_PAINTER
			-- A tiny offscreen painter, for measuring captions.
		local
			s: CAIRO_SURFACE
			c: CAIRO_CONTEXT
			th: SW_THEME
		once
			create s.make (8, 8)
			create c.make (s)
			create th.make_dark
			create Result.make (c, th)
		end

	painter_for (a_ctx: CAIRO_CONTEXT): SW_PAINTER
		local
			th: SW_THEME
		do
			create th.make_dark
			create Result.make (a_ctx, th)
		end

	settings: OCR_SETTINGS

	thumbnail: detachable CAIRO_SURFACE

	show_thumbnail: BOOLEAN

	on_transport_agent: detachable PROCEDURE [INTEGER]

	Light_left: INTEGER = 12
	Light_top: INTEGER = 11
	Light_size: INTEGER = 12
	Light_pitch: INTEGER = 18
	Thumb_margin: INTEGER = 6
	Caption_left: INTEGER = 8
	Caption_height: INTEGER = 17
	Caption_baseline: INTEGER = 18
	Transport_size: INTEGER = 12
	Transport_gap: INTEGER = 7
	Transport_margin: INTEGER = 10
	Transport_top: INTEGER = 11
	Recovery_inset: INTEGER = 40
	Recovery_margin: INTEGER = 60

end
