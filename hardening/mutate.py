#!/usr/bin/env python3
"""
X06 Mutation Warfare harness for simple_ocr_capture.

One mutation at a time: apply, build, run the suite, classify, revert.
A mutation whose anchor text is not unique is SKIPPED rather than applied,
so a mutation can never silently land somewhere other than intended.

Classification:
  NO_COMPILE  the mutant does not build (not a valid mutation)
  KILLED      the suite reported a failure, or the binary died outright
  SURVIVED    the suite passed with the bug in place  <-- a weakness
"""
import io, os, subprocess, sys, json

ROOT = os.path.dirname(os.path.abspath(os.path.join(__file__, "..")))
SRC = os.path.join(ROOT, "src")
EXE = os.path.join(ROOT, "EIFGENs", "simple_ocr_capture_tests", "F_code",
                   "simple_ocr_capture.exe")

# (id, category, file, anchor_original, mutated)
MUTATIONS = [
    # ---------------- OCR_PAGE_POSITION ----------------
    ("M01", "boundary",   "ocr_page_position.e", "i > l_text.count + 1", "i >= l_text.count + 1"),
    ("M02", "arithmetic", "ocr_page_position.e", "i > l_text.count + 1", "i > l_text.count - 1"),
    ("M03", "comparison", "ocr_page_position.e", "if i <= l_text.count and then is_digit", "if i < l_text.count and then is_digit"),
    ("M04", "boolean",    "ocr_page_position.e", "if i <= l_text.count and then is_digit", "if i <= l_text.count or else is_digit"),
    ("M05", "comparison", "ocr_page_position.e", "if l_digits.count <= Maximum_digits", "if l_digits.count < Maximum_digits"),
    ("M06", "boundary",   "ocr_page_position.e", "l_digits.count <= Maximum_digits and then", "l_digits.count <= Maximum_digits + 2 and then"),
    ("M07", "arithmetic", "ocr_page_position.e", "\t\t\t\ti := i + 1", "\t\t\t\ti := i + 2"),
    ("M08", "boundary",   "ocr_page_position.e", "k > l_values.count - 1", "k > l_values.count"),
    ("M09", "comparison", "ocr_page_position.e", "if l_values.i_th (k) > 0", "if l_values.i_th (k) >= 0"),
    ("M10", "comparison", "ocr_page_position.e", "and then l_values.i_th (k + 1) > l_values.i_th (k)", "and then l_values.i_th (k + 1) >= l_values.i_th (k)"),
    ("M11", "arithmetic", "ocr_page_position.e", "and then l_values.i_th (k + 1) > l_values.i_th (k)", "and then l_values.i_th (k + 1) > l_values.i_th (k + 1)"),
    ("M12", "boolean",    "ocr_page_position.e", "if not has_total or else l_values.i_th (k + 1) > total then", "if has_total or else l_values.i_th (k + 1) > total then"),
    ("M13", "comparison", "ocr_page_position.e", "or else l_values.i_th (k + 1) > total then", "or else l_values.i_th (k + 1) < total then"),
    ("M14", "arithmetic", "ocr_page_position.e", "\t\t\t\tk := k + 1", "\t\t\t\tk := k + 2"),
    ("M15", "returns",    "ocr_page_position.e", "Result := a_char >= '0' and a_char <= '9'", "Result := False"),
    ("M16", "boolean",    "ocr_page_position.e", "Result := a_char >= '0' and a_char <= '9'", "Result := a_char >= '0' or a_char <= '9'"),
    ("M17", "deletion",   "ocr_page_position.e", "\t\t\t\t\tpair_count := pair_count + 1", "\t\t\t\t\tpair_count := pair_count"),
    ("M18", "deletion",   "ocr_page_position.e", "\t\t\tposition := 0\n\t\t\ttotal := 0", "\t\t\ttotal := 0"),
    ("M19", "boolean",    "ocr_page_position.e", "\t\t\thas_position := False\n\t\t\thas_total := False", "\t\t\thas_position := True\n\t\t\thas_total := False"),
    ("M20", "returns",    "ocr_page_position.e", 'Result := l_trim.same_string ({STRING_32} "of")', 'Result := True or else l_trim.same_string ({STRING_32} "of")'),
    ("M21", "deletion",   "ocr_page_position.e", "\t\t\tl_trim.to_lower", "\t\t\tl_trim.right_adjust"),
    ("M22", "boundary",   "ocr_page_position.e", "Maximum_digits: INTEGER = 9", "Maximum_digits: INTEGER = 12"),

    # ---------------- OCR_TEXT_COMPARE ----------------
    ("M23", "returns",    "ocr_text_compare.e", "if l_first.same_string (l_second) then\n\t\t\t\tResult := True", "if l_first.same_string (l_second) then\n\t\t\t\tResult := False"),
    ("M24", "comparison", "ocr_text_compare.e", "Result := (l_head + l_tail) * 100 >= Similarity_percent * l_shorter", "Result := (l_head + l_tail) * 100 > Similarity_percent * l_shorter"),
    ("M25", "arithmetic", "ocr_text_compare.e", "Result := (l_head + l_tail) * 100 >= Similarity_percent", "Result := (l_head - l_tail) * 100 >= Similarity_percent"),
    ("M26", "arithmetic", "ocr_text_compare.e", "(l_head + l_tail) * 100 >= Similarity_percent * l_shorter", "(l_head + l_tail) * 10 >= Similarity_percent * l_shorter"),
    ("M27", "returns",    "ocr_text_compare.e", "\t\t\t\t\tResult := 100\n", "\t\t\t\t\tResult := 0\n"),
    ("M28", "arithmetic", "ocr_text_compare.e", "common_tail (l_first, l_second, l_shorter - l_head)) * 100) // l_shorter", "common_tail (l_first, l_second, l_shorter + l_head)) * 100) // l_shorter"),
    ("M29", "arithmetic", "ocr_text_compare.e", "l_head + common_tail (l_first, l_second, l_shorter - l_head)) * 100) // l_shorter", "l_head + common_tail (l_first, l_second, l_shorter - l_head)) * 99) // l_shorter"),
    ("M30", "boundary",   "ocr_text_compare.e", "Result >= l_limit or else a_first.item (Result + 1)", "Result > l_limit or else a_first.item (Result + 1)"),
    ("M31", "comparison", "ocr_text_compare.e", "a_first.item (Result + 1) /= a_second.item (Result + 1)", "a_first.item (Result + 1) = a_second.item (Result + 1)"),
    ("M32", "boundary",   "ocr_text_compare.e", "\t\t\t\tResult >= a_limit\n", "\t\t\t\tResult > a_limit\n"),
    ("M33", "arithmetic", "ocr_text_compare.e", "a_first.item (a_first.count - Result) /= a_second.item (a_second.count - Result)", "a_first.item (a_first.count - Result) /= a_second.item (a_second.count + Result)"),
    ("M34", "boolean",    "ocr_text_compare.e", "Result := a_char = ' ' or a_char = '%N' or a_char = '%R' or a_char = '%T'", "Result := a_char = ' ' and a_char = '%N' and a_char = '%R' and a_char = '%T'"),
    ("M35", "boundary",   "ocr_text_compare.e", "Similarity_percent: INTEGER = 97", "Similarity_percent: INTEGER = 50"),
    ("M36", "boundary",   "ocr_text_compare.e", "Similarity_percent: INTEGER = 97", "Similarity_percent: INTEGER = 100"),
    ("M37", "arithmetic", "ocr_text_compare.e", "l_shorter := l_first.count.min (l_second.count)\n\t\t\t\tl_head := common_head (l_first, l_second)\n\t\t\t\t\t-- Capped", "l_shorter := l_first.count.max (l_second.count)\n\t\t\t\tl_head := common_head (l_first, l_second)\n\t\t\t\t\t-- Capped"),
    ("M38", "arithmetic", "ocr_text_compare.e", "l_limit := a_first.count.min (a_second.count)", "l_limit := a_first.count.max (a_second.count)"),
    ("M39", "deletion",   "ocr_text_compare.e", "\t\t\tResult.right_adjust\n", "\n"),
    ("M40", "boolean",    "ocr_text_compare.e", "if not l_space and then not Result.is_empty then", "if not l_space or else not Result.is_empty then"),

    # ---------------- OCR_IMAGE_NAME ----------------
    ("M41", "returns",    "ocr_image_name.e", "Result := sanitized (a_label)\n\t\t\tif Result.is_empty then", "Result := sanitized (a_label)\n\t\t\tif not Result.is_empty then"),
    ("M42", "boundary",   "ocr_image_name.e", "if Result.count < Maximum_length then", "if Result.count <= Maximum_length then"),
    ("M43", "arithmetic", "ocr_image_name.e", "create Result.make (a_text.count.min (Maximum_length))", "create Result.make (a_text.count.max (Maximum_length))"),
    ("M44", "boolean",    "ocr_image_name.e", "elseif not l_underscore and then not Result.is_empty then", "elseif not l_underscore or else not Result.is_empty then"),
    ("M45", "comparison", "ocr_image_name.e", "Result.is_empty or else Result.item (Result.count) /= '_'", "Result.is_empty or else Result.item (Result.count) = '_'"),
    ("M46", "deletion",   "ocr_image_name.e", "\t\t\t\tResult.remove_tail (1)", "\t\t\t\tResult.append_character ('x')"),
    ("M47", "boundary",   "ocr_image_name.e", "\t\t\t\tResult.count >= 4", "\t\t\t\tResult.count >= 2"),
    ("M48", "returns",    "ocr_image_name.e", "Result := (a_char >= 'a' and a_char <= 'z')", "Result := True or (a_char >= 'a' and a_char <= 'z')"),
    ("M49", "boundary",   "ocr_image_name.e", "Maximum_length: INTEGER = 60", "Maximum_length: INTEGER = 6"),

    # ---------------- OCR_IMAGE_STORE ----------------
    ("M50", "returns",    "ocr_image_store.e", 'Result := l_lower.starts_with_general (Image_prefix)', 'Result := True or else l_lower.starts_with_general (Image_prefix)'),
    ("M51", "boolean",    "ocr_image_store.e", "and then (l_lower.ends_with_general (Png_suffix)\n\t\t\t\t\tor else l_lower.ends_with_general (Bmp_suffix))", "or else (l_lower.ends_with_general (Png_suffix)\n\t\t\t\t\tor else l_lower.ends_with_general (Bmp_suffix))"),
    ("M52", "deletion",   "ocr_image_store.e", "\t\t\tif Result.count = 1 and then is_letter (Result.item (1)) then\n\t\t\t\tResult.append_character (':')\n\t\t\tend\n", ""),
    ("M53", "comparison", "ocr_image_store.e", "l_at < 1 or else is_separator (l_path.item (l_at))", "l_at < 1 or else not is_separator (l_path.item (l_at))"),
    ("M54", "arithmetic", "ocr_image_store.e", "Result := l_path.substring (l_at + 1, l_path.count)", "Result := l_path.substring (l_at, l_path.count)"),
    ("M55", "boolean",    "ocr_image_store.e", "Result := not l_leaf.is_empty and then not l_leaf.has (':')", "Result := not l_leaf.is_empty or else not l_leaf.has (':')"),
    ("M56", "deletion",   "ocr_image_store.e", "\t\t\tif not Result.is_empty and then not is_separator (Result.item (Result.count)) then\n\t\t\t\tResult.append_character ('\\')\n\t\t\tend\n", ""),
    ("M57", "returns",    "ocr_image_store.e", "Result := a_char = '\\' or a_char = '/'", "Result := False"),

    # ---------------- OCR_JSON_UTIL ----------------
    ("M58", "deletion",   "ocr_json_util.e", 'when \'%"\' then Result.append ("\\%"")', 'when \'%"\' then Result.append ("%"")'),
    ("M59", "comparison", "ocr_json_util.e", "if c.code < 0x20 then", "if c.code > 0x20 then"),
    ("M60", "arithmetic", "ocr_json_util.e", "Result.append (hex_digit (c.code // 16))", "Result.append (hex_digit (c.code \\\\ 16))"),
]


