#!/usr/bin/env python3
"""
Extract English source strings from Localizable.xcstrings and emit a
JSON file suitable for use as translation input.

Output: tmp/translate-inputs/source.json

Each entry has the shape:
  {
    "key": {
      "value": "<English string>",
      "comment": "<translator comment>",
      "formatSpecifiers": ["<spec1>", ...]   # ordered list
    },
    ...
  }

Format specifiers captured: %@, %1$@..%9$@, %lld, %d, %ld
"""

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"
OUTPUT_PATH = REPO_ROOT / "tmp" / "translate-inputs" / "source.json"

# Matches positional (%1$@) and non-positional (%@, %lld, %d, %ld) specifiers.
FORMAT_SPEC_RE = re.compile(r"%(?:\d+\$)?[@dlu](?:ld|ll)?")


def extract_format_specifiers(value: str) -> list[str]:
    return FORMAT_SPEC_RE.findall(value)


def main() -> None:
    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        sys.exit(1)

    with CATALOG_PATH.open(encoding="utf-8") as f:
        catalog = json.load(f)

    strings: dict = catalog.get("strings", {})
    output: dict = {}

    for key, entry in sorted(strings.items()):
        en_localization = entry.get("localizations", {}).get("en", {})
        string_unit = en_localization.get("stringUnit", {})
        value = string_unit.get("value", "")
        comment = entry.get("comment", "")

        output[key] = {
            "value": value,
            "comment": comment,
            "formatSpecifiers": extract_format_specifiers(value),
        }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    (REPO_ROOT / "tmp" / "translate-outputs").mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")

    print(f"Extracted {len(output)} keys → {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
