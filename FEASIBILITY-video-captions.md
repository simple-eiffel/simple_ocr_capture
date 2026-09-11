# Feasibility: video caption intake (YouTube CC roll to transcript)

Requested by Larry 2026-09-11, studied against v1.11.0 and the sample
`C:\Users\LJR19\Videos\YouTube-CC-30-second-example.mp4` (1896x1068,
30 fps, 910 frames, 30.4 s, h264 + aac).

Verdict up front: **possible, and cheaper than page capture.** The right
route is a live caption-area capture from the playing YouTube tab, read
by the OCR engine that ships inside Windows (`Windows.Media.Ocr`), with
no audio, no intermediate files, and playback at 2x to 3x. Everything
measured below was actually run today; numbers are from this machine.

---

## What the sample video showed

Captions are YouTube's two-line **roll-up** style. Each new cue keeps the
previous bottom line as its top line and adds one new line, and a line can
also **grow word by word** before it rolls. Fifteen consecutive stable
cues read:

```
Hello everyone, this is Watcher Pastor
here to tell you. Today we are talking
about goat demons. | Now depending
about goat demons. | Now depending on your translation
Now depending on your translation in the | Bible,
Now depending on your translation in the | Bible, there might be something
Bible, there might be something like uh | some type
some type of devil or | maybe goats
...
```

Consequences for design:

- Every capture overlaps the one before it. The transcript is built by
  **suffix/prefix merge at word level**, not by appending. The existing
  OCR_TEXT_COMPARE common_head/common_tail idea is the seed, moved from
  characters to words.
- Cue timing at 1x, measured by fingerprinting only the white text pixels
  inside the black caption box (moving hands behind the box are ignored):

| Measure | Value |
|---|---|
| distinct caption changes in 30.4 s | 14 |
| mean gap between changes | 2.1 s |
| shortest gap | 0.7 s |
| longest gap | 3.9 s |

---

## Engine bake-off on one caption crop (1896x130)

| Engine | Cold | Warm | Accuracy on the crop | Notes |
|---|---|---|---|---|
| **Windows.Media.Ocr** (in the OS, en-US pack) | 58 ms on a full 1896x1068 frame | **4 to 12 ms** per crop; 15 crops in 239 ms | both lines exact; one garbage line on a mid-transition frame | no model download, no server, no GPU, in-process WinRT |
| olmOCR-2 7B q8 via Ollama 11434 | 12.8 s | 207 ms | both lines exact | serialises on the GPU; the app's current engine |
| whisper.cpp large-v3-turbo q5 on the audio | 47.3 s for 30 s of audio | | misheard "Watcher Pastor" as "what you're about to" | CPU build; slower than real time |
| whisper.cpp base.en on the audio | 4.9 s | | returned "I Thanks." | unusable |

The mid-transition garbage line (`Lills Is-vva | ne110 everyone`) came
from a crop taken while the caption box was redrawing. It is not an
engine flaw; it says the capture must wait for the box to **settle**
before reading it.

---

## Option A. Live caption-area capture from the YouTube tab: RECOMMENDED

Same shape as the page reader, one region instead of three:

1. Larry drags a **caption region** once (the black box band).
2. A 50 ms tick grabs that region with the existing OCR_GRAB path
   (SW_SCREEN BitBlt into a CAIRO_SURFACE). Nothing touches disk.
3. A cheap **fingerprint** of the grab (bright pixels only, downscaled)
   decides whether anything changed. Unchanged frames cost nothing more.
4. A changed fingerprint that then holds still for 2 to 3 ticks is
   **settled**; only then is the surface handed to OCR.
5. The OCR result is merged into the running transcript by word-level
   suffix/prefix overlap. A result that shares no overlap with the tail
   and is short garbage is dropped and logged, not appended.
6. Stop when the region stops changing for N seconds, or the video's
   own end is detected, or Larry presses Stop.

Per-cue cost with Windows OCR: grab ~5 ms + fingerprint <1 ms + OCR
~10 ms. That is about two ticks. With olmOCR the OCR leg is 200 ms warm
and must run off the tick in the worker, as it does today.

