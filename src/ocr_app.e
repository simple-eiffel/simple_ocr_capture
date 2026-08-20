note
	description: "[
		Application root. One executable, two modes:

		  <exe>                        the GUI
		  <exe> --worker <img> <txt>   OCR one image, no GUI
		  <exe> --shot <x> <y> <w> <h> capture + OCR + print (diagnostic)

		Worker mode is dispatched BEFORE any Vision2 object exists. The GUI
		spawns a worker per capture, and none of them should pay to start a
		windowing subsystem.
	]"

class
	OCR_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Run the GUI, or a headless mode if the command line asks.
		local
			l_args: ARGUMENTS_32
			l_cli: OCR_CLI
			l_gui: OCR_GUI
		do
			create l_args
			if l_args.argument_count >= 1 and then is_headless_flag (l_args.argument (1)) then
				create l_cli.make
			else
				create l_gui.make
				l_gui.launch
			end
		end

feature {NONE} -- Implementation

	is_headless_flag (a_argument: READABLE_STRING_32): BOOLEAN
			-- Does `a_argument' select a mode that must not start the GUI?
		do
			Result := a_argument.same_string_general ("--worker")
				or a_argument.same_string_general ("--shot")
				or a_argument.same_string_general ("--label-worker")
				or a_argument.same_string_general ("--rescan")
				or a_argument.same_string_general ("--image-name")
				or a_argument.same_string_general ("--compare")
				or a_argument.same_string_general ("--health")
				or a_argument.same_string_general ("--runlog")
				or a_argument.same_string_general ("--metrics")
				or a_argument.same_string_general ("--outline")
				or a_argument.same_string_general ("--postclick")
				or a_argument.same_string_general ("--audit")
		end

end
