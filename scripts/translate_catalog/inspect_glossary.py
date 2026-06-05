#!/usr/bin/env python3
"""
Read-only inspector for scripts/translate_catalog/glossary.json.

Replaces the recurring ad-hoc `python3 -c "import json; g=json.load(...)"`
one-liners used to poke at the translation glossary. Pure read-only.

Glossary shape: {"meta": {...}, "protected": [...], "terms": {TERM: {
  "context", "en", "partOfSpeech", "sourceKeys", "translations": {locale: str}}}}.

Subcommands:
  info
      Print meta, protected terms, term count, and the list of English terms.
      With --kept-english, also flag, per term, how many non-en locales still
      carry the English term verbatim (a translation that never got localized).

  term TERM [TERM ...] [--locales a,b,c]
      Print each term's translations across locales (sorted), and which non-en
      locales still equal the English term.

Exit status 0 on success, 1 if a named term is missing (term).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
GLOSSARY_PATH = Path(__file__).resolve().parent / "glossary.json"


def load_glossary() -> dict:
    with open(GLOSSARY_PATH, encoding="utf-8") as f:
        return json.load(f)


def kept_english_locales(term: str, translations: dict[str, str]) -> list[str]:
    """Non-en locales whose translation is still the English term verbatim."""
    return sorted(
        loc
        for loc, val in translations.items()
        if val == term and not loc.startswith("en")
    )


def cmd_info(g: dict, args: argparse.Namespace) -> int:
    print("META:", json.dumps(g.get("meta", {}), ensure_ascii=False))
    print("PROTECTED:", json.dumps(g.get("protected", []), ensure_ascii=False))
    terms = g.get("terms", {})
    print(f"{len(terms)} terms:")
    for term in sorted(terms):
        if args.kept_english:
            tr = terms[term].get("translations", {})
            kept = kept_english_locales(term, tr)
            note = f"  | kept-English in {len(kept)} locales" if kept else ""
            print(f"  {term!r}{note}")
        else:
            print(f"  {term!r}")
    return 0


def cmd_term(g: dict, args: argparse.Namespace) -> int:
    terms = g.get("terms", {})
    requested = [loc.strip() for loc in args.locales.split(",")] if args.locales else None
    missing = False
    for term in args.terms:
        entry = terms.get(term)
        if entry is None:
            print(f"{term!r}: <NOT IN GLOSSARY>")
            missing = True
            continue
        tr = entry.get("translations", {})
        show_locs = requested if requested is not None else sorted(tr)
        print(f"{term!r}  (en={entry.get('en')!r}, pos={entry.get('partOfSpeech')!r})")
        print(f"  locale count: {len(tr)}")
        for loc in show_locs:
            print(f"    {loc:8} {tr.get(loc)!r}")
        kept = kept_english_locales(term, tr)
        print(f"  non-en locales still English: {kept}")
        print()
    return 1 if missing else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_info = sub.add_parser("info", help="meta, protected, term list")
    p_info.add_argument(
        "--kept-english",
        action="store_true",
        help="flag terms still carrying English verbatim in non-en locales",
    )

    p_term = sub.add_parser("term", help="show a term's translations across locales")
    p_term.add_argument("terms", nargs="+")
    p_term.add_argument(
        "--locales", help="comma-separated locales (default: all present for the term)"
    )

    args = parser.parse_args(argv)
    g = load_glossary()

    handler = {"info": cmd_info, "term": cmd_term}[args.cmd]
    return handler(g, args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