Fits the existing architecture: OCR_GRAB unchanged, OCR_TEXT_COMPARE
generalised, a new OCR_CAPTION_RUN beside OCR_AUTO_RUN, a new
OCR_WINDOWS_ENGINE beside OCR_ENGINE behind a shared deferred parent.
The Windows engine is a new inline C external over the WinRT activation
API (RoInitialize, RoGetActivationFactory, IOcrEngine); nothing in the
ecosystem wraps it yet (grep over simple_ocr_capture, simple_vision,
simple_shell, simple_widgets, simple_speech found nothing).

### Playback speed: yes, and there is a ceiling

Audio is irrelevant to this route, so the tab can be muted and the
video run faster. The ceiling is set by the shortest cue lifetime, not
by OCR:

| Speed | shortest cue on screen (0.7 s at 1x) | 50 ms ticks that see it | settle margin |
|---|---|---|---|
| 1x | 700 ms | 14 | wide |
| 2x | 350 ms | 7 | comfortable |
| 3x | 233 ms | 4 | enough for a 2-tick settle |
| 4x | 175 ms | 3 | marginal; one timer hiccup loses a cue |
| 8x | 88 ms | 1 | cues will be missed |

Two more limits above 2x:

- YouTube's own menu stops at 2x. Higher rates need the player's HTML5
  element (`video.playbackRate = 3`) from the DevTools console or a
  small bookmarklet; Chromium honours up to 16x.
- YouTube's caption renderer skips cues shorter than its render tick at
  high rates; that is the player dropping captions before we ever see
  them, and no capture speed recovers them.

Recommendation: **default 2x, allow 3x, refuse above 4x** with the
50 ms tick. Log every dropped or unmerged read so a run can be checked.

---

## Option B. Record the caption band to MP4, then read it offline

Snipping Tool (or ffmpeg gdigrab) records the region; a second pass
decodes frames and OCRs them. It works, and ffmpeg can pipe raw frames
to memory so no PNG trail is left (the fingerprint script used for the
cue counts above did exactly that: `ffmpeg ... -f rawvideo -` into a
pipe, zero files). But it is strictly more work than A for no gain:
the recording still takes the full playback time, it adds a 30 MB per
30 s file per video, and it needs simple_ffmpeg or simple_process in the
loop. Worth keeping only as a **batch mode for already-downloaded
videos**, where the same fingerprint-settle-merge core reads frames from
an ffmpeg pipe instead of the screen.

## Option C. Transcribe the audio: NOT RECOMMENDED here

It is possible to grab system audio silently through code: WASAPI
loopback (simple_audio's domain) captures what is sent to the output
device without a microphone. But it has three problems for this use:

- Muting the tab or the mixer mutes the loopback stream too, so Larry
  would hear the video. Silent capture needs a virtual audio device
  (VB-Cable or similar) as the default output, an extra install.
- Sped-up playback distorts the audio; whisper accuracy drops with it.
- On this machine whisper large-v3-turbo runs slower than real time on
  CPU and already misheard a proper noun the captions had right. The
  captions are the better source when they exist.

Keep it as a fallback for videos with no captions at all, and as an
offline batch job, not a live one.

## Option D. Other choices considered

- **YouTube transcript panel and timedtext endpoint.** When the panel
  exists it is copy-paste; Larry's case is the videos where it does not.
  The timedtext URL behind the CC button can be fetched, but it is
  undocumented, changes, and needs the page's session. Not a foundation.
- **Chrome DevTools Protocol** reading the caption DOM nodes
  (`.ytp-caption-segment`) instead of pixels. Exact text, no OCR at all,
  works at any speed. Needs Chrome launched with remote debugging and a
  websocket client (simple_web has the HTTP side). Strong second choice;
  brittle only where YouTube renames classes. Could be added later as a
  "text source" behind the same merge core.
- **UI Automation** reading caption text. The caption overlay is a canvas
  in the player, not accessible text. Dead end.

---

## Suggested build order

1. OCR_WINDOWS_ENGINE: inline C WinRT wrapper, in-memory bitmap in, text
   lines out. Test: the 15 cue crops above, expected strings baked in.
2. OCR_CAPTION_MERGE: word-level suffix/prefix merge with the roll-up
   and grow-in-place cases from the sample as tests.
3. OCR_CAPTION_RUN: tick, grab, fingerprint, settle, OCR, merge, stop
   rule, per-cue log line.
4. GUI: one caption region selector, speed hint, running transcript
   preview in the strip.
5. Later: batch mode over an ffmpeg pipe (Option B), DevTools text
   source (Option D).

Each step ships on its own. The engine in step 1 is also a general win
for the page reader: printed English pages at ~10 ms a page would remove
the 11 s wait that OCR_CYCLE exists to hide.

---

## Addendum 2026-09-11: caption-track fetch confirmed on a real target

Larry supplied https://youtu.be/fouffdu6dDk ("Heaven Isn't the Whole
Story", BLK SHP Bible Talk, 23:39, uploaded 2026-08-14). yt-dlp
2026.08.19 with `--skip-download --write-auto-sub --sub-format json3`
returned the English track in under two seconds: a 382 KB json3 file,
1433 text events, spanning the full 23:40. The video has NO manual
subtitles; the track is YouTube's automatic caption (en and en-orig),
which is exactly what the CC button renders. The text was reassembled
into a 24 KB plain-text transcript with no playback at all.

This reorders the options. For any video with a CC button, the caption
track is the primary source: seconds instead of hours, exact text, no
speed ceiling. The screen-capture route (Option A) stays as the fallback
for videos where the track cannot be fetched, and the audio route stays
as the fallback for videos with no captions.

For the Eiffel implementation the same track can be fetched without
yt-dlp: the endpoint is the player's timedtext URL, obtainable from the
watch page's player response (captionTracks[].baseUrl, append
&fmt=json3). simple_http fetches it, simple_json parses it. Two warnings
from the run: yt-dlp reported no JavaScript runtime and no impersonation
target, both irrelevant to subtitles today but a sign that YouTube's
page changes will need occasional repair. The json3 track itself is
clean: 717 text events, zero consecutive duplicates, no aAppend
roll-up events, 4465 words. The roll-up merge is a screen-route
concern only; the track needs plain concatenation.

