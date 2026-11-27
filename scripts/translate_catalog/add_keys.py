#!/usr/bin/env python3
"""
Add new English string keys to Localizable.xcstrings.

Input: a JSON file (or - for stdin / heredoc) with shape:
  {
    "key.name": {
      "comment": "Translator comment",
      "value": "English string value"
    },
    ...
  }

Each key is added with localizations.en.stringUnit.state "translated" and no
extractionState, so a build in Xcode or sync_catalog.py keeps its comment in step
with the Swift source.

Existing keys are skipped by default; use --force to overwrite. A key that a build
in Xcode or sync_catalog.py already added from Swift (English state "new", no
translations) is not skipped: it is replaced like a new one.

Usage:
  python3 scripts/translate_catalog/add_keys.py keys.json
  python3 scripts/translate_catalog/add_keys.py - << 'EOF'
  {"my.key": {"comment": "...", "value": "English text"}}
  EOF
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from paths import CATALOG_PATH  # noqa: E402
from xcstrings_io import write_xcstrings  # noqa: E402


def make_entry(comment: str, value: str) -> dict:
    return {
        "comment": comment,
        "localizations": {
            "en": {
                "stringUnit": {
                    "state": "translated",
                    "value": value,
                }
            }
        },
    }


def extracted_only(entry: dict) -> bool:
    """True for an entry only a sync has written: no English value yet, or English still `new` and
    nothing translated."""
    localizations = entry.get("localizations", {})
    if not localizations:
        return True
    return set(localizations) == {"en"} and localizations["en"].get("stringUnit", {}).get("state") == "new"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("input", help="JSON file with new keys, or - for stdin.")
    parser.add_argument("--force", action="store_true", help="Overwrite existing keys.")
    args = parser.parse_args()

    try:
        if args.input == "-":
            new_keys: dict = json.load(sys.stdin)
        else:
            with open(args.input, encoding="utf-8") as f:
                new_keys = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError) as e:
        print(f"ERROR reading input: {e}", file=sys.stderr)
        return 1

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 1

    with CATALOG_PATH.open(encoding="utf-8") as f:
        catalog: dict = json.load(f)

    strings: dict = catalog.setdefault("strings", {})
    added: list[str] = []
    skipped: list[str] = []

    for key, entry in new_keys.items():
        comment = entry.get("comment", "")
        value = entry.get("value", "")
        if not value:
            print(f"  SKIP {key!r}: missing value", file=sys.stderr)
            skipped.append(key)
            continue
        if key in strings and not args.force and not extracted_only(strings[key]):
            print(f"  SKIP {key!r}: already in catalog (use --force to overwrite)")
            skipped.append(key)
            continue
        strings[key] = make_entry(comment, value)
        added.append(key)

    write_xcstrings(catalog, CATALOG_PATH)

    print(f"Added {len(added)} key(s): {added}")
    if skipped:
        print(f"Skipped {len(skipped)}: {skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
