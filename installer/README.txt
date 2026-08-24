Simple OCR Capture
==================

Capture a region of the screen, run it through a local OCR model, and append
the text to a single file.

New in 1.8.0: the interface is rebuilt on the simple_widgets toolkit
(pure Eiffel - no Vision2). Settings are organised into tabs; findings
live in a real grid; the region picker dims the frozen desktop and
re-lights your selection; the desktop outlines are click-through
frames; right-clicking a misspelled word now offers Ignore and Add to
dictionary (your Windows dictionary - Edge and Office honour it too). Built for reading through a document page by page:
set the region once, then hit the hotkey after each page turn.


REQUIREMENTS
------------

  * Windows 10 or 11, 64-bit
  * Ollama              https://ollama.com/download
                        installed only - the application starts it itself
  * An OCR model        the application offers to download this on first run

Nothing else. The application ships as a single executable and needs no
runtime, no redistributable and no Python.

The default model is olmOCR-2 (about 9.5 GB). A discrete GPU with 12 GB or
more of VRAM is strongly recommended; on this machine a full page takes
roughly 25-45 seconds on an RTX 5070 Ti.


FIRST RUN
---------

 1. Launch Simple OCR Capture. You do NOT need to start Ollama yourself -
    see "THE OCR SERVER" below.
 2. If the model is missing it will offer to download it. Say yes and wait -
    the window stays usable while it downloads.
 3. Press "Set Region by Dragging..." and drag a rectangle over the area you
    want transcribed. Press Esc or right-click to cancel.
 4. Set the output folder.
 5. Press "Test Capture" to confirm the region is right.
 6. Press "Check Setup / Install Model" for a full report confirming that
    every part of the chain is up and working.


THE OCR SERVER
--------------

The application starts and supervises the Ollama server it needs. Ollama
itself must be installed, but it does not have to be running.

  At launch      If nothing is answering on the configured endpoint, the
                 application starts a server on it, using its own settings
                 rather than whatever the machine has configured. This takes
                 a few seconds and is reported in the status line.

  While running  It checks every 15 seconds that the server is still there.
                 If it disappears, a dialog asks whether to start it back
                 up. Decline, and a second dialog asks whether to close the
                 application, since captures cannot work without it. Decline
                 that too and it keeps running quietly without asking again,
                 until you use "Check Setup / Install Model".

  On exit        The server is left running deliberately, so the model stays
                 loaded and the next session's first capture is fast.

"Check Setup / Install Model" runs the full check: Ollama installed, server
responding, model installed, output folder writable, and a real recognition
request answered. The last one is the only check that proves the model works
rather than merely being listed, so it can take up to a minute on a cold
load. The same report is available without the interface:

    simple_ocr_capture.exe --health

which prints the same report to the console.

Note that the shipped executable is a windowed program, so that it never drags
a console window along behind the interface. The diagnostic modes above print
their reports, but Windows does not make a windowed program's exit code
available to a shell the way it does for a console program - read the printed
report rather than testing an exit code from a script.

Two things are worth knowing if you also use Ollama elsewhere:

  * The server is started on the endpoint in the settings (127.0.0.1:11435 by
    default), not Ollama's usual 11434. This keeps it clear of any other
    Ollama - a WSL one, or the tray application - already using that port.

  * OLLAMA_ORIGINS is overridden for the server this application starts. A
    machine-wide value with no valid scheme (for example the "app://obsidian.md"
    that some setups add) makes the Ollama server abort at startup before it
    ever listens, which is indistinguishable from Ollama not being installed.

Its log is written to %LOCALAPPDATA%\Ollama\simple_ocr_serve.log.


AUTO-ADVANCE
------------

Reads a whole book unattended: capture the page, turn it, capture the next.