### Members-only videos (tested 2026-09-11)

https://www.youtube.com/live/elAhMGTGn48 ("Understanding Goat Demons in
the Bible", What Your Pastor Didn't Tell You, live stream 2026-05-05,
1:04:55, availability subscriber_only). This is the video the 30-second
sample was clipped from; the fetched track opens with the same words the
screen OCR read.

- Anonymous fetch: refused ("Join this channel to get access to
  members-only content"). Title, channel, date and length are still
  served anonymously; only the player response is gated.
- With Larry's signed-in Edge session (`--cookies-from-browser edge`):
  3037 cookies read, track fetched, 703 KB json3, 3101 events, 7443
  words, 76 paragraphs, full 1:04:55. Speaker changes are marked `>>`.
- Two snags, both operational: Edge's startup boost keeps nine msedge
  processes alive after the last window closes and holds the cookie
  database open (Stop-Process -Name msedge -Force clears it, or turn
  startup boost off); and without a JavaScript runtime yt-dlp finds no
  video formats and aborts before writing subtitles unless
  `--ignore-no-formats-error` is given.

Design consequence: the caption-track path needs the user's YouTube
session for members-only content. In the Eiffel implementation that
means either reading the browser cookie store (fragile, locked by
startup boost, app-bound encryption in newer builds) or fetching the
track from inside the signed-in tab through DevTools, where the session
is already present. The screen-capture fallback needs neither.

---

## Design: video sources and GUI (2026-09-11, after both fetch tests)

Correction to the engine section above: Windows OCR is already in the
app. OCR_CYCLE launches winocr_boxes.ps1 through powershell.exe to get
word boxes for OCR_FIGURE_FINDER. The caption engine promotes that
out-of-process helper to an in-process WinRT call; it does not add a
new dependency.

### Three ways in, one transcript out

| Source | Open videos | Members-only | Speed | Text quality | Needs |
|---|---|---|---|---|---|
| 1. Caption track fetch | yes | only with the user's session | seconds | exact, with `>>` speaker marks | HTTP + JSON; session cookies for gated content |
| 2. Live caption capture (screen) | yes | yes, the tab is already signed in | playback time at 2x to 3x | OCR-exact after settle | region pick, Windows OCR in-process |
| 3. Audio (whisper) | yes | yes | slower than real time on CPU | worst; misheard names | audio loopback or a downloaded file |

All three feed one class, the transcript assembler: word-overlap merge
for source 2, plain concatenation for source 1, whisper segments for
source 3. One output file format, one findings log, one status strip.

Selection rule, in order, automatic unless the user pins a source:
try 1 anonymously; if the gate refuses, try 1 with the session if the
user has enabled that; else fall to 2, which needs the video playing
in the user's tab; 3 only on explicit request for caption-less videos.

### Session for members-only content

Two ways to carry the user's YouTube login into source 1:

- Browser cookie store. Works, as today's test showed, but the store is
  locked whenever Edge runs (startup boost keeps it running), and newer
  Chromium builds app-bind the encryption. A setting the user turns on
  knowingly, never a default.
- Fetch from inside the signed-in tab through DevTools. The session is
  already there, no cookie file is ever touched. Needs Edge or Chrome
  started with remote debugging, which the app can do itself.

Recommendation: cookie store first (small, proven today), DevTools
later as the durable route. Never write cookies to disk.

### GUI additions

A new tab, **Video**, beside Capture and Auto-advance. The existing
tabs stay as they are; books and videos do not share controls.

Video tab, top to bottom:

1. **URL** text box with a Fetch button. Below it a muted line that
   fills in after the probe: title, channel, length, and "open" or
   "members only".
2. **Source** radio: Caption track (recommended), Screen capture,
   Audio. Defaults to Caption track; greys out choices the probe rules
   out and says why in the muted line ("members only: needs your
   browser session, enable it in Engine").
3. **Screen capture group**, shown when that source is chosen:
   "Set Caption Region by Dragging..." (one region, drawn with the same
   outline machinery), a **Playback speed** combo of 1x, 2x, 3x with
   the ceiling explained in a muted line, and a Start/Stop button that
   reuses the auto-run's primary-button styling. The status strip shows
   cues seen, cues merged, cues dropped.
4. **Transcript preview**: a read-only text box showing the last few
   merged lines as they arrive, so a wrong region is visible in the
   first ten seconds rather than at the end.

Engine tab additions: a **YouTube session** section with one checkbox,
"Use my browser login for members-only videos", a browser picker (Edge,
Chrome, Firefox), and a Check button that reports whether the cookie
store is readable right now and names the blocking process if not.
A **Caption OCR** line stating "Windows OCR, in-process, no model" so
the user sees it costs nothing.

Output tab: unchanged file model. A video transcript goes to one file
named from the title, with the URL, channel, date, and source written
as a header, the way the two transcripts saved today are.

Findings tab: three new finding kinds with remedies. "Members-only gate
refused" (enable session or use screen capture). "Cookie store locked
by process N" (close it, or turn off startup boost). "Caption cues
dropped at 3x" (lower the speed).

Maintenance tab: nothing new. Screen capture writes no images, so the
image store has nothing to sweep.

### Build order, revised

1. Caption track fetch, anonymous: probe, fetch, concatenate, save.
2. Video tab with URL, probe line, source radio, output naming.
3. Session support for members-only, cookie store route, Engine tab
   section.
4. Windows OCR in-process engine, replacing the PowerShell helper for
   figures too.
5. Screen capture source: region, tick, fingerprint, settle, merge,
   speed combo, preview.
6. Audio source, last, behind simple_speech.

---

## Status 2026-09-11 (evening): steps 1 and 2 built, in pure Eiffel

Shipped in 1.12.0: OCR_HTTP speaks https; OCR_CAPTION_TRACK asks the
player endpoint as the Android client and reads the json3 track;
OCR_CAPTION_TEXT assembles paragraphs; OCR_VIDEO_RUN writes the file;
the Video tab and `--captions` drive it; OCR_SW_OUTPUT_PROMPT asks where
the text goes before any unattended run. Live on youtu.be/fouffdu6dDk:
4465 words, 22 paragraphs, one second, no Python, no browser.

Two findings that change the plan above:

- The watch page's caption URL (web client) answers 200 with an empty
  body; the Android client's URL works. The Eiffel path never touches
  the watch page.
- simple_json was unusable on the 391 KB track under DBC (quadratic
  invariants on SIMPLE_JSON_ARRAY, 158 s of CPU). Fixed in simple_json
  the same day: O(1) invariants and a SIMPLE_JSON_STREAM that reads
  in chunks; the events now stream through it.

Step 3 is re-decided: no cookie store and no yt-dlp. Larry's rule is a
100%-Eiffel product. The members-only route is a WebView2 sign-in
inside the app (simple_browser) with the player POST made from the
signed-in page, or the WebView2 cookie manager feeding OCR_HTTP. Steps
4 to 6 stand as written.
