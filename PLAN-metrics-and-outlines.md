# PLAN — Run Metrics and Region Outlines

**Project:** simple_ocr_capture
**Baseline:** v1.3.0, installed and verified at `C:\Program Files\Simple OCR Capture\`
**Written:** 2026-08-17
**Status:** ANALYSED, NOT BUILT. No code written, nothing compiled.

> Written while a book scan was ~34% complete and must not be disturbed.
> Every finding below comes from reading the sources, not from running the
> compiler. Nothing here has been through `ec.sh`. Treat all line numbers as
> accurate to this baseline and re-check them if the sources have moved.

Two independent feature sets. Part A can ship without Part B and vice versa.

---

# PART A — Run metrics: scan rate, page rate, ETA

## A.1 What was asked for

Three numbers surfaced on the interface, given that the status window now
carries a "Page NNN of NNN" or "Location NNNN of NNNN" indicator:

1. **Page-scans per minute** as a rate.
2. **Pages per minute**, i.e. pages-per-scan converted to a per-minute rate.
3. **ETA** from the current time to the end of the book.

## A.2 Findings against the current code

### Metric 1 is free

`OCR_AUTO_RUN.pages_done` (`src/ocr_auto_run.e:71`) increments exactly once per
completed capture, at `src/ocr_auto_run.e:322`. One clean event, one place.
Bracket it with a start timestamp taken in `start` (`:113`) and metric 1 needs
no new information of any kind. It cannot be wrong.

### `pages_done` is misnamed and the misnaming becomes harmful here

It counts **captures**, not pages. That has been harmless so far. Displaying a
"pages per minute" figure next to a counter called `pages_done` that means
something else is a trap for the next reader.

Rename to `captures_done`. Referenced in only three places: `progress_line`
and `stall_reason` in the same class, and `src/ocr_gui.e:256`.

### Metric 2 is two different problems wearing one name

"Pages per scan" pulls in opposite directions depending on reader window size:

| Situation | Example | Pages/scan |
|---|---|---|
| Reader window small — one printed page spans several screenfuls | 3 screens per page | ~0.33 |
| Reader window large — one screenful shows several printed pages | `90-92 / 139` | ~3 |

The first case needs **no parsing**: `label_changed` (`src/ocr_auto_run.e:409`)
already detects an indicator transition. Count transitions per minute and every
single-page-at-a-time reader is covered correctly.

The second case requires reading the range out of `90-92`. That is parsing.

### Metric 3 needs parsing, but is *more* robust than metric 2 — not less

The key insight: **ETA does not need the pages-per-scan ratio at all.**

```
ETA = (total − position) ÷ (rate of position advance)
```

Both numbers come from the same indicator in the same units. If the reader
counts in Kindle locations, both sides are locations and the quotient is still
minutes. The program never has to decide what a "page" is.

### The hazard: label parsing has failed twice before

`OCR_AUTO_RUN`'s own design note (`src/ocr_auto_run.e:20-26`) records both
failures:

1. A format validator that required `<page> / <total>` — the next book showed
   "Page iii of 214" and every page was rejected until the run gave up.
2. A page-step check that halted on skips — wrong the moment a reader
   legitimately displays two to four pages at once.

**What makes this attempt different is not a better parser. It is that a failed
parse must cost nothing.** Both previous failures parsed in order to *decide*
something. These metrics only *display*. A failed parse shows `ETA —` and the
run is untouched.

Enforce that structurally, not by intention:

- The parser class holds no run state and is reachable from no decision.
- `OCR_RUN_METRICS` must not be referenced by `has_advanced` (`:396`),
  `text_changed` (`:420`), or `retry_advance` (`:329`).

If a future session cannot reach the metrics from a decision, it cannot repeat
the mistake.

### The parse rule that covers the observed formats

Extract every integer run from the label. Take **first = position, last =
total**. Require at least two integers and `total > position`.

| Label | Integers | Result |
|---|---|---|
| `Page 224 of 416` | 224, 416 | pos 224, total 416 |
| `90-92 / 139` | 90, 92, 139 | pos 90, total 139, span 3 |
| `Location 3120 of 8890` | 3120, 8890 | pos 3120, total 8890 |
| `Page iii of 214` | 214 | no position → no ETA, run unaffected |

Roman-numeral front matter yields nothing, which is correct: front matter is
short and the ETA resumes at page 1.

Sanity guards: discard when `position > total`; if `total` changes mid-run take
the most recent (a reader can cross into a new section).

### Do NOT use timer ticks as a clock

The obvious move is counting the 50 ms ticks, since `poll` already runs on one.
It is wrong. Windows timer granularity is ~15.6 ms, so a 50 ms `EV_TIMEOUT`
actually fires at ~46.9 or ~62.5 ms and Vision2 does not compensate. Over an
hour that is a double-digit error — instrumentation that is quietly wrong,
which is worse than none.

Use wall clock. Confirmed present in the 25.02 time library:

- `DATE_TIME.definite_duration (other): DATE_TIME_DURATION` — `date_time.e:360`
- `DATE_TIME_DURATION.seconds_count: INTEGER_64` — `date_time_duration.e:124`

Two consequences:

- **Pause must stop the clock** (`:135` / `:145`) or a lunch break destroys both
  the rate and the ETA.
- A DST shift mid-run jumps an hour. Real for an overnight run, rare. Accept it
  rather than building a monotonic clock.

Compute only on capture completion — roughly once per 40 s — and cache the
rendered strings. Creating a `DATE_TIME` twenty times a second in `poll` is
pure waste.

### Rate window

Take the position rate over a sliding window of the last ~10 captures, not the
whole run. The first capture pays a cold model load of up to 45 s and a
whole-run average carries that penalty for an hour. Fall back to the whole-run
average until ten samples exist.

## A.3 Design

Two new classes, both pure — no I/O, no Vision2, both unit-testable with no
screen:

**`OCR_PAGE_POSITION`** — the extractor. Explicitly *not* the deleted
`OCR_PAGE_LABEL`: that was a validator that rejected what it could not parse;
this one yields nothing and says so via `has_position` / `has_total`.

```
set_from (a_label: READABLE_STRING_32)
has_position, has_total: BOOLEAN
position, total, span: INTEGER
```

**`OCR_RUN_METRICS`** — fed four events, answers six queries.

```
note_start / note_capture (a_label) / note_pause / note_resume
scans_per_minute, pages_per_scan, pages_per_minute: DOUBLE
has_eta: BOOLEAN
eta_minutes: INTEGER
projected_finish: DATE_TIME
```

### Hook points — four one-liners

| Where | File:line | Call |
|---|---|---|
| Run begins | `ocr_auto_run.e:113` | `note_start` |
| Capture completes | `ocr_auto_run.e:322` | `note_capture (current_label)` |
| Pause | `ocr_auto_run.e:135` | `note_pause` |
| Resume | `ocr_auto_run.e:145` | `note_resume` |

### Display — three places, increasing cost

1. **The log** — one line per page beside the existing `[auto]` entries. Nearly
   free, and it makes a finished run analysable after the fact, which is what
   the log exists for. **Do this first.**
2. **Main window status line** — `report` (`ocr_main_window.e:68`) already takes
   any string. Zero layout risk.
3. **The strip** — a second caption line under the page caption. Contained but
   not free: `current_height` (`ocr_status_strip.e:232`), `Caption_height`
   (`:484`) and the draw at `:301` all need a second line, and the strip grows
   ~17 px. Treat as a separate decision.

### Explicitly out of scope

**Do not write metrics into the transcript separator**
(`ocr_cycle.e:348`). That format is what `ingest.py` parses, and there is
already one unresolved ingest break outstanding (see §C.1). Do not create a
second.

## A.3b Empirical validation against a live run (2026-08-17)

The whole of Part A was computed by hand against the Hardin *Jesus Driven Life*
run while it was in flight — 126 captures, pages 5→352 of 485, 45.2 minutes.
The transcript separator already carries capture number, indicator and
timestamp, so every input the design needs was recoverable from the output file
alone. That is a good sign: the metrics need no new plumbing, only arithmetic.

| Metric | Whole run | Last 30 | Last 10 |
|---|---|---|---|
| Seconds per scan | 21.7 | 22.5 | 22.0 |
| Scans per minute | 2.76 | 2.66 | 2.73 |
| Pages per scan | 2.78 | 3.07 | 3.10 |
| Pages per minute | 7.67 | 8.17 | 8.45 |
| ETA to page 485 | 17.3 min | 16.3 min | 15.7 min |

### Per-scan page-delta distribution — the important result

```
  delta -90 :    1  #
  delta  -4 :    1  #
  delta   0 :    2  ##
  delta   1 :    4  ####
  delta   2 :   23  #######################
  delta   3 :   84  ############################################################
  delta   4 :    4  ####
  delta   6 :    4  ####
  delta   7 :    1  #
  delta  92 :    1  #
