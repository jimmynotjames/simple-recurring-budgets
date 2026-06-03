#!/usr/bin/env python3
"""
Convert existing flat keys in Localizable.xcstrings into **plural** keys (CLDR
`variations.plural`), so count-dependent strings like "%lld logged expense(s)" get
grammatically correct forms in every language.

For each key you pass, this sets the English (`en`) localization to a
`variations.plural` block with the categories you provide, and **removes every
non-en locale entry** for that key so `extract.py --missing` re-translates it as a
plural (each locale then gets the categories *that* language needs). Run the normal
translate flow afterward.

Input: JSON (file path or - for stdin) mapping each key to its English plural forms:
  {
    "addEditBudget.orphanWarning.title": {
      "one":   "Start date is after %lld logged expense",
      "other": "Start date is after %lld logged expenses"
    }
  }

`other` is required; include `one` (and any other CLDR category English needs).
Keys absent from the catalog, or already plural, are skipped with a warning.

Usage:
  python3 scripts/translate_catalog/pluralize_keys.py updates.json
  python3 scripts/translate_catalog/pluralize_keys.py -            # JSON on stdin
  python3 scripts/translate_catalog/pluralize_keys.py --dry-run updates.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"

sys.path.insert(0, str(Path(__file__).parent))
from extract import CLDR_CATEGORIES  # noqa: E402


def load_updates(arg: str) -> dict:
    raw = sys.stdin.read() if arg == "-" else Path(arg).read_text(encoding="utf-8")
    return json.loads(raw)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("updates", help="JSON file (or - for stdin) of {key: {category: english}}.")
    parser.add_argument("--dry-run", action="store_true", help="Report what would change; write nothing.")
    args = parser.parse_args(argv)

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 1

    updates = load_updates(args.updates)
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    strings = catalog.setdefault("strings", {})

    changed = 0
    for key, forms in updates.items():
        if key not in strings:
            print(f"  SKIP {key!r}: not in catalog", file=sys.stderr)
            continue
        if not isinstance(forms, dict) or "other" not in forms:
            print(f"  SKIP {key!r}: needs an object with at least 'other'", file=sys.stderr)
            continue
        bad = [c for c in forms if c not in CLDR_CATEGORIES]
        if bad:
            print(f"  SKIP {key!r}: invalid categories {bad} (allowed: {list(CLDR_CATEGORIES)})", file=sys.stderr)
            continue
        localizations = strings[key].setdefault("localizations", {})
        if "plural" in localizations.get("en", {}).get("variations", {}):
            print(f"  SKIP {key!r}: already plural", file=sys.stderr)
            continue

        # Set en → plural; drop every other locale so extract --missing re-translates as plural.
        localizations.clear()
        localizations["en"] = {
            "variations": {
                "plural": {cat: {"stringUnit": {"state": "translated", "value": val}}
                           for cat, val in forms.items()}
            }
        }
        n_cats = len(forms)
        print(f"  {'(dry-run) ' if args.dry_run else ''}pluralized {key!r}: en {n_cats} category(ies); "
              "all non-en locales cleared for re-translation")
        changed += 1

    if not args.dry_run and changed:
        with CATALOG_PATH.open("w", encoding="utf-8") as f:
            json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.write("\n")
    print(f"\n{'Would convert' if args.dry_run else 'Converted'} {changed} key(s). "
          "Next: extract.py --missing → dispatch → translate → validate → merge.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
