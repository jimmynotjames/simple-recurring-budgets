#!/usr/bin/env python3
"""
Mark existing keys' non-en translations as needs_review in Localizable.xcstrings,
WITHOUT changing the English source — so extract.py --missing re-emits them and the
normal translate pipeline re-translates them.

Use this when the *translation* of a key must change even though its English text did
not — most commonly when a glossary term was re-translated (e.g. "Carry-Over" stopped
being a protected English term and gained per-locale renderings), so every string that
embeds that term needs to flow through translation again to pick up the new wording.

This is the term-changed sibling of update_keys.py (English-changed). Unlike update_keys,
it never touches the `en` localization, so the English source and its `translated` state
are left exactly as-is.

For each key:
  - Sets every non-`en` locale entry's stringUnit.state to "needs_review"
    (en-AU, en-CA, en-GB are treated as non-en and are also invalidated)
  - For plural (`variations.plural`) entries, invalidates every category's state
  - Leaves the `en` localization untouched
  - Keys absent from the catalog cause a non-zero exit (so typos surface loudly)

Usage:
  python3 scripts/translate_catalog/invalidate_keys.py --keys k1,k2,...
  python3 scripts/translate_catalog/invalidate_keys.py --keys-file PATH
  python3 scripts/translate_catalog/invalidate_keys.py --keys k1,k2 --dry-run

Next: python3 scripts/translate_catalog/extract.py --missing
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


def parse_keys(arg: str | None, path: Path | None) -> set[str]:
    keys: list[str] = []
    if arg:
        keys.extend(k.strip() for k in arg.split(",") if k.strip())
    if path:
        with path.open(encoding="utf-8") as f:
            keys.extend(line.strip() for line in f if line.strip() and not line.startswith("#"))
    return set(keys)


def invalidate_localization(loc_entry: dict) -> int:
    """Set state→needs_review for a locale entry (flat or plural). Returns units touched."""
    touched = 0
    if "stringUnit" in loc_entry:
        loc_entry["stringUnit"]["state"] = "needs_review"
        touched += 1
    plural = loc_entry.get("variations", {}).get("plural")
    if plural:
        for unit in plural.values():
            if "stringUnit" in unit:
                unit["stringUnit"]["state"] = "needs_review"
                touched += 1
    return touched


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--keys", help="Comma-separated list of keys to invalidate.")
    parser.add_argument("--keys-file", type=Path, help="Path to a file with one key per line.")
    parser.add_argument(
        "--locales",
        help="Comma-separated locales to invalidate (default: all non-en locales). "
        "Use to re-translate a key in only some locales — e.g. when a glossary term "
        "was corrected for one market and the rest are already right.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be invalidated; do not write the catalog.",
    )
    args = parser.parse_args(argv)

    keys = parse_keys(args.keys, args.keys_file)
    if not keys:
        parser.error("must pass --keys or --keys-file with at least one key")

    if args.locales:
        target_locales = [loc.strip() for loc in args.locales.split(",") if loc.strip()]
        unknown = [loc for loc in target_locales if loc not in LOCALES]
        if unknown:
            parser.error(f"not target locales: {unknown}")
    else:
        target_locales = LOCALES

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 1

    with CATALOG_PATH.open(encoding="utf-8") as f:
        catalog: dict = json.load(f)
    strings: dict = catalog.get("strings", {})

    missing = sorted(k for k in keys if k not in strings)
    if missing:
        print(f"ERROR: {len(missing)} key(s) not in catalog:", file=sys.stderr)
        for k in missing:
            print(f"  - {k}", file=sys.stderr)
        return 1

    total_locales = 0
    for key in sorted(keys):
        localizations = strings[key].get("localizations", {})
        invalidated = 0
        for locale in target_locales:
            loc_entry = localizations.get(locale)
            if loc_entry is None:
                continue
            if invalidate_localization(loc_entry):
                invalidated += 1
        total_locales += invalidated
        print(f"  {key!r}: {invalidated} locale(s) marked needs_review")

    if args.dry_run:
        print(f"\nDry run: would invalidate {len(keys)} key(s) ({total_locales} locale entries). Catalog unchanged.")
        return 0

    write_xcstrings(catalog, CATALOG_PATH)

    print(f"\nInvalidated {len(keys)} key(s), {total_locales} locale entries marked needs_review.")
    print("Next: python3 scripts/translate_catalog/extract.py --missing")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
