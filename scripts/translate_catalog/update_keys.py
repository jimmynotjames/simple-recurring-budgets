#!/usr/bin/env python3
"""
Update the English source text (and/or comment) for existing keys in
Localizable.xcstrings, then mark all non-en translations as needs_review
so extract.py --missing picks them up for re-translation automatically.

Input: a JSON file (or - for stdin / heredoc) with shape:
  {
    "key.name": {
      "value": "New English string",
      "comment": "Updated translator hint (optional — omit to keep existing)"
    },
    ...
  }

For each key:
  - Sets localizations.en.stringUnit.value to the new value
  - Sets localizations.en.stringUnit.state to "translated"
  - Updates comment when provided (omitting leaves the existing comment intact)
  - Sets every existing non-en locale entry's stringUnit.state to "needs_review"
    (en-AU, en-CA, en-GB are treated as non-en and are also invalidated)
  - Entries with only "variations" (plural forms) are left untouched

Keys absent from the catalog are skipped with a warning — use add_keys.py
to insert brand-new keys instead.

Usage:
  python3 scripts/translate_catalog/update_keys.py updates.json
  python3 scripts/translate_catalog/update_keys.py - << 'EOF'
  {"my.key": {"value": "New English text"}}
  EOF
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"

sys.path.insert(0, str(Path(__file__).parent))
from locales import LOCALES  # noqa: E402
from xcstrings_io import write_xcstrings  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("input", help="JSON file with key updates, or - for stdin.")
    args = parser.parse_args()

    try:
        if args.input == "-":
            updates: dict = json.load(sys.stdin)
        else:
            with open(args.input, encoding="utf-8") as f:
                updates = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError) as e:
        print(f"ERROR reading input: {e}", file=sys.stderr)
        return 1

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 1

    with CATALOG_PATH.open(encoding="utf-8") as f:
        catalog: dict = json.load(f)

    strings: dict = catalog.setdefault("strings", {})
    updated: list[str] = []
    skipped: list[str] = []

    for key, entry in updates.items():
        if key not in strings:
            print(
                f"  SKIP {key!r}: not in catalog (use add_keys.py for new keys)",
                file=sys.stderr,
            )
            skipped.append(key)
            continue

        new_value = entry.get("value", "")
        new_comment = entry.get("comment")

        if not new_value:
            print(f"  SKIP {key!r}: missing value", file=sys.stderr)
            skipped.append(key)
            continue

        catalog_entry = strings[key]

        if new_comment is not None:
            catalog_entry["comment"] = new_comment

        localizations = catalog_entry.setdefault("localizations", {})
        localizations["en"] = {
            "stringUnit": {
                "state": "translated",
                "value": new_value,
            }
        }

        invalidated = 0
        for locale in LOCALES:
            loc_entry = localizations.get(locale)
            if loc_entry is None:
                continue
            if "stringUnit" in loc_entry:
                loc_entry["stringUnit"]["state"] = "needs_review"
                invalidated += 1

        print(f"  {key!r}: en updated, {invalidated} locale(s) marked needs_review")
        updated.append(key)

    write_xcstrings(catalog, CATALOG_PATH)

    print(f"\nDone: {len(updated)} key(s) updated, {len(skipped)} skipped.")
    if updated:
        print("Next: python3 scripts/translate_catalog/extract.py --missing")
    return 0


if __name__ == "__main__":
    sys.exit(main())
