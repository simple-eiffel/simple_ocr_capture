# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [1.9.0] - 2026-08-25 — the region picker no longer locks the session

Critical fix. In 1.8.0, pressing any of the three "drag a region"
buttons froze the entire Windows session: crosshair cursor, a desktop
that ignored every click and key, and nothing short of Ctrl+Alt+Del
and signing out would end it.

### The cause

`simple_shell.h` kept its shared state - the event queue, the window
handles - as file-scope `static` data in a header included by the
inline externals of five classes. Finalized C compiles each class
into its own translation unit, and every unit gets a PRIVATE copy of
every static. The overlay's window procedure pushed its events
(mouse, Escape, right-click) into SHELL_OVERLAY's copy of the queue;
the pump drained SHELL_WINDOW's. Nothing ever arrived. The topmost
fullscreen picker sat over every monitor eating all input, with no
handler left alive to dismiss it. (Pre-1.8.0 builds were immune by
accident: all the C lived in one class, hence one unit.)

### Fixed

- **simple_shell 1.6.0**: every mutable global in `simple_shell.h`
  is now `SHELL_SHARED` (`__declspec(selectany)`) - linker-merged
  into ONE process-wide instance regardless of how many generated
  files include the header. A regression test pushes a marker event
  from one class's translation unit and drains it through another's;
  it cannot pass on the 1.8.0 arrangement. Shell assault 13/13.
- **Escape hatches below the Eiffel loop**: the overlay window
  procedure hides the overlay ITSELF on Escape, right-click and
  Alt+F4 before reporting the cancel; a dead-man watchdog thread
  reads the physical Escape key (GetAsyncKeyState - no focus, no
  queue needed) - held ~2 seconds posts the cancel, still visible at
  ~5 exits the process. Losing the application beats losing the
  session.
- **simple_widgets**: modal surfaces (dialogs, popup menus,
  pick-and-drop) no longer swallow shell events (21..23 strip, 25
  fast tick, 31..35 overlay). A health dialog opening mid-drag would
  have trapped the user under the overlay a second way; now Escape
  still lands, and the capture clock keeps ticking behind any
  dialog. Widgets assault 193/193.

### Added

