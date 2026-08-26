# Feasibility: strip timing lines, figure extraction, Markdown transcript

Requested by Larry 2026-08-26, studied against the code as of v1.10.0.
Verdict up front: **all three are possible.** Nothing asked for is
blocked by a hard limit; the differences are only in how much design
each needs. Suggested build order: A (small) → B (small) → C (the
real work), each independently shippable.

---

## A. Strip lines: started / first estimate / drift — POSSIBLE, small

**What exists.** `OCR_RUN_METRICS` already owns everything the ask
needs: `start_time: DATE_TIME` (set by `note_start`), a pause-aware
wall clock (`elapsed_seconds` — pauses stop the clock by design), a
windowed page rate, `eta_minutes` and `finish_clock` ("finishing
about 9:44 PM"). The strip grows a line of height per caption line
automatically (`strip_line` is newline-separated; the sizing law is
already assaulted).

**What gets added.**

1. `started_stamp` — `start_time` formatted "started 7:58 PM Aug 26"
   (the `clock_of` formatter exists; add the date).
2. **First-estimate freeze** — the first time `has_eta` turns True,
   record `initial_eta_minutes`, `initial_finish: DATE_TIME`, and the
   elapsed seconds at which the estimate was made. Design choice:
   freeze the *first available* estimate rather than waiting for the
   window to settle — "how good was the first guess" is exactly the
   question being asked, warts included. (The windowed rate already
   sheds the cold-start penalty, so the first guess is not absurd.)
3. **Rolling drift** — every capture, compare the *current* projected
   finish against the frozen one:
   `drift_minutes = (elapsed + eta_minutes) - (elapsed_at_first + initial_eta)`.
   Displayed as e.g. `first ETA 10:04 PM · now +8m` (or `-3m` when
   the run is beating the guess). An accuracy percentage
   (`100 - |drift| / initial * 100`) is computable too; the signed
   minutes read better on a 320px strip.

**Testability.** The whole class is deliberately drivable through
`note_capture_at` with injected times and no clock; the freeze and
drift laws are pure additions testable the same way.

**Cost.** A few dozen lines in `OCR_RUN_METRICS`, two more strip
lines (the strip already grows), tests. No new dependencies.

---

## B. Markdown transcript — POSSIBLE, small (and mostly *unsuppression*)

**The pivotal fact.** The current prompt says *"Transcribe all text…
Output only the transcribed text, nothing else"* — it deliberately
suppresses structure. But olmOCR-2's native behavior (verified
against Ai2's own documentation) is to emit **Markdown**: headings as
Markdown, tables as HTML, math as LaTeX — **and it labels figures
and charts with markdown syntax in reading order**. MD mode is
largely a matter of *letting the model do what it already does*.

**What gets added.**

1. Settings: `output_format` — `txt` (default, today's behavior) or
   `md`. In md mode `Default_text_file_name` becomes
   `ocr_capture.md` (the name is already a setting).
2. Prompt swap in md mode: transcribe as markdown, keep figure
   labels. (The txt prompt stays exactly as-is — zero change to the
   shipped behavior.)
3. Writer: unchanged append flow; in md mode a page break can become
   a horizontal rule or heading if wanted.
4. **Dedup guard**: `OCR_TEXT_COMPARE.is_same_screen` (the
   "did the page actually turn?" tolerance compare) must compare
   *flattened text only* — its `flattened` step gains
   markdown-stripping (image links, emphasis, table tags) so figure
   lines and formatting jitter can never masquerade as progress.

**Cost.** Small. The risky part is only (4), and it is pure and
testable.

---

## C. Figure detection + extraction — POSSIBLE, the real work

**The pixels already exist.** Every capture is saved as
`ocr_*.png` — full page pixels on disk. Extracting a figure is a
*crop of an existing file*, and simple_cairo already does
sub-surface blits and `write_png` (the region picker is proof).
No new imaging machinery is needed.

**The key design decision: never ask an AI for coordinates.**
Qwen2.5-VL (olmOCR-2's base) does support grounding with JSON
bounding boxes — but through Ollama the resize parameters that make
its coordinates trustworthy are not settable, so VLM-reported boxes
arrive in an uncertain coordinate space. Rather than fight that,
the design splits the job:

1. **Detector — deterministic, local, fast.** Extend
   `winocr_label.ps1` (Windows.Media.Ocr) to also emit **per-word
   bounding boxes** (`OcrWord.BoundingRect` — the API already
   returns them; the script currently keeps only `.Text`). Run it on
   the full page (~0.3–0.5s, hidden entirely under the 7B model's
   seconds). Then, in pure Eiffel over the page surface's raw ARGB
   data: grid the page, mark cells that are inky-but-not-text
   (variance relative to the page's dominant background — so
   dark-mode readers work), dilate to bridge chart labels, flood-fill
   into rectangles, keep candidates above a size floor. Classical
   layout analysis, fully deterministic, testable with bare numbers
   like the band and handle laws.
2. **Classifier — AI, optional, coordinate-free.** Crop each
   candidate and ask the model one cheap question — *figure /
   photograph / chart, or just text and decoration?* A yes/no on a
   crop is immune to the coordinate-space problem and only runs when
   candidates exist (prose pages cost nothing).
3. **Placement — the model's own markers.** In md mode olmOCR-2
   emits figure labels *in reading order*. Pair the Nth marker with
   the Nth candidate top-to-bottom and replace the marker with
   `![Figure — p. 123](images/ocr_0123_fig1.png)`. On a count
   mismatch, fall back to position-ratio insertion, and as a last
   resort append the figures at the end of that page's block —
   degraded placement, never lost images.
4. **Storage.** Crops land in an `images/` folder beside the
   transcript, named by the existing `OCR_IMAGE_NAME` scheme plus a
   figure ordinal, so links are relative and the folder travels.

**Honest limits (the "not possible" list).**

- *Placement is heuristic.* Without coordinates from the
  transcription pass, a figure can land a paragraph off on unusual
  layouts. For single-column ebook pages — the actual use — the
  marker pairing should be right nearly always.
- *Screen pixels only.* The crop is exactly as sharp as the reader
  rendered it. No vector rescue, no upscaling. (If a book is
  figure-heavy, zooming the reader before those pages is the lever.)
- *Ollama-grounded coordinates are not trustworthy* — designed
  around, as above, not fought.
- *Figures made mostly of text* (dense tables styled as images) may
  classify either way; tables olmOCR-2 already transcribes as HTML,
  which md mode keeps, so little is lost either way.
- Windows OCR needs a language pack — already a dependency of the
  page-label reader, so nothing new.

**Empirical spikes before committing** (each an afternoon):
1. What olmOCR-2's figure markers actually look like on Larry's
   three readers (Kindle, ProQuest, Ebook Central pages).
2. Detector thresholds on real captured pages (the grid/variance
   knobs).
3. The classifier prompt's hit rate on real crops.

---

## Suggested plan

| Phase | Ships as | Size |
|---|---|---|
| A — strip timing lines | 1.11.0 | small |
| B — md transcript (no figures yet) | 1.12.0 | small |
| C — figure pipeline into md | 1.13.0 | the real work, gated on the three spikes |

A and B have no unknowns. C's unknowns are all empirically
answerable with the hardware and models already installed.