Set it up once, in the "Auto-advance" panel:

  1. "Set Advance Button by Dragging..." - drag a box around the reader's
     NEXT PAGE control. The MIDDLE of that box is what gets clicked, so put
     the box on the button, not around it. Nothing is ever clicked until you
     have dragged this box.

  2. "Set Page Indicator by Dragging..." - drag a box around the reader's
     page number ("90-92 / 139"). This is optional but strongly recommended;
     see below.

  3. Press Start. Pause and Stop are beside it, and the same three controls
     appear as play/pause/stop glyphs at the right-hand end of the
     always-on-top strip, so you can stop a run without hunting for this
     window.

The page turns the instant the screenshot is taken, not after the OCR, so the
reader repaints during the ten to forty seconds the model is busy. By the time
the strip says READY the next page is already there and no waiting is left to
do. "Min. settle (ms)" is only a floor between the click and the next
screenshot; with a normal OCR it never comes into play.

The page indicator is used for three things, none of which is deciding whether
the reader moved on:

  * the strip shows it under the thumbnail, so a glance tells you which page
    is being transcribed;
  * it is written into the transcript above each page's text, as
    "----- capture 612  [page 14 / 163] -----";
  * it names the saved screenshot - see DAILY USE.

Whatever the indicator says is taken as it stands. No particular format is
required or assumed - ProQuest alone presents "90-92 / 139" in one reader and
"Page iii of 214" in another, with prefixes, roman numerals and different
separators, so the text is recorded and compared rather than parsed.

A run continues while each capture differs from the one before it, and stops
when a capture comes back the same. That is the whole test: the reader moved
on, or it did not.

The page indicator takes no part in that decision. It is an annotation - it
records what the reader was displaying - and it names the saved screenshot.
Two earlier versions did derive progress from it and both were wrong: one
demanded the label change, which fails the moment a printed page spans several
screenfuls; the next measured the page numbers for skips, which fails the
moment a reader legitimately shows two to four pages at a time. The text is
the only witness that holds in every case.

A page that will not turn is clicked twice more before the run gives up. A
click can fail to land for reasons that pass on their own - a stray keystroke
taking it, a control not yet enabled after a section break - and ending a
hundred-page run over one of those is the more expensive mistake.

The click also puts things back as it found them: the mouse pointer returns to
where it was, and so does the foreground window. An unattended run therefore
does not steal focus from whatever else you are doing once per page.

That also means a reader mid-load can occasionally be captured: the indicator
area has nothing readable on it, the model produces something anyway, and it
differs from the previous page, so the turn looks genuine. Rather than guess,
any capture that comes back with very little text is flagged in the log as

    WARNING: very little text - check this page

so those pages can be found afterwards. They are not discarded: a splash
screen and a legitimately near-empty page - a single bibliography line, a
part title - are the same size, and only a reader can tell them apart.

A capture whose text is identical to the block just written is NOT appended
again. That happens by design at the end of a book: the run captures, sees no
advance, clicks twice more and captures each time before concluding the book
has ended. Those retries are worth keeping - they rescue a genuinely missed
click - but their text is not, and it used to leave three copies of the last
page in every transcript to be trimmed by hand.

Runs stop by themselves on a failed page turn or a failed capture, and say why
in a dialog. Nothing silently appends the same page over and over. Reaching
the end of a book stops the run the same way, since the last page cannot turn.


SEEING WHERE THE REGIONS ARE
----------------------------

The three rectangles - capture region, advance button, page indicator - are
just numbers until something draws them. "Show regions on screen" draws each
one on the DESKTOP, over your reader, as a dashed marching-ants outline.

Each has its own colour AND its own dash pattern, because all three can be
shown at once over a page of any colour:

    capture region    cyan     long dash
    advance button    amber    dot
    page indicator    green    dash-dot

The frame is drawn just OUTSIDE its rectangle, so it never covers the content
being checked and never appears in a captured image.

A box is outlined automatically the moment you finish dragging it, and stays
until you untick it. That turns a drag from an act of faith into something you
can see: cycle a few pages in the reader and watch whether the boxes still line
up. They can be left on for a whole unattended run - any outline that would
cross the capture rectangle is taken down for the few milliseconds of each
screenshot and put straight back, so nothing is ever photographed.

