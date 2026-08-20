# X03: Contract Assault — simple_ocr_capture

Run: 2026-08-20 · Target: `simple_ocr_capture_tests` · Compiler: EiffelStudio 25.02.9.8732

## Scope

Pure-logic classes only — those exercisable without a screen, a system-wide
hotkey or an OCR server:

`OCR_PAGE_POSITION` · `OCR_TEXT_COMPARE` · `OCR_IMAGE_NAME` · `OCR_JSON_UTIL` · `OCR_IMAGE_STORE`

The GUI classes (`OCR_MAIN_WINDOW`, `OCR_GUI`, `OCR_STATUS_STRIP`,
`OCR_REGION_SELECTOR`, `OCR_OUTLINE_SET`) are out of scope: contracts can be
added to them, but nothing can execute them from a test runner, so a "PASS"
would mean only that the code never ran.

## Assertions are live — proved, not assumed

A passing contract is worthless if assertions are compiled out. Before trusting
any result below, a deliberately false invariant was injected:

```eiffel
DELIBERATELY_FALSE_probe: pair_count = -12345
```

Built with `ec.sh test` (finalize `-keep`) and run:

```
--- indicator reader ---

simple_ocr_capture: system execution failed.
Following is the set of recorded exceptions:
******************************** Thread exception *****************************
In thread           Root thread            0x0 (thread id)
EXIT=1
```

The probe was then removed and the clean run confirmed (`EXIT=0`). **Contract
checking is active in the shipped configuration.**

## Contracts deployed

### Invariant assault — `OCR_PAGE_POSITION`

The class carried **no invariant at all**. Seven clauses added:

| Contract | Axis | Result |
|---|---|---|
| `position_not_negative: position >= 0` | range | PASS |
| `total_not_negative: total >= 0` | range | PASS |
| `pair_count_not_negative: pair_count >= 0` | range | PASS |
| `consistent: has_total implies has_position` | relationship | PASS |
| `ordered: has_total implies total > position` | relationship | PASS |
| `quiet_when_absent: not has_position implies position = 0` | semantic | PASS |
| `paired: has_position = has_total` | relationship | PASS |

### Postcondition assault — `OCR_PAGE_POSITION.set_from`

Six clauses added to the existing three:

| Contract | Axis | Result |
|---|---|---|
| `position_positive: has_position implies position > 0` | range | PASS |
| `found_implies_pair: has_total implies pair_count > 0` | semantic | PASS |
| `none_implies_quiet: pair_count = 0 implies not has_position` | semantic | PASS |
| `total_bounded: has_total implies total <= Maximum_value` | range | PASS |
| `quiet_position: not has_position implies position = 0` | old/semantic | PASS |
| `quiet_total: not has_total implies total = 0` | old/semantic | PASS |

**Contracts deployed: 13. Contract failures: 0.**

Every assault contract held. They stay as permanent hardening.

## Findings

No contract *failed*, but the adversarial probes that accompanied them exposed
three behaviours worth recording. All three are asserted in
`testing/adversarial_tests.e` **as the code currently behaves**, so that
changing any of them is a deliberate act that shows up as a test failure.

### X03-001 — The last page of a book reads as nothing

`OCR_PAGE_POSITION.set_from` requires the total to be **strictly greater** than
the position (`ocr_page_position.e`, pairing loop):

```eiffel
l_values.i_th (k + 1) > l_values.i_th (k)
```

Consequences, confirmed by execution:

```
[Page 416 of 416] -> nothing (correct - not enough numbers)
[1 of 1]          -> nothing (correct - not enough numbers)
```

So the **final page of every book**, and **any single-page document**, produce
no position at all — precisely when a progress readout and an ETA matter most.
The strip loses its figures on the last page of a run.

Severity: **low impact, high surprise.** Nothing breaks; the reader simply goes
quiet. The postcondition `ordered` now states the behaviour explicitly, where
before it was an unstated consequence of a comparison operator.

Fix, if wanted: relax to `>=` and adjust `ordered` to `total >= position`. Not
applied — it widens what counts as a pair, and the class's whole design history
is about *narrowing* that. Deliberately left for a decision.

### X03-002 — A minus sign is silently dropped

```
[Page -5 of 416] -> 5 of 416
```

Digit runs are collected without surrounding punctuation, so `-5` and `5` are
indistinguishable. Harmless in practice — a negative page cannot occur — but it
means the extractor cannot report that it saw something malformed.

### X03-003 — Two blank OCR reads compare as "the same screen"

`OCR_TEXT_COMPARE.is_same_screen ("", "")` is `True`, and
`agreement_percent ("", "")` is `100`.

A model returning nothing twice therefore reads as *"the page did not turn"*
and stops an unattended run. That is arguably the right outcome — a run
producing no text should stop — but it is reached by accident (both flatten to
empty, and empty equals empty) rather than by decision, and the stop message
will blame a failed page turn rather than a failed OCR.

## Contracts that passed

All 13. Retained as hardening. Of note, `paired: has_position = has_total`
holding across every probe confirms the two booleans are **always equal** —
`OCR_PAGE_POSITION` exposes two queries where one would do. A simplification
opportunity, not a bug; not applied, since both are used by callers.

## VERIFICATION CHECKPOINT

### Compilation

```
=== TEST MODE (finalize -keep) ===
Running: ec.exe -batch -config simple_ocr_capture.ecf -target simple_ocr_capture_tests -finalize -keep -c_compile
Eiffel Compilation Manager
Version 25.02.9.8732 - win64
...
C compilation completed
✓ Built: EIFGENs/simple_ocr_capture_tests/F_code/simple_ocr_capture.exe
```

### Test execution

Full output in `hardening/test-run.txt`.

```
========================
Results: 41 passed, 0 failed
ALL TESTS PASSED
```

### Results

- Tests run: **41**
- Tests passed: **41**
- Tests failed: **0**
- Contracts deployed: **13**
- Contract failures: **0**
- Findings recorded: **3** (X03-001, X03-002, X03-003)
- Errors: None

## Deviation from the workflow as written

`00-INDEX-MAINTENANCE-XTREME.md` mandates:

```bash
/d/prod/ec.sh -batch -config {lib}.ecf -target {lib}_tests -c_compile
./EIFGENs/{lib}_tests/W_code/{lib}.exe
```

Both are **blocked** by current ecosystem build standards — raw compiler flags
bypass F_code enforcement, and `W_code` is EiffelStudio intermediate code. This
run used `ec.sh test` and `EIFGENs/simple_ocr_capture_tests/F_code/`. The index
should be updated.

## Next step

→ X04-ADVERSARIAL-TESTS (already partly satisfied: `testing/adversarial_tests.e`
holds 24 assault tests). Then X05 stress, X06 mutation.
