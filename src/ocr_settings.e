note
	description: "[
		User-settable configuration, persisted as JSON under
		%APPDATA%\simple_ocr_capture\settings.json.

		Every field the GUI exposes lives here. `load' silently falls back to
		defaults for anything missing or malformed, so a hand-edited or
		partially-written settings file can never stop the app from starting.
	]"

class
	OCR_SETTINGS

inherit
	ANY
		redefine
			default_create
		end

create
	default_create

feature {NONE} -- Initialization

	default_create
			-- Populate with defaults.
		do
			region_x := 0
			region_y := 0
			region_width := 800
			region_height := 600
			create output_folder.make_from_string_general (default_output_folder)
			create text_file_name.make_from_string_general (Default_text_file_name)
			save_text := True
			save_image := True
			add_separators := True
			create image_format.make_from_string ("png")
			hotkey_modifiers := {OCR_HOTKEY}.Mod_control | {OCR_HOTKEY}.Mod_alt
			hotkey_key := {OCR_HOTKEY}.Vk_g
			create endpoint.make_from_string ("http://127.0.0.1:11435/api/generate")
			create model.make_from_string ("richardyoung/olmocr2:7b-q8")
			create ocr_prompt.make_from_string_general (Default_prompt)
			num_ctx := 16384
			num_predict := 8192
			strip_x := 40
			strip_y := 40
			show_strip := True
			show_thumbnail := True
			beep_on_ready := True
			capture_index := 0
			ocr_timeout_seconds := 300
				-- Both auto-advance rectangles start at zero extent, which
				-- `is_advance_region_valid' treats as "not set" and refuses to
				-- click. Auto-advance is off until asked for.
			advance_x := 0
			advance_y := 0
			advance_width := 0
			advance_height := 0
			page_label_x := 0
			page_label_y := 0
			page_label_width := 0
			page_label_height := 0
			auto_advance := False
			advance_delay_ms := 5000
				-- Nothing has been read yet, so there is nothing on disk these
				-- values could destroy. Only a `load' that finds a file it cannot
				-- parse clears this.
			is_load_trusted := True
		end

feature -- Access: capture region

	region_x, region_y: INTEGER
			-- Top-left corner of the capture rectangle, in screen coordinates.

	region_width, region_height: INTEGER
			-- Size of the capture rectangle.

feature -- Access: output

	output_folder: STRING_32
			-- Directory receiving the text file and any saved images.

	text_file_name: STRING_32
			-- Name of the single file OCR text is appended to.

	save_text: BOOLEAN
			-- Append recognized text to `text_file_name'?

	save_image: BOOLEAN
			-- Keep the captured image alongside the text?

	add_separators: BOOLEAN
			-- Write a "----- capture N  <timestamp> -----" header before each
			-- block of text? Off gives one continuous transcript, which is what
			-- you want when OCRing a book page by page.

	image_format: STRING_8
			-- "png" or "bmp". PNG is lossless; JPEG is deliberately absent
			-- because its artifacts measurably hurt OCR accuracy.

	capture_index: INTEGER
			-- Number of captures taken; drives image file numbering.

feature -- Access: trigger

	hotkey_modifiers: NATURAL_32
			-- Win32 MOD_* flags for the system-wide trigger.

	hotkey_key: NATURAL_32
			-- Virtual key code for the system-wide trigger.

feature -- Access: OCR

	endpoint: STRING_8
			-- Ollama generate endpoint.

	model: STRING_8
			-- Model tag to run.

	ocr_prompt: STRING_32
			-- Instruction sent with each image.

	ocr_timeout_seconds: INTEGER
			-- Request timeout. Generous, since a cold model load alone can
			-- take ~45s.

	num_ctx: INTEGER
			-- Context window in tokens.
			--
			-- THIS IS NOT A TUNING KNOB, IT IS A CORRECTNESS SETTING. The image
			-- and the transcription share one context. Ollama's default is 4096;
			-- a 1700x1816 screenshot consumes 4034 tokens on its own, leaving 62
			-- for output. The reply then stops mid-word with done_reason
			-- "length" - a full page of 22 verses came back as two - and nothing
			-- about it looks like an error. Measured 2026-08-05: at 4096 the
			-- reply was 188 characters; at 16384 the same image returned all
			-- 3674 characters with done_reason "stop".
			--
			-- Raise this if captures of large regions come back truncated;
			-- it costs VRAM.

	num_predict: INTEGER
			-- Maximum tokens to generate. Distinct from `num_ctx': this caps the
			-- answer, `num_ctx' caps image-plus-answer together.

