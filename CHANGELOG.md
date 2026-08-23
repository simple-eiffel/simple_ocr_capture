# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased] — the simple_widgets rebuild (in flight)

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

[Unreleased]: https://github.com/simple-eiffel/simple_ocr_capture/compare/v1.7.0...HEAD
[1.7.0]: https://github.com/simple-eiffel/simple_ocr_capture/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/simple-eiffel/simple_ocr_capture/releases/tag/v1.6.0