If the page indicator and the advance button end up on the same spot, the
status line says so, and it is written into the log at the start of every run.
They should never coincide: one is text to read, the other a button to click.
It is a warning, not a refusal - an unusual reader could conceivably print a
page number on its own control.


READING THE PAGE INDICATOR
--------------------------

Whatever the reader displays is recorded as it stands. To show progress, two
numbers are also pulled out of it - a position and a total - and that is done
by arithmetic, never by expecting a particular wording:

    "Page 224 of 416"                        224 of 416
    "90-92 / 139"                             92 of 139
    "Page 12 of 170  Location 890 of 8890"   890 of 8890
    "100% Page 168 of 170 . Location 3101 of 3116"   3101 of 3116
    "Page i of 330"                          nothing - roman numerals

Every "<number> of <number>" or "<number> / <number>" pair is found, and the
one with the LARGEST total is used. That is the location counter when a reader
shows one, and the page counter when it does not. The location counter is the
more stable of the two: it runs unbroken across front matter, body and index,
its total never changes and its position never resets.

Front matter often yields nothing at all - roman numerals are not digits, and
a reader with no location counter has nothing else to offer. The strip then
says "No ETA - Standby ..." and starts reporting figures once real page
numbers appear, usually two captures later.

A reader that CHANGES what it counts part-way through - locations giving way
to pages, roman numerals to arabic - is handled without intervention. A single
odd reading is held back rather than obeyed, because one capture cannot tell a
garbled read from a genuine change. If the next capture agrees with it, the new
series is adopted and the rates start again from there. If it does not, the odd
reading is discarded.

If the indicator was reading and then stops for several captures, the status
line says so. Pages are still captured correctly - advance detection never uses
the indicator - but they stop being named and annotated by page, and that is
worth knowing at the time rather than afterwards. A page box left in edit mode
by a stray keystroke looks exactly like this.


WATCHING PROGRESS
-----------------

Once an unattended run has two captures behind it, the strip shows how it is
going, under the page indicator:

    Page 205 of 379   54%
    2.9 scan/min   8.5 pg/min
    ETA 20 min   (174 pages left)
    finishing about 9:44 PM

The settings window carries the same figures in one line, and every page's
rates go into the log.

Two of these deserve a word. "Pages" and "scans" are NOT the same thing: a
reader showing three pages at a time transcribes three pages per scan, and a
printed page larger than the window takes several scans to cover. Both happen,
neither is an error, and that is why both rates are shown.

The percentage is of the whole BOOK, not of the session, so a run started at
page 10 of 379 opens at 2% rather than 0%.

The finish time carries no zone label deliberately. It is your machine's local
clock, which is correct; the abbreviation is the part that cannot be got right
without guessing, and a confidently wrong "EST" in July is worse than none.


THE RUN LOG
-----------

Every book gets a machine-readable record beside its transcript, named to
match:

    the-jesus-driven-life.txt  ->  the-jesus-driven-life.runlog.jsonl

One JSON object per line, written as each event happens rather than buffered -
a run that dies is exactly the run whose record matters. It holds the
rectangles the run started with, every capture with its image file name, page
indicator and character count, every page turn with how many extra clicks it
cost, and the reason the run stopped.

The capture-to-image-name pairing is the useful part for anything downstream:
an ingest step can join on it instead of deriving file names from a counter,
which makes it immune to any future change in how images are named.


FINDINGS
--------

A list on the main window of problems worth your attention, with what to do
about each:

    When      Where           Problem                        What to do
    --------  --------------  -----------------------------  ------------------
    10:14:22  336-337 / 356   [error] The reader jumped       Stop, put the
                              FORWARDS, from 35% to 95%       reader back, restart

Rows appear as problems happen. Two are worth knowing about:

  THE READER JUMPED    Measured as a change in percent complete, which works
                       whatever the reader counts - comparing "245 of 267"
                       with "1 of 11296" is meaningless as numbers and obvious
                       as a ratio. Forwards means pages are being skipped;
                       backwards means text already transcribed is being
                       scanned again. Reported, never fatal: the run is still
                       capturing correctly, and halting on a misjudged jump
                       would be the worse mistake.

  THE INDICATOR STOPPED READING   Pages are still captured - advance detection
                       never uses the indicator - but they stop being named and
                       annotated by page.

