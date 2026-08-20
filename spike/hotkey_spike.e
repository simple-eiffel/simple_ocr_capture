note
	description: "[
		Throwaway spike proving OCR_HOTKEY works: registers Ctrl+Alt+G
		system-wide, polls for presses, prints each one. Run it, then inject
		the combo from another process to confirm it fires without this app
		having focus.
	]"

class
	HOTKEY_SPIKE

create
	make

feature {NONE} -- Initialization

	make
			-- Register Ctrl+Alt+G and report presses for `Run_seconds'.
		local
			l_hotkey: OCR_HOTKEY
			l_ticks, l_presses, l_total: INTEGER
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_hotkey.make
			create l_env

			print ("=== HOTKEY SPIKE ===%N")
			print ("registering Ctrl+Alt+G ...%N")
			io.output.flush

			if not l_hotkey.register (l_hotkey.Mod_control | l_hotkey.Mod_alt, l_hotkey.Vk_g) then
				print ("RESULT: FAIL - RegisterHotKey refused (combo owned by another app?)%N")
				io.output.flush
			else
				print ("registered: " + l_hotkey.is_registered.out + "%N")
				print ("listening for " + Run_seconds.out + "s ...%N")
				io.output.flush

				from
					l_ticks := 0
				until
					l_ticks >= Run_seconds * Ticks_per_second
				loop
					l_presses := l_hotkey.taken_presses
					if l_presses > 0 then
						l_total := l_total + l_presses
						print ("HOTKEY FIRED (x" + l_presses.out + ") total=" + l_total.out + "%N")
						io.output.flush
					end
					l_env.sleep (Tick_nanoseconds)
					l_ticks := l_ticks + 1
				end

				print ("total presses: " + l_total.out + "%N")
				if l_total > 0 then
					print ("RESULT: PASS%N")
				else
					print ("RESULT: FAIL - no presses detected%N")
				end
				io.output.flush
				l_hotkey.cleanup
			end
		end

feature {NONE} -- Constants

	Run_seconds: INTEGER = 15

	Ticks_per_second: INTEGER = 20

	Tick_nanoseconds: INTEGER_64 = 50_000_000
			-- 50ms, matching the GUI timer tick the real app will use.

end
