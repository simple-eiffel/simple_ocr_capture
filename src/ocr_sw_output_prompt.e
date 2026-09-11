note
	description: "[
		The question asked before any unattended capture starts: where
		does the text go, and under what name? A drawn sheet holding
		the output folder, a Browse button, the file name, the full
		path that results, and a line saying what will happen to it -
		created, or appended to behind N KB already there.

		A run that reads a whole book, or fetches an hour of captions,
		must not land in last week's file because a field on another
		tab was never changed. The sheet puts both values in front of
		the user at the moment they matter; the verb button carries the
		rest of the work as a continuation, the way every confirm flow
		in this window does.
	]"

class
	OCR_SW_OUTPUT_PROMPT

inherit
	SW_COLUMN

create
	make_prompt

feature {NONE} -- Initialization

	make_prompt (a_title, a_explanation, a_folder, a_name, a_verb: READABLE_STRING_GENERAL)
			-- A sheet titled `a_title', explaining itself with
			-- `a_explanation', prefilled with `a_folder' and `a_name',
			-- whose primary button reads `a_verb'.
		require
			verb_given: not a_verb.is_empty
		local
			l_row: SW_ROW
			l_folder_label, l_name_label: SW_LABEL
		do
			make
			create verb.make_from_string_general (a_verb)
			create folder_box.make_single_line (a_folder)
			folder_box.set_spellcheck (False)
			create name_box.make_single_line (a_name)
			name_box.set_spellcheck (False)
			create path_label.make_mono ("")
			create status_label.make_ui ("")
			status_label := status_label.as_muted.with_wrap
			create verb_button.make_primary (a_verb, Void)
				-- every attached attribute is set: agents are safe now
			verb_button.set_on_click (agent do_accept)
			folder_box.set_on_change (agent refresh_status)
			name_box.set_on_change (agent refresh_status)
			put (create {SW_LABEL}.make (a_title, {SW_PAINTER}.Role_ui, 17.0, True))
			put ((create {SW_LABEL}.make_ui (a_explanation)).as_muted.with_wrap)
			create l_folder_label.make_ui ("Folder")
			create l_row.make
			l_row := l_row.add (l_folder_label.as_muted).add (folder_box)
				.add (create {SW_BUTTON}.make ("Browse...", agent do_browse))
			folder_box.set_grow (1.0)
			put (l_row)
			create l_name_label.make_ui ("File name")
			create l_row.make
			l_row := l_row.add (l_name_label.as_muted).add (name_box)
			name_box.set_grow (1.0)
			put (l_row)
			put (path_label)
			put (status_label)
			create l_row.make
			l_row := l_row.add (verb_button).add (create {SW_BUTTON}.make ("Cancel", agent do_cancel))
			put (l_row)
			refresh_status
		ensure
			folder_kept: folder.same_string_general (trimmed (a_folder))
			name_kept: file_name.same_string_general (trimmed (a_name))
		end

feature -- Access

	verb: STRING_32
			-- What the primary button says.

	folder: STRING_32
			-- The folder as typed, trimmed.
		do
			Result := trimmed (folder_box.text)
		end

	file_name: STRING_32
			-- The file name as typed, trimmed.
		do
			Result := trimmed (name_box.text)
		end

	full_path: STRING_32
			-- `folder' and `file_name' joined; empty while either is.
		do
			create Result.make (folder.count + file_name.count + 1)
			if is_complete then
				Result.append (folder)
				if Result.item (Result.count) /= '\' then
					Result.append_character ('\')
				end
				Result.append (file_name)
			end
		ensure
			empty_when_incomplete: not is_complete implies Result.is_empty
			joined_when_complete: is_complete implies Result.ends_with (file_name)
		end

	is_complete: BOOLEAN
			-- Are both values present?
		do
			Result := not folder.is_empty and then not file_name.is_empty
		end

	folder_exists: BOOLEAN
		do
			Result := not folder.is_empty and then (create {DIRECTORY}.make (folder)).exists
		end

	file_exists: BOOLEAN
		do
			Result := is_complete and then (create {RAW_FILE}.make_with_name (full_path)).exists
		end

	on_accept: detachable PROCEDURE [STRING_32, STRING_32]
			-- Called with (folder, file_name) once both are present.

	on_cancel: detachable PROCEDURE

	on_browse: detachable PROCEDURE
			-- The host shows its folder picker and calls `set_folder'.

feature -- Element change

	set_folder (a_folder: READABLE_STRING_GENERAL)
			-- The Browse round trip's answer.
		do
			folder_box.set_text (a_folder)
			refresh_status
		ensure
			set: folder.same_string_general (trimmed (a_folder))
		end

	set_file_name (a_name: READABLE_STRING_GENERAL)
		do
			name_box.set_text (a_name)
			refresh_status
		ensure
			set: file_name.same_string_general (trimmed (a_name))
		end

	set_on_accept (a_action: PROCEDURE [STRING_32, STRING_32])
		do
			on_accept := a_action
		ensure
			set: on_accept = a_action
		end

	set_on_cancel (a_action: PROCEDURE)
		do
			on_cancel := a_action
		ensure
			set: on_cancel = a_action
		end

	set_on_browse (a_action: PROCEDURE)
		do
			on_browse := a_action
		ensure
			set: on_browse = a_action
		end

	press_accept
			-- The verb button, driveable by hosts and tests.
		do
			do_accept
		end

feature -- Status report

	status_line: STRING_32
			-- What pressing the verb would do to the named file.
		local
			l_file: RAW_FILE
		do
			create Result.make (120)
			if folder.is_empty then
				Result.append_string_general ("Choose the folder the transcript goes in.")
			elseif file_name.is_empty then
				Result.append_string_general ("Name the file the transcript goes in.")
			elseif not folder_exists then
				Result.append_string_general ("This folder does not exist yet. It will be created when you press ")
				Result.append (verb)
				Result.append_character ('.')
			else
				create l_file.make_with_name (full_path)
				if l_file.exists then
					Result.append_string_general ("This file exists (")
					Result.append_string_general (((l_file.count + 1023) // 1024).out)
					Result.append_string_general (" KB). New text is appended after what is already there.")
				else
					Result.append_string_general ("A new file will be created.")
				end
			end
		ensure
			never_empty: not Result.is_empty
		end

	refresh_status
			-- Redraw the path and status lines from the boxes.
		do
			path_label.set_text (full_path)
			status_label.set_text (status_line)
			folder_box.set_invalid (folder.is_empty)
			name_box.set_invalid (file_name.is_empty)
		end

feature {NONE} -- Engine

	folder_box: SW_TEXT_BOX

	name_box: SW_TEXT_BOX

	path_label: SW_LABEL

	status_label: SW_LABEL

	verb_button: SW_BUTTON

	do_accept
			-- Hand (folder, file_name) on - or point at the gap.
		do
			refresh_status
			if is_complete and then attached on_accept as a then
				a.call (folder, file_name)
			end
		end

	do_cancel
		do
			if attached on_cancel as a then
				a.call
			end
		end

	do_browse
		do
			if attached on_browse as a then
				a.call
			end
		end

	trimmed (a_text: READABLE_STRING_GENERAL): STRING_32
		do
			create Result.make_from_string_general (a_text)
			Result.left_adjust
			Result.right_adjust
		end

invariant
	verb_given: not verb.is_empty

end
