note
	description: "[
		Synthesises a left mouse click at a point on the virtual desktop, used to
		press the reader's "next page" control between captures.

		The pointer is put back where it was afterwards. Without that, every page
		turn would drag the user's cursor to the corner of the screen and leave
		it there, which over a hundred-page session is intolerable.

		The foreground window is put back too. A click activates whatever window
		it lands on, so an unattended run would steal focus from whatever its
		owner was doing - taking notes, answering mail - once per page, for
		hours. Restoring it means a run can proceed in the background.
	]"
	design: "[
		SendInput rather than mouse_event: mouse_event is superseded, and
		SendInput's absolute coordinates are normalised to 0..65535 across the
		WHOLE virtual desktop, so it addresses a second monitor correctly where
		SetCursorPos-plus-mouse_event depends on the primary screen's origin.

		A click is only ever issued for a rectangle the user dragged. That
		interlock is the same one `register' in OCR_HOTKEY enforces, and for the
		same reason: a coordinate defaulted to zero would quietly click the
		top-left corner of the desktop - the Start button - once per page.
	]"

class
	OCR_CLICKER

create
	make

feature {NONE} -- Initialization

	make
			-- Prepare a clicker.
		do
			create last_error.make_empty
		ensure
			no_error: last_error.is_empty
		end

feature -- Access

	last_error: STRING_32
			-- Why the most recent `click_centre_of' refused; empty when it clicked.

feature -- Basic operations

	click_centre_of (a_x, a_y, a_width, a_height: INTEGER): BOOLEAN
			-- Click the middle of the rectangle at `a_x', `a_y'. True when the
			-- click was issued.
			--
			-- The middle rather than a corner: the user drags a box around a
			-- button, and the edges of that box are the parts most likely to
			-- fall outside the button itself.
		do
			last_error.wipe_out
			if a_width <= 0 or a_height <= 0 then
				last_error := {STRING_32} "No advance button region set - drag one first."
			else
				c_click_at (a_x + a_width // 2, a_y + a_height // 2)
				Result := True
			end
		ensure
			error_iff_refused: Result = last_error.is_empty
		end

feature -- Spike: clicking without stealing focus

	post_click_at (a_x, a_y: INTEGER): BOOLEAN
			-- Deliver a click to the window at (`a_x', `a_y') by POSTING mouse
			-- messages rather than injecting them. True when the foreground
			-- window was unchanged afterwards - that is, when no focus was
			-- stolen.
			--
			-- The point of the whole exercise: `SendInput' activates whatever it
			-- clicks, and for the moment focus sits on the reader the user's own
			-- keystrokes are delivered there. A posted message does not activate
			-- anything, so the routing never moves.
			--
			-- Whether the target ACTS on it is another matter, and the reason
			-- this is a spike. Chromium-based applications hit-test raw input
			-- and commonly ignore posted mouse messages; native windows commonly
			-- honour them. Reported separately from the focus result, because a
			-- click that steals no focus and also does nothing is useless.
		do
			last_error.wipe_out
			Result := c_post_click_at (a_x, a_y) /= 0
		end

	last_post_report: STRING_32
			-- What `post_click_at' found: the window it targeted and whether the
			-- foreground changed.
		attribute
			create Result.make_empty
		end

feature {NONE} -- Externals

	c_post_click_at (a_x, a_y: INTEGER): INTEGER
			-- Post a click to the window under (`a_x', `a_y'). Returns 1 when
			-- the foreground window was the same before and after.
		external
			"C inline use %"windows.h%""
		alias
			"[
				POINT pt;
				HWND target, fg_before, fg_after;
				LPARAM lp;

				pt.x = $a_x;
				pt.y = $a_y;
				fg_before = GetForegroundWindow ();

				target = WindowFromPoint (pt);
				if (target == NULL) return 0;

				/* Message coordinates are relative to the target's client area,
				   not the screen. */
				ScreenToClient (target, &pt);
				lp = MAKELPARAM (pt.x, pt.y);

				PostMessage (target, WM_LBUTTONDOWN, MK_LBUTTON, lp);
				PostMessage (target, WM_LBUTTONUP, 0, lp);

				Sleep (60);
				fg_after = GetForegroundWindow ();
				return (fg_before == fg_after) ? 1 : 0;
			]"
		end

feature {NONE} -- Externals (original)

	c_click_at (a_x, a_y: INTEGER)
			-- Move the pointer to (`a_x', `a_y'), click, and put it back.
		external
			"C inline use %"windows.h%""
		alias
			"[
				POINT before;
				HWND before_focus;
				INPUT in[3];
				int vx = GetSystemMetrics (SM_XVIRTUALSCREEN);
				int vy = GetSystemMetrics (SM_YVIRTUALSCREEN);
				int vw = GetSystemMetrics (SM_CXVIRTUALSCREEN);
				int vh = GetSystemMetrics (SM_CYVIRTUALSCREEN);
				LONG nx, ny;

				if (vw <= 1) vw = 2;
				if (vh <= 1) vh = 2;

				/* SendInput's absolute space is 0..65535 over the whole desktop. */
				nx = (LONG) (((double) ($a_x - vx) * 65535.0) / (double) (vw - 1));
				ny = (LONG) (((double) ($a_y - vy) * 65535.0) / (double) (vh - 1));

				if (!GetCursorPos (&before)) { before.x = 0; before.y = 0; }
				before_focus = GetForegroundWindow ();

				ZeroMemory (in, sizeof (in));
				in[0].type = INPUT_MOUSE;
				in[0].mi.dx = nx;
				in[0].mi.dy = ny;
				in[0].mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
				in[1].type = INPUT_MOUSE;
				in[1].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
				in[2].type = INPUT_MOUSE;
				in[2].mi.dwFlags = MOUSEEVENTF_LEFTUP;

				SendInput (3, in, sizeof (INPUT));
				SetCursorPos (before.x, before.y);

				/* Let the reader act on the click before taking the foreground
				   back. Restoring immediately can arrive while it is still
				   handling activation, and the page then does not turn. */
				Sleep (120);

				if (before_focus != NULL && before_focus != GetForegroundWindow ())
				{
					/* A process may only set the foreground window under
					   conditions Windows decides; attaching to the current
					   foreground thread's input queue is what earns the right.
					   If it is refused anyway the click still stands - only the
					   focus restoration is lost. */
					DWORD this_thread = GetCurrentThreadId ();
					DWORD fore_thread = GetWindowThreadProcessId (GetForegroundWindow (), NULL);

					if (fore_thread != 0 && fore_thread != this_thread)
					{
						AttachThreadInput (this_thread, fore_thread, TRUE);
						SetForegroundWindow (before_focus);
						AttachThreadInput (this_thread, fore_thread, FALSE);
					}
					else
					{
						SetForegroundWindow (before_focus);
					}
				}
			]"
		end

invariant
	error_attached: last_error /= Void

end
