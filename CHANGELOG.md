# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/simple-eiffel/simple_ocr_capture/compare/v1.6.0...HEAD
[1.6.0]: https://github.com/simple-eiffel/simple_ocr_capture/releases/tag/v1.6.0