```

Three findings, each of which confirms a decision already made:

1. **The mode is 3 pages per scan, not 1.** Any design that assumed one scan =
   one page would be wrong on this book by a factor of three.

2. **`delta 0` appears twice** — the indicator held still while the text moved
   on. That is the multi-screenful case, and it is exactly why advance detection
   is text-only. An indicator-based rule would have halted this run twice.

3. **`delta -90` and `delta +92` are a matched pair** — one garbled indicator
   read, immediately self-correcting. **This is precisely the input that killed
   the removed `max_page_step` feature**: a single bad OCR read of the page
   number, not a real skip, which would have stopped a 45-minute run dead. The
   strongest possible argument for the rule in §A.2: *the parse may inform the
   display and must never gate the run.*

### Refinement discovered from this data

Outlier readings like the ±90 pair are rare but real. The windowed rate
`(position_now − position_at_window_start) / elapsed` is robust to a bad reading
in the *middle* of the window but **not** to one landing on either endpoint —
that would produce a wild ETA for one capture.

Add a guard: reject a position sample that implies a per-scan delta outside a
sane band (say −1 to +20) and carry the previous sample forward. Cheap, and it
keeps a single bad OCR read from producing an absurd ETA.

## A.3c The run log — and why it also fixes the ingest break

**Larry's question: should this instrumentation live in its own `*.log` file?**

Yes, and the exercise in §A.3b is the argument. Every number in that table was
recovered by regex-parsing prose out of the transcript. It worked, but only by
luck of three things holding at once: `add_separators` was on, the separator
format had not changed, and `DATE_TIME.out` happened to be parseable. None of
those are guarantees, and the first is a user-toggleable setting.

There is also a conflict to resolve. §A.2 says *do not* put metrics in the
transcript separator, because `ingest.py` parses that format. A separate file
removes the tension entirely: metrics go somewhere ingest never looks.

### Two sinks, different jobs

1. **Human line → the existing `ocr_capture.log`**, beside the `[auto]` entries.
   For reading after a run stopped unexpectedly. Per-install, prose.

2. **Machine row → a per-book run log in the OUTPUT folder**, beside the images
   and transcript: `<book>.runlog.tsv`. Per-book evidence that travels with the
   book. One row per capture, appended as it happens — never buffered, or a
   crashed run loses exactly the record that would explain it.

Suggested columns:

```
iso_timestamp  capture_index  image_filename  raw_label  position  total
chars  seconds_since_previous  advance_reason  retry_count
```

### This kills the outstanding ingest blocker

§C.1 records that v1.3.0's indicator-based PNG naming broke `ingest.py`, which
derives filenames as `ocr_%04d.png` from the capture number. The two options on
the table were a JSONL sidecar or making ingest glob and match.

**The run log is the sidecar.** A row carrying both `capture_index` and
`image_filename` lets ingest join on it directly and never derive a filename
again — which also makes ingest immune to any *future* naming change.

So this is not a third option competing with §5 of the `_db` handoff. It is the
same artifact, arrived at from the other direction, and building it once
discharges both items. TSV or JSONL is a coin-flip; **JSONL matches what the
`_db` handoff already specified**, so prefer it and give it the `.jsonl`
extension rather than inventing a second format.

**Consequence for sequencing:** this promotes the run log from "nice
instrumentation" to the highest-value item in the whole plan. It should be
built first, before any of the display work.

## A.3d BUILT AND VERIFIED 2026-08-17

`src/ocr_page_position.e` and `src/ocr_run_metrics.e`, hooked into
`OCR_AUTO_RUN` at all four events. Verified by a new `--metrics` CLI self-test,
which reproduces the numbers measured by hand from the Hardin run:

```
scans/min : 2.7272727272727271   (measured Hardin: 2.73)
pages/scan: 3                    (measured Hardin: 3.07)
pages/min : 8.1818181818181817   (measured Hardin: 8.17)
ETA       : 43 min = (485-130)/8.18
position after garbled -90/+92 read: 266, NOT 352
elapsed after immediate pause/resume: 0
```

### One design flaw the self-test caught

`scans_per_minute` originally divided by the wall clock, so the testing seam
(`note_capture_at`, which injects elapsed time) did not cover it and the test
reported `0`. Two things were wrong, and the fix addresses both:

- **n captures span n-1 intervals.** Dividing by the count inflates the rate,
  badly on a short run.
- **"Now" drifts between captures**, so a clock-measured rate sags for twenty
  seconds and jumps on each capture.

Now measured over `captures - 1` intervals ending at the last capture. Steadier
live, and the class is fully drivable from known times with no clock at all.

**Two of the three "failures" in the first run were wrong expectations, not
wrong code** — the ETA of 43 and the post-garble 5.45 pages/min were both
arithmetically right for the data fed. Corrected in the test rather than
"fixed" in the class.

## A.3e QUEUED — clock time of completion on the strip

**Requested 2026-08-17, to be built after the Alberino run finishes.**

A third strip line giving the actual wall-clock finish time, not just minutes
remaining:

```
 Page 175 of 379
 2.9 scan/min   8.5 pg/min
 ETA 24 min   (204 pages left)
 finishing about 9:44 PM
```

"About twenty-four minutes" requires arithmetic and a glance at a clock to be
useful when you are deciding whether to wait or come back later; a time of day
does not.

**Also requested: percent complete.** Placed ON the page line rather than given
a row of its own —

```
 Page 205 of 379   54%
 2.9 scan/min   8.5 pg/min
 ETA 20 min   (174 pages left)
 finishing about 9:44 PM
