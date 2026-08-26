note
	description: "[
		How fast a reading session is going, and when it will finish.

		Three numbers:
		  * scans per minute  - captures completed per minute
		  * pages per minute  - printed pages per minute, which is NOT the same
		  * ETA               - minutes to the end of the book

		Fed four events by the auto-advance driver: `note_start', `note_capture',
		`note_pause', `note_resume'.
	]"
	design: "[
		WALL CLOCK, NOT TIMER TICKS. The obvious source of elapsed time is the
		50 ms tick the driver already runs on. It is wrong: Windows timer
		granularity is ~15.6 ms, so a 50 ms EV_TIMEOUT actually fires at ~46.9
		or ~62.5 ms and Vision2 does not compensate. Over an hour that is a
		double-digit error - instrumentation that is quietly wrong, which is
		worse than none.

		PAUSE STOPS THE CLOCK. A run paused over lunch would otherwise report a
		collapsed rate and an ETA measured in days.

		ETA NEEDS NO PAGES-PER-SCAN. Both the position and the total come from
		the same indicator in the same units, so

		    ETA = (total - position) / rate of position advance

		holds whether the reader counts pages, locations or anything else. The
		program never has to decide what a "page" is.

		WINDOWED, NOT WHOLE-RUN. The first capture of a session pays a cold
		model load of up to 45 seconds; a whole-run average carries that penalty
		for an hour.

		OUTLIERS ARE DROPPED. A garbled indicator read is real: one live run
		produced a matched -90/+92 pair from a single misread page number. A
		sample implying an impossible step is ignored rather than allowed to
		throw the rate. This is also why the removed `max_page_step' feature was
		wrong - it HALTED on exactly this input.
	]"

class
	OCR_RUN_METRICS

create
	make

feature {NONE} -- Initialization

	make
			-- Prepare to measure a run.
		do
			create start_time.make_now
			create samples.make (Window_size + 1)
		ensure
			nothing_counted: captures = 0
		end

feature -- Access

	captures: INTEGER
			-- Captures completed since `note_start'.

	position: INTEGER
			-- Most recent believable reader position; zero when unknown.

	total: INTEGER
			-- Most recent believable end point; zero when unknown.

feature -- Status report

	has_position: BOOLEAN
			-- Has a believable position been read?

	has_total: BOOLEAN
			-- Is the end of the book known?

	has_page_rate: BOOLEAN
			-- Are there enough position samples to measure a page rate?
		do
			Result := samples.count >= 2 and then window_seconds > 0
				and then window_pages > 0
		end

	has_jumped: BOOLEAN
			-- Did the last capture adopt a position a long way from the previous
			-- one? Set by `rebaseline'; cleared by `clear_jump'.

	jumped_from, jumped_to: INTEGER
			-- Percent complete either side of that move.

	jumped_backwards: BOOLEAN
			-- Was the jump backwards - the reader returning to somewhere already
			-- transcribed - rather than forwards past unread pages?
		do
			Result := has_jumped and then jumped_to < jumped_from
		end

	clear_jump
			-- Acknowledge the jump, so it is reported once and not every capture.
		do
			has_jumped := False
		ensure
			cleared: not has_jumped
		end

	has_eta: BOOLEAN
			-- Can a finish time be projected?
		do
			Result := has_page_rate and has_total and then total > position
		end

