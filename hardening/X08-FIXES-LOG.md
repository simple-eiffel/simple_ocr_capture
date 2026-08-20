# X08: Surgical Fixes — simple_ocr_capture

Run: 2026-08-20 · Input: X07 triage

## What "fix" means here

X06 found no broken code. It found **code nothing was watching**. So every fix
in this phase adds a defence rather than changing behaviour — and that is the
correct response to a surviving mutation, not a lesser one.

**No production source was modified in X08.** The only `src/` change in this
whole hardening pass is the 13 contracts added in X03. That is deliberate: a
mutation survivor is evidence about the *tests*, and "fixing" it by rewriting
working code would be the wrong lesson.

## Fix 1 — GAP-A: put real files on disk (rank 1)

**New class `testing/store_file_tests.e`, 8 tests.**

Each builds a fixture under `%TEMP%\ocr_x08\<name>`, exercises the store
against it, and removes it. Nothing touches the user's configured output folder.

| Test | What it defends |
|---|---|
| `test_matches_only_ocr_images` | The whitelist. Three images against five decoys — transcript, sidecar, findings, cover, notes — each asserted present or absent by name |
| `test_directory_named_like_an_image_is_not_one` | `is_plain_file`, with a real `ocr_folder.png` directory |
| `test_counts_and_size_reflect_the_folder` | `image_count` and `total_bytes` against known byte counts |
| `test_empty_folder_reports_nothing` | The no-images path |
| `test_delete_removes_images_and_spares_the_rest` | Deletion, asserting the decoys are **still on disk afterwards** |
| `test_move_transfers_content_and_leaves_decoys` | A move, asserting the bytes arrived and the source is gone |
| `test_move_skips_a_collision_rather_than_overwriting` | The archive file still reads `ORIGINAL archive`; the skipped source is kept |
| `test_move_onto_itself_is_refused` | The self-move guard, with the file intact afterwards |

This is the fix that matters. The delete/move feature can now break only by
breaking a test.

## Fix 2 — GAP-B: reach the similarity threshold

Four tests added to `ADVERSARIAL_TESTS`. The key one constructs text that is
**similar but not identical** — 100 characters differing at one interior
position — which is the band the class exists for and which no previous test
entered:

```eiffel
l_a := repeated ('a', 60) + "X" + repeated ('b', 39)
l_b := repeated ('a', 60) + "Y" + repeated ('b', 39)
assert_false ("not identical", l_a.same_string (l_b))
assert_true  ("above threshold is same screen", l_cmp.is_same_screen (l_a, l_b))
```

Every earlier comparison test either flattened to an exact match — so
`same_string` returned early and the scoring line never executed — or differed
wildly, so any threshold rejected it. Six mutations lived in that blind spot.

Also added: a below-threshold case, a direct pin on `Similarity_percent = 97`
(previously an unverified constant), and a trailing-space test for
`right_adjust`.

## Fix 3 — GAP-D: distinguish "largest total wins"

```eiffel
l_reader.set_from ("Location 890 of 8890  Page 12 of 170")
assert_integers_equal ("largest total wins", 8890, l_reader.total)
```

The existing test put the largest pair **last**, so it could not tell the
class's actual rule from "keep the last pair". This one puts the largest
**first**. It defends the exact bug the class was rewritten to fix.

## Fix 4 — GAP-C: make the digit cap do observable work

The old overflow test used 10- and 11-digit values that `is_integer` rejects on
its own, so the nine-digit cap was never the thing doing the rejecting. Two new
tests use values that **fit in INTEGER_32**:

- `1000000000 of 2000000000` — ten digits, fits, must be **refused** by the cap
- `100000000 of 200000000` — nine digits, must be **accepted**

Together they pin the cap at exactly nine from both sides.

## Fix 5 — GAP-E: assert the result, not the symptom

`test_name_never_ends_in_underscore` checked only that the last character was
not `_`. A mutation replacing the trim with an append produced
`"Page_12_of_99_x"`, which satisfies that. Added:

```eiffel
assert_true ("trimmed exactly", l_result.same_string ({STRING_32} "Page_12_of_99"))
```

## Fix 6 — GAP-F: JSON control characters

Two tests. One builds a string containing `0x01` and asserts the output holds
`\u0001`; one asserts printable text passes through untouched. The OCR prompt is
user-editable text that lands in exactly this path, and it had one test covering
quotes.

## Fix 7 — GAP-G: leading underscore and trailing space

`test_name_never_begins_with_underscore` (input `"...Page 12"`, asserting exactly
`"Page_12"`) and `test_flattened_strips_trailing_space`.

## Fix 8 — the last two survivors, and one wrong first attempt

The first re-run left three survivors: M24, M37 and the known equivalent M43.

**M24** — `>=` to `>` on the scoring line — needed a case sitting *exactly* on
the threshold, which nothing had. 97 matching leading characters out of 100,
with the trailing three differing so the tail contributes nothing:

```eiffel
l_a := repeated ('a', 97) + "XYZ"
l_b := repeated ('a', 97) + "PQR"
assert_integers_equal ("exactly at the threshold", 97, l_cmp.agreement_percent (l_a, l_b))
assert_true ("threshold is inclusive", l_cmp.is_same_screen (l_a, l_b))
```

Killed on the next run.

**M37** — `min` to `max` when choosing which text to measure against — took two
attempts, and the failure is the more useful half.

The first attempt compared 100 characters against 110 of the same character,
reasoning that `min` and `max` would then differ and the verdict would flip.
It did not: **the tail cap is derived from the same variable.** With `max`, the
`l_shorter - l_head` limit loosens by exactly the amount the denominator grows,
the extra characters all match, and the two versions agree. The mutation
survived the "fix" aimed at it.

The distinguishing case needs the longer text to differ in its *suffix*, so the
loosened tail cap finds nothing to count:

```eiffel
l_short := repeated ('a', 100)
l_long  := repeated ('a', 100) + repeated ('b', 100)
```

Original: measures against 100, scores 100% -> same screen.
Mutated: measures against 200, tail finds nothing, scores 50% -> different screen.

That is worth recording because it is the trap mutation testing sets for the
person answering it: a test can *look* aimed at a mutation and still not
discriminate. The only reliable check is to re-run the mutation and watch it
die. Both of these were re-run individually and confirmed KILLED before the
final campaign.

## Fixture hygiene

The first run of the new store tests left two empty directories in `%TEMP%`.
Teardown now removes the destination root and the shared root once empty:

```
=== litter check ===
clean - nothing left behind
```

Empty shells are harmless, but a temp folder that accumulates across runs is how
a fixture starts finding files it did not create.

## Result

| | Before | After |
|---|---:|---:|
| Test classes | 2 | 3 |
| Tests | 41 | **61** |
| Production files changed | — | **0** |

```
========================
Results: 61 passed, 0 failed
ALL TESTS PASSED
```

## Next step

→ X09-HARDENING-LOG.md
