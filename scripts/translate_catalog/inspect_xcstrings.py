#!/usr/bin/env python3
"""
Read-only inspector for Localizable.xcstrings.

Replaces the recurring ad-hoc `python3 -c "import json; ..."` one-liners used to
poke at the catalog during translation work. Pure read-only: never writes the
catalog. For "untranslated copy" detection (a locale value that equals the
English source) use scripts/translate_audit/untranslated_copies.py instead —
this tool deliberately does not duplicate that audit.

Subcommands:
  info
      Print sourceLanguage, key count, and every locale present in the catalog
      (with a per-locale string count).

  find SUBSTRING [--in {key,value,both}] [--ignore-case/--case-sensitive]
      List keys whose key name and/or English source value contains SUBSTRING.
      Default scans both key and English value, case-insensitive. Prints the
      English value for each hit, plus a trailing comma-separated key list
      (handy for piping into --keys / --keys-file of other pipeline scripts).

  show KEY [KEY ...] [--locales a,b,c]
      For each key, print the value + state for English and each requested
      locale (default: all locales present for that key, sorted).

Exit status is 0 on success, 1 if a named key is missing (show) or no hits
(find), so the tool composes in `&&` chains.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"


def load_catalog() -> dict:
    with open(CATALOG_PATH, encoding="utf-8") as f:
        return json.load(f)


def en_value(entry: dict) -> str:
    """English source value for a catalog entry, '' if absent."""
    return (
        entry.get("localizations", {})
        .get("en", {})
        .get("stringUnit", {})
        .get("value", "")
    )


def unit(entry: dict, loc: str) -> tuple[str | None, str | None]:
    """(value, state) for a locale on an entry; (None, None) if absent."""
    u = entry.get("localizations", {}).get(loc, {}).get("stringUnit", {})
    return u.get("value"), u.get("state")


def cmd_info(strings: dict, catalog: dict, _args: argparse.Namespace) -> int:
    print(f"sourceLanguage: {catalog.get('sourceLanguage')}")
    print(f"keys: {len(strings)}")
    counts: dict[str, int] = {}
    for entry in strings.values():
        for loc in entry.get("localizations", {}):
            counts[loc] = counts.get(loc, 0) + 1
    print(f"locales present: {len(counts)}")
    for loc in sorted(counts):
        print(f"  {loc:8} {counts[loc]} strings")
    return 0


def cmd_find(strings: dict, _catalog: dict, args: argparse.Namespace) -> int:
    needle = args.substring.lower() if args.ignore_case else args.substring
    scope = args.in_
    hits: list[tuple[str, str]] = []
    for key, entry in strings.items():
        en = en_value(entry)
        hay_key = key.lower() if args.ignore_case else key
        hay_val = en.lower() if args.ignore_case else en
        match = (
            (scope in ("key", "both") and needle in hay_key)
            or (scope in ("value", "both") and needle in hay_val)
        )
        if match:
            hits.append((key, en))
    hits.sort()
    print(f"{len(hits)} keys match {args.substring!r} (in={scope}):")
    for key, en in hits:
        print(f"  {key}")
        print(f"      en: {en!r}")
    if hits:
        print()
        print("COMMA LIST:")
        print(",".join(k for k, _ in hits))
    return 0 if hits else 1


def cmd_show(strings: dict, _catalog: dict, args: argparse.Namespace) -> int:
    requested = [loc.strip() for loc in args.locales.split(",")] if args.locales else None
    missing = False
    for key in args.keys:
        entry = strings.get(key)
        if entry is None:
            print(f"{key}\n  <KEY NOT IN CATALOG>")
            missing = True
            continue
        locs = entry.get("localizations", {})
        show_locs = requested if requested is not None else sorted(locs)
        print(key)
        env, ens = unit(entry, "en")
        print(f"   {'en':8} {env!r} [{ens}]")
        for loc in show_locs:
            if loc == "en":
                continue
            v, s = unit(entry, loc)
            print(f"   {loc:8} {v!r} [{s}]")
        print()
    return 1 if missing else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("info", help="catalog summary + locales present")

    p_find = sub.add_parser("find", help="find keys by key name / English value")
    p_find.add_argument("substring")
    p_find.add_argument(
        "--in", dest="in_", choices=["key", "value", "both"], default="both"
    )
    ci = p_find.add_mutually_exclusive_group()
    ci.add_argument("--ignore-case", dest="ignore_case", action="store_true", default=True)
    ci.add_argument("--case-sensitive", dest="ignore_case", action="store_false")

    p_show = sub.add_parser("show", help="show value+state across locales for key(s)")
    p_show.add_argument("keys", nargs="+")
    p_show.add_argument(
        "--locales", help="comma-separated locales (default: all present for the key)"
    )

    args = parser.parse_args(argv)
    catalog = load_catalog()
    strings = catalog.get("strings", {})

    handler = {"info": cmd_info, "find": cmd_find, "show": cmd_show}[args.cmd]
    return handler(strings, catalog, args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