def read(path):
    return io.open(path, encoding="utf-8").read()


def write(path, s):
    io.open(path, "w", encoding="utf-8", newline="").write(s)


def build():
    r = subprocess.run(["bash", "./build.sh", "-t"], cwd=ROOT,
                       capture_output=True, text=True, timeout=600)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def classify(out):
    if "ALL TESTS PASSED" in out:
        return "SURVIVED", []
    fails = [l.strip()[6:] for l in out.splitlines() if l.strip().startswith("FAIL:")]
    if "system execution failed" in out:
        return "KILLED", fails or ["<binary died>"]
    if "TESTS FAILED" in out or fails:
        return "KILLED", fails
    return "NO_COMPILE", []


def main():
    only = sys.argv[1:] if len(sys.argv) > 1 else None
    results = []
    for mid, cat, fname, old, new in MUTATIONS:
        if only and mid not in only:
            continue
        path = os.path.join(SRC, fname)
        original = read(path)
        n = original.count(old)
        if n != 1:
            print("%s SKIPPED (anchor matched %d times)" % (mid, n), flush=True)
            results.append(dict(id=mid, category=cat, file=fname, result="SKIPPED",
                                detail="anchor matched %d times" % n, killers=[]))
            continue
        try:
            write(path, original.replace(old, new))
            code, out = build()
            if "ERROR" in out and "Built:" not in out and "PASSED" not in out and "FAIL" not in out:
                verdict, killers = "NO_COMPILE", []
            else:
                verdict, killers = classify(out)
            print("%s %-10s %-22s %s %s" % (mid, cat, fname, verdict,
                  ("<- " + ", ".join(killers[:3])) if killers else ""), flush=True)
            results.append(dict(id=mid, category=cat, file=fname, result=verdict,
                                mutation="%s  ->  %s" % (old.strip()[:70], new.strip()[:70]),
                                killers=killers))
        finally:
            write(path, original)

    with io.open(os.path.join(ROOT, "hardening", "X06-results.json"), "w",
                 encoding="utf-8") as f:
        f.write(json.dumps(results, indent=1))
    print("\nwrote hardening/X06-results.json (%d entries)" % len(results))


if __name__ == "__main__":
    main()
