#!/usr/bin/env python3
"""Fail when two strings that share a screen collapse to the same words in a locale.

Some keys are only meaningful in contrast with a neighbour. "Discard" sits beside
"Cancel" on one alert, and English keeps them apart, but the natural rendering of
"discard" in many languages is the same word as "cancel". A translator who sees one
key at a time cannot know the two will meet, so the pipeline has to know instead.

Usage:
  python3 scripts/translate_audit/distinct_pairs.py            # exit 1 on any collision
  python3 scripts/translate_audit/distinct_pairs.py --json     # machine-readable
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "translate_catalog"))
from paths import CATALOG_PATH  # noqa: E402
import app_config  # noqa: E402

SOURCE_LANGUAGE = "en"

# Pairs that appear together and must stay distinguishable, from i18n/distinct_pairs.json. Add a
# pair there when a new key is only meaningful next to another; keep the reason, it is what a
# future reader needs to decide whether the pair still applies.
DISTINCT_PAIRS: list[tuple[str, str, str]] = app_config.distinct_pairs()


def _values(catalog: dict, key: str) -> dict[str, str]:
    entry = catalog["strings"].get(key)
    if entry is None:
        raise KeyError(key)
    return {
        language: unit.get("stringUnit", {}).get("value", "")
        for language, unit in entry.get("localizations", {}).items()
    }


def _normalize(value: str) -> str:
    return " ".join(value.split()).casefold()


def find_collisions(catalog: dict) -> list[dict]:
    collisions = []
    for first, second, reason in DISTINCT_PAIRS:
        first_values = _values(catalog, first)
        second_values = _values(catalog, second)
        for language in sorted(set(first_values) & set(second_values)):
            if language == SOURCE_LANGUAGE:
                continue
            a, b = first_values[language], second_values[language]
            if a and b and _normalize(a) == _normalize(b):
                collisions.append(
                    {"locale": language, "first": first, "second": second, "value": a, "reason": reason}
                )
    return collisions


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--json", action="store_true", help="Emit collisions as JSON.")
    args = parser.parse_args(argv)

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    try:
        collisions = find_collisions(catalog)
    except KeyError as missing:
        print(f"distinct_pairs: key {missing} in DISTINCT_PAIRS is not in the catalog", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(collisions, ensure_ascii=False, indent=2))
        return 1 if collisions else 0

    if collisions:
        print(f"distinct_pairs: {len(collisions)} collision(s) — strings that share a screen read "
              f"identically:", file=sys.stderr)
        for c in collisions:
            print(f"  {c['locale']:8} {c['first']}  ==  {c['second']}  ->  {c['value']!r}", file=sys.stderr)
        print("\nFix: re-translate the first key with a comment that names its neighbour "
              "(invalidate_keys.py, then the translate-new-strings skill).", file=sys.stderr)
        return 1

    print(f"distinct_pairs: {len(DISTINCT_PAIRS)} pair(s) distinct in every locale.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
