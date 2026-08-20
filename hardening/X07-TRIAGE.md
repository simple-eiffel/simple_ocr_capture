# X07: Triage — simple_ocr_capture

Run: 2026-08-20 · Inputs: X03 contract assault, X06 mutation warfare

## What the attack phase actually produced

No crash, no memory error, no data-loss defect. That is worth stating plainly
rather than dressing up: **X03 deployed 13 contracts and every one held.** The
value came from elsewhere — three behaviours nobody had written down, and
eighteen places where the test suite was not watching.

Triage therefore splits into two piles: *behaviour to decide about* (X03) and
*defences to build* (X06).

## Pile 1 — behaviours found, awaiting a decision

| ID | Behaviour | Severity | Disposition |
|---|---|---|---|
| X03-001 | Last page of a book (`"416 of 416"`) yields no position | **Medium** | **Record, do not change** |
| X03-002 | Minus sign dropped: `"-5"` reads as `5` | Low | Record only |
| X03-003 | Two blank OCR reads compare as "same screen" | Low–Medium | Record only |

### X03-001 — why it is not being "fixed"

The one-character change is obvious: `>` becomes `>=`. It is being left alone
deliberately.

`OCR_PAGE_POSITION` exists because two predecessors read the indicator too
loosely and drove real runs wrong — one paired a page position with a location
total on every capture; another required a particular reader's wording and
rejected an entire book. Its whole design history is about **narrowing** what
counts as a pair. Widening it to admit `n of n` also admits `0 of 0`, `1 of 1`
from a misread, and any doubled number the model emits, in exchange for a
progress figure on the final page of a run — a page the user is by definition
about to see finish.

The cost of being wrong here is a bad ETA on every page; the benefit is a good
ETA on one. That trade is the user's to make, not mine. The behaviour is now
stated in the postcondition, asserted in the suite, and written down here.

### X03-003 — the honest description

Two blank reads stopping a run is *probably right*. The objection is not the
outcome, it is that the outcome is reached by accident — empty flattens to
empty, empty equals empty — and the message the user sees blames a failed page
turn when the real fault is the OCR returning nothing. A future change might
separate "the page did not turn" from "the model said nothing", which are
different problems with different remedies.

## Pile 2 — defence gaps, all actionable

Ordered by consequence if the code were wrong:

| Rank | Gap | Survivors | Consequence if the code broke | Action |
|---|---|---:|---|---|
| **1** | **GAP-A** store matching never executed | 3 | **Deletes the transcript.** The feature erases a book's images; nothing automated checked which files it selects | **Fix now** |
| 2 | GAP-B similarity threshold never reached | 6 | Unattended runs stop early or never stop | Fix now |
| 3 | GAP-D "largest total wins" not distinguished | 1 | Wrong ETA all run, the exact original bug | Fix now |
| 4 | GAP-C digit cap boundary untested | 3 | Integer overflow on a long counter | Fix now |
| 5 | GAP-E weak assertion admits a broken trim | 1 | Ugly file names | Fix now |
| 6 | GAP-F JSON control chars untested | 2 | Malformed request body from a pasted prompt | Fix now |
| 7 | GAP-G trailing space / leading underscore | 2 | Cosmetic | Fix now |

**GAP-A is rank 1 by a wide margin.** Every other gap costs a wrong number.
This one costs the user's transcript — the artefact the whole application
exists to produce. It survived because the eight store tests all exercise
*path arithmetic* and none of them puts a file on disk.

The behaviour had been verified by hand through the `--images` CLI verb against
a fixture with decoys. That verification was real, and it is also gone: it lived
in a terminal, not in the suite. Mutation testing is what turned "I checked it"
back into "it is checked".

## Not in scope

`OCR_MAIN_WINDOW` — 1926 lines, 35 features, 4 preconditions, no invariant.
The largest contract gap in the codebase, and untouchable by this workflow
because nothing can execute a window from a test runner. Recorded in X01,
deliberately not attempted here; adding contracts no test can reach would
inflate the numbers without adding a single defence.

## Decision

Fix all seven defence gaps. Change none of the three behaviours.

## Next step

→ X08-FIXES-LOG.md
