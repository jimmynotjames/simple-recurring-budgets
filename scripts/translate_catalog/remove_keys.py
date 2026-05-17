#!/usr/bin/env python3
"""
Remove one or more keys (with all locale entries) from Localizable.xcstrings.

Use this when Swift code drops a `String(localized: ...)` call and the catalog
key becomes orphaned. The script removes the named keys cleanly so the catalog
stays in sync with the source.

Preserves JSON ordering (sorted keys) and trailing newline so the diff is the
removal only.

Usage:
  python3 scripts/translate_catalog/remove_keys.py --keys k1,k2,...
  python3 scripts/translate_catalog/remove_keys.py --keys-file PATH
  python3 scripts/translate_catalog/remove_keys.py --keys k1,k2 --dry-run

Exits non-zero if any requested key is not present in the catalog (so typos
surface loudly).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"


def parse_keys(arg: str | None, path: Path | None) -> set[str]:
    keys: list[str] = []
    if arg:
        keys.extend(k.strip() for k in arg.split(",") if k.strip())
    if path:
        with path.open(encoding="utf-8") as f:
            keys.extend(line.strip() for line in f if line.strip() and not line.startswith("#"))
    return set(keys)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--keys", help="Comma-separated list of keys to remove.")
    parser.add_argument("--keys-file", type=Path, help="Path to a file with one key per line.")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be removed; do not write the catalog.",
    )
    args = parser.parse_args(argv)

    keys = parse_keys(args.keys, args.keys_file)
    if not keys:
        parser.error("must pass --keys or --keys-file with at least one key")

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 1

    with CATALOG_PATH.open(encoding="utf-8") as f:
        catalog: dict = json.load(f)
    strings: dict = catalog.get("strings", {})

    missing = sorted(k for k in keys if k not in strings)
    present = sorted(k for k in keys if k in strings)

    if missing:
        print(f"ERROR: {len(missing)} key(s) not in catalog:", file=sys.stderr)
        for k in missing:
            print(f"  - {k}", file=sys.stderr)
        return 1

    for k in present:
        print(f"  remove {k}")
        if not args.dry_run:
            del strings[k]

    if args.dry_run:
        print(f"\nDry run: would remove {len(present)} key(s). Catalog unchanged.")
        return 0

    with CATALOG_PATH.open("w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")

    print(f"\nRemoved {len(present)} key(s). Catalog now has {len(strings)} keys.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