feature -- Access: status strip

	strip_x, strip_y: INTEGER
			-- Last position of the always-on-top progress strip.

	show_strip: BOOLEAN
			-- Display the progress strip?

	show_thumbnail: BOOLEAN
			-- Show a small image of the last capture under the lights, so the
			-- region can be eyeballed without opening the output folder.

	beep_on_ready: BOOLEAN
			-- Sound a tone when a cycle completes?

feature -- Access: auto-advance

	advance_x, advance_y, advance_width, advance_height: INTEGER
			-- Rectangle around the reader's "next page" control. Its middle is
			-- what gets clicked between captures.

	page_label_x, page_label_y, page_label_width, page_label_height: INTEGER
			-- Rectangle around the reader's page indicator ("90-92 / 139"),
			-- read by OCR to record which pages a capture covers and to tell
			-- whether the page actually turned.

	auto_advance: BOOLEAN
			-- Turn the page automatically after each successful capture?

	advance_delay_ms: INTEGER
			-- How long to wait after clicking before capturing again, letting
			-- the reader render the new page.

feature -- Status report

	is_region_valid: BOOLEAN
			-- Is the capture rectangle usable?
		do
			Result := region_width > 0 and region_height > 0
		end

	is_advance_region_valid: BOOLEAN
			-- Has an advance button rectangle been set?
			--
			-- Zero extent is not merely unusable, it is dangerous: a defaulted
			-- rectangle would put the click at the top-left of the desktop once
			-- per page. Nothing clicks until the user has dragged a real box.
		do
			Result := advance_width > 0 and advance_height > 0
		end

	is_page_label_region_valid: BOOLEAN
			-- Has a page indicator rectangle been set?
		do
			Result := page_label_width > 0 and page_label_height > 0
		end

	output_folder_exists: BOOLEAN
			-- Is the output folder actually there?
			--
			-- Asked rather than assumed. The capture cycle used to CREATE it
			-- silently, so a typo in the path produced a new folder and a book
			-- scanned quietly into the wrong place.
		local
			l_dir: DIRECTORY
			l_retried: BOOLEAN
		do
			if not l_retried and then not output_folder.is_empty then
				create l_dir.make_with_name (output_folder)
				Result := l_dir.exists
			end
		rescue
			l_retried := True
			retry
		end

	is_label_over_advance: BOOLEAN
			-- Do the page-indicator and advance-button rectangles overlap?
			--
			-- They never sensibly should: one is text to be read, the other a
			-- control to be clicked. A page-indicator box was once dragged onto
			-- the advance button, and the run then read "10" off it for seven
			-- pages - naming every image ocr_10-N.png and annotating every
			-- transcript block with the same wrong page - while nothing in the
			-- output said anything was amiss.
			--
			-- Reported rather than enforced. An unusual reader could conceivably
			-- print a page number on its own control, and refusing a rectangle
			-- the user deliberately chose is precisely the mistake the removed
			-- label-format validator made.
		do
			Result := is_advance_region_valid and then is_page_label_region_valid
				and then page_label_x < advance_x + advance_width
				and then page_label_x + page_label_width > advance_x
				and then page_label_y < advance_y + advance_height
				and then page_label_y + page_label_height > advance_y
		end

	text_file_path: STRING_32
			-- Full path of the appended text file.
		do
			create Result.make_from_string (output_folder)
			if not Result.is_empty and then Result.item (Result.count) /= '\' then
				Result.append_character ('\')
			end
			Result.append (text_file_name)
		end

feature -- Element change

	set_region (a_x, a_y, a_width, a_height: INTEGER)
			-- Set the capture rectangle.
		require
			positive_extent: a_width > 0 and a_height > 0
		do
			region_x := a_x
			region_y := a_y
			region_width := a_width
			region_height := a_height
		ensure
			set: region_x = a_x and region_y = a_y
			sized: region_width = a_width and region_height = a_height
			valid: is_region_valid
		end

	set_advance_region (a_x, a_y, a_width, a_height: INTEGER)
			-- Set the rectangle whose middle is clicked to turn the page.
		require
			positive_extent: a_width > 0 and a_height > 0
		do
			advance_x := a_x
			advance_y := a_y
			advance_width := a_width
			advance_height := a_height
		ensure
			set: advance_x = a_x and advance_y = a_y
			sized: advance_width = a_width and advance_height = a_height
			valid: is_advance_region_valid
		end

	set_page_label_region (a_x, a_y, a_width, a_height: INTEGER)
			-- Set the rectangle the page indicator is read from.
		require
			positive_extent: a_width > 0 and a_height > 0
		do
			page_label_x := a_x
			page_label_y := a_y
			page_label_width := a_width
			page_label_height := a_height
		ensure
			set: page_label_x = a_x and page_label_y = a_y
			sized: page_label_width = a_width and page_label_height = a_height
			valid: is_page_label_region_valid
		end

	set_auto_advance (a_value: BOOLEAN)
		do
			auto_advance := a_value
		ensure
			set: auto_advance = a_value
		end

	set_advance_delay_ms (a_value: INTEGER)
			-- Set the settle time, clamped to something a reader can actually
			-- repaint in.
		do
			advance_delay_ms := a_value.max (Minimum_advance_delay_ms)
		ensure
			not_below_floor: advance_delay_ms >= Minimum_advance_delay_ms
		end

	clear_region
			-- Forget the capture rectangle.
			--
			-- A command of its own rather than a weaker precondition on
			-- `set_region'. That routine promises `is_region_valid' afterwards,
			-- which is exactly why it refuses a zero extent - and why "unset"
			-- needs its own way of being said. Without these, a Clear All that
			-- went through the ordinary setters simply could not clear anything.
		do
			region_x := 0
			region_y := 0
			region_width := 0
			region_height := 0
		ensure
			not_set: not is_region_valid
		end

	clear_advance_region
			-- Forget the rectangle that gets clicked to turn the page.
		do
			advance_x := 0
			advance_y := 0
			advance_width := 0
			advance_height := 0
		ensure
			not_set: not is_advance_region_valid
		end

	clear_page_label_region
			-- Forget the rectangle the page indicator is read from.
		do
			page_label_x := 0
			page_label_y := 0
			page_label_width := 0
			page_label_height := 0
		ensure
			not_set: not is_page_label_region_valid
		end

	set_output_folder (a_folder: READABLE_STRING_GENERAL)
		do
			create output_folder.make_from_string_general (a_folder)
		ensure
			set: output_folder.same_string_general (a_folder)
		end

	Default_text_file_name: STRING_8 = "ocr_capture.txt"
			-- Name used on a fresh install, and what Clear All resets to.
			--
			-- Reset to this rather than to nothing: `set_text_file_name' will
			-- not accept an empty name, and a placeholder that is obviously not
			-- a book title cannot silently append one book onto another's
			-- transcript, which is the failure the reset exists to prevent.

	set_text_file_name (a_name: READABLE_STRING_GENERAL)
		require
			not_empty: not a_name.is_empty
		do
			create text_file_name.make_from_string_general (a_name)
		ensure
			set: text_file_name.same_string_general (a_name)
		end

	set_save_text (a_flag: BOOLEAN)
		do
			save_text := a_flag
		ensure
			set: save_text = a_flag
		end

	set_save_image (a_flag: BOOLEAN)
		do
			save_image := a_flag
		ensure
			set: save_image = a_flag
		end

	set_add_separators (a_flag: BOOLEAN)
		do
			add_separators := a_flag
		ensure
			set: add_separators = a_flag
		end

	set_image_format (a_format: READABLE_STRING_8)
		require
			supported: a_format.same_string ("png") or a_format.same_string ("bmp")
		do
			create image_format.make_from_string (a_format)
		ensure
			set: image_format.same_string (a_format)
		end

	set_hotkey (a_modifiers, a_key: NATURAL_32)
		require
			key_set: a_key /= 0
			has_modifier: a_modifiers /= 0
				-- A modifier-less global hotkey is not a lesser setting, it is a
				-- destructive one: RegisterHotKey with no modifiers claims the
				-- bare key from EVERY application on the system. Registering
				-- plain "A" makes the letter A untypeable everywhere until the
				-- process exits.
		do
			hotkey_modifiers := a_modifiers
			hotkey_key := a_key
		ensure
			set: hotkey_modifiers = a_modifiers and hotkey_key = a_key
		end

	set_endpoint (a_url: READABLE_STRING_8)
		require
			not_empty: not a_url.is_empty
		do
			create endpoint.make_from_string (a_url)
		ensure
			set: endpoint.same_string (a_url)
		end

	set_model (a_model: READABLE_STRING_8)
		require
			not_empty: not a_model.is_empty
		do
			create model.make_from_string (a_model)
		ensure
			set: model.same_string (a_model)
		end

	set_ocr_prompt (a_prompt: READABLE_STRING_GENERAL)
		do
			create ocr_prompt.make_from_string_general (a_prompt)
		end

	set_ocr_timeout_seconds (a_seconds: INTEGER)
		require
			positive: a_seconds > 0
		do
			ocr_timeout_seconds := a_seconds
		ensure
			set: ocr_timeout_seconds = a_seconds
		end

	set_num_ctx (a_tokens: INTEGER)
		require
			positive: a_tokens > 0
		do
			num_ctx := a_tokens
		ensure
			set: num_ctx = a_tokens
		end

	set_num_predict (a_tokens: INTEGER)
		require
			positive: a_tokens > 0
		do
			num_predict := a_tokens
		ensure
			set: num_predict = a_tokens
		end

	set_strip_position (a_x, a_y: INTEGER)
		do
			strip_x := a_x
			strip_y := a_y
		ensure
			set: strip_x = a_x and strip_y = a_y
		end

	set_show_strip (a_flag: BOOLEAN)
		do
			show_strip := a_flag
		ensure
			set: show_strip = a_flag
		end

	set_show_thumbnail (a_flag: BOOLEAN)
		do
			show_thumbnail := a_flag
		ensure
			set: show_thumbnail = a_flag
		end

	set_beep_on_ready (a_flag: BOOLEAN)
		do
			beep_on_ready := a_flag
		ensure
			set: beep_on_ready = a_flag
		end

	bump_capture_index
			-- Advance the capture counter.
		do
			capture_index := capture_index + 1
		ensure
			advanced: capture_index = old capture_index + 1
		end

feature -- Persistence

	is_load_trusted: BOOLEAN
			-- May these values be written back to disk?
			--
			-- False once `load' has met a settings file it could not read: the
			-- object then holds defaults that would silently replace a damaged
			-- but possibly recoverable file.

	settings_path: STRING_32
			-- Full path of the settings file.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			create Result.make (64)
			if attached l_env.item ("APPDATA") as al_appdata and then not al_appdata.is_empty then
				Result.append_string_general (al_appdata)
			else
				Result.append_string_general (".")
			end
			Result.append_string_general ("\simple_ocr_capture")
			Result.append_string_general ("\settings.json")
		end

	store
			-- Write current values to `settings_path', creating the directory
			-- if needed. Failure is silent: losing settings must never take
			-- the app down mid-capture.
			--
			-- Written to a temporary file and moved into place, never straight
			-- over the real one. A direct write truncates first, so a crash - or
			-- a second instance reading at that instant - sees a half file,
			-- which `load' cannot parse and silently replaces with defaults.
			-- The next `store' then makes those defaults permanent, losing the
			-- output folder, the capture region and the running index at once.
		local
			l_dir: DIRECTORY
			l_file: PLAIN_TEXT_FILE
			l_target: RAW_FILE
			l_temporary: RAW_FILE
			l_path: PATH
			l_retried: BOOLEAN
		do
			if not l_retried and is_load_trusted then
				create l_path.make_from_string (settings_path)
				if attached l_path.parent as al_parent then
					create l_dir.make_with_path (al_parent)
					if not l_dir.exists then
						l_dir.recursive_create_dir
					end
				end

				create l_file.make_with_name (temporary_path)
				l_file.create_read_write
				l_file.put_string (as_json)
				l_file.close

					-- Delete-then-rename rather than one atomic move: Eiffel's
					-- rename fails on Windows when the target exists. The window
					-- between the two is a few microseconds and leaves the
					-- complete new file behind it, where a truncating write left
					-- a partial one for as long as it took to serialise.
				create l_target.make_with_name (settings_path)
				if l_target.exists then
					l_target.delete
				end
				create l_temporary.make_with_name (temporary_path)
				if l_temporary.exists then
					l_temporary.rename_file (settings_path)
				end
			end
		rescue
			l_retried := True
			retry
		end

	temporary_path: STRING_32
			-- Scratch file `store' builds the new settings in.
		do
			Result := settings_path + {STRING_32} ".tmp"
		ensure
			non_empty: not Result.is_empty
		end

	load
			-- Read values from `settings_path'. Missing file, missing keys and
			-- malformed JSON all leave the corresponding defaults in place.
		local
			l_file: PLAIN_TEXT_FILE
			l_content: STRING_8
			l_quick: SIMPLE_JSON_QUICK
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_file.make_with_name (settings_path)
				if l_file.exists and then l_file.is_readable then
					l_file.open_read
					l_file.read_stream (l_file.count)
					l_content := l_file.last_string.twin
					l_file.close
					create l_quick.make
					if attached l_quick.parse_object (l_content) as al_obj then
						apply (al_obj)
					else
							-- A file that exists but will not parse is damaged, not
							-- absent. Writing defaults back over it would destroy
							-- whatever is still in there, so `store' is barred
							-- until this object has been given values it can trust.
						is_load_trusted := False
					end
				end
			end
		rescue
			l_retried := True
			is_load_trusted := False
			retry
		end

feature {NONE} -- Persistence implementation

	as_json: STRING_8
			-- Current values as a JSON object.
		local
			u: OCR_JSON_UTIL
		do
			create u
			create Result.make (768)
			Result.append ("{%N")
			Result.append ("  %"region_x%": " + region_x.out + ",%N")
			Result.append ("  %"region_y%": " + region_y.out + ",%N")
			Result.append ("  %"region_width%": " + region_width.out + ",%N")
			Result.append ("  %"region_height%": " + region_height.out + ",%N")
			Result.append ("  %"output_folder%": " + u.quoted (output_folder) + ",%N")
			Result.append ("  %"text_file_name%": " + u.quoted (text_file_name) + ",%N")
			Result.append ("  %"save_text%": " + save_text.out.as_lower + ",%N")
			Result.append ("  %"save_image%": " + save_image.out.as_lower + ",%N")
			Result.append ("  %"add_separators%": " + add_separators.out.as_lower + ",%N")
			Result.append ("  %"image_format%": " + u.quoted (image_format) + ",%N")
			Result.append ("  %"hotkey_modifiers%": " + hotkey_modifiers.out + ",%N")
			Result.append ("  %"hotkey_key%": " + hotkey_key.out + ",%N")
			Result.append ("  %"endpoint%": " + u.quoted (endpoint) + ",%N")
			Result.append ("  %"model%": " + u.quoted (model) + ",%N")
			Result.append ("  %"ocr_prompt%": " + u.quoted (ocr_prompt) + ",%N")
			Result.append ("  %"ocr_timeout_seconds%": " + ocr_timeout_seconds.out + ",%N")
			Result.append ("  %"num_ctx%": " + num_ctx.out + ",%N")
			Result.append ("  %"num_predict%": " + num_predict.out + ",%N")
			Result.append ("  %"strip_x%": " + strip_x.out + ",%N")
			Result.append ("  %"strip_y%": " + strip_y.out + ",%N")
			Result.append ("  %"show_strip%": " + show_strip.out.as_lower + ",%N")
			Result.append ("  %"show_thumbnail%": " + show_thumbnail.out.as_lower + ",%N")
			Result.append ("  %"beep_on_ready%": " + beep_on_ready.out.as_lower + ",%N")
			Result.append ("  %"advance_x%": " + advance_x.out + ",%N")
			Result.append ("  %"advance_y%": " + advance_y.out + ",%N")
			Result.append ("  %"advance_width%": " + advance_width.out + ",%N")
			Result.append ("  %"advance_height%": " + advance_height.out + ",%N")
			Result.append ("  %"page_label_x%": " + page_label_x.out + ",%N")
			Result.append ("  %"page_label_y%": " + page_label_y.out + ",%N")
			Result.append ("  %"page_label_width%": " + page_label_width.out + ",%N")
			Result.append ("  %"page_label_height%": " + page_label_height.out + ",%N")
			Result.append ("  %"auto_advance%": " + auto_advance.out.as_lower + ",%N")
			Result.append ("  %"advance_delay_ms%": " + advance_delay_ms.out + ",%N")
			Result.append ("  %"capture_index%": " + capture_index.out + "%N")
			Result.append ("}%N")
		end

	apply (a_obj: SIMPLE_JSON_OBJECT)
			-- Overwrite fields present in `a_obj', leaving the rest at defaults.
		do
			region_x := integer_from (a_obj, "region_x", region_x)
			region_y := integer_from (a_obj, "region_y", region_y)
			region_width := integer_from (a_obj, "region_width", region_width)
			region_height := integer_from (a_obj, "region_height", region_height)
			if attached a_obj.string_item ({STRING_32} "output_folder") as al_s then
				output_folder := al_s.twin
			end
			if attached a_obj.string_item ({STRING_32} "text_file_name") as al_s and then not al_s.is_empty then
				text_file_name := al_s.twin
			end
			save_text := boolean_from (a_obj, "save_text", save_text)
			save_image := boolean_from (a_obj, "save_image", save_image)
			add_separators := boolean_from (a_obj, "add_separators", add_separators)
			if attached a_obj.string_item ({STRING_32} "image_format") as al_s then
				if al_s.same_string_general ("png") or al_s.same_string_general ("bmp") then
					image_format := narrowed (al_s)
				end
			end
			hotkey_modifiers := integer_from (a_obj, "hotkey_modifiers", hotkey_modifiers.to_integer_32).to_natural_32
			hotkey_key := integer_from (a_obj, "hotkey_key", hotkey_key.to_integer_32).to_natural_32
			if hotkey_modifiers = 0 or hotkey_key = 0 then
					-- Repair rather than honour: a settings file carrying a
					-- modifier-less hotkey would hijack a bare key at startup.
				hotkey_modifiers := {OCR_HOTKEY}.Mod_control | {OCR_HOTKEY}.Mod_alt
				hotkey_key := {OCR_HOTKEY}.Vk_g
			end
			if attached a_obj.string_item ({STRING_32} "endpoint") as al_s and then not al_s.is_empty then
				endpoint := narrowed (al_s)
			end
			if attached a_obj.string_item ({STRING_32} "model") as al_s and then not al_s.is_empty then
				model := narrowed (al_s)
			end
			if attached a_obj.string_item ({STRING_32} "ocr_prompt") as al_s then
				ocr_prompt := al_s.twin
			end
			ocr_timeout_seconds := integer_from (a_obj, "ocr_timeout_seconds", ocr_timeout_seconds)
			if ocr_timeout_seconds <= 0 then
				ocr_timeout_seconds := 300
			end
			num_ctx := integer_from (a_obj, "num_ctx", num_ctx)
			if num_ctx < 4096 then
					-- Below this the image alone can fill the window, silently
					-- truncating every capture. Refuse to honour it.
				num_ctx := 16384
			end
			num_predict := integer_from (a_obj, "num_predict", num_predict)
			if num_predict <= 0 then
				num_predict := 8192
			end
			strip_x := integer_from (a_obj, "strip_x", strip_x)
			strip_y := integer_from (a_obj, "strip_y", strip_y)
			show_strip := boolean_from (a_obj, "show_strip", show_strip)
			show_thumbnail := boolean_from (a_obj, "show_thumbnail", show_thumbnail)
			beep_on_ready := boolean_from (a_obj, "beep_on_ready", beep_on_ready)
			advance_x := integer_from (a_obj, "advance_x", advance_x)
			advance_y := integer_from (a_obj, "advance_y", advance_y)
			advance_width := integer_from (a_obj, "advance_width", advance_width)
			advance_height := integer_from (a_obj, "advance_height", advance_height)
			page_label_x := integer_from (a_obj, "page_label_x", page_label_x)
			page_label_y := integer_from (a_obj, "page_label_y", page_label_y)
			page_label_width := integer_from (a_obj, "page_label_width", page_label_width)
			page_label_height := integer_from (a_obj, "page_label_height", page_label_height)
			auto_advance := boolean_from (a_obj, "auto_advance", auto_advance)
			advance_delay_ms := integer_from (a_obj, "advance_delay_ms", advance_delay_ms).max (Minimum_advance_delay_ms)
			capture_index := integer_from (a_obj, "capture_index", capture_index)
		end

	integer_from (a_obj: SIMPLE_JSON_OBJECT; a_key: STRING_8; a_default: INTEGER): INTEGER
			-- Integer at `a_key', or `a_default' when absent or not a number.
		do
			Result := a_default
			if attached a_obj.item (a_key.to_string_32) as al_value then
				if al_value.is_integer then
					Result := al_value.integer_value.to_integer_32
				elseif al_value.is_number then
					Result := al_value.real_value.truncated_to_integer
				end
			end
		end

	boolean_from (a_obj: SIMPLE_JSON_OBJECT; a_key: STRING_8; a_default: BOOLEAN): BOOLEAN
			-- Boolean at `a_key', or `a_default' when absent or not a boolean.
		do
			Result := a_default
			if attached a_obj.item (a_key.to_string_32) as al_value then
				if al_value.is_boolean then
					Result := al_value.boolean_value
				end
			end
		end

	narrowed (a_text: READABLE_STRING_32): STRING_8
			-- `a_text' as UTF-8 bytes. Endpoint, model tag and image format are
			-- protocol values, held as STRING_8 rather than STRING_32.
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
		ensure
			attached_result: Result /= Void
		end

	default_output_folder: STRING_32
			-- %USERPROFILE%\Documents\OCR Captures, or "." if unresolvable.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			create Result.make (64)
			if attached l_env.item ("USERPROFILE") as al_home and then not al_home.is_empty then
				Result.append_string_general (al_home)
				Result.append_string_general ("\Documents\OCR Captures")
			else
				Result.append_string_general (".")
			end
		end

feature -- Constants

	Default_prompt: STRING_32 = "Transcribe all text in this image exactly as it appears, verbatim. Output only the transcribed text, nothing else."

	Page_label_prompt: STRING_32 = "Read the page number or page range shown in this image. Output only what is written, nothing else."
			-- Used for the page indicator, where the general prompt's "transcribe
			-- everything" invites the model to describe the surrounding chrome.

	Minimum_advance_delay_ms: INTEGER = 500
			-- Floor for the settle time. Below this the capture races the
			-- reader's repaint and photographs the previous page, which the
			-- advance check would then correctly - and confusingly - call a
			-- failure to turn.

invariant
	folder_attached: output_folder /= Void
	name_not_empty: not text_file_name.is_empty
	format_known: image_format.same_string ("png") or image_format.same_string ("bmp")
	timeout_positive: ocr_timeout_seconds > 0
	context_usable: num_ctx >= 4096
	prediction_positive: num_predict > 0

end