```

A percentage next to the two numbers it is computed from reads as one fact
instead of two, and it holds the strip at four lines rather than five. The
strip sits over the reader for hours, so every line it does not need is worth
having back.

Note the percentage is of the WHOLE book, so a run started at page 10 opens at
2%, not 0%. That is the honest number — it measures the book, not the session —
but it is worth not mistaking for a bug.

### Implementation notes

- Percent comes from the same `position` / `total` the ETA already uses, so it
  needs no new data and inherits the same outlier guard.
- `OCR_RUN_METRICS` gains `finish_clock: STRING_32` — `DATE_TIME.make_now` plus
  `eta_minutes` via `minute_add`, rendered as 12-hour `h:mm AM/PM`.
- Append as a fourth line in `strip_line`, guarded by `has_eta` so it is absent
  until there is something to project. The strip already grows one
  `Caption_height` per line and measures each for width, so there is no layout
  work.
- **Do NOT hard-code a zone label such as "EST".** `make_now` is local time, so
  the number is already correct on the user's own machine, but the abbreviation
  is not: it is EDT for most of the year and Eiffel has no ready access to the
  Windows zone abbreviation. A bare "9:44 PM" is unambiguous on a desktop app;
  a wrong zone suffix is worse than none.
- Recompute per capture like the rest, so it tracks a run that speeds up or
  slows down rather than freezing at whatever the first estimate was.

## A.3f QUEUED — indicators that change units mid-book

**Found 2026-08-18 from the VanderKam *1 Enoch* scan.** The user hand-captured
the front matter rather than risk it, which turned out to avoid a real defect
neither of us had anticipated.

### The scenario

A reader can show a *location* counter through the front matter and only start
showing page numbers once the body begins — and then show BOTH:

```
front matter :  "Location 45 of 8890"
body         :  "Page 12 of 170   Location 890 of 8890"
```

### Two separate defects, and the second is worse

**1. The step guard freezes.** `is_believable` rejects a position implying a
jump outside -1..+20. At the handover, position falls from ~500 (locations) to
1 (pages) — a delta near -499 — so the reading is refused. Since `position` is
only updated on an accepted sample, the baseline stays anchored to the stale
location value and **every subsequent page reading is refused for the rest of
the run.** The scan keeps working perfectly; the ETA, percent and pages/min
freeze, with nothing saying why.

**2. The parser mis-pairs the combined format** — and this one bites even
without a handover. `OCR_PAGE_POSITION` takes the FIRST and LAST integer, so
four numbers pair a page position with a location total:

```
"Page 12 of 170  Location 890 of 8890"  ->  position 12, total 8890
                                            percent 0%, ETA meaningless
