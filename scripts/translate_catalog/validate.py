#!/usr/bin/env python3
"""
Validate per-locale translation JSON files against the source.

Checks each tmp/translate-outputs/{locale}.json file:
  1. File exists and parses as valid JSON.
  2. Every key present in source.json is present in the output.
  3. The multiset of format specifiers in each translation equals the source's.
  4. Value is non-empty.
  5. For non-en-* locales, the value is NOT byte-equal to the English source
     (catches silent translation failures).

Exits with code 0 only if all locales pass. Prints a summary table.

Usage:
  python3 scripts/translate_catalog/validate.py [--subset] [locale ...]
  # If no locales given, validates all locales in locales.py.
  # --subset: only validate keys present in each output file (does not require
  #           the full source key set). Use this when the output came from a
  #           partial translation run driven by `extract.py --missing`.
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path
from typing import Tuple

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_PATH = REPO_ROOT / "tmp" / "translate-inputs" / "source.json"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "translate-outputs"

sys.path.insert(0, str(Path(__file__).parent))
from locales import LOCALES  # noqa: E402
from extract import FORMAT_SPEC_RE, CLDR_CATEGORIES  # noqa: E402  — single source of truth


def specifier_multiset(value: str) -> collections.Counter:
    return collections.Counter(FORMAT_SPEC_RE.findall(value))


def has_translatable_content(value: str) -> bool:
    """Return True if value has alphabetic characters outside format specifiers.

    Values like "0", "%@", "%1$@, %2$@" have nothing to translate and are
    legitimately identical across all locales.
    """
    stripped = FORMAT_SPEC_RE.sub("", value)
    # [^\W\d] matches any Unicode letter (Latin, CJK, Arabic, Cyrillic, etc.)
    return bool(re.search(r"[^\W\d]", stripped, re.UNICODE))


def _validate_plural(locale: str, key: str, src_plural: dict, translated, errors: list) -> None:
    """Validate a plural key's output: a CLDR-category object with a non-empty `other` and
    matching format specifiers in every category."""
    if not isinstance(translated, dict):
        errors.append(f"[{locale}] Key {key!r}: expected a plural object, got {type(translated).__name__}")
        return
    cats = {c: v for c, v in translated.items() if c in CLDR_CATEGORIES}
    unknown = {c for c in translated if c not in CLDR_CATEGORIES and not c.endswith("__note")}
    if unknown:
        errors.append(f"[{locale}] Key {key!r}: invalid plural categories {sorted(unknown)} (allowed: {list(CLDR_CATEGORIES)})")
    other = cats.get("other")
    if not isinstance(other, str) or not other.strip():
        errors.append(f"[{locale}] Key {key!r}: plural missing a non-empty 'other' form")
        return
    ref_specs = specifier_multiset(src_plural.get("other") or next(iter(src_plural.values())))
    for cat, value in cats.items():
        if not isinstance(value, str) or not value.strip():
            errors.append(f"[{locale}] Key {key!r}: plural category {cat!r} is empty")
            continue
        if specifier_multiset(value) != ref_specs:
            errors.append(
                f"[{locale}] Key {key!r}: plural {cat!r} specifier mismatch "
                f"source={dict(ref_specs)} translated={dict(specifier_multiset(value))}"
            )


def validate_locale(locale: str, source: dict, subset: bool = False) -> Tuple[list, list]:
    """Return (errors, warnings). Only errors count toward the exit code.

    When ``subset`` is True, keys present in ``source`` but absent from the
    output file are not flagged as errors — only the keys actually present in
    the output file are checked.
    """
    errors: list[str] = []
    warnings: list[str] = []
    output_path = OUTPUTS_DIR / f"{locale}.json"

    if not output_path.exists():
        return [f"[{locale}] File missing: {output_path}"], []

    try:
        with output_path.open(encoding="utf-8") as f:
            translations: dict = json.load(f)
    except json.JSONDecodeError as exc:
        return [f"[{locale}] Invalid JSON: {exc}"], []

    is_english_variant = locale.startswith("en-")

    for key, src_entry in source.items():
        if key not in translations:
            if subset:
                continue
            errors.append(f"[{locale}] Missing key: {key!r}")
            continue

        translated = translations[key]

        # Plural keys carry a `plural` object in the source and expect a CLDR-category object back.
        if "plural" in src_entry:
            _validate_plural(locale, key, src_entry["plural"], translated, errors)
            continue

        src_value = src_entry["value"]
        src_specs = specifier_multiset(src_value)

        # Accept both flat string and {"value": "...", ...} dict produced by some models
        if isinstance(translated, dict):
            translated = translated.get("value", "")

        if not isinstance(translated, str):
            errors.append(f"[{locale}] Key {key!r}: value is not a string (got {type(translated).__name__})")
            continue

        if not translated.strip():
            errors.append(f"[{locale}] Key {key!r}: empty translation")
            continue

        tran_specs = specifier_multiset(translated)
        if tran_specs != src_specs:
            errors.append(
                f"[{locale}] Key {key!r}: specifier mismatch "
                f"source={dict(src_specs)} translated={dict(tran_specs)}"
            )

        # Identical-to-source is a WARNING only (not a hard error): many short
        # technical terms are legitimate loanwords, brand names, or product
        # concepts intentionally kept in English (e.g. "iCloud", "Carry-Over",
        # "Version", "Budget", "Symbol" in languages that use these words).
        if (
            not is_english_variant
            and src_value
            and translated == src_value
            and has_translatable_content(src_value)
        ):
            warnings.append(
                f"[{locale}] Key {key!r}: translation identical to English source "
                f"(loanword/brand-name/intentional or possible missed translation)"
            )

    extra_keys = (
        set(translations.keys())
        - set(source.keys())
        - {k for k in translations if k.startswith("_") or k.endswith("__note")}
    )
    if extra_keys:
        errors.append(f"[{locale}] Unexpected extra keys: {sorted(extra_keys)}")

    return errors, warnings


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--subset", action="store_true", help="Only check keys present in each output file; do not require the full source set.")
    parser.add_argument("locales", nargs="*", help="Locales to validate (default: all in locales.py).")
    args = parser.parse_args(argv)

    if not SOURCE_PATH.exists():
        print(f"ERROR: source file not found at {SOURCE_PATH}. Run extract.py first.", file=sys.stderr)
        return 1

    with SOURCE_PATH.open(encoding="utf-8") as f:
        source: dict = json.load(f)

    if args.locales:
        locales = args.locales
    elif args.subset:
        # In subset mode with no explicit locales, validate exactly the locales that have an
        # output file — otherwise we'd report "File missing" for every locale that wasn't part
        # of this partial run (the full LOCALES default only makes sense for a full backfill).
        locales = [loc for loc in LOCALES if (OUTPUTS_DIR / f"{loc}.json").exists()]
        if not locales:
            print(f"No output files in {OUTPUTS_DIR} to validate (--subset). Run dispatch + subagents first.", file=sys.stderr)
            return 1
    else:
        locales = LOCALES
    all_errors: dict[str, list[str]] = {}
    all_warnings: dict[str, list[str]] = {}
    fail_count = 0
    warn_count = 0

    for locale in locales:
        errors, warnings = validate_locale(locale, source, subset=args.subset)
        all_errors[locale] = errors
        all_warnings[locale] = warnings
        if errors:
            fail_count += 1
        if warnings:
            warn_count += 1

    print(f"\n{'Locale':<12} {'Status':<8} {'Detail'}")
    print("-" * 60)
    for locale in locales:
        errors = all_errors[locale]
        warnings = all_warnings[locale]
        if errors:
            status = "FAIL"
            detail = f"{len(errors)} error(s)"
        elif warnings:
            status = "WARN"
            detail = f"{len(warnings)} warning(s)"
        else:
            status = "PASS"
            detail = ""
        print(f"{locale:<12} {status:<8} {detail}")
        for err in errors:
            print(f"  ✗ {err}")
        for warn in warnings:
            print(f"  ⚠ {warn}")

    print()
    if fail_count:
        print(f"FAILED: {fail_count}/{len(locales)} locale(s) had hard errors.")
        return 1
    else:
        total_warnings = sum(len(w) for w in all_warnings.values())
        print(
            f"PASSED: all {len(locales)} locale(s) passed validation"
            + (f" ({total_warnings} informational identical-to-source warning(s))" if total_warnings else "")
            + "."
        )
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
