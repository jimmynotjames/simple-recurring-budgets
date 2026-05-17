#!/usr/bin/env python3
"""
Extract English source strings from Localizable.xcstrings and emit a
JSON file suitable for use as translation input.

Default output: tmp/translate-inputs/source.json

Each entry has the shape:
  {
    "key": {
      "value": "<English string>",
      "comment": "<translator comment>",
      "formatSpecifiers": ["<spec1>", ...]   # ordered list
    },
    ...
  }

Format specifiers captured: %@, %1$@..%9$@, %lld, %d, %ld

Modes:
  (default)         emit every translatable key in the catalog
  --keys k1,k2,...  emit only the specified keys
  --keys-file PATH  emit only keys listed (one per line) in PATH
  --missing         scan the catalog for (key, locale) pairs that are
                    absent or have state in {new, needs_review, stale};
                    emit source.json for the union of missing keys AND
                    manifest.json mapping {locale: [keys...]}.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"
INPUTS_DIR = REPO_ROOT / "tmp" / "translate-inputs"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "translate-outputs"
SOURCE_PATH = INPUTS_DIR / "source.json"
MANIFEST_PATH = INPUTS_DIR / "manifest.json"

sys.path.insert(0, str(Path(__file__).parent))
from locales import LOCALES  # noqa: E402

FORMAT_SPEC_RE = re.compile(r"%(?:\d+\$)?[@dlu](?:ld|ll)?")

UNTRANSLATED_STATES = {"new", "needs_review", "stale"}


def extract_format_specifiers(value: str) -> list[str]:
    return FORMAT_SPEC_RE.findall(value)


def build_entry(key: str, strings: dict) -> dict:
    entry = strings[key]
    en_localization = entry.get("localizations", {}).get("en", {})
    string_unit = en_localization.get("stringUnit", {})
    value = string_unit.get("value", "")
    comment = entry.get("comment", "")
    return {
        "value": value,
        "comment": comment,
        "formatSpecifiers": extract_format_specifiers(value),
    }


def is_translatable(entry: dict) -> bool:
    return entry.get("shouldTranslate", True)


def find_missing(strings: dict) -> dict[str, list[str]]:
    """Return {locale: [keys...]} for keys that need translation in that locale.

    A (key, locale) pair is "missing" when the locale entry is absent or its
    stringUnit.state is in {new, needs_review, stale}. Mirrors the logic in
    check_translations.py so passing here implies passing pre-push.
    """
    missing: dict[str, list[str]] = {locale: [] for locale in LOCALES}
    for key, entry in strings.items():
        if not is_translatable(entry):
            continue
        localizations = entry.get("localizations", {})
        for locale in LOCALES:
            loc_entry = localizations.get(locale)
            if loc_entry is None:
                missing[locale].append(key)
                continue
            # Plural/device variations are not yet supported in subset mode.
            # check_translations.py remains the authoritative gate and will
            # surface any variation-shaped issues at pre-push time.
            if "variations" in loc_entry:
                continue
            state = loc_entry.get("stringUnit", {}).get("state", "")
            if state in UNTRANSLATED_STATES:
                missing[locale].append(key)
    return {locale: sorted(keys) for locale, keys in missing.items() if keys}


def write_source(keys: list[str], strings: dict) -> None:
    output = {key: build_entry(key, strings) for key in sorted(keys)}
    INPUTS_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    with SOURCE_PATH.open("w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"Extracted {len(output)} keys → {SOURCE_PATH}")


def write_manifest(manifest: dict[str, list[str]]) -> None:
    INPUTS_DIR.mkdir(parents=True, exist_ok=True)
    with MANIFEST_PATH.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    locale_count = len(manifest)
    pair_count = sum(len(v) for v in manifest.values())
    print(f"Manifest: {locale_count} locale(s), {pair_count} key-locale pair(s) → {MANIFEST_PATH}")


def parse_keys(arg: str | None, path: Path | None) -> list[str] | None:
    keys: list[str] = []
    if arg:
        keys.extend(k.strip() for k in arg.split(",") if k.strip())
    if path:
        with path.open(encoding="utf-8") as f:
            keys.extend(line.strip() for line in f if line.strip() and not line.startswith("#"))
    return keys or None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--keys", help="Comma-separated list of keys to extract.")
    parser.add_argument("--keys-file", type=Path, help="Path to a file with one key per line.")
    parser.add_argument("--missing", action="store_true", help="Extract only keys missing/stale in any locale; also writes manifest.json.")
    args = parser.parse_args()

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 1

    with CATALOG_PATH.open(encoding="utf-8") as f:
        catalog = json.load(f)
    strings: dict = catalog.get("strings", {})

    if args.missing:
        if args.keys or args.keys_file:
            print("ERROR: --missing is mutually exclusive with --keys / --keys-file", file=sys.stderr)
            return 2
        manifest = find_missing(strings)
        if not manifest:
            print("No missing or stale translations found — nothing to do.")
            # Still write empty artifacts so downstream tools don't trip on stale data.
            write_source([], strings)
            write_manifest({})
            return 0
        union_keys = sorted({k for keys in manifest.values() for k in keys})
        write_source(union_keys, strings)
        write_manifest(manifest)
        return 0

    explicit_keys = parse_keys(args.keys, args.keys_file)
    if explicit_keys is not None:
        unknown = [k for k in explicit_keys if k not in strings]
        if unknown:
            print(f"ERROR: keys not in catalog: {unknown}", file=sys.stderr)
            return 2
        write_source(explicit_keys, strings)
        return 0

    # Default: every translatable key in the catalog.
    all_keys = [k for k, v in strings.items() if is_translatable(v)]
    write_source(all_keys, strings)
    return 0


if __name__ == "__main__":
    sys.exit(main())
