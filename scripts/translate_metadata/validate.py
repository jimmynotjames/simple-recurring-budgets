#!/usr/bin/env python3
"""
Validate per-storefront metadata transcreation JSON files against the source.

Checks each tmp/metadata-outputs/{storefront}.json file:
  1. File exists and parses as valid JSON.
  2. Every field present in source.json is present (unless --subset).
  3. Each value is a non-empty string.
  4. Each value is within the field's App Store Connect character limit.
  5. The `name` field begins with the brand token.
  6. The `keywords` field has no spaces after commas, no empty/duplicate terms,
     and fits the 100-char limit (a hard error here, warnings for the rest).
  7. For non-English storefronts, the value is not byte-identical to the English
     source (catches silent no-op "translations").
  8. No unexpected extra fields.

Exits 0 only if all storefronts pass (warnings do not fail the build).

Usage:
  python3 scripts/translate_metadata/validate.py [--subset] [storefront ...]
  # No storefronts given -> validate all in metadata_locales.py.
  # --subset: only check fields present in each output file (for partial runs
  #           driven by `extract.py --missing`).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Tuple

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_PATH = REPO_ROOT / "tmp" / "metadata-inputs" / "source.json"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "metadata-outputs"

sys.path.insert(0, str(Path(__file__).parent))
from metadata_locales import (  # noqa: E402
    BRAND,
    FIELD_LIMITS,
    STOREFRONT_LOCALES,
)


def check_keywords(storefront: str, value: str) -> Tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    if ", " in value:
        warnings.append(
            f"[{storefront}] keywords: contains ', ' (space after comma wastes the "
            "100-char limit; use bare commas)"
        )
    terms = [t.strip() for t in value.split(",")]
    if any(t == "" for t in terms):
        errors.append(f"[{storefront}] keywords: contains an empty term")
    lowered = [t.lower() for t in terms if t]
    dupes = sorted({t for t in lowered if lowered.count(t) > 1})
    if dupes:
        warnings.append(f"[{storefront}] keywords: duplicate term(s) {dupes}")
    return errors, warnings


def validate_storefront(storefront: str, source: dict, subset: bool = False) -> Tuple[list, list]:
    errors: list[str] = []
    warnings: list[str] = []
    output_path = OUTPUTS_DIR / f"{storefront}.json"

    if not output_path.exists():
        return [f"[{storefront}] File missing: {output_path}"], []

    try:
        with output_path.open(encoding="utf-8") as f:
            out: dict = json.load(f)
    except json.JSONDecodeError as exc:
        return [f"[{storefront}] Invalid JSON: {exc}"], []

    is_english_variant = storefront.startswith("en-")

    for field, src_entry in source.items():
        src_value = src_entry["value"]
        limit = src_entry.get("charLimit", FIELD_LIMITS.get(field))

        if field not in out:
            if subset:
                continue
            errors.append(f"[{storefront}] Missing field: {field!r}")
            continue

        value = out[field]
        if isinstance(value, dict):  # some models wrap as {"value": ...}
            value = value.get("value", "")

        if not isinstance(value, str):
            errors.append(f"[{storefront}] {field}: value is not a string (got {type(value).__name__})")
            continue

        if not value.strip():
            errors.append(f"[{storefront}] {field}: empty value")
            continue

        if limit is not None and len(value) > limit:
            errors.append(f"[{storefront}] {field}: {len(value)} chars exceeds limit of {limit}")

        if field == "name" and not value.startswith(BRAND):
            errors.append(f"[{storefront}] name: must start with brand {BRAND!r} (got {value!r})")

        if field == "keywords":
            k_errors, k_warnings = check_keywords(storefront, value)
            errors.extend(k_errors)
            warnings.extend(k_warnings)

        if not is_english_variant and value == src_value:
            warnings.append(
                f"[{storefront}] {field}: identical to English source "
                "(loanword/brand or possible missed transcreation)"
            )

    extra = set(out.keys()) - set(source.keys()) - {k for k in out if k.startswith("_")}
    if extra:
        errors.append(f"[{storefront}] Unexpected extra field(s): {sorted(extra)}")

    return errors, warnings


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--subset", action="store_true", help="Only check fields present in each output file.")
    parser.add_argument("storefronts", nargs="*", help="Storefronts to validate (default: all).")
    args = parser.parse_args(argv)

    if not SOURCE_PATH.exists():
        print(f"ERROR: source file not found at {SOURCE_PATH}. Run extract.py first.", file=sys.stderr)
        return 1

    with SOURCE_PATH.open(encoding="utf-8") as f:
        source: dict = json.load(f)

    storefronts = args.storefronts if args.storefronts else STOREFRONT_LOCALES
    all_errors: dict[str, list[str]] = {}
    all_warnings: dict[str, list[str]] = {}
    fail_count = 0

    for storefront in storefronts:
        errors, warnings = validate_storefront(storefront, source, subset=args.subset)
        all_errors[storefront] = errors
        all_warnings[storefront] = warnings
        if errors:
            fail_count += 1

    print(f"\n{'Storefront':<12} {'Status':<8} {'Detail'}")
    print("-" * 60)
    for storefront in storefronts:
        errors = all_errors[storefront]
        warnings = all_warnings[storefront]
        if errors:
            status, detail = "FAIL", f"{len(errors)} error(s)"
        elif warnings:
            status, detail = "WARN", f"{len(warnings)} warning(s)"
        else:
            status, detail = "PASS", ""
        print(f"{storefront:<12} {status:<8} {detail}")
        for err in errors:
            print(f"  ✗ {err}")
        for warn in warnings:
            print(f"  ⚠ {warn}")

    print()
    if fail_count:
        print(f"FAILED: {fail_count}/{len(storefronts)} storefront(s) had hard errors.")
        return 1
    total_warnings = sum(len(w) for w in all_warnings.values())
    print(
        f"PASSED: all {len(storefronts)} storefront(s) passed validation"
        + (f" ({total_warnings} informational warning(s))" if total_warnings else "")
        + "."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
