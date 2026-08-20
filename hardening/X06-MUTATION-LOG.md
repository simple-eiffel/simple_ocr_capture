# X06: Mutation Warfare — simple_ocr_capture

Run: 2026-08-20 · Harness: `hardening/mutate.py` · Raw data: `hardening/X06-results.json`

## Method

60 mutations, applied **one at a time**: mutate → `ec.sh test` (finalize `-keep`)
→ run the 41-test suite → classify → revert. The harness reverts in a `finally`
block and refuses to apply a mutation whose anchor text is not unique in the
file, so a mutation can never silently land somewhere other than intended.

`git status` on `src/` was empty after the campaign: every mutation reverted.

Verdicts:

- **KILLED** — the suite reported a failure, or the binary died on a contract
- **SURVIVED** — the suite passed with the bug in place ← a weakness
- **EQUIVALENT** — no behavioural difference; excluded from the score

## Mutation Summary

- Total mutations: **60**
- Failed to compile: **0**
- Killed: **41**
- Survived: **18**
- Equivalent: **1**
- **Mutation score: 41 / 59 = 69%**

Interpretation per the workflow scale: **Good, but has gaps** (70–89% is "good";
this lands just under).

## Results by Category

| Category | Killed | Survived | Equivalent | Score |
|---|---:|---:|---:|---:|
| returns | 7 | 1 | 0 | **87%** |
| comparison | 7 | 3 | 0 | 70% |
| arithmetic | 9 | 4 | 1 | 69% |
| boolean | 6 | 3 | 0 | 66% |
| boundary | 7 | 4 | 0 | 63% |
| deletion | 5 | 3 | 0 | 62% |
| **TOTAL** | **41** | **18** | **1** | **69%** |

Strongest: **returns** — gutting a function's result is caught almost every time.
Weakest: **deletion** and **boundary** — removing a guard, or moving a limit by
one, is what this suite is least likely to notice.

## Surviving Mutations — grouped by root cause

### GAP-A — `OCR_IMAGE_STORE`'s file matching is never executed (3 survivors)

**The most serious finding of the campaign.**

| ID | Mutation | Effect if real |
|---|---|---|
| M50 | `is_ocr_image` returns True for **every** file | delete/move would sweep up the transcript, the `.sidecar.txt` files and `.findings.jsonl` |
| M51 | prefix `and then` extension → `or else` | any `.png` in the folder matches, including a cover scan the user put there |
| M56 | `joined` stops inserting the path separator | every path malformed |

Root cause: the 8 store tests exercise **path arithmetic only**
(`leaf_name`, `destination_folder`, `has_usable_leaf`). Not one of them puts a
real file on disk, so `is_ocr_image`, `is_plain_file` and `joined` are never
called by the suite at all.

The behaviour *was* verified — by hand, through the `--images` CLI verb, against
a fixture with decoy files. But that verification is not in the suite, so
nothing defends it from here on. **This is exactly the gap mutation testing
exists to find:** hand-verified once, unprotected forever.

### GAP-B — the similarity threshold path is never reached (6 survivors)

M24, M25, M26, M35, M36, M37 — every mutation to the `is_same_screen` scoring
line survives, including turning the threshold into 50%, into 100%, changing
`+` to `-`, and changing `min` to `max`.

Root cause: every comparison test either **flattens to an exact match** (so the
`same_string` early return fires and the scoring line never runs) or is
**wildly different** (so any threshold rejects it). There is no test in the
band that matters — *similar but not identical*, which is the entire reason the
class exists.

`Similarity_percent = 97` is currently an unverified constant.

### GAP-C — the digit cap boundary is untested (3 survivors)

M05 (`<=` → `<`), M06 (cap 9 → 11), M22 (cap 9 → 12). The only overflow test
uses 10- and 11-digit numbers that `is_integer` rejects anyway, so the cap
itself is doing no observable work in the suite. A 10-digit value that *does*
fit in INTEGER_32 (e.g. `1000000000 of 2000000000`) would distinguish them.

### GAP-D — "largest total wins" is not actually verified (1 survivor)

M12 flips `not has_total or else …` to `has_total or else …`, which makes the
loop keep the **last** pair rather than the **largest**. It survives because in
`test_position_largest_total_wins` the largest pair *is* the last one:

```
"Page 12 of 170  Location 890 of 8890"   ->  (12,170), (890,8890)
```

The test that exists to prove the class's central design decision does not
distinguish it from a much simpler rule. A case where the largest total comes
**first** is needed.

### GAP-E — weak assertion lets a broken trim through (1 survivor)

M46 replaces `Result.remove_tail (1)` with `Result.append_character ('x')` in
the trailing-underscore trim. `test_name_never_ends_in_underscore` only asserts
that the last character is not `_` — and `"Page_12_of_99_x"` satisfies that. The
assertion checks the symptom, not the result.

### GAP-F — JSON control-character escaping is untested (2 survivors)

M59 (`c.code < 0x20` → `> 0x20`) and M60 (`// 16` → `\\ 16`). The single JSON
test covers quotes only. Control characters in a `\u00XX` escape are unexercised,
and the OCR prompt is user-editable text that lands in exactly that path.

### GAP-G — miscellaneous (2 survivors)

- **M39** — deleting `Result.right_adjust` from `flattened`. No test has trailing
  whitespace that survives collapsing.
- **M44** — `and then` → `or else` in the leading-underscore guard, which lets a
  name begin with `_`. No test starts with punctuation followed by text.

## Equivalent mutations

- **M43** — `a_text.count.min (Maximum_length)` → `.max (…)` in
  `create Result.make (…)`. This sets the initial **capacity** of a STRING_32,
  which cannot change behaviour. Correctly excluded from the score.

## Kill map — which tests are earning their keep

| Test | Mutations killed |
|---|---:|
| `test_position_simple` / `_slash` / `_largest_total_wins` | 9 (as a trio) |
| `test_store_destination_folder` + siblings | 4 |
| `test_single_character_texts` | 4 |
| `test_head_and_tail_cannot_double_count` | 3 |
| `test_compare_identical` | 3 |
| `test_image_name_from_indicator` | 3 |
| `test_compare_rewrapped` | 2 |
| `test_two_blank_screens_compare_equal` | 2 |
| `test_zero_position_refused` | 1 (sole killer of M09) |
| `test_last_page_of_book_reads_as_nothing` | 1 (sole killer of M10) |
| `test_separator_is_case_insensitive` | 1 (sole killer of M21) |
| `test_json_escapes_quotes` | 1 (sole killer of M58) |
| `test_store_drive_root_has_no_leaf` | 1 (sole killer of M55) |
| `test_position_resets_between_labels` | 1 (sole killer of M18) |
| `test_compare_different` | 1 (sole killer of M33) |

Worth noting: the two tests written to record **findings** rather than to prove
correctness — `test_last_page_of_book_reads_as_nothing` and
`test_zero_position_refused` — are each the *only* killer of a mutation. Pinning
known behaviour turns out to be load-bearing.

## Conclusions

- **Weakest area:** deletion (62%) and boundary (63%). Removing a guard or
  shifting a limit by one is what this suite least often notices.
- **Strongest area:** returns (87%).
- **Critical gap:** GAP-A. The delete/move feature — the one that erases a
  book's worth of images — has *no* automated test that touches a real file.

## Next step

→ X07-TRIAGE.md
