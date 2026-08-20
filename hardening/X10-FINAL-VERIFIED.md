# X10: Final Verification — simple_ocr_capture

Run: 2026-08-20 · Compiler: EiffelStudio 25.02.9.8732 · All results below are actual output.

## Headline

| Measure | Before hardening | After |
|---|---:|---:|
| Test classes | 0 (no test target existed) | **3** |
| Tests | 0 | **61** |
| Contracts on `OCR_PAGE_POSITION` | 1 postcondition, no invariant | **14 clauses** |
| Mutation score | — | **100%** (59/59 non-equivalent) |
| Production defects found | — | 0 |
| Behaviours documented | — | 3 |
| Production files changed | — | 1 (`ocr_page_position.e`, contracts only) |

## 1. Mutation score: 69% → 100%

Two full campaigns, 60 mutations each, one at a time: mutate → `ec.sh test` →
run the suite → classify → revert.

```
FIRST CAMPAIGN  (41 tests)   41 killed, 18 survived, 1 equivalent   ->  69%
FINAL CAMPAIGN  (61 tests)   59 killed,  1 survived, 1 equivalent   -> 100%
```

Final campaign, actual output:

```
exit=0
59            <- KILLED count
M43 arithmetic ocr_image_name.e       SURVIVED
```

The single survivor is **M43**, the one mutation classified equivalent before
either campaign ran: `a_text.count.min (Maximum_length)` to `.max (…)` inside
`create Result.make (…)`, which sets a STRING_32's initial **capacity** and
cannot change behaviour. It is not killable, because there is nothing to kill.

**Every non-equivalent mutation is now killed.** 0 skipped, 0 failed to compile,
across both campaigns.

### By category

| Category | First | Final |
|---|---:|---:|
| returns | 87% | **100%** |
| comparison | 70% | **100%** |
| arithmetic | 69% | **100%** |
| boolean | 66% | **100%** |
| boundary | 63% | **100%** |
| deletion | 62% | **100%** |

## 2. Every target builds

```
===== 1. TYPE CHECK =====
✓ Syntax and type check passed

===== 2. TEST SUITE =====
========================
Results: 61 passed, 0 failed
ALL TESTS PASSED

===== 3. GUI APPLICATION =====
✓ Built: EIFGENs/ocr_capture/F_code/simple_ocr_capture.exe

===== 4. HEADLESS CLI =====
✓ Built: EIFGENs/ocr_cli/F_code/simple_ocr_capture.exe
```

All F_code, contracts baked in.

## 3. No behaviour changed

The `--metrics` diagnostic output was captured before any contract was added
(`hardening/baseline-metrics.txt`) and compared after the whole pass:

```
===== 5. --metrics matches original baseline? =====
exit=0
IDENTICAL to pre-hardening baseline
```

14 contract clauses were added to a class that parses model output on every
capture, and its observable behaviour is byte-identical.

## 4. The destructive feature still works end to end

```
===== 6. --images end to end =====
folder: C:\Users\LJR19\AppData\Local\Temp\x10\Book
leaf:   Book
count:  3
size:   15 bytes
to: D:\Book
moved: 3  skipped: 0  failed: 0
```

Destination held `ocr_1.png ocr_2.png ocr_3.png`; the source folder retained
`ocr_capture.txt`. Cross-volume C: to D:, transcript untouched.

```
===== 8. --health exit code =====
exit=0
```

## 5. Nothing left behind

```
===== 10. no test litter anywhere =====
TEMP clean
D: clean
```

The 8 file-backed tests build fixtures under `%TEMP%\ocr_x08` and remove them,
including the shared root once the last one empties it. The user's configured
output folder is never touched by any test.

`git status` on `src/` after both campaigns: **empty**. Every one of the 120
applied mutations reverted.

## 6. Assertions are live in the shipped configuration

Re-stated because every number above depends on it. A deliberately false
invariant was injected and the finalized binary died:

```
simple_ocr_capture: system execution failed.
******************************** Thread exception *****************************
EXIT=1
```

Removed; clean run confirmed. `ec.sh test` finalizes with `-keep`, so contract
checking is present in the artefact, not only in a debug build.