```

Any book whose reader shows both counters is affected from the first page.

### The fix: pair extraction, then a confirmed series

**Parse PAIRS, not first-and-last.** Find each `<number> (of|/) <number>` where
the total exceeds the position. Units-agnostic — it never looks for the word
"Page", which is the mistake the deleted `OCR_PAGE_LABEL` made.

| Label | Pairs found | Result |
|---|---|---|
| `Page 224 of 416` | (224,416) | unchanged |
| `Location 3120 of 8890` | (3120,8890) | unchanged |
| `Page iii of 214` | none — no number before "of" | unchanged, still nothing |
| `10` | none | unchanged, still nothing |
| `Page 12 of 170  Location 890 of 8890` | (12,170), (890,8890) | **fixed** — takes (12,170) |
| `90-92 / 139` | (92,139) | position 92 rather than 90 |

The last row is the one behaviour change: the number taken is the one adjacent
to the separator, so a range reports its END page. Immaterial to percent and
ETA, and arguably more accurate.

**Track a series, keyed by its total, and require confirmation to change it.**

- **Prefer the pair with the LARGEST total.** That is the location counter when
  one is present, and the page counter when it is not — decided by arithmetic,
  never by looking for the word "Location", which would be the deleted
  `OCR_PAGE_LABEL` mistake all over again.
- While a reading continues the series — same total, step within -1..+20 —
  accept it, exactly as now.
- **Any reading that does NOT continue the series becomes PENDING rather than
  being discarded.** Adopt it only when the next capture is itself a plausible
  continuation of the pending reading (same total, step within -1..+20).
  Otherwise drop the pending and carry on unchanged.
- On adoption: re-baseline to the new series, reset the sample window, and skip
  the step guard across the boundary.

### Why the largest total is the right anchor

A location counter is the most stable thing on the indicator. It is monotonic
across the WHOLE book - cover, roman front matter, body, appendix, index - its
total never changes, and its position never resets. Anchor to it and the
handover described above simply never happens: there is nothing to switch to,
because the series was never interrupted.

It also makes roman numerals a non-event. `Page iii of 214` contributes no
numeric position, but nobody cares, because progress was never being measured
from the page counter in the first place.

"Largest total" is how to find it without naming it. Locations are always far
more numerous than pages - 8,890 against 170 - so the arithmetic identifies the
finer counter on its own, and a finer counter also yields a smoother rate.

**But it cannot be the only rule.** Alberino, Hardin and Sherman showed no
location at all, only `Page N of N`. Anchoring exclusively to locations would
break every book scanned so far. Preferring the largest total degrades
correctly: with one pair present it behaves exactly as today.

**Known cost:** when locations are the anchor, the percentage measures the whole
file while the page number beside it counts body pages, so the two disagree
slightly - most visibly in front matter, which locations count and page numbers
do not. The percentage is the more honest measure of work remaining; the
mismatch is worth a line in the README rather than a fix.

### Why "does it persist consistently" is still needed

Anchoring to the largest total removes the COMMON case of a series change. It
does not remove all of them - a garbled location total, a reader that drops the
location partway, or a page-only book that renumbers will still shift the
series - so the pending rule stays as the safety net beneath it.

My first draft keyed the switch on the TOTAL changing. Roman-numeral front
matter breaks that, and the case is real on this reader:

```
"Page iii of 214"   ->  "Page 1 of 214"      the total NEVER changes
```

If the OCR reads `iii` correctly there is no numeric position, no pair, and
nothing to go wrong. But `iii` misread as `111` gives a perfectly plausible
(111, 214), and the arrival of page 1 is then a -110 step against an UNCHANGED
total — rejected by the step guard, and never rescued by a total-change rule.
Stuck for the rest of the book, exactly the failure this section exists to
prevent.

The pending rule handles all three cases with one mechanism, because it asks
the only question that actually separates them — *does the disagreement
survive another capture, and does it behave like a real series?*

| Case | First odd reading | Next capture | Outcome |
|---|---|---|---|
| One-off garble | `Page 352 of 485` | back to `Page 266` | pending dropped, no damage |
| Units handover | `Page 1 of 170` | `Page 3 of 170` | consistent -> adopt, re-baseline |
| Roman -> arabic | `Page 1 of 214` | `Page 3 of 214` | consistent -> adopt, re-baseline |
| Garble twice, inconsistent | `Page 352` | `Page 91` | not a series, dropped |

In short: reality is allowed to overrule the guard, but only by repeating
itself coherently. A single strange reading never moves anything; two readings
that agree with each other always do.

This also subsumes the total-change case, so there is no separate rule for it —
a changed total simply fails the "continues the series" test like anything
else.

Cost of confirmation: one capture (~20 s) of stale ETA at the handover, and
rates unavailable for about two captures after it while the new window fills.
Both are honest — the rate genuinely is unknown in the new units.

### Full auto-scan from the cover, end to end

| Phase | Indicator | Behaviour |
|---|---|---|
| Cover / front matter | `Location 45 of 8890` | tracks locations; ETA in location units, correct |
| First body page | `Page 1 of 170  Location 340 of 8890` | 170 is a candidate; hold previous figures |
| Next capture | `Page 3 of 170  Location 355 of 8890` | 170 confirmed; adopt, reset window |
| Rest of book | `Page N of 170  Location …` | tracks pages; percent matches visible page numbers |
| A garbled read | `Page 352 of 170` (nonsense) | total unchanged, step guard rejects it |

No phase chokes, and the only cost is a brief gap at the one genuine boundary.

### Also worth documenting

Manual hotkey captures never read the page indicator — that read is part of the
auto-advance cycle. So hand-captured pages carry no `[page …]` annotation and
fall back to counter-based image names (`ocr_4089.png`). Correct behaviour, but
undocumented, and it is what produced the five unlabelled captures at the start
of *1 Enoch*.

## A.4 Work items

- [x] **Per-capture JSONL run log — BUILT AND VERIFIED 2026-08-17.**
      `src/ocr_run_log.e`, hooked into `OCR_CYCLE` (capture rows, success and
      failure) and `OCR_AUTO_RUN` (run_start / advance / stop). Verified via a
      new `--runlog` CLI self-test: 5 rows, all valid JSON, quote / backslash /
      tab / newline / U+00E9 all round-trip, empty image path handled,
      timestamps sort as text. Both targets finalize clean.
      **Bug found and fixed by that self-test:** `STRING_32.last_index_of` has
      precondition `start_index >= 1`, so an empty path aborted the program —
      and an empty image path is normal whenever `save_image` is off. Recorded
      as an oracle gotcha.
- [ ] `OCR_PAGE_POSITION` + tests over all four observed label formats
- [ ] Outlier guard on position samples (see §A.3b) — reject deltas outside
      −1..+20 and carry the previous sample forward
- [ ] `OCR_RUN_METRICS` + tests including pause/resume clock behaviour
- [ ] Rename `pages_done` → `captures_done` (3 call sites)
- [ ] Four hook calls in `OCR_AUTO_RUN`
- [ ] Log line per capture
- [ ] Main-window status line
- [ ] *(decision)* strip second caption line

---

> **PART B BUILT AND USER-VERIFIED 2026-08-17.** `src/ocr_region_outline.e`
> (four topmost edge strips, dashed, marching ants) and `src/ocr_outline_set.e`
> (three regions, own colour AND own dash pattern). Four checkboxes in
> OCR_MAIN_WINDOW.
>
> **Geometry spike passed** via a new `--outline x y w h [ms]` CLI mode: a
> rectangle requested at screen (500,400) landed exactly there, interior and
> exterior both zero marked pixels. Popup `set_position`/`set_size` are faithful
> in physical pixels at 150%, confirming §B.2.
>
> **Design changes made during the build, all from user feedback:**
>
> - **Checkboxes, not click-and-hold.** A hold gesture buys only "glance
>   without leaving it on" and costs a real failure mode — a swallowed release
>   leaves twelve topmost windows stuck with no obvious way to clear them.
> - **The frame is drawn OUTSIDE the rectangle.** Drawn on the border it covered
>   3px of every edge of the area being photographed: into the PNG, to the OCR
>   model, and hiding the content being checked.
> - **Post-drag reveal.** Finishing a drag ticks that region's box and draws it,
>   so the outline is confirmation of the drag just made. Not left to the
>   checkbox's own action: `enable_select` on an already-ticked box fires
>   nothing, so re-dragging would have left the OLD rectangle drawn.
> - **Shutter interlock in OCR_CYCLE, not in the button handlers.** Only
>   outlines that actually intersect the capture rectangle come down, only for
>   the milliseconds of the screenshot, and the checkboxes stay ticked. This
>   matters in the real config: the user's advance button sits against the right
>   edge of the page, so its outline crosses the capture region even though the
>   capture region's own outline does not. Putting the interlock in the cycle
>   covers every capture path rather than the three someone remembered.
>
> Accepted limitation: Vision2 has no alpha, so the gaps between dashes carry a
> thin dark backdrop. Invisible on dark content, a faint hairline on white.
> User has accepted this.

# PART B — Region outlines on the main GUI

## B.1 What was asked for

On the **primary GUI**, not the always-on-top strip:

1. **Click-and-hold** buttons — outline appears while held, vanishes on release
   — one each for: the **scan area**, the **advance button**, and the **page
   NNN of NNN / location NNNN of NNNN** region.
2. **Click-on / click-off** toggle buttons doing the same three, latching.
3. While a toggle is lit, **drag a new box**; on release the old box is replaced
   and the new one stays outlined until the toggle is clicked off.
4. **Two more buttons for all three boxes at once** — one hold, one toggle.

Eight buttons total.

5. **Outlines drawn as dashes and dots** (`--.--.--.`) rather than solid.

## B.2 Findings against the current code

### The mechanism already exists in the codebase, twice

`OCR_STATUS_STRIP` is a borderless, topmost, non-focusing `EV_POPUP_WINDOW`
that stays visible over a full-screen reader. An outline is that same thing,
four times per box, two pixels thick.

`disconnect_from_window_manager` is what stops it taking focus and **must be
called before `show`** — see the note at `ocr_status_strip.e:10-13`.

**Recommended: thin live strips.** Four `EV_POPUP_WINDOW`s per rectangle
(top/bottom/left/right), created lazily, shown and hidden as a set. No inline C,
no layered windows, no transparency — and the reader stays *live* underneath.

### Why the region selector cannot be reused for this

`OCR_REGION_SELECTOR` **freezes the desktop**: it screenshots once and displays
the photograph full-screen. `ocr_region_selector.e:6-10` documents why — a live
overlay lets the page scroll or a tooltip pop up mid-drag, so what you select is
not what gets captured.

Right for dragging, wrong for alignment checking. You would be inspecting a
photograph, with the settings window *in* the photograph covering the reader.

### DPI scaling — checked, and it is fine

This was the first real worry. `ocr_main_window.e:929-937` documents that
Vision2 renders `set_size` at 2/3 on the 150% display. If popup geometry scaled
the same way, every outline would land in the wrong place — worse than no
feature, because it would be confidently wrong.

Two pieces of evidence from code in daily use say it does not:

- The strip's drag math (`ocr_status_strip.e:365`, `:397`) derives an offset
  from `window.x_position` and feeds it back to `set_position`. If that were
  scaled the strip would drift away from the cursor during a drag. It does not.
- The transport glyphs are laid out from `current_width - Transport_margin - …`
  (`ocr_status_strip.e:170`), i.e. relative to the requested 320 px. At 2/3 the
  window would be 213 px and the glyphs would fall outside it, invisible. They
  are pressed daily.

**Conclusion:** the 2/3 problem is specific to `EV_TITLED_WINDOW`; popup
geometry is faithful in screen pixels.

**Still verify first.** Before building eight buttons, put a throwaway outline
on one known rectangle and confirm it lands. Half an hour that de-risks the
whole feature.

### Dashes and dots — yes, and they earn their keep

Draw them as short segments in a loop rather than reaching for a line style.
That is already the idiom here: the play triangle at `ocr_status_strip.e:184-192`
is a run of `draw_segment` calls, chosen because "a run of segments needs no
coordinate array and cannot be got subtly wrong."

Two benefits beyond appearance:

- **A dashed box reads as an overlay, not as reader chrome.** A solid box over a
  document looks like it might belong to the document.
- **Pattern distinguishes the three boxes better than colour.** For the
  all-three view give each rectangle its own *pattern as well as* its own
  colour — long dash for capture, dot for advance, dash-dot for the page
  indicator. Colour alone fails against a colourful page.

**Marching ants are free.** Offset the dash phase by one on each tick of the
50 ms ticker already running (`ocr_gui.e:440`). An animated outline is
unmistakable against static page content. Make it fixed behaviour, not a
setting.

### Where the spec breaks: latched mode plus drag

**Cannot work as literally described.** The drag needs the frozen-desktop
selector, which is full-screen — so the moment it opens, the "click again to
turn off" button is underneath it and unreachable. The only exit would be Esc,
which currently means *cancel* (`ocr_region_selector.e:155-161`).

**Resolution that keeps everything asked for:**

- **Both button columns drive the same live outline.** Momentary hides on
  release; toggle hides on second click. "Click again to turn off" works
  literally, because nothing ever covers the button.
- **Re-dragging stays on the existing three "Set … by Dragging" buttons**
  (`ocr_main_window.e:499`, `:526`, `:554`), which gain the current rectangles
  drawn as reference outlines on the frozen desktop — roughly fifteen lines in
  `on_expose` (`ocr_region_selector.e:86`) plus a setter.
- If a toggle was lit before the drag, it stays lit after and immediately shows
  the new box.

That delivers the requested behaviour — old box gone, new box showing, stays
until turned off — and fixes something wrong all along: today you drag blind and
then run Test Capture to find out whether you got it. With reference outlines
you see the old box while placing the new one.

### Genuine ambiguity to resolve

With all three showing, a drag has no way to say **which** rectangle it
redefines. Recommendation: make the all-three controls **display-only** and
leave redefinition to the per-box buttons.

### The covering problem — no good software fix

Outlines are topmost, so they draw over the settings window too. You would be
looking at a box floating over your own GUI rather than over the reader. The
main window is 1350×1400 (`ocr_main_window.e:941-942`) and will cover most
readers.

Hiding the main window on button-press **would break momentary mode outright**:
a hidden button cannot deliver its release event, so the outline would stick on.

Practical answer: position the main window clear of the reader while aligning.
This works precisely because nothing is frozen — both windows can be moved with
the outlines live.

### Stuck-outline safety net

If a release event is ever swallowed, twelve topmost windows stay on screen with
no obvious way to clear them. Cheap insurance:

- also hide on `pointer_leave_actions`
- also hide on the main window losing focus
- the all-three toggle clears everything unconditionally

## B.3 Design

**`OCR_REGION_OUTLINE`** — one rectangle's worth of outline. Pure geometry and
painting, owns its four popup windows.

```
make (a_colour: EV_COLOR; a_pattern: INTEGER)
set_rectangle (a_x, a_y, a_width, a_height: INTEGER)
show / hide
advance_phase        -- marching ants, called from the ticker
```

**Button group** — a new `EV_FRAME` in `root_box`, laid out 4×2:

| Row | Peek (hold) | Show (toggle) |
|---|---|---|
| Capture region | `EV_BUTTON` | `EV_TOGGLE_BUTTON` |
| Advance button | `EV_BUTTON` | `EV_TOGGLE_BUTTON` |
| Page indicator | `EV_BUTTON` | `EV_TOGGLE_BUTTON` |
| All three | `EV_BUTTON` | `EV_TOGGLE_BUTTON` |

`EV_TOGGLE_BUTTON` confirmed present in Vision2 25.02
(`library/vision2/interface/widgets/primitives/ev_toggle_button.e`). Use it for
the Show column so the lit state is visible on the button itself.

Hold behaviour uses `pointer_button_press_actions` / `pointer_button_release_actions`
from `EV_PRIMITIVE`.

## B.4 Work items

- [ ] **Spike first:** one throwaway outline on one known rectangle, confirm it
      lands correctly at 150% scaling. Gate everything else on this.
- [ ] `OCR_REGION_OUTLINE` with dash patterns
- [ ] Marching-ants phase advance off the existing ticker
- [ ] 4×2 button group in `OCR_MAIN_WINDOW`
- [ ] Agent wiring through `OCR_GUI`
- [ ] Reference outlines in `OCR_REGION_SELECTOR.on_expose` + setter
- [ ] Stuck-outline safety nets

---

# PART D — Main-window usability (requested 2026-08-17, not yet built)

Four asks that arrived while the run log was being built. None are blocked by
anything; all are small next to Parts A and B.

> **D.1, D.2 and D.4 BUILT 2026-08-17.** New class `src/ocr_log_file.e`; new
> `Clear All / Open Log / Clear Log` row in `OCR_MAIN_WINDOW`; `OCR_CYCLE.log`
> now delegates instead of building the log path inline. Both targets compile
> clean. Two compile failures were hit and recorded as oracle gotchas: a
> newline does not end an Eiffel call (a parenthesised expression on the next
> line becomes an argument), and `RAW_FILE.change_name` is obsolete in favour
> of `rename_file`.
>
> **First user test found two more, both real, both now fixed:**
>
> 1. **Browse killed the application.** `EV_DIRECTORY_DIALOG.set_start_directory`
>    has `a_path_exists` as a *precondition*. Clear All had emptied the folder
>    field, so the next Browse passed `""` and — with assertions baked into the
>    shipped binary — aborted instantly, before anything could reach the log.
>    Now guarded on non-empty **and** existing.
>
> 2. **Clear All looked like it worked and persisted almost nothing.** It
>    blanked the fields and called `store_to_settings`, which by design skips
>    zero-extent rectangles and empty names to protect against half-typed
>    values. So the screen cleared while the old region and file name stayed on
>    disk. Worse, the same flaw was in the folder-change reset: the box cleared
>    but the *stored* name did not, so the next capture would still have written
>    to the previous book's transcript — the exact failure the feature exists to
>    prevent.
>
>    Root cause: `set_region`, `set_advance_region` and `set_page_label_region`
>    all `ensure` validity and so `require` a positive extent — **`OCR_SETTINGS`
>    had no way to express "unset".** Fixed by giving it explicit
>    `clear_region` / `clear_advance_region` / `clear_page_label_region`
>    commands rather than weakening the setters, plus a
>    `Default_text_file_name` constant to reset to (the name setter will not
>    accept empty). Clear All now writes to `settings` directly and reloads the
>    controls from it.

## D.1 Clear the file name when the output folder changes

Changing the target folder should clear the text file name field. Today the
name persists across a folder change, so a new book silently appends to a
transcript named after the previous one.

## D.2 A "Clear All" button

Clears the three scan-box rectangles, the output folder, and the file name.
**Leaves everything else untouched** — hotkey, model, endpoint, `num_ctx`,
prompt and strip position all survive. That boundary is the whole point: it
resets what changes per book, not what was configured once.

Worth a confirmation prompt, since it discards rectangles that took dragging to
set.

## D.3 Tighten the window — DONE 2026-08-17

**Result: 1350x1505 → 1000x1310 physical. 26% narrower, 13% shorter, 36% less
area.** Measured DPI-aware, before and after, on the live window.

### The scaling comment was wrong, and it mattered

The old note at `ocr_main_window.e:929-937` claimed Vision2 shrinks `set_size`
to two thirds on a 150% display, and the constants were inflated to compensate.
That was a **measurement error, not a Vision2 behaviour**: the window had been
measured with a DPI-UNAWARE tool, which reports every coordinate divided by the
scale factor — hence exactly 2/3 at 150%, "perfectly linear", which should have
been the clue.

Measured again after `SetProcessDPIAware()`: a request of 1350 wide produced a
window 1350 physical pixels wide. **What you write is what Windows creates.**
The comment has been replaced with this finding so nobody re-adds the fudge.

This also independently confirms the §B.2 conclusion that popup geometry is
faithful — reached there from the strip's drag maths, here from direct
measurement.

### What was actually costing the space

| Cause | Fix |
|---|---|
| Preview panel was the only *expanding* item in its group, so it soaked up every spare pixel of window height | `disable_item_expand`, height 150 → 76 |
| X/Y/W/H fields shared the full width four ways — ~300 px each to hold "166" | `Coord_field_width = 74`, packed left |
| Every button stretched to the full window width | new `left_aligned` helper |
| Timeout / context / settle fields ran the full width | new `labelled_number` helper, `Number_field_width = 110` |
| `hotkey_label` — created empty, **never written to by anything**, reserving a blank row for the life of the window | deleted |
| Group border 8 / padding 6, multiplied across six groups | `Group_border = 6`, `Gap = 4` |

`Label_width` went 112 → 130: at 112 the caption "Min. settle (ms)" was being
clipped to "Min. settle (ms".

Three identical hand-built X/Y/W/H rows collapsed into one `coordinate_row`
helper.

### Where it stops

1310 physical tall against a requested 1200 — the content's own minimum height
is now the binding constraint, not the request. Going shorter means removing
content, not tightening layout. The empty preview panel is the only remaining
block of dead space and it is there to hold a test capture.

## D.4 The diagnostic log: buttons and lifetime

Three asks, of which the first two are trivial and the third has a genuine
design question.

- **Open the log in a text editor.** `cmd.exe /c start "" "<path>"` through
  `SIMPLE_ASYNC_PROCESS`, which is already a dependency. Using `start` rather
  than naming an editor respects whatever the user has associated with `.txt`.
- **Clear the log.** Truncate `ocr_capture.log`. Confirm first.
- **Log lifetime — recommendation below.**

### Recommendation on log lifetime

The question was: clear at GUI start, clear per book scan, or one file per
autoscan run?

**Do not clear at GUI start.** That destroys the record of the crash that was
just survived — and the moment a user opens the log is precisely the moment
after something went wrong. It optimises for tidiness at the exact cost of the
log's only purpose.

**Per-book separation is already solved**, as of the run log built in §A.3c: it
is named after the transcript, so every book gets its own file automatically,
with no policy needed.

**For `ocr_capture.log`, cap the size and rotate once.** When it exceeds a few
MB, rename to `ocr_capture.log.1` and start fresh, keeping exactly one previous
generation. Bounded on disk, never loses the recent past, and needs no decision
from the user. This is the least complex option that does not throw away
evidence.

So: two buttons, one size cap, and no per-run clearing.

---

# PART E — Reader profiles (requested 2026-08-18, not built)

Named presets for the three rectangles, selectable from the main window, then
adjustable with the drag-and-outline tools that already exist.

The need is real and recurring: there are at least four readers in use — Amazon
Kindle, ProQuest online, the ProQuest local application, and whatever comes
next — and every switch between them means re-dragging three boxes from
scratch.

## What a profile holds, and what it must not

| In | Out |
|---|---|
| capture region | output folder — per BOOK, not per reader |
| advance button | text file name — per book |
| page indicator | hotkey, model, endpoint, context size, prompt — global |
| minimum settle delay | capture index |

The division is the whole design. A profile answers "where is this reader's
furniture", never "what am I reading". Mixing the two is how the placeholder
file name leaked one book into another's transcript.

## The caveat that makes the outlines essential

**The rectangles are absolute screen coordinates.** A profile is really "this
reader, at this window size, on this monitor". Move or resize the window,
change resolution, dock a second display, and every stored rectangle is wrong —
silently, because a mis-aimed box still captures something.

So a profile is a STARTING POINT, never a guarantee. Selecting one must
therefore show its outlines immediately, exactly as finishing a drag now does,
so the first thing a user sees is whether the boxes still land. Without the
outline feature this would be a liability; with it, it is safe.

Corollary: the existing overlap warning should fire on profile load too, not
only after a drag.

## A curated list, NOT a description of readers

Found 2026-08-18: ProQuest online does not lay itself out consistently. A new
book put the page area, the controls and the page indicator all in different
places. The same reader, a different arrangement.

So a profile must NOT claim to describe "the ProQuest reader". It is one saved
arrangement that the user found useful, with a free-text name of their
choosing, and there can be as many as they like:

    ProQuest online - portrait
    ProQuest online - wide
    ProQuest local
    Kindle

Consequences for the design:

- **Names are free text.** Nothing keys off them, nothing parses them, and no
  behaviour depends on which one is selected.
- **Selecting one is a starting point, never an answer.** Showing its outlines
  immediately is therefore not a nicety - it is the step that tells the user
  whether this saved arrangement still fits the book in front of them.
- **The value may be partial and is still worth having.** If the toolbar stays
  put between books and only the page area moves, a profile saves two drags of
  three. That is worth the feature on its own.
- **This lowers the priority of the whole part.** The drag-and-verify workflow
  already works and takes seconds; profiles shave it, they do not enable it.

## Storage

A separate `readers.json` beside `settings.json`, NOT a new field inside it.
`OCR_SETTINGS` hand-rolls flat JSON; an array of objects would mean teaching it
nesting, and a corrupt profile list must never be able to take the working
settings down with it. Separate files fail independently.

## Interface sketch

A row in the Auto-advance group:

```
Reader: [ ProQuest online      v ]  [ Save ]  [ Save As... ]  [ Delete ]
```

Selecting loads the three rectangles into the fields, ticks their outline
boxes, and reports what happened on the status line. Save overwrites the
selected profile from the current fields; Save As prompts for a name.

## What a profile knows about the INDICATOR — and the line it must not cross

A profile should also record what that reader's progress readout looks like:

```
Kindle           page + location, arabic throughout
ProQuest online  page only, roman front matter, no location counter
ProQuest local   (not yet characterised)
```

**This is advisory metadata. It must never reach the parser.** `OCR_PAGE_LABEL`
encoded expected format and REFUSED anything else; the next book showed
"Page iii of 214" and every page was rejected until the run gave up. A declared
expectation can be wrong — a reader updates its interface, a book displays
differently — and anything that DEPENDS on it is then wrong on every page.
Extraction stays arithmetic: find `N of N` pairs, prefer the largest total,
yield nothing when there is nothing. That works on all three readers today
without being told anything about any of them.

### So what does declaring it actually buy?

Not correctness — the parser already handles every observed format unaided.
Two things it cannot do for itself:

**1. Telling "expected blank" apart from "your box is mis-aimed".** Both look
identical from inside: no position, capture after capture. On ProQuest that is
NORMAL through the roman front matter. On Kindle, which always shows a
location, ten captures with no position means the page-indicator rectangle is
pointing at the wrong thing — and the current program cannot say so, because it
has no idea what it should be seeing. A profile turns that silence into either
"front matter, as expected" or "check the page indicator box".

This is worth having precisely because a mis-aimed indicator box is a mistake
already made once, on a live run, and it went unnoticed for seven pages.

**2. ~~Explaining a blank figure.~~ WITHDRAWN — a simpler answer wins.** The
strip should simply print

```
No ETA - Standby ...
```

whenever there is no position yet. That is honest in every case — roman front
matter, an indicator not yet set, a label the model could not read — and needs
no profile, no reader knowledge and no explanation of WHY. An empty line looks
broken; "standby" does not, and it makes no claim that could later be false.

Worth doing on its own, ahead of profiles: it is a few lines in `strip_line`
and removes one of the two reasons this feature existed.

### Small feature this justifies on its own: "the indicator stopped reading"

Live case, Ugaritic run 2026-08-18. A stray keystroke put ProQuest's page box
into EDIT mode - the reader waiting for a page number to be typed - so the
number was cleared and the OCR saw only `of 330`. One number, no pair, no
position. For eleven captures.

Everything behaved correctly: the parser refused the reading, the tracked
position held at 155 rather than corrupting, and text-based advance detection
carried on turning pages with nothing lost. But NOTHING SAID SO. The strip
simply stopped counting up, and the damage - eleven images named
`ocr_of_330-N.png` instead of by page - was only noticed because an external
watcher was looking for exactly this.

The program has all it needs to notice unaided: **an indicator that WAS parsing
and then stops for several consecutive captures has broken, whatever the
reason.** No reader knowledge required, no profile, no format expectation -
just "this was working and now it is not".

    Page indicator stopped reading (11 captures). Check the reader - a page
    box left in edit mode looks like this.

Status line only, never a stop: the run is still capturing correctly and
halting it would be the worse outcome. Note this needs no profile at all, so it
can ship well ahead of Part E.

### Fail-safe by construction

Both uses are diagnostic and cosmetic. A wrong expectation produces a spurious
warning or a missing one, never a refused capture, never a stopped run, never a
wrong number. That is the whole difference between this and the feature that
failed twice: **describe, do not decide.**

## Worth shipping with it

Seed the file with the readers already characterised, so it is useful on first
run rather than empty: Kindle (page + location, largest-total anchor),
ProQuest online (`Page i of 330`, no location, no ETA during front matter), and
the ProQuest local application once its format has been seen. The coordinates
will be wrong on any other machine, but the NAMES and the notes about each
reader's indicator are the part worth carrying.

# PART H — A findings grid, fed by two writers

A multi-column list on the main window (`EV_MULTI_COLUMN_LIST`) showing what
has gone wrong, in what page range, and what to do about it:

```
Time      Pages       Problem                         What to do
--------  ----------  ------------------------------  ------------------------------
10:14:22  126->336    Reader jumped 210 pages          Re-scan 127-335
10:31:57  155         Page indicator stopped reading   Click away from the page box
11:02:04  146         Text does not join across seam   Re-capture page 146
```

## The important idea: ONE file, TWO writers

Findings live in `<transcript-stem>.findings.jsonl`, beside the transcript and
the run log. The grid is only a view of it.

**The program writes what it OBSERVES, live.** Cheap, local, immediate: an OCR
failure, a missing folder, a page that would not turn, an indicator that
stopped reading, a suspiciously short capture.

### The reader jumping is SELF-DETECTABLE - percent is units-agnostic

The costliest failures so far have both been the reader moving somewhere
unexpected, and the program had everything needed to notice both:

    Jehu's Tribute  '123-126 / 356' -> '336-337 / 356'      35% -> 94%
    Heiser Demons   'Page 245 of 267' -> 'Location 1 of 11296'  92% -> 0%

`percent_complete` already exists and is comparable ACROSS series, because it
is a ratio. That is the whole trick: comparing 245-of-267 with 1-of-11296 is
meaningless in raw numbers and obvious as a percentage. No reader knowledge, no
profile, no format expectation - the two things this project has repeatedly
been burned by.

So the check is simply: **percent moves by more than a threshold in one
capture, and the move persists.** Persistence matters for the same reason the
pending rule needs it - one capture cannot distinguish a garbled read from a
real move.

The program ALREADY knows when this happens: `rebaseline' fires exactly then.
The whole feature is reporting an event that is currently silent.