- **The build is always checkable**: the title bar carries the
  version ("Simple OCR Capture 1.9.0"), and a menu bar arrives with
  Help -> About - a composed modal panel (title, version and build
  date, an AI-models section naming the OCR model, endpoint and
  page-label reader straight from live settings, the substrate, and
  the picker's escape hatch), built from labels, labelled separators
  and fact rows rather than one wrapped text run. OCR_VERSION is the
  one authoritative mark; keep it in step with the installer's
  AppVersion at every release.

### Also healed by the same root cause

- Status strip clicks (the transport corner), drag-position memory
  and expose repaints - their events (21..23) were going into a
  third orphaned copy of the queue in 1.8.0.
- The clipboard now opens against the real window handle instead of
  a translation unit's null copy of it.

### If it ever wedges again

Escape held five seconds force-quits the application from a watchdog
thread even if its event loop is gone. And independent of this app:
Ctrl+Win+D opens a fresh virtual desktop (the overlay stays behind),
from which Task Manager can end the process - no sign-out needed.


## [1.8.0] - 2026-08-23 — rebuilt on simple_widgets

The Vision2 GUI is being rebuilt on simple_widgets / simple_shell /
simple_cairo — the very libraries whose platform C this application
seeded (its ocr_cairo_win.h became simple_shell). Phase ledger:

- **Phase 1 (substrates)**: simple_shell 1.3.0 grew SHELL_OUTLINES
  (click-through frame regions — the desktop outlines without the
  four-popup-edges trick) and renumbered overlay events out of the
  main window's namespace; simple_widgets grew the
  set_on_shell_event seam for app-owned windows.
- **Phase 2 (capture)**: OCR_GRAB replaces the capture engine's
  Vision2 half — SW_SCREEN BitBlt grab, cairo PNG, a forty-line BMP
  writer, CAIRO_SURFACE thumbnails. `--shot` no longer creates an
  EV_APPLICATION: workers are truly windowless. Proven end-to-end:
  a real screen grab OCR'd through the local model. Engine suite
  61/61 throughout.
- **Phase 3 (regions)**: OCR_SW_SELECTOR - the frozen-desktop drag
  picker on SHELL_OVERLAY, painted with a full SW_PAINTER through
  the overlay DC (dim wash, band re-lit, banner); the band law is
  pure and assaulted with bare numbers (any drag direction names
  the same box; a tap is a cancel). OCR_SW_OUTLINES - the three
  region outlines as click-through frame windows (colour AND wall
  thickness separate them; frames sit OUTSIDE the region so walls
  never enter a capture). Suspend/resume proven with REAL windows.
  Suite 63/63.
- **Phase 4 (the strip)**: OCR_SW_STRIP on SHELL_STRIP - stage
  lights, caption, thumbnail, page/rates beneath it, and the
  play/pause/stop transport from the drawn-glyph set, all painted
  through the strip DC. Dragging is the C side gift (native
  HTCAPTION outside the transport corner); event 22 persists where
  it lands. Sizing laws and the transport zone assaulted - including
  the cross-layer pin that the transport lives inside the C no-drag
  corner. Suite 64/64.
- **Phases 5+6 (the window, and THE FLIP)**: OCR_SW_MAIN_WINDOW -
  the whole settings surface as tabs (Capture, Auto-advance, Output,
  Engine, Findings, Maintenance) over one status line; findings in a
  real data grid; every confirm flow a drawn-modal CONTINUATION;
  the preview an SW_IMAGE over the grab's thumbnail. OCR_SW_GUI -
  the same composition root and agent seams, clocked by
  simple_shell's new 50ms fast timer, routing overlay events to the
  selector and strip events to the strip. simple_shell 1.4.0 grew
  the fast timer, a programmatic window close, and a WINDOWLESS
  pump (--outline now shows its magenta frame with no application
  object at all). VISION2 IS GONE from the ECF; seven EV classes
  deleted; ocr_cycle/ocr_auto_run capture through OCR_GRAB. The
  installer's exe/cairo.dll sources now point at the real target.
  One launch crash caught BY CONTRACT (rrect radius 0 violates
  cairo's positive_radius - three squares wanted to be squares) and
  fixed. Engine suite 64/64; app runs.


## [Unreleased]

## [1.8.0] - 2026-08-21

The cairo face becomes the product.

### Added

- New GUI built on simple_cairo and pure Win32 - no Vision2, no GTK. Full
  parity with the classic window plus the floating status strip: live page
  position, rate, ETA, finish time, six-dot health trail, transport controls.
- Page-indicator OCR via Windows.Media.Ocr (`winocr_label.ps1`, run by the
  inbox Windows PowerShell 5.1): the five-word label reads in ~0.3 s instead
  of seconds through the 7B model, taking the label leg off the critical
  path. Falls back to the model worker when the script is absent.
- The exe is its own OCR worker: headless flags dispatch past the GUI into
  the classic CLI, so the installed binary spawns itself for `--worker` and
  `--label-worker`. The installer now ships exe + cairo.dll + winocr_label.ps1.
- Session log (`ocr_cairo_session.log`) replaces console prints; label reads
  and harvests are logged per page; worker failure reasons reach the strip.

### Fixed

- Run engine now mirrors the classic harvest: sidecar collection,
  `[OCR FAILED]` refusal, byte-identical retry skip, capture headers, and a
  per-page settings store so `capture_index` survives relaunches.
- End-of-book detection requires two consecutive unchanged re-grabs, one
  settle period apart - a slow page render no longer ends the run early.

## [1.7.0] - 2026-08-20

### Added

- **Delete Images** and **Move Images** buttons in the settings window, for
  clearing a finished book's screenshots out of the output folder or moving
  them onto a roomier drive. Both match `ocr_*.png` and `ocr_*.bmp` only, so
  the transcript, the `.sidecar.txt` files and the `.findings.jsonl` are never
  touched, and both confirm with a count and a total size before doing anything.
- **Move to drive** setting, persisted. The destination is that drive plus the
  output folder's own name - `D:` with `C:\Books\Boyarin` gives `D:\Boyarin` -
  and the full path is shown in the confirmation before anything moves.
- `--images list|delete|move <folder> [drive]` and `--settings [drive]` headless
  verbs, so the above is testable without a GUI.

### Testing

- **Test target `simple_ocr_capture_tests`**, following the ecosystem pattern:
  `TEST_APP` console runner over `LIB_TESTS` and `ADVERSARIAL_TESTS`, both on
  `TEST_SET_BASE` from simple_testing. **61 tests, all passing.** Run with
  `./build.sh -t`.
- **Contract assault (maintenance-xtreme X01-X03)** on the pure-logic classes.
  13 new contracts on `OCR_PAGE_POSITION`, which previously had no invariant at
  all and no preconditions. All 13 hold and stay as hardening. Evidence in
  `hardening/`.
- **Mutation warfare (X06) and hardening (X07-X10).** Two full 60-mutation
  campaigns, one mutation at a time, each compiled and run against the suite.
  The first scored **69%** and exposed that the delete/move feature had no test
  touching a real file - making the image matcher accept every file left all 41
  tests passing, which would have deleted the transcript. 20 tests added,
  including 8 file-backed ones. Final score **100%** of non-equivalent
  mutations. The harness ships as `hardening/mutate.py`.

### Known behaviour recorded

- `OCR_PAGE_POSITION` returns **no position for the last page of a book**
  ("Page 416 of 416") or a single-page document ("1 of 1"), because a pair
  requires the total to be strictly greater than the position. Documented in
  `hardening/X03-CONTRACTS-LOG.md` as finding X03-001 and asserted in the test
  suite, so changing it is a deliberate act. Not changed.
- A minus sign in an indicator is dropped: "Page -5 of 416" reads as 5 (X03-002).
- Two blank OCR reads compare as "the same screen", so a twice-failing model
  stops an unattended run reporting a failed page turn (X03-003).

### Notes

- A move copies, re-checks the destination size, and only then removes the
  original: `copy_to` reports nothing, so deleting on faith would lose images
  to a full disk. A file already present at the destination is skipped rather
  than overwritten, and one unreadable file no longer abandons the batch.

## [1.6.0] - 2026-08-19

First release published to GitHub. The application had been developed and
shipped as an installer for several months before the source was moved into a
repository, so the entries below describe the state at 1.6.0 rather than the
change made in it.

### Capture

- Drag-to-set capture region, with Esc/right-click to cancel
- System-wide hotkey (Ctrl+Alt+G by default)
- Region outlines drawn on the desktop for all three rectangles, each with its
  own colour and dash pattern, suspended automatically around the shutter so
  they are never photographed into the capture
- Images named from the reader's page indicator rather than a bare counter
- PNG or BMP output

### Unattended runs

- Auto-advance: click the page-turn button, capture, repeat
- A page that will not turn stops the run instead of clicking blindly on
- Text identical to the block just written is not appended again
- Clicks restore the pointer position and foreground window

### Output and diagnostics

- Single appended transcript file, with optional per-capture header lines
- Progress strip with scan rate, page rate and ETA
- Findings grid fed by both the running application and `--audit`
- Run log recording each page's starting rectangles and decisions
- Output folder is never created silently — a missing path is confirmed first

### Platform

- Ships as a single executable: no runtime, no redistributable, no Python
- Talks to Ollama over WinHTTP rather than libcurl, so there is nothing to
  redistribute and no runtime DLL resolution to fail
- Starts and supervises the Ollama server itself
- Per-user install, no UAC prompt

## Earlier releases

These shipped as installers before the repository existed. Detailed notes were
not kept; the dates are those of the published installer artifacts.

| Version | Date |
|---|---|
| 1.5.0 | 2026-08-18 |
| 1.4.0 | 2026-08-17 |
| 1.3.0 | 2026-08-14 |
| 1.2.3 | 2026-08-10 |
| 1.2.2 | 2026-08-09 |
| 1.2.1 | 2026-08-08 |
| 1.2.0 | 2026-08-08 |
| 1.1.0 | 2026-08-08 |
| 1.0.0 | 2026-08-06 |

[1.9.0]: https://github.com/simple-eiffel/simple_ocr_capture/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/simple-eiffel/simple_ocr_capture/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/simple-eiffel/simple_ocr_capture/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/simple-eiffel/simple_ocr_capture/releases/tag/v1.6.0
