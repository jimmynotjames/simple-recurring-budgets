#!/usr/bin/env python3
"""
Rename string keys in Localizable.xcstrings, preserving all translations.

Use when a key identifier changes (e.g. a UI element moved to a different
screen) but the displayed text and all translations stay the same. No
re-translation is needed after a pure rename.

Input: a JSON file (or - for stdin / heredoc) mapping old key → new key:
  {
    "old.key.name": "new.key.name",
    ...
  }

For each pair:
  - Copies the entire entry (comment, extractionState, all localizations)
    from old key to new key
  - Removes the old key
  - Skips pairs where old key is absent (warn)
  - Skips pairs where new key already exists unless --force is given (warn)

Usage:
  python3 scripts/translate_catalog/rename_keys.py renames.json
  python3 scripts/translate_catalog/rename_keys.py renames.json --dry-run
  python3 scripts/translate_catalog/rename_keys.py - << 'EOF'
  {"old.key.name": "new.key.name"}
  EOF
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"

sys.path.insert(0, str(Path(__file__).parent))
from xcstrings_io import write_xcstrings  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("input", help="JSON file mapping old→new key names, or - for stdin.")
    parser.add_argument("--force", action="store_true", help="Overwrite new key if it already exists.")
    parser.add_argument("--dry-run", action="store_true", help="Print what would change; do not write.")
    args = parser.parse_args()

    try:
        if args.input == "-":
            renames: dict = json.load(sys.stdin)
        else:
            with open(args.input, encoding="utf-8") as f:
                renames = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError) as e:
        print(f"ERROR reading input: {e}", file=sys.stderr)
        return 1

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 1

    with CATALOG_PATH.open(encoding="utf-8") as f:
        catalog: dict = json.load(f)

    strings: dict = catalog.setdefault("strings", {})
    renamed: list[tuple[str, str]] = []
    skipped: list[str] = []

    for old_key, new_key in renames.items():
        if old_key not in strings:
            print(f"  SKIP {old_key!r}: not in catalog", file=sys.stderr)
            skipped.append(old_key)
            continue
        if new_key in strings and not args.force:
            print(
                f"  SKIP {old_key!r} → {new_key!r}: new key already exists (use --force to overwrite)",
                file=sys.stderr,
            )
            skipped.append(old_key)
            continue
        if not args.dry_run:
            strings[new_key] = copy.deepcopy(strings[old_key])
            del strings[old_key]
        print(f"  {old_key!r} → {new_key!r}")
        renamed.append((old_key, new_key))

    if args.dry_run:
        print(f"\nDry run: would rename {len(renamed)} key(s), skip {len(skipped)}. Catalog unchanged.")
        return 0

    write_xcstrings(catalog, CATALOG_PATH)

    print(f"\nDone: {len(renamed)} key(s) renamed, {len(skipped)} skipped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
