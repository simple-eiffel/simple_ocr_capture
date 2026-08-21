note
	description: "[
		Entry point of the cairo-face build.

		Headless flags go to the classic CLI (worker mode and friends);
		anything else boots the cairo face. This is what lets the installed
		exe spawn ITSELF as its own OCR worker: the run engine resolves
		worker_exe to this very binary, and each `--worker' child comes back
		in through here, straight past the GUI.
	]"

class
	OCR_CAIRO_APP

create
	make

feature {NONE} -- Initialization

	make
		local
			l_args: ARGUMENTS_32
			l_cli: OCR_CLI
			l_gui: OCR_CAIRO_GUI
		do
			create l_args
			if l_args.argument_count >= 1 and then is_headless_flag (l_args.argument (1)) then
				create l_cli.make
			else
				create l_gui.make
			end
		end

	is_headless_flag (a_argument: READABLE_STRING_32): BOOLEAN
			-- Same list as OCR_APP: modes that must not start a GUI.
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
