# X09: Harden Defenses — simple_ocr_capture

Run: 2026-08-20 · Principle: never fix the same bug twice

## The permanent defences

X08 built the tests. X09 records what is now **structurally** protected — what
would have to break, and be noticed, for each past mistake to return.

### 1. Contracts that cannot be quietly removed

The 13 assault contracts from X03 are compiled into the shipped binary.
`ec.sh test` finalizes with `-keep`, so assertion checking is **on in the
artefact users run**, not merely in a debug build. That was verified, not
assumed: a deliberately false invariant killed the process, and was removed.

The invariant on `OCR_PAGE_POSITION` is the durable part. The class previously
had none, so any future edit that left `position` set while `has_position` was
False, or `total` below `position`, would have produced a silently wrong ETA.
Now it stops the process at the point of corruption.

### 2. Behaviours pinned by test, not by comment

Three behaviours are asserted **as they actually are**:

| Test | Pins |
|---|---|
| `test_last_page_of_book_reads_as_nothing` | X03-001 |
| `test_minus_sign_is_ignored` | X03-002 |
| `test_two_blank_screens_compare_equal` | X03-003 |

A comment saying "this is intentional" is a claim. A test saying it is a
tripwire: change the behaviour and the suite says so, in the right place, to
whoever changed it. Notably, X06 showed two of these are the **sole killer** of
a mutation — pinning known behaviour turned out to be load-bearing, not
documentation.

### 3. The destructive feature is defended by fixture

`OCR_IMAGE_STORE` is the only class here that destroys user data. Its defences
now run on every build:

- The whitelist is checked against **five named decoys**, each asserted absent
- Deletion is checked by asserting the decoys are **still on disk afterwards** —
  not merely that the right count was reported
- A move is checked by **byte content at the destination**, not by the counter
- Collision is checked by reading the archive file back and finding it unchanged
- Self-move is checked with the source file still present and intact

The reported counters (`last_done`, `last_skipped`, `last_failed`) are never
trusted as the sole evidence; every one is corroborated by the file system.

### 4. Constants pinned

`Similarity_percent = 97`, `Maximum_digits = 9` (from both sides) and
`Maximum_length = 60` are now asserted. Before X06 all three could be changed to
almost anything without a single test noticing.

### 5. The mutation harness is committed

`hardening/mutate.py` ships with the repository. Re-running it re-measures the
suite. This is the defence that makes the others durable: without it, the next
person to add a feature has no way to find out that their tests are decorative.

Its two safety properties are deliberate:

- reverts in a `finally` block, so an interrupted run cannot leave a mutant
- **refuses** to apply a mutation whose anchor is not unique, reporting SKIPPED
  rather than mutating the wrong line

### 6. Assertions verified live, as a standing procedure

Recorded in the oracle so future sessions inherit it: before reporting a
contract assault as clean, inject a false contract and confirm the binary dies.
A green run from a build with assertions stripped is worse than no run at all,
because it looks like evidence.

## What is deliberately *not* hardened

`OCR_MAIN_WINDOW` — 1926 lines, 35 features, 4 preconditions, **no invariant**.
The largest contract gap in the codebase.

Contracts could be added. No test could reach them, so they would be unverified
claims that improve a count and defend nothing. Recorded in X01 and X07, left
alone on purpose. Honest gaps beat decorative coverage.

The same applies to `OCR_GUI`, `OCR_STATUS_STRIP`, `OCR_REGION_SELECTOR`,
`OCR_OUTLINE_SET`, `OCR_CAPTURE`, `OCR_CLICKER`, `OCR_HOTKEY`, `OCR_HTTP`,
`OCR_ENGINE`, `OCR_RUNTIME`, `OCR_HEALTH` and `OCR_PREFLIGHT`.

## Regression risk introduced by this phase

Production source changed in X03 only: 13 contracts on `OCR_PAGE_POSITION`.
Contracts can themselves be wrong, and a wrong invariant crashes a shipped
application. Mitigation:

- all 13 held across 59 tests and 60 mutations
- each states something the implementation already guaranteed; none required a
  code change to satisfy
- the campaign exercised them under 60 deliberately broken variants of the code,
  which is a far harder test than the suite alone

## Next step

→ X10-FINAL-VERIFIED.md
