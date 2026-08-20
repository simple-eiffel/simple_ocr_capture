# X01: Reconnaissance — simple_ocr_capture

Run: 2026-08-20 · Baseline established before any contract was added.

## Attack surface

29 classes in `src/`. Contract density measured by counting `require`,
`ensure` and invariant clauses per class:

| Class | Lines | require | ensure | invariant | Testable headlessly |
|---|---:|---:|---:|---:|---|
| `ocr_main_window` | 1926 | 4 | 3 | **0** | no — GUI |
| `ocr_auto_run` | 1112 | 1 | 8 | 5 | no — drives screen + clock |
| `ocr_cli` | 904 | **0** | 1 | **0** | entry point |
| `ocr_settings` | 847 | 11 | 28 | 7 | yes |
| `ocr_status_strip` | 685 | 3 | 13 | 2 | no — GUI |
| `ocr_gui` | 683 | **0** | **0** | **0** | no — GUI |
| `ocr_cycle` | 626 | 1 | 6 | 3 | no — capture + HTTP |
| `ocr_run_metrics` | 623 | 1 | 16 | 3 | yes |
| `ocr_image_store` | 502 | 5 | 7 | 3 | yes |
| `ocr_audit` | 502 | **0** | 1 | **0** | partly — file IO |
| `ocr_region_outline` | 386 | 3 | 6 | 3 | no — GUI |
| `ocr_runtime` | 342 | 3 | 9 | 3 | no — Win32 |
| `ocr_health` | 314 | 1 | 8 | 4 | no — probes server |
| `ocr_run_log` | 292 | **0** | 4 | **0** | partly — file IO |
| `ocr_region_selector` | 278 | **0** | **0** | 1 | no — GUI |
| `ocr_outline_set` | 275 | 7 | 2 | **0** | no — GUI |
| `ocr_http` | 256 | 2 | 3 | 2 | no — WinHTTP |
| `ocr_findings` | 229 | **0** | 2 | **0** | partly — file IO |
| `ocr_engine` | 222 | 1 | 3 | 2 | no — OCR server |
| `ocr_log_file` | 209 | **0** | **0** | **0** | partly — file IO |
| `ocr_clicker` | 205 | **0** | 2 | 1 | no — SendInput |
| `ocr_preflight` | 192 | **0** | 3 | 2 | no — probes |
| `ocr_capture` | 185 | 3 | 2 | 1 | no — screen grab |
| `ocr_page_position` | 168 | **0** | 1 | **0** | **yes — prime target** |
| `ocr_hotkey` | 166 | 1 | 5 | **0** | no — Win32 |
| `ocr_text_compare` | 142 | **0** | 3 | **0** | **yes — prime target** |
| `ocr_image_name` | 111 | **0** | 3 | **0** | **yes — prime target** |
| `ocr_json_util` | 83 | 1 | 3 | **0** | yes |
| `ocr_app` | 57 | **0** | **0** | **0** | no — root |

### Reading

- **Thinnest coverage on the largest class.** `ocr_main_window` is 1926 lines
  and 35 features with 4 preconditions and no invariant. It is also the least
  testable, being a window.
- **The pure-logic classes are the least contracted.** `ocr_page_position`,
  `ocr_text_compare` and `ocr_image_name` all parse or compare untrusted OCR
  output, and among them carried **zero preconditions and zero invariants**.
  They are also the only ones a test runner can drive. That is where X03 went.
- Best covered: `ocr_settings` (11/28/7) and `ocr_image_store` (5/7/3).

## Baseline

No test target existed. `--metrics` served as an informal harness; its output
before any change is preserved in `hardening/baseline-metrics.txt`:

```
--- indicator reader ---
  [Page 224 of 416] -> 224 of 416
  [90-92 / 139] -> 92 of 139
  [Location 3120 of 8890] -> 3120 of 8890
  [Page iii of 214] -> nothing (correct - not enough numbers)
  [Page 10 of 379] -> 10 of 379
  [] -> nothing (correct - not enough numbers)
  [no numbers at all] -> nothing (correct - not enough numbers)
...
position after garble: 266   (expect 266, NOT 352)
```

Baseline compile: `./build.sh -c` → `✓ Syntax and type check passed`, exit 0.

## Test target built

Following the ecosystem pattern (`simple_container`, `simple_alpine`):

```
simple_ocr_capture.ecf   -> target simple_ocr_capture_tests, root TEST_APP,
                            libraries: ISE testing + simple_testing
testing/test_app.e       -> console runner
testing/lib_tests.e      -> TEST_SET_BASE, 17 tests
testing/adversarial_tests.e -> TEST_SET_BASE, 24 assault tests
build.sh -t              -> finalize + run
```

## Next step

→ X02-VULNS-ACTUAL.md
