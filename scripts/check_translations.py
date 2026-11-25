#!/usr/bin/env python3
"""
Check Localizable.xcstrings for strings that are untranslated or missing
translations for any supported locale, including the source language.

Exits 0 if every key has a `translated`-state stringUnit for the source
language AND every supported target locale.
Exits 1 if any key is missing or has a non-translated state (new,
needs_review, stale) for the source language or any target locale.

Also exits 1 if the file's bytes differ from what Xcode would write for the same
content, so a build in Xcode never rewrites a committed catalog.

The source language is checked too: its stringUnit has its own `state`, and
while that is `new`, APIs without a `defaultValue` fallback (such as
`Text(LocalizedStringKey)`) resolve to the literal key at runtime.

Usage:
  python3 scripts/check_translations.py [--json]

  --json   emit {"issues": [...]} instead of the human-readable report
"""

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_catalog"))
from locales import LOCALES  # noqa: E402
from paths import CATALOG_PATH  # noqa: E402
from xcstrings_io import is_xcode_format  # noqa: E402

# States that mean a translation is not ready to ship.
UNTRANSLATED_STATES = {"new", "needs_review", "stale"}

SOURCE_LANGUAGE = "en"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--json", action="store_true", help='Emit {"issues": [...]} instead of the human report.')
    args = parser.parse_args(argv)

    if not CATALOG_PATH.exists():
        if args.json:
            print(json.dumps({"issues": [f"ERROR: catalog not found at {CATALOG_PATH}"]}))
        else:
            print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 1

    data = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    source_language = data.get("sourceLanguage", SOURCE_LANGUAGE)
    strings: dict = data.get("strings", {})

    issues: list[str] = []

    if not is_xcode_format(CATALOG_PATH):
        issues.append(
            f"  FORMAT   {CATALOG_PATH.name} is not in Xcode's byte format: "
            "python3 scripts/translate_catalog/sync_catalog.py --format"
        )

    for key, entry in strings.items():
        # Keys marked shouldTranslate=false (e.g. locale-invariant identifiers) are intentionally skipped.
        if not entry.get("shouldTranslate", True):
            continue

        localizations: dict = entry.get("localizations", {})

        source_entry = localizations.get(source_language)
        if source_entry is None:
            issues.append(f"  MISSING  [{source_language}] {key!r} (source)")
        elif "variations" in source_entry:
            _check_variations(source_entry["variations"], source_language, key, issues)
        else:
            state = source_entry.get("stringUnit", {}).get("state", "")
            if state in UNTRANSLATED_STATES:
                issues.append(f"  {state.upper():<9}[{source_language}] {key!r} (source)")

        for locale in LOCALES:
            loc_entry = localizations.get(locale)

            if loc_entry is None:
                issues.append(f"  MISSING  [{locale}] {key!r}")
                continue

            if "variations" in loc_entry:
                _check_variations(loc_entry["variations"], locale, key, issues)
                continue

            string_unit = loc_entry.get("stringUnit", {})
            state = string_unit.get("state", "")
            if state in UNTRANSLATED_STATES:
                issues.append(f"  {state.upper():<9}[{locale}] {key!r}")

    if args.json:
        print(json.dumps({"issues": issues}, ensure_ascii=False, indent=2))
        return 1 if issues else 0

    if issues:
        print(f"check_translations: {len(issues)} issue(s) found in {CATALOG_PATH.name}\n")
        for line in issues:
            print(line)
        print(
            "\nRun scripts/translate_catalog/ (extract → translate → validate → merge) "
            "to generate missing translations before pushing."
        )
        return 1

    print(
        f"check_translations: all {len(strings)} strings fully translated "
        f"across source ({source_language}) + {len(LOCALES)} target locales."
    )
    return 0


def _check_variations(variations: dict, locale: str, key: str, issues: list[str]) -> None:
    """Recursively check plural/device variation stringUnits."""
    for _variant_kind, variant_map in variations.items():
        for _variant_name, variant_entry in variant_map.items():
            if "stringUnit" in variant_entry:
                state = variant_entry["stringUnit"].get("state", "")
                if state in UNTRANSLATED_STATES:
                    issues.append(f"  {state.upper():<9}[{locale}] {key!r} (variation)")
            elif "variations" in variant_entry:
                _check_variations(variant_entry["variations"], locale, key, issues)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
