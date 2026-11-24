#!/usr/bin/env python3
"""
Grow the glossary as the app gains repeated terminology.

After translations change, run `--detect` to find English terms that now recur across
keys but are NOT yet in glossary.json. Repeated *exact* strings (under >= --min-keys
keys) are **high-confidence** new terms, written to tmp/glossary/terms.json in the
curated shape, ready to translate. Uncovered frequent single words go to
tmp/glossary/candidates_review.json for human review (ambiguous; a word isn't always
a term worth pinning).

Not every exact duplicate is terminology: placeholders ("0"), full accessibility
sentences, and "Label, %@" a11y strings recur (often because a key has a `.recurring.`
twin). Those are listed in IGNORED_NONTERMS, a small hand-curated set, and skipped.
It's an explicit list, not a content heuristic, on purpose: the recurrence is
idiosyncratic and a guessy rule could silently drop a real future term.

Never calls an LLM. To add the detected high-confidence terms:
    python3 scripts/translate_catalog/glossary_sync.py --detect
    # then run the standard glossary translate cycle on the new terms:
    python3 scripts/translate_catalog/glossary_build.py --dispatch
    # … fan out glossary-locale (Opus) agents over tmp/glossary/prompts/{locale}.md …
    python3 scripts/translate_catalog/glossary_build.py --merge   # appends to glossary.json

Usage:
  python3 scripts/translate_catalog/glossary_sync.py --detect [--min-keys N]
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import glossary_build as gb  # noqa: E402

REVIEW_PATH = gb.GLOSSARY_DIR / "candidates_review.json"

# Exact English strings that recur across keys but are deliberately NOT glossary terms
# (so `--detect` stops proposing them). The glossary pins recurring *terminology*
# ("Carry-Over", "Add Funds"); these are placeholders / numbers / full accessibility
# strings whose recurrence is incidental (a bare placeholder shared by two fields, or a
# key and its `.recurring.` twin with identical text). Hand-curated rather than a
# heuristic: a guessy content rule risks silently dropping a real future term. Each
# entry notes why.
#
# Add an entry when `--detect` surfaces a genuine non-term; the staleness check below
# warns if an entry stops recurring. Matched whitespace-/case-insensitively via
# _normset, like the glossary `known` check.
IGNORED_NONTERMS = {
    "0",  # placeholder digit in the allocation / amount fields — locale-invariant, not a term
    "End date, %@",  # VoiceOver "Label, value" label; recurs only via the base/.recurring. key twin
    "Start date, %@",  # ditto
    "Opens a calendar to pick the start date.",  # VoiceOver hint sentence; recurs via the twin
}


def _normset(values) -> set[str]:
    return {" ".join(v.split()).casefold() for v in values}


def cmd_detect(min_keys: int) -> int:
    strings = gb.load_catalog()
    items = gb.translatable_items(strings)
    glossary = gb.load_glossary()
    known = _normset(glossary.get("terms", {}).keys())
    ignored = _normset(IGNORED_NONTERMS)

    # High-confidence: exact-duplicate English strings not already a glossary term.
    dup: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for key, en, comment in items:
        dup[en].append((key, comment))
    new_terms = []
    filtered_nonterms = 0
    ignored_seen: set[str] = set()  # which IGNORED_NONTERMS actually still recur (staleness check)
    for en, ks in sorted(dup.items(), key=lambda kv: (-len(kv[1]), kv[0].casefold())):
        if len(ks) < min_keys:
            continue
        normed = " ".join(en.split()).casefold()
        if normed in known:
            continue
        # Skip curated non-terms (see IGNORED_NONTERMS).
        if normed in ignored:
            ignored_seen.add(normed)
            filtered_nonterms += 1
            continue
        comments = sorted({c for _, c in ks if c})
        new_terms.append({
            "en": en,
            "context": comments[0] if comments else f"Repeated across {len(ks)} keys.",
            "partOfSpeech": "",
            "sourceKeys": [k for k, _ in ks],
        })

    # Ambiguous: frequent content words not yet covered (for human review).
    word_df: dict[str, set[str]] = defaultdict(set)
    for key, en, _ in items:
        for tok in {t.casefold() for t in gb.TOKEN_RE.findall(en)}:
            if tok in gb.STOPWORDS or len(tok) < 2:
                continue
            word_df[tok].add(key)
    review = [
        {"word": w, "df": len(keys), "exampleKeys": sorted(keys)[:6]}
        for w, keys in sorted(word_df.items(), key=lambda kv: (-len(kv[1]), kv[0]))
        if len(keys) >= 3 and w not in known and w not in {p.casefold() for p in gb.PROTECTED}
    ]

    gb.GLOSSARY_DIR.mkdir(parents=True, exist_ok=True)
    with gb.TERMS_PATH.open("w", encoding="utf-8") as f:
        json.dump({"terms": new_terms}, f, ensure_ascii=False, indent=2)
        f.write("\n")
    with REVIEW_PATH.open("w", encoding="utf-8") as f:
        json.dump({"frequentWordsNotInGlossary": review}, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Detected {len(new_terms)} high-confidence new term(s) (exact string in >= {min_keys} keys) "
          f"→ {gb.TERMS_PATH}")
    if filtered_nonterms:
        print(f"Filtered {filtered_nonterms} curated non-term duplicate(s) — see IGNORED_NONTERMS.")
    # Staleness: surface ignore entries that no longer recur so the list gets pruned.
    stale = sorted(s for s in IGNORED_NONTERMS if " ".join(s.split()).casefold() not in ignored_seen)
    if stale:
        print(f"WARNING: {len(stale)} IGNORED_NONTERMS entr(y/ies) no longer recur in the catalog "
              f"(remove them): {stale}")
    print(f"Wrote {len(review)} ambiguous frequent word(s) for review → {REVIEW_PATH}")
    if new_terms:
        print("\nTo add the high-confidence terms to glossary.json:")
        print("  python3 scripts/translate_catalog/glossary_build.py --dispatch")
        print("  # fan out glossary-locale (Opus) agents over tmp/glossary/prompts/{locale}.md")
        print("  python3 scripts/translate_catalog/glossary_build.py --merge")
    else:
        print("\nNo new high-confidence terms — glossary is current.")
    return 1 if new_terms else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--detect", action="store_true", required=True,
                        help="Detect repeated terminology not yet in the glossary.")
    parser.add_argument("--min-keys", type=int, default=2,
                        help="An exact English string must appear in >= N keys to auto-add (default 2).")
    args = parser.parse_args(argv)
    if not gb.CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {gb.CATALOG_PATH}", file=sys.stderr)
        return 2
    return cmd_detect(args.min_keys)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