Severity by direction, because the consequences differ:

- **Backwards** - error. The reader has gone back; every further capture
  re-scans what is already transcribed. Heiser cost four junk captures before
  it was spotted by eye.
- **Forwards** - error. Pages are being skipped. Jehu's Tribute lost 209.
- **Series changed without a big percent move** - info. This is the ordinary
  units handover (locations giving way to pages at the front of a book), which
  is benign and should not look like a fault.

Whether it should also PAUSE the run is a separate decision, and the argument
that killed `max_page_step' does not apply with the same force: a 90-point
percent move is not ambiguous the way a multi-page forward step is, and the
cost of continuing is an entire book re-scanned. Suggest: report always, and
offer pausing as a setting rather than building it in.

**`--audit` writes what it DEDUCES, afterwards.** A new CLI mode that reads the
run logs and transcripts of a folder and appends findings. Not run during a
scan: it needs the whole corpus, and doing this sort of judging mid-run is how
the removed `max_page_step' feature went wrong.

### An AUDIT SCRIPT, not an AI call

An earlier draft of this section said the deduced half needed a model. That was
wrong, and the audit performed by hand on 2026-08-18 is the evidence: almost
all of it was arithmetic and pattern matching.

| Finding | How it is actually detected |
|---|---|
| Coverage gaps | parse labels, arithmetic over the page set |
| Duplicate blocks | string equality, then 97% similarity |
| Page-order breaks | compare consecutive page numbers |
| `[OCR FAILED]`, `[TRUNCATED]` | literal string match |
| Suspiciously short captures | character count threshold |
| Indicator stopped reading | no `N of N` pair in the label |
| Text joins across a seam | previous block does not end in `.!?"` AND next begins lowercase |

