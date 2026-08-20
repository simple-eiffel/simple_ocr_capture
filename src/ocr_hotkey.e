note
	description: "[
		System-wide hotkey. Fires while any application has focus, and consumes
		the keystroke so the focused application never sees it.

		Poll `taken_presses' from a GUI timer tick; it returns how many times the
		hotkey fired since the previous call and resets the counter.

			create hotkey.make
			if hotkey.register (hotkey.Mod_control | hotkey.Mod_alt, hotkey.Vk_g) then
				-- on each timer tick:
				if hotkey.taken_presses > 0 then start_capture_cycle end
			end
	]"
	design: "[
		Registration targets a message-only window owned by this class rather
		than the thread queue. Vision2 pumps the same thread with
		GetMessage(NULL); a thread-queue hotkey would be retrieved there and
		dropped, since DispatchMessage routes nowhere when msg.hwnd is NULL.
	]"

class
	OCR_HOTKEY

create
	make

feature {NONE} -- Initialization

	make
			-- Create an unregistered hotkey.
		do
			last_modifiers := 0
			last_key := 0
		ensure
			not_registered: not is_registered
		end

feature -- Access

	last_modifiers: NATURAL_32
			-- Modifier flags passed to the most recent `register' attempt.

	last_key: NATURAL_32
			-- Virtual key code passed to the most recent `register' attempt.

feature -- Status report

	is_registered: BOOLEAN
			-- Is a system-wide hotkey currently held by `Current'?
		do
			Result := c_is_registered /= 0
		end

feature -- Element change

	register (a_modifiers, a_key: NATURAL_32): BOOLEAN
			-- Claim the system-wide hotkey `a_modifiers' + `a_key'.
			-- Returns False when another application already owns the combo,
			-- or when `a_modifiers' is empty.
			--
			-- The modifier requirement is a safety interlock, not validation.
			-- RegisterHotKey with no modifiers claims the BARE key across the
			-- whole desktop: registering plain "A" makes the letter A
			-- untypeable in every application until this process exits. That
			-- has happened once here, from a settings-window round-trip that
			-- silently zeroed the modifiers, so the refusal lives at the lowest
			-- level where it cannot be bypassed by a caller's mistake.
		require
			key_not_zero: a_key /= 0
		do
			if a_modifiers = 0 then
				last_modifiers := 0
				last_key := a_key
				-- Result stays False; nothing is registered.
			else
			last_modifiers := a_modifiers
				last_key := a_key
				Result := c_register (a_modifiers, a_key) /= 0
			end
		ensure
			registered_on_success: Result implies is_registered
			never_modifierless: a_modifiers = 0 implies not Result
			key_recorded: last_key = a_key
		end

	unregister
			-- Release the hotkey, if held.
		do
			c_unregister
		ensure
			released: not is_registered
		end

feature -- Basic operations

	taken_presses: INTEGER
			-- Number of times the hotkey fired since the previous call.
			-- Resets the counter, so each press is reported exactly once.
		do
			Result := c_take_presses
		ensure
			not_negative: Result >= 0
		end

	cleanup
			-- Release the hotkey and destroy the message-only window.
		do
			c_cleanup
		ensure
			released: not is_registered
		end

feature -- Constants (Win32 modifier flags)

	Mod_alt: NATURAL_32 = 1
	Mod_control: NATURAL_32 = 2
	Mod_shift: NATURAL_32 = 4
	Mod_win: NATURAL_32 = 8

feature -- Constants (common virtual key codes)

	Vk_g: NATURAL_32 = 0x47
	Vk_f9: NATURAL_32 = 0x78
	Vk_f10: NATURAL_32 = 0x79
	Vk_f11: NATURAL_32 = 0x7A
	Vk_f12: NATURAL_32 = 0x7B

feature {NONE} -- Externals

	c_register (a_modifiers, a_key: NATURAL_32): INTEGER
		external
			"C inline use %"ocr_hotkey.h%""
		alias
			"return soh_register ((unsigned int) $a_modifiers, (unsigned int) $a_key);"
		end

	c_unregister
		external
			"C inline use %"ocr_hotkey.h%""
		alias
			"soh_unregister ();"
		end

	c_is_registered: INTEGER
		external
			"C inline use %"ocr_hotkey.h%""
		alias
			"return soh_is_registered ();"
		end

	c_take_presses: INTEGER
		external
			"C inline use %"ocr_hotkey.h%""
		alias
			"return soh_take_presses ();"
		end

	c_cleanup
		external
			"C inline use %"ocr_hotkey.h%""
		alias
			"soh_cleanup ();"
		end

end