feature -- Recording

	note_start
			-- Begin, or begin again.
		do
			create start_time.make_now
			paused_seconds := 0
			pause_started_raw := 0
			is_paused := False
			captures := 0
			last_capture_seconds := 0
			has_pending := False
			has_jumped := False
			jumped_from := 0
			jumped_to := 0
			pending_position := 0
			pending_total := 0
			pending_seconds := 0
			position := 0
			total := 0
			has_position := False
			has_total := False
			has_initial_estimate := False
			initial_eta_minutes := 0
			initial_elapsed_seconds := 0
			create initial_finish_display.make_empty
			samples.wipe_out
		ensure
			reset: captures = 0
			no_first_guess: not has_initial_estimate
		end

	note_capture (a_label: READABLE_STRING_GENERAL)
			-- Record a completed capture whose indicator read `a_label'.
		do
			note_capture_at (a_label, elapsed_seconds)
		end

	note_capture_at (a_label: READABLE_STRING_GENERAL; a_seconds: INTEGER)
			-- Record a capture that landed `a_seconds' into the run.
			--
			-- The elapsed time is a parameter rather than read from the clock
			-- inside, so the arithmetic here can be tested against a known
			-- sequence instead of against whatever the wall clock happens to
			-- say. `note_capture' supplies the real value.
		require
			not_negative: a_seconds >= 0
		local
			l_reader: OCR_PAGE_POSITION
		do
			captures := captures + 1
			last_capture_seconds := a_seconds

			create l_reader
			l_reader.set_from (a_label)
			if l_reader.has_position then
				if continues_series (l_reader) then
					accept (a_seconds, l_reader)
					has_pending := False
				elseif continues_pending (l_reader) then
						-- A second reading that agrees with the first odd one.
						-- Reality has repeated itself coherently, so it wins.
					rebaseline (a_seconds, l_reader)
				else
						-- First odd reading. Remembered, not obeyed and not
						-- discarded: one capture cannot tell a garbled read from
						-- a genuine change of series.
					pending_position := l_reader.position
					pending_total := l_reader.total
					pending_seconds := a_seconds
					has_pending := True
				end
			end
				-- The FIRST projectable finish is frozen the moment it
				-- exists - warts included, because "how good was the
				-- first guess" is exactly the question the strip will
				-- be answering for the rest of the run.
			if not has_initial_estimate and then has_eta then
				has_initial_estimate := True
				initial_eta_minutes := eta_minutes
				initial_elapsed_seconds := a_seconds
				initial_finish_display := finish_clock
			end
		ensure
			counted: captures = old captures + 1
			first_guess_sticks: old has_initial_estimate implies
				(initial_eta_minutes = old initial_eta_minutes
				and initial_elapsed_seconds = old initial_elapsed_seconds)
		end

	note_pause
			-- Stop the clock.
		do
			if not is_paused then
				pause_started_raw := raw_elapsed_seconds
				is_paused := True
			end
		ensure
			paused: is_paused
		end

	note_resume
			-- Start it again, without counting the gap.
		do
			if is_paused then
				paused_seconds := paused_seconds + (raw_elapsed_seconds - pause_started_raw)
				is_paused := False
			end
		ensure
			running: not is_paused
		end

feature -- Measurement

	elapsed_seconds: INTEGER
			-- Seconds of actual work since `note_start', excluding pauses.
		local
			l_raw: INTEGER
		do
			l_raw := raw_elapsed_seconds
			Result := l_raw - paused_seconds
			if is_paused then
				Result := Result - (l_raw - pause_started_raw)
			end
			Result := Result.max (0)
		ensure
			not_negative: Result >= 0
		end

	scans_per_minute: DOUBLE
			-- Captures completed per minute.
			--
			-- Measured over the INTERVALS BETWEEN captures - `captures - 1' gaps
			-- ending at the last capture - not over "time since start divided by
			-- count". Two reasons, and they agree:
			--
			--   * n captures span n-1 intervals. Dividing by the count instead
			--     inflates the rate, badly on a short run.
			--   * "now" drifts forward between captures, so a rate measured to
			--     the clock sags for twenty seconds and jumps on each capture.
			--     Measuring to the last capture holds steady.
			--
			-- It also makes this testable: the whole class can then be driven
			-- from `note_capture_at' with known times and no clock at all.
		do
			if captures >= 2 and then last_capture_seconds > 0 then
				Result := (captures - 1) * 60.0 / last_capture_seconds
			end
		ensure
			not_negative: Result >= 0.0
		end

	pages_per_scan: DOUBLE
			-- Printed pages covered by each capture.
			--
			-- Well above one when the reader shows several pages at a time,
			-- well below when a page is larger than the reader's window. Both
			-- happen; neither is an error.
		do
			if has_page_rate and then samples.count >= 2 then
				Result := window_pages / (samples.count - 1)
			end
		ensure
			not_negative: Result >= 0.0
		end

	pages_per_minute: DOUBLE
			-- Printed pages transcribed per minute.
		do
			if has_page_rate then
				Result := window_pages * 60.0 / window_seconds
			end
		ensure
			not_negative: Result >= 0.0
		end

	eta_minutes: INTEGER
			-- Minutes to the end of the book; zero when unknown.
		do
			if has_eta then
				Result := ((total - position) / pages_per_minute).rounded
			end
		ensure
			not_negative: Result >= 0
		end

	strip_line: STRING_32
			-- A short form for the always-on-top strip; empty when there is
			-- nothing to say yet.
			--
			-- Not `summary_line': that runs to about sixty characters and the
			-- strip is 320 pixels wide. The position is left out because the
			-- strip already prints it directly above this, under the thumbnail -
			-- repeating it would cost the width that the rates need.
			-- Newline-separated: the strip draws one line per entry and grows
			-- taller to suit. Kept to two short lines rather than one long one,
			-- because a single line ran past the right edge and rendered
			-- "ETA 25m" as "ETA 25" - a number that quietly loses its unit.
		do
			create Result.make (48)
			if captures >= 2 then
				Result.append_string_general (one_decimal (scans_per_minute))
				Result.append_string_general (" scan/min")
				if has_page_rate then
					Result.append_string_general ("   ")
					Result.append_string_general (one_decimal (pages_per_minute))
					Result.append_string_general (" pg/min")
				end
				if has_eta then
					Result.append_character ('%N')
					Result.append_string_general ("ETA ")
					Result.append_string_general (eta_minutes.out)
					Result.append_string_general (" min")
					if has_total then
						Result.append_string_general ("   (")
						Result.append_string_general ((total - position).out)
						Result.append_string_general (" pages left)")
					end
						-- A duration needs arithmetic and a glance at a clock
						-- before it answers "wait, or come back later?". A time of
						-- day answers it directly.
					Result.append_character ('%N')
					Result.append_string_general ("finishing about ")
					Result.append (finish_clock)
				else
						-- Say so rather than leaving a gap. There is no position
						-- yet in more cases than are worth explaining - roman front
						-- matter on a reader with no location counter, an indicator
						-- box not set, a label the model could not read, or simply
						-- too few samples to measure a rate. An empty line reads as
						-- broken; this reads as not-yet, makes no claim that could
						-- turn out to be false, and needs no knowledge of which
						-- reader is in front of it.
					Result.append_character ('%N')
					Result.append_string_general ("No ETA - Standby ...")
				end
				Result.append_character ('%N')
				Result.append_string_general ("started ")
				Result.append (started_display)
				if has_initial_estimate then
					Result.append_character ('%N')
					Result.append_string_general ("1st ETA ")
					Result.append (initial_finish_display)
					if has_eta then
						if drift_minutes > 0 then
							Result.append_string_general ("  +")
							Result.append_string_general (drift_minutes.out)
							Result.append_character ('m')
						elseif drift_minutes < 0 then
							Result.append_string_general ("  ")
							Result.append_string_general (drift_minutes.out)
							Result.append_character ('m')
						else
							Result.append_string_general ("  on pace")
						end
					end
				end
			end
		end

	percent_complete: INTEGER
			-- How far through the BOOK, not through the session.
			--
			-- Of the whole book deliberately: a run started at page 10 of 379
			-- opens at 2%, not 0%. That is the honest number - it answers "how
			-- much of this book is done", which is the question actually being
			-- asked while watching it run.
		do
			if has_total and then total > 0 then
				Result := (position * 100) // total
			end
		ensure
			in_range: Result >= 0 and Result <= 100
		end

	finish_clock: STRING_32
			-- Wall-clock time the run should finish; empty when unknown.
			--
			-- No zone suffix. `make_now' is local time so the number is right on
			-- this machine, but the ABBREVIATION is not something Eiffel can get
			-- at - hard-coding "EST" would be wrong for most of the year, when
			-- the same clock is EDT. A bare "9:44 PM" on a desktop application
			-- is unambiguous; a confidently wrong zone is not.
		local
			l_when: DATE_TIME
		do
			create Result.make_empty
			if has_eta then
				create l_when.make_now
				l_when.minute_add (eta_minutes)
				Result.append_string_general (clock_of (l_when))
			end
		end

	started_display: STRING_32
			-- When the run began, as "Aug 26 7:58 AM".
		do
			create Result.make (20)
			Result.append_string_general (month_short (start_time.month))
			Result.append_character (' ')
			Result.append_string_general (start_time.day.out)
			Result.append_character (' ')
			Result.append_string_general (clock_of (start_time))
		ensure
			non_empty: not Result.is_empty
		end

	has_initial_estimate: BOOLEAN
			-- Has the first projectable finish been frozen yet?

	initial_eta_minutes: INTEGER
			-- The first ETA the run could compute, frozen at the
			-- moment `has_eta' first turned True.

	initial_finish_display: STRING_32
			-- The wall-clock finish that first estimate named, frozen.
		attribute
			create Result.make_empty
		end

	drift_minutes: INTEGER
			-- How far the CURRENT projected finish has moved from the
			-- frozen first one: positive = running late, negative =
			-- beating the guess, zero = on pace. Meaningful when
			-- `has_initial_estimate' and `has_eta'. Pure arithmetic
			-- on capture seconds, so the assault drives it with
			-- injected times and no clock.
		local
			l_delta: INTEGER
		do
			if has_initial_estimate and then has_eta then
				l_delta := (last_capture_seconds + eta_minutes * 60)
					- (initial_elapsed_seconds + initial_eta_minutes * 60)
				Result := l_delta.abs // 60
				if l_delta < 0 then
					Result := -Result
				end
			end
		end

	summary_line: STRING_32
			-- One line for the status bar and the log.
		do
			create Result.make (96)
			Result.append_string_general (one_decimal (scans_per_minute))
			Result.append_string_general (" scans/min")
			if has_page_rate then
				Result.append_string_general ("  ")
				Result.append_string_general (one_decimal (pages_per_minute))
				Result.append_string_general (" pages/min")
			end
			if has_position then
				Result.append_string_general ("  at ")
				Result.append_string_general (position.out)
				if has_total then
					Result.append_string_general (" of ")
					Result.append_string_general (total.out)
				end
			end
			if has_eta then
				Result.append_string_general ("  ETA ")
				Result.append_string_general (eta_minutes.out)
				Result.append_string_general (" min")
			end
		ensure
			non_empty: not Result.is_empty
		end