Even the last one - the check that separated the real gaps from the false ones
- is a two-clause pattern. It agreed with the evidence on all six pages tested:
139, 169, 170 and 268 join; 146 and 272-273 do not.

So the audit is deterministic, repeatable, offline and reviewable, and can be
re-run after every fix without asking anyone.

### What the audit must NOT pretend to know

Three things resist pattern matching, and the audit should report them as
UNCERTAIN rather than assert them:

**Ambiguous seams.** The page 146 break falls inside a bibliography, where
every entry begins capitalised and ends with a full stop - exactly where the
join heuristic is weakest. Flag it; do not rule on it.

**Whether a page number is a real page.** Pages 344 and 355-356 do not exist in
that book. No analysis of the transcript could establish that; the USER knew
it. The audit can only say "no content for these numbers" and leave the
judgement to a person. Two earlier reports of mine asserted missing pages that
were never missing, both times from exactly this over-reach.

**Anything nobody thought to check.** A script finds what it was written to
find. The `of 330` indicator failure surfaced only because a frozen-position
check happened to exist. That is the residual value of a human or a model
looking over a run - not doing the arithmetic, but noticing a CATEGORY of
problem that is not in the script yet. When such a category is found, it gets
added to `--audit` and stops needing anyone.

## Schema

```json
{"t":"2026-08-18T11:02:04","source":"analysis","severity":"warn",
 "pages":"146","problem":"Text does not join across the seam",
 "remedy":"Re-capture page 146","fix_file":"jehus-tribute-146.txt"}
```