"Run Audit" checks the FINISHED transcript and adds what it finds: captures
that failed or were truncated, blocks repeating an earlier capture, page
numbers going backwards, jumps far larger than the run's usual step, and
captures with very little text.

Findings are also written beside the transcript as <book>.findings.jsonl, so
they survive the window being closed. "Clear List" empties the display only;
the file is never touched from a button.

Two checks cannot be certain and are marked with a "?": a page number with no
covering capture may not be a real page - some books number pages that are
never displayed - and a seam that looks broken may be a bibliography, where
every entry begins capitalised and ends with a full stop.

The same audit is available without the interface:

    simple_ocr_capture.exe --audit "<transcript.txt>"


IF THE PROGRESS STRIP GOES MISSING
----------------------------------

Press "Show Strip". It puts the strip back at the top-left of the screen and
re-ticks "Show progress strip" - it always MOVES it, because anyone pressing
that button has already failed to find it where it was.

The application also checks a couple of times a second that the strip is where
it should be, and restores it if not. That covers a position left outside the
desktop after a monitor is unplugged or a resolution changes, which leaves a
window "shown" and invisible.


THE OUTPUT FOLDER
-----------------

If the output folder does not exist, you are asked before anything is created:

    This output folder does not exist:
        C:\...\Scholars\Cooley-Shelle
    Create it?

Answering no is not an error - it simply says to change the folder, and asks
again if the next one does not exist either.

Earlier versions created the folder silently. A single mistyped character
therefore produced a new directory and scanned a whole book quietly into it,
which is a bad way to find out about a typo.


BETWEEN BOOKS
-------------

"Clear All" resets what changes from book to book - the three rectangles, the
output folder and the file name - and leaves everything else alone. Hotkey,
model, endpoint, context size and prompt all survive.

Changing the output folder also clears the file name, on purpose. Keeping the
previous book's name is how one book silently gets appended to another's
transcript.

"Open Log" and "Clear Log" do what they say. The log is capped at four
megabytes and rotates once, keeping one previous generation as
ocr_capture.log.1. It is NOT cleared when the application starts: the moment
anyone opens that file is the moment after something went wrong, and starting
each session by destroying the last session's account of itself would optimise
for tidiness at the cost of the log's only purpose.


DAILY USE
---------

Press the hotkey (Ctrl+Alt+G by default). The progress strip fills left to
right through five stages:

    o o o o o    idle
    * o o o o    1  capture started
    * * o o o    2  screen captured
    * * * o o    3  OCR running
    * * * * o    4  results written
    * * * * *    5  READY

Wait for READY before turning the page. The strip stays on top of whatever
you are reading and never takes focus, so it will not interrupt you.

Beneath the lights the strip shows a small picture of the last capture, so
you can confirm at a glance that the region grabbed the right thing. It
appears as soon as the screenshot is taken, well before the OCR finishes, so
a mis-aimed region is obvious immediately rather than a page later. Turn it
off with "Show last capture" if you want a smaller strip.

Text is appended to one file. Images are saved alongside it, named after what
the reader was showing:

    ocr_Page_224_of_416.png
    ocr_90-92_139.png
    ocr_Page_iii_of_214.png

so a folder of screenshots can be read against the book instead of against a
counter. Where a printed page is larger than the reader's window it is
captured in portions, all carrying the same indicator; the later ones take a
"-2", "-3" suffix. Nothing is ever overwritten. Captures made with no page
indicator configured fall back to ocr_NNNN.png on the capture counter.


RE-SCANNING A PAGE
------------------

The OCR is a sampling model, so a second pass over the same image is another
SAMPLE, not a repair - and it routinely recovers material the first pass
dropped. Every captured page is kept as a PNG for exactly this reason.

    simple_ocr_capture.exe --rescan <image.png> [<image.png> ...]