feature {NONE} -- Implementation

	continues_series (a_reader: OCR_PAGE_POSITION): BOOLEAN
			-- Is `a_reader' the next reading of the series being tracked?
			--
			-- Same total, and a step within -1..`Maximum_step'. A live run
			-- produced a matched -90/+92 pair from one garbled read, which
			-- would otherwise have thrown the rate for a whole window.
			--
			-- Minus one, not zero: a reader showing a range can legitimately
			-- report a first page one lower than the previous screenful.
		do
			if not has_position then
				Result := True
			else
				Result := a_reader.total = total and then is_small_step (a_reader.position, position, total)
			end
		end

	continues_pending (a_reader: OCR_PAGE_POSITION): BOOLEAN
			-- Does `a_reader' carry on from the odd reading held in `pending'?
		do
			Result := has_pending and then a_reader.total = pending_total
				and then is_small_step (a_reader.position, pending_position, pending_total)
		end

	is_small_step (a_to, a_from, a_total: INTEGER): BOOLEAN
			-- Is moving from `a_from' to `a_to' a plausible single step in a
			-- series of `a_total'?
			--
			-- Scaled to the series, NOT a fixed number of units. A flat limit of
			-- 20 is right for pages and nonsense for locations: one screenful
			-- advances two or three PAGES but seventy-odd LOCATIONS, so a fixed
			-- page-sized limit rejected every location reading after the first
			-- and pinned the position at its opening value. Caught by the
			-- handover self-test, which is exactly what it was written for.
			--
			-- A twentieth of the book is the ceiling: no reader shows five per
			-- cent of a book in one screenful, and it still catches the garble
			-- this guard exists for - the live -90/+92 pair was 19% of its book.
		do
			Result := (a_to - a_from) >= -1
				and (a_to - a_from) <= (a_total // Step_divisor).max (Minimum_step)
		end

	accept (a_seconds: INTEGER; a_reader: OCR_PAGE_POSITION)
			-- Take `a_reader' as the next reading of the current series.
		do
			samples.extend ([a_seconds, a_reader.position])
			if samples.count > Window_size then
				samples.start
				samples.remove
			end
			position := a_reader.position
			has_position := True
			if a_reader.has_total then
				total := a_reader.total
				has_total := True
			end
		end

	rebaseline (a_seconds: INTEGER; a_reader: OCR_PAGE_POSITION)
			-- Abandon the tracked series and start measuring the pending one.
			--
			-- Needed because a reader can genuinely change what it is counting
			-- part-way through a book: locations giving way to page numbers,
			-- roman front matter giving way to arabic. Both look exactly like a
			-- garbled reading for one capture and nothing like one for two.
			--
			-- The pending sample is carried in alongside the current one, so
			-- the new series has two points immediately and a rate is available
			-- at once rather than a capture later.
		local
			l_was: INTEGER
		do
				-- How far through the book we THOUGHT we were, before adopting.
				-- Percent rather than raw position, because the two readings can
				-- be in different units entirely - comparing "245 of 267" with
				-- "1 of 11296" is meaningless as numbers and obvious as a ratio.
			l_was := percent_complete

			samples.wipe_out
			samples.extend ([pending_seconds, pending_position])
			samples.extend ([a_seconds, a_reader.position])
			position := a_reader.position
			total := a_reader.total
			has_position := True
			has_total := a_reader.has_total
			has_pending := False

				-- A big move in one step is the reader having gone somewhere,
				-- not the run progressing. Both of the costly failures so far
				-- were exactly this: 35% -> 94% skipped 209 pages, and
				-- 92% -> 0% re-scanned a book already transcribed.
				--
				-- Recorded, not acted upon. The caller decides what to do.
			if has_total and then total > 0 then
				jumped_from := l_was
				jumped_to := percent_complete
				has_jumped := (jumped_to - jumped_from).abs >= Jump_percent
			end
		ensure
			adopted: position = a_reader.position
			nothing_pending: not has_pending
		end

	window_seconds: INTEGER
			-- Seconds spanned by the samples held.
		do
			if samples.count >= 2 then
				Result := samples.last.seconds - samples.first.seconds
			end
		end

	window_pages: INTEGER
			-- Pages advanced across the samples held.
		do
			if samples.count >= 2 then
				Result := samples.last.position - samples.first.position
			end
		end

	raw_elapsed_seconds: INTEGER
			-- Wall-clock seconds since `note_start', pauses included.
		local
			l_now: DATE_TIME
		do
			create l_now.make_now
				-- `definite_duration (other)' is the duration FROM `other' TO
				-- Current, so this is positive.
			Result := l_now.definite_duration (start_time).seconds_count.to_integer_32
			Result := Result.max (0)
		end

	clock_of (a_when: DATE_TIME): STRING_8
			-- `a_when' as "h:mm AM/PM".
		local
			h, m: INTEGER
		do
			h := a_when.hour
			m := a_when.minute
			create Result.make (10)
			if h = 0 then
				Result.append ("12")
			elseif h > 12 then
				Result.append ((h - 12).out)
			else
				Result.append (h.out)
			end
			Result.append_character (':')
			if m < 10 then
				Result.append_character ('0')
			end
			Result.append (m.out)
			if h >= 12 then
				Result.append (" PM")
			else
				Result.append (" AM")
			end
		ensure
			has_colon: Result.has (':')
		end

	one_decimal (a_value: DOUBLE): STRING_8
			-- `a_value' to one decimal place.
			--
			-- Hand-rolled rather than via FORMAT_DOUBLE, which pads to a fixed
			-- width and would put spaces in the middle of a status line.
		local
			l_tenths: INTEGER
		do
			l_tenths := (a_value * 10.0 + 0.5).truncated_to_integer.max (0)
			Result := (l_tenths // 10).out
			Result.append_character ('.')
			Result.append ((l_tenths \\ 10).out)
		ensure
			has_point: Result.has ('.')
		end

	samples: ARRAYED_LIST [TUPLE [seconds: INTEGER; position: INTEGER]]
			-- Recent (elapsed, position) readings, oldest first.

	pending_position, pending_total, pending_seconds: INTEGER
	has_pending: BOOLEAN
			-- An odd reading seen once, held back until a second capture says
			-- whether it was a garbled read or a genuine change of series.

	last_capture_seconds: INTEGER
			-- Elapsed time of the most recent capture. The rate is measured to
			-- here rather than to "now", so it does not sag between captures.

	start_time: DATE_TIME
	paused_seconds: INTEGER
	pause_started_raw: INTEGER
	is_paused: BOOLEAN

	initial_elapsed_seconds: INTEGER
			-- Elapsed seconds at the moment the first ETA was frozen.

	month_short (a_month: INTEGER): STRING_8
			-- Three-letter month name.
		require
			in_year: a_month >= 1 and a_month <= 12
		do
			inspect a_month
			when 1 then
				Result := "Jan"
			when 2 then
				Result := "Feb"
			when 3 then
				Result := "Mar"
			when 4 then
				Result := "Apr"
			when 5 then
				Result := "May"
			when 6 then
				Result := "Jun"
			when 7 then
				Result := "Jul"
			when 8 then
				Result := "Aug"
			when 9 then
				Result := "Sep"
			when 10 then
				Result := "Oct"
			when 11 then
				Result := "Nov"
			else
				Result := "Dec"
			end
		ensure
			three_letters: Result.count = 3
		end

feature -- Constants

	Window_size: INTEGER = 10
			-- Position samples kept. Ten captures is a few minutes of reading -
			-- long enough to average out a slow page, short enough that the
			-- cold-start penalty leaves the window quickly.

	Step_divisor: INTEGER = 20
			-- The largest believable jump between consecutive captures is a
			-- twentieth of the series. Proportional rather than absolute, so it
			-- means the same thing whether the reader counts pages or locations.

	Jump_percent: INTEGER = 8
			-- Percent of a book that must be crossed in ONE capture before it
			-- counts as the reader having moved rather than the run advancing.
			--
			-- Eight, from the evidence: the two real jumps were 59 and 92 points,
			-- while an ordinary capture on the fastest reader seen covers about
			-- one percent. There is a wide gap between the two, so the threshold
			-- is not delicate.

	Minimum_step: INTEGER = 20
			-- Floor for a short book, where a twentieth would be a page or two
			-- and a reader showing four at a time would trip the guard.

invariant
	counted: captures >= 0
	samples_attached: samples /= Void
	bounded_window: samples.count <= Window_size

end
