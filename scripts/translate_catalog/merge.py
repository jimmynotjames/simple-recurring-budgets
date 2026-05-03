#!/usr/bin/env python3
"""
Merge per-locale translation JSON files back into Localizable.xcstrings.

Reads tmp/translate-outputs/{locale}.json for every locale in locales.py and
writes per-key localizations entries into the catalog.

Idempotent: re-running with identical inputs produces an identical catalog.
Stable JSON ordering (sorted keys) keeps diffs clean.
Preserves all existing catalog fields (comment, extractionState, etc.).

Usage:
  python3 scripts/translate_catalog/merge.py [locale ...]
  # If no locales given, merges all locales in locales.py.
"""

import json
import sys
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "translate-outputs"

sys.path.insert(0, str(Path(__file__).parent))
from locales import LOCALES  # noqa: E402


def load_translations(locale: str) -> Optional[dict]:
    path = OUTPUTS_DIR / f"{locale}.json"
    if not path.exists():
        print(f"  SKIP {locale}: output file not found at {path}", file=sys.stderr)
        return None
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def main(argv: list[str]) -> int:
    locales = argv if argv else LOCALES

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 1

    with CATALOG_PATH.open(encoding="utf-8") as f:
        catalog: dict = json.load(f)

    strings: dict = catalog.setdefault("strings", {})
    merged_count = 0
    skipped_locales: list[str] = []

    for locale in locales:
        translations = load_translations(locale)
        if translations is None:
            skipped_locales.append(locale)
            continue

        locale_merged = 0
        for key, translated_value in translations.items():
            if key.startswith("_"):
                continue
            # Accept both flat string and {"value": "...", ...} dict produced by some models
            if isinstance(translated_value, dict):
                translated_value = translated_value.get("value", "")
            if key not in strings:
                print(f"  WARN [{locale}] key {key!r} not in catalog — skipping", file=sys.stderr)
                continue
            entry = strings[key]
            localizations = entry.setdefault("localizations", {})
            localizations[locale] = {
                "stringUnit": {
                    "state": "translated",
                    "value": translated_value,
                }
            }
            locale_merged += 1

        print(f"  Merged {locale_merged} keys for {locale}")
        merged_count += locale_merged

    with CATALOG_PATH.open("w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")

    print(f"\nMerge complete: {merged_count} total key-locale pairs written to catalog.")
    if skipped_locales:
        print(f"Skipped (no output file): {skipped_locales}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