- `source` - "run" or "analysis". Shown in the grid, because a finding deduced
  an hour ago and one observed a moment ago deserve different trust.
- `fix_file` - the suggested output name for a corrective scan, computed from
  the transcript stem and the page range. Named for WHAT IS BEING FIXED, not
  for an error code: `-127-335` still means something in six months,
  `-ERR07` does not.

## Staleness is the one real hazard

A findings file is only as current as the last analysis. A gap listed there may
already have been filled. So the grid must show WHEN each finding was made, and
a corrective scan should mark its findings resolved rather than leaving them to
mislead. Better still: analysis reruns cheaply, so re-running it after a fix is
the intended workflow rather than an afterthought.

## `--audit` specification

    simple_ocr_capture.exe --audit "<folder>"

Reads every `*.runlog.jsonl` and its matching `*.txt` in the folder, and
appends to `<stem>.findings.jsonl`. Prints the same rows to the console so it
is useful without the GUI.

Checks, in order of confidence:

| Check | Severity | Certain? |
|---|---|---|
| `[OCR FAILED]` / `[TRUNCATED]` markers in the text | error | yes |
| Capture rows carrying an error | error | yes |
| Blocks identical, or >=97% similar with the same label | warn | yes |
| Page numbers going backwards | warn | yes |
| A jump larger than the run's typical step | warn | yes |
| Captures below the short-text threshold | info | yes |
| Labels yielding no position after some had | warn | yes |
| Page numbers with no covering capture | **uncertain** | ONLY for range-labelling readers - see below |
| Seam where text appears not to join | **uncertain** | NO - weak in bibliographies |

### Gap detection must depend on how the reader LABELS

Learned by running the audit on `principalities-powers-and-allegiances`
(2026-08-18), where the set-difference check reported 328 of 488 numbers
missing and every one was wrong.

Two reader classes, and they need different checks:

**Range-labelling** (`123-126 / 356` - ProQuest). Each label states every page
on screen, so a number absent from the union really is absent. Set difference
works; it is what found the genuine 209-page hole in Jehu's Tribute.

**Single-number** (`Page 107 of 488` - Kindle). The label names only the FIRST
page of a screenful that shows three or four. Most numbers never appear in any
label, so set difference reports the whole book missing. Useless.

Tell them apart by the labels themselves: if any label contains a range, the
reader is range-labelling. No configuration, no profile, no guessing.

