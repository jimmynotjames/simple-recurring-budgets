#!/usr/bin/env python3
"""
Extract English source + every locale's CURRENT translation from
Localizable.xcstrings, for the translation-quality audit (Track B).

Unlike scripts/translate_catalog/extract.py (which emits only the English source
for *translating*), this emits the existing translations too, so an auditor can
grade them. Writes tmp/translate-audit-inputs/audit_source.json:

  {
    "key": {
      "value": "<English source>",
      "comment": "<translator comment>",
      "formatSpecifiers": ["%@", ...],
      "translations": { "de": "<de string>", "ja": "<ja string>", ... }
    },
    ...
  }

Only flat `stringUnit` translations are captured; a key whose locale entry uses a
plural/device `variations` block is skipped *for that locale* (consistent with the
translate pipeline's subset mode). `check_translations.py` remains the structural gate.

Reuses scripts/translate_catalog/{locales.py, extract.py} via import (no duplication).

Modes:
  (default)          every translatable key, all target locales
  --keys k1,k2,...   only these keys
  --keys-file PATH   keys from a file (one per line; '#' comments ignored)
  positional locales restrict output to those target locales
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"
CATALOG_DIR = REPO_ROOT / "scripts" / "translate_catalog"
AUDIT_INPUTS_DIR = REPO_ROOT / "tmp" / "translate-audit-inputs"
AUDIT_SOURCE_PATH = AUDIT_INPUTS_DIR / "audit_source.json"

# Reuse the catalog pipeline's single sources of truth.
sys.path.insert(0, str(CATALOG_DIR))
from locales import LOCALES  # noqa: E402
from extract import extract_format_specifiers  # noqa: E402


def stringunit_value(localization: dict | None) -> str | None:
    """Return the flat stringUnit value, or None if absent or a variations block."""
    if not localization:
        return None
    if "variations" in localization:
        return None  # plural/device variations: not handled in audit subset mode
    value = localization.get("stringUnit", {}).get("value")
    return value if value else None


def is_translatable(entry: dict) -> bool:
    return entry.get("shouldTranslate", True)


def build_entry(key: str, strings: dict, locales: list[str]) -> dict:
    entry = strings[key]
    localizations = entry.get("localizations", {})
    en_value = stringunit_value(localizations.get("en")) or ""
    translations: dict[str, str] = {}
    for locale in locales:
        val = stringunit_value(localizations.get(locale))
        if val is not None:
            translations[locale] = val
    return {
        "value": en_value,
        "comment": entry.get("comment", ""),
        "formatSpecifiers": extract_format_specifiers(en_value),
        "translations": translations,
    }


def parse_keys(arg: str | None, path: Path | None) -> list[str] | None:
    keys: list[str] = []
    if arg:
        keys.extend(k.strip() for k in arg.split(",") if k.strip())
    if path:
        with path.open(encoding="utf-8") as f:
            keys.extend(line.strip() for line in f if line.strip() and not line.startswith("#"))
    return keys or None


def write_source(entries: dict) -> None:
    AUDIT_INPUTS_DIR.mkdir(parents=True, exist_ok=True)
    with AUDIT_SOURCE_PATH.open("w", encoding="utf-8") as f:
        json.dump(entries, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    pair_count = sum(len(v["translations"]) for v in entries.values())
    print(f"Extracted {len(entries)} key(s), {pair_count} (key,locale) translation pair(s) → {AUDIT_SOURCE_PATH}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--keys", help="Comma-separated list of keys to extract.")
    parser.add_argument("--keys-file", type=Path, help="Path to a file with one key per line.")
    parser.add_argument("locales", nargs="*", help="Target locales to include (default: all in locales.py).")
    args = parser.parse_args(argv)

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 1

    locales = args.locales if args.locales else LOCALES
    unknown_locales = [loc for loc in locales if loc not in LOCALES]
    if unknown_locales:
        print(f"ERROR: not target locales: {unknown_locales}", file=sys.stderr)
        return 2

    with CATALOG_PATH.open(encoding="utf-8") as f:
        catalog = json.load(f)
    strings: dict = catalog.get("strings", {})

    explicit_keys = parse_keys(args.keys, args.keys_file)
    if explicit_keys is not None:
        unknown = [k for k in explicit_keys if k not in strings]
        if unknown:
            print(f"ERROR: keys not in catalog: {unknown}", file=sys.stderr)
            return 2
        keys = explicit_keys
    else:
        keys = [k for k, v in strings.items() if is_translatable(v)]

    entries = {k: build_entry(k, strings, locales) for k in sorted(keys)}
    write_source(entries)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
