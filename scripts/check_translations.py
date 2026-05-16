#!/usr/bin/env python3
"""
Check Localizable.xcstrings for strings that are untranslated or missing
translations for any supported locale.

Exits 0 if all strings are fully translated.
Exits 1 if any string is missing from the localization file or has a
non-translated state (new, needs_review, stale) for any required locale.

Usage:
  python3 scripts/check_translations.py
"""

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"

sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_catalog"))
from locales import LOCALES  # noqa: E402

# States that mean a translation is not ready to ship.
UNTRANSLATED_STATES = {"new", "needs_review", "stale"}


def main() -> int:
    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 1

    data = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    strings: dict = data.get("strings", {})

    issues: list[str] = []

    for key, entry in strings.items():
        # Keys marked shouldTranslate=false (e.g. locale-invariant identifiers) are intentionally skipped.
        if not entry.get("shouldTranslate", True):
            continue

        localizations: dict = entry.get("localizations", {})

        for locale in LOCALES:
            loc_entry = localizations.get(locale)

            if loc_entry is None:
                issues.append(f"  MISSING  [{locale}] {key!r}")
                continue

            # Handle plural variants (stringSet) — check each variant.
            if "variations" in loc_entry:
                # Plural/device variations: check each stringUnit within.
                _check_variations(loc_entry["variations"], locale, key, issues)
                continue

            string_unit = loc_entry.get("stringUnit", {})
            state = string_unit.get("state", "")
            if state in UNTRANSLATED_STATES:
                issues.append(f"  {state.upper():<9}[{locale}] {key!r}")

    if issues:
        print(f"check_translations: {len(issues)} issue(s) found in {CATALOG_PATH.name}\n")
        for line in issues:
            print(line)
        print(
            "\nRun scripts/translate_catalog/ (extract → translate → merge → validate) "
            "to generate missing translations before pushing."
        )
        return 1

    print(f"check_translations: all {len(strings)} strings fully translated across {len(LOCALES)} locales.")
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
    sys.exit(main())