Each page is written beside its image as "<image>.rescan.txt". The original
transcript is never touched: the two versions are there to be compared, and
which one to keep is a decision for a reader, not for this program.

Re-running with the SAME prompt tends to reproduce the same omission, so a
prompt can be given for that run alone, without disturbing the saved settings:

    simple_ocr_capture.exe --rescan --prompt "<text>" <image.png>

That is what recovers a dropped marginal column or footnote block. Measured on
one page of a study edition whose margin and footnotes were both missing:

    stored prompt   414 chars, no margin, no footnotes
    zone prompt   4,939 chars, all 8 footnotes, 4 of 5 margin clusters

A prompt naming the page's zones - "a running head, the body, a narrow
MARGINAL CROSS-REFERENCE COLUMN on the right, FOOTNOTES at the foot" - is what
made the difference. Note that the model is not reliable about LABELLING those
zones even when it transcribes them: on that page it filed the margin block
under a footnotes heading. Recovering the text is dependable; the tags are not.


SETTINGS
--------

Settings live in:

    %APPDATA%\simple_ocr_capture\settings.json

A diagnostic log is written beside it as ocr_capture.log.


THE LOG
-------

    %APPDATA%\simple_ocr_capture\ocr_capture.log

An unattended run is by definition unwatched, so when one stops after an hour
the log is the only account of what it saw. Every auto-advance line is tagged
[auto] and records:

  * the rectangles the run started with - most trouble turns out to be a box
    aimed at the wrong place, and the coordinates cannot be reconstructed
    afterwards
  * every page indicator read, both as the model produced it and as the run
    used it, so a stray newline or an extra word is visible
  * every click, with the exact point pressed
  * every capture: how many characters came back, and the first and last 70
    of them - enough to identify the page without copying the transcript into
    the log
  * every stop, pause, resume and failure, with the reason

A normal page looks like this:

    [auto] indicator raw=[Page 41 of 214] used=[Page 41 of 214]
    [auto] clicked advance at (1867,168) while OCR runs
    [auto] capture done chars=4192 text=[The Hebrew word ... of the seven days.]
    [auto] Auto-advance: 38 page(s) written, last was Page 41 of 214. Page ready.

and the end of a book looks like this:

    [auto] Stopped after 225 page(s): the page did not advance (indicator
           still reads Page 213 of 214). The click may have missed the
           button, or the book may have ended.

Two settings are worth understanding:

  Context tokens (num_ctx)
      The image and the transcribed text share one context window. If this is
      too small the image fills it and the transcription is cut off partway
      through - silently, with no error, looking like clean prose that simply
      stops. The default of 16384 handles a full page. Raise it if captures of
      large regions come back short; it costs VRAM. Any capture that is cut off
      gets a [TRUNCATED] marker written into the output file.

  Hotkey
      Needs at least one of Ctrl, Alt or Shift. A modifier-less hotkey would
      claim the bare key from every application on the system, so the
      application refuses to register one.


KNOWN LIMITATIONS
-----------------

  * The model normalises visually ambiguous characters. A lowercase "l" inside
    a hash or serial number can come back as a digit "1", and prompting does
    not prevent it - it is inherent to a language model reading rather than a
    character classifier. Do not trust the output for checksums, licence keys,
    base64 or similar high-entropy strings without checking them. Prose,
    footnotes and tables are where it is strong.

  * The window opens at a size tuned for a 150% display and may look oversized
    at 100%. It is freely resizable; the chosen size is not yet remembered.

  * Captures are sequential. Triggering during a cycle is ignored rather than
    queued, and the hotkey is ignored entirely while auto-advance is running.

  * Auto-advance clicks a fixed point on the screen. If you move or resize the
    reader window mid-run, the click lands somewhere else. The page will then
    fail to turn, which stops the run - it does not click blindly on - but the
    advance box needs re-dragging for the new window position.


UNINSTALLING
------------

Use Add/Remove Programs. Your captured images and transcripts are never
touched - they live in the folder you chose. The uninstaller asks separately
whether to remove your settings.