For single-number readers the right check is **a step larger than the run's own
typical step** - the median or mode of the observed steps. On this book, steps
were 3 and 4 throughout with nothing larger, so it would have reported nothing,
correctly. On Jehu's Tribute the 126 -> 336 jump was ~70x the typical step and
would have stood out at once.

Note this is the same arithmetic the removed `max_page_step' feature used, and
it is safe HERE for the reason it was unsafe there: the audit reports after the
fact, where a false positive costs a second look. `max_page_step' halted a live
run, where a false positive cost the run.

Two rules the audit must hold to:

- **Never delete or rewrite anything.** It appends findings and prints. Every
  repair today was done by a separate, reviewable step, and that separation is
  what made it safe to be wrong.
- **Say how sure it is.** An uncertain row that reads as certain is worse than
  no row: it sends someone re-capturing pages that were never missing, which is
  precisely the mistake made twice by hand today.

Re-running after a fix is the intended workflow, so findings should carry the
run they came from and be replaceable rather than merely accumulating.

## Why not have the program call an AI for this

Considered and rejected for the RUNTIME half. The runtime errors are finite and
already enumerated in the code, so a written table of cause and remedy is
instant, works with Ollama down - which is itself one of the errors - and
cannot invent a remedy the program does not have. A model asked "why did this
fail" produces plausible prose about things this program does not do.

The deduced half is the opposite: open-ended reasoning over a whole run, which
is exactly where a model earns its place. Hence the split, and hence one file
that both can append to.

# PART G — Stop at a chosen page

Requested 2026-08-18, after two partial-range scans in one day both needed
watching so they could be stopped in the right place by hand.

A field beside "Min. settle (ms)":

    Stop at page [     ]     blank = run to the end of the book

When the tracked position reaches it, the run stops exactly as it does at the
end of a book - same message, same stop row, same modal.

## Why this is safe where `max_page_step' was not

The removed `max_page_step' halted when the program DECIDED a jump was too
large. It was wrong whenever a reader legitimately showed several pages at a
time, and it killed good runs.

This stops on a target the USER set. It makes no judgement about what a normal
step looks like, so it cannot be wrong about one. The failure mode is a run
that stops where it was told to.

## Design notes

- Reads `position` from `OCR_RUN_METRICS`, which already tracks it and already
  rejects garbled readings - no new parsing, no new guard.
- Trigger on `position >= limit`, not equality: this reader labels RANGES
  ("332-335 / 356"), so the exact number may never appear on its own.
- Blank or zero means no limit, which must be the default - a stop condition
  nobody asked for is the old mistake wearing a new hat.
- Say WHY in the stop message: "reached the page limit of 335" reads very
  differently from "the book may have ended" when found in a log an hour later.
- No limit can be enforced while the indicator is unreadable. If the position
  is unknown the run simply continues, which is the honest behaviour: better to
  overrun and trim than to stop early on a bad reading.

# PART F — Clicking without stealing focus

## The problem

`OCR_CLICKER` clicks with `SendInput` and absolute screen coordinates - a
genuine synthetic mouse event. That ACTIVATES whatever window is under the
cursor, so for the ~120 ms before focus is restored the reader owns the
keyboard, and any key the user physically presses in that instant is delivered
to the reader instead of to whatever they were typing in.

Observed live, Ugaritic run 2026-08-18: a stray keypress put ProQuest's page
box into edit mode, and eleven captures were named `ocr_of_330-N.png` before
anyone noticed.

Note the click does not BECOME a keystroke. It changes where the user's own
keystrokes are delivered. The two event types stay separate; only the routing
moves.

## F.1 The real fix - post the click instead of injecting it

`PostMessage (hwnd, WM_LBUTTONDOWN / WM_LBUTTONUP, ...)` delivers a click to a
window WITHOUT activating it. No focus change, so no misdirected keystrokes are
possible at all - the entire class of problem disappears rather than being
compensated for.

    WindowFromPoint  -> HWND under the advance button
    ScreenToClient   -> click point in that window's own coordinates
    PostMessage      -> WM_LBUTTONDOWN then WM_LBUTTONUP

**The doubt worth spiking before building:** Chromium-based applications - and
ProQuest online runs in Edge - commonly IGNORE posted synthetic mouse messages,
because they hit-test raw input rather than the message queue. The local
ProQuest application and other native readers may well accept them.

So this is per-reader, not universal. Design accordingly: try the posted click,
verify the page turned by the existing text comparison, and fall back to
`SendInput` when it does not work. The fallback already exists and is proven;
this only has to be better where it works.

## F.2 The cheap certain win - verify the focus restore

`c_click_at` already saves `GetForegroundWindow ()` before clicking and restores
it after. It never checks whether the restore SUCCEEDED. Comparing the two
afterwards and logging a mismatch costs about four lines, needs no hook, and
catches the worse version of this failure - focus not coming back at all, so
the user's typing goes to the reader for far longer than an instant.

Log only, never a stop.

## Rejected: grabbing and replaying the keyboard

Considered and turned down. Capturing keystrokes during the focus window needs
`WH_KEYBOARD_LL`, a global low-level hook that sees every keystroke in every
application. Gating it to 120 ms does not change what the code IS, and AV and
EDR tooling treat it accordingly - a poor thing to ship in a tool that lives in
a documents folder.

Replay is also unreliable in a way that is worse than the disease: synthesised
keys go wherever focus happens to be at that moment, and modifiers, dead keys,
IME composition and autorepeat all mangle. Losing a keystroke is annoying;
silently INJECTING one into the wrong window is worse.

Above all it treats the symptom. The stray key exists only because focus moved,
so not moving focus (F.1) is strictly simpler than catching what falls through.

# PART C — Carried-over backlog, not part of the above

## C.1 Unresolved decision — blocks nothing, but bites at ingest time

**New PNG naming breaks `ingest.py`.** v1.3.0 names images after the reader's
indicator (`ocr_Page_224_of_416.png`), but the handoff at `Scholars/_db` §2.2
records that ingest derives filenames as `ocr_%04d.png` from the capture number.
Existing books are unaffected; the next book scanned *for ingest* is.

**RESOLVED IN PRINCIPLE — see §A.3c.** The per-capture run log carries both
`capture_index` and `image_filename`, so ingest joins on it instead of deriving
a filename, and becomes immune to future naming changes. This is the same
artifact as the `_db` §5 JSONL sidecar; build it once, both items close.

Still Larry's call whether to also patch `ingest.py` to glob-and-match as a
stopgap for books scanned before the run log ships.

## C.2 Still queued from the `Scholars/_db` handoff

- JSONL sidecar (§5)
- Generations / never-overwrite (§3.4)
- UI-frame rejection (§3.2)
- Book-boundary marker (§3.1)
- Manifest fields: `source_type`, `pages_per_capture`

## C.3 Re-capture needed — cannot be fixed in software

Blank or tiny source images; re-OCR will not help:

- Franklin p.21, capture 757
- Walton *Cosmology* p.125, capture 12

Note that `_db` handoff §3.3 is **wrong** on this point: it lists these as
needing re-OCR. They need re-capture.

---

# Verification gates (per CLAUDE.md)

Nothing in this plan is "done" without pasted output:

```bash
/d/prod/simple_oracle/oracle-cli.exe check          # before writing Eiffel
/d/prod/ec.sh check -config simple_ocr_capture.ecf -target ocr_capture_tests
/d/prod/ec.sh test  -config simple_ocr_capture.ecf -target ocr_capture_tests
```

Run from the **project root**, not `src/` — running from `src/` returns a
meaningless "0 errors" without ever reading the ECF.

Grep the actual compiler output for `Error code:` — `ec.sh` has been observed
printing a green "Syntax and type check passed" while the output contained a
syntax error.

Record any new failure with `oracle-cli learn gotcha` before moving on.