## What this pass did NOT find

**No bugs.** No crash, no memory error, no data-loss defect, no wrong result.
Stating that plainly matters more than dressing it up: the code was already
correct in the areas reachable by this workflow.

What it found instead was **code nothing was watching** — and one finding there
was serious. Making `is_ocr_image` match every file left all 41 tests passing.
That mutation, in the feature that erases a book's images, would have deleted
the transcript. It survived because all eight store tests exercised path
arithmetic and none put a file on disk.

The behaviour had been verified by hand through the `--images` CLI verb against
a fixture with decoys. That verification was real — and it lived in a terminal,
not in the suite. Mutation testing is what turned "I checked it" back into "it
is checked".

## Behaviours recorded, deliberately not changed

| ID | Behaviour | Status |
|---|---|---|
| X03-001 | `"Page 416 of 416"` and `"1 of 1"` yield no position | pinned by test |
| X03-002 | `"Page -5 of 416"` reads as 5 | pinned by test |
| X03-003 | Two blank OCR reads compare as the same screen | pinned by test |

X03-001 is a one-character change (`>` to `>=`) that is being left to the user.
Widening the pairing rule also admits `0 of 0`, `1 of 1` from a misread, and any
doubled number the model emits, in exchange for a progress figure on the final
page of a run. The class's whole design history is about narrowing that rule
after two predecessors read the indicator too loosely and drove real runs wrong.

Each is asserted **as the code actually behaves**, so changing one is a
deliberate act that fails a named test. X06 showed two of them are the *sole*
killer of a mutation — pinning known behaviour is load-bearing, not commentary.

## Known gap, stated rather than papered over

`OCR_MAIN_WINDOW` — 1926 lines, 35 features, 4 preconditions, **no invariant**.
The largest contract gap in the codebase. Nothing can execute a window from a
test runner, so contracts added there would be unverified claims that raise a
count and defend nothing. Untouched on purpose, in X01, X07, X09 and here.

The same holds for `OCR_GUI`, `OCR_STATUS_STRIP`, `OCR_REGION_SELECTOR`,
`OCR_OUTLINE_SET`, `OCR_CAPTURE`, `OCR_CLICKER`, `OCR_HOTKEY`, `OCR_HTTP`,
`OCR_ENGINE`, `OCR_RUNTIME`, `OCR_HEALTH`, `OCR_PREFLIGHT`.

**The 100% score is over the pure-logic classes, not the application.** Read it
as "the tests that exist have teeth", not "the application is verified".

## Deviation from the workflow as written

`00-INDEX-MAINTENANCE-XTREME.md` mandates:

```bash
/d/prod/ec.sh -batch -config {lib}.ecf -target {lib}_tests -c_compile
./EIFGENs/{lib}_tests/W_code/{lib}.exe
```

Raw compiler flags and W_code are both blocked by current build standards. This
entire pass used `ec.sh check` / `ec.sh test` and
`EIFGENs/simple_ocr_capture_tests/F_code/`. The index should be updated.

## Artefacts

| File | What it is |
|---|---|
| `hardening/X01-RECON-ACTUAL.md` | attack surface, per-class contract density |
| `hardening/X02-VULNS-ACTUAL.md` | 29 vulnerability vectors assessed |
| `hardening/X03-CONTRACTS-LOG.md` | 13 contracts deployed, live-assertion proof |
| `hardening/X06-MUTATION-LOG.md` | first campaign, 69%, 7 root-cause gaps |
| `hardening/X07-TRIAGE.md` | ranked decisions |
| `hardening/X08-FIXES-LOG.md` | 8 fixes, including one wrong first attempt |
| `hardening/X09-HARDENING-LOG.md` | permanent defences |
| `hardening/X10-FINAL-VERIFIED.md` | this file |
| `hardening/mutate.py` | the harness, committed and re-runnable |
| `hardening/baseline-metrics.txt` | pre-hardening behaviour |
| `hardening/X10-final-campaign.txt` | final campaign raw output |

X04 was satisfied by `testing/adversarial_tests.e` (35 assault tests).
**X05 stress-attack was not run** — no stress scenario in this application is
meaningful without a screen and an OCR server.
