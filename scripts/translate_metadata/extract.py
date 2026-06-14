#!/usr/bin/env python3
"""
Extract the English App Store metadata source from fastlane/metadata/en-US/ and
emit a JSON file suitable for use as transcreation input.

Default output: tmp/metadata-inputs/source.json

Each authored (non-empty) field has the shape:
  {
    "<field>": {
      "value": "<English source text>",
      "charLimit": <int>          # App Store Connect hard limit (characters)
    },
    ...
  }

Fields left blank in en-US are NOT written to source.json — it stays an
authored-fields-only map ({field: {value, charLimit}}) that validate.py and
dispatch_prompts.py consume. Blank fields are reported to the console for
visibility; merge.py and check_metadata.py independently re-derive blank-field
handling straight from the en-US source folder (blank in the source means blank in
every translation), so no consumer has to know about a special key.

Modes:
  (default)   emit source.json for every non-empty translatable en-US field.
  --missing   additionally scan every target storefront for fields that are
              absent or empty, and write manifest.json mapping
              {storefront: [fields...]} — exactly the work that remains.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
METADATA_DIR = REPO_ROOT / "fastlane" / "metadata"
INPUTS_DIR = REPO_ROOT / "tmp" / "metadata-inputs"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "metadata-outputs"
SOURCE_PATH = INPUTS_DIR / "source.json"
MANIFEST_PATH = INPUTS_DIR / "manifest.json"

sys.path.insert(0, str(Path(__file__).parent))
from metadata_locales import (  # noqa: E402
    FIELD_LIMITS,
    SOURCE_LOCALE,
    STOREFRONT_LOCALES,
    TRANSLATABLE_FIELDS,
)


def read_field(locale: str, field: str) -> str:
    """Return the stripped contents of metadata/<locale>/<field>.txt, or ""."""
    path = METADATA_DIR / locale / f"{field}.txt"
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8").strip()


def read_source() -> tuple[dict[str, dict], list[str]]:
    """Return (source, blank_fields).

    source: every translatable field with non-empty en-US content, in the
        {field: {value, charLimit}} shape every downstream script expects.
    blank_fields: TRANSLATABLE_FIELDS that are empty in en-US. Reported for
        visibility only and NOT written to source.json — merge.py and
        check_metadata.py re-derive blank handling from the en-US source folder.
    """
    source: dict[str, dict] = {}
    blank_fields: list[str] = []
    for field in TRANSLATABLE_FIELDS:
        value = read_field(SOURCE_LOCALE, field)
        if value:
            source[field] = {"value": value, "charLimit": FIELD_LIMITS[field]}
        else:
            blank_fields.append(field)
    return source, blank_fields


def find_missing(source: dict[str, dict]) -> dict[str, list[str]]:
    """Return {storefront: [fields...]} for fields absent/empty in that storefront."""
    missing: dict[str, list[str]] = {}
    for storefront in STOREFRONT_LOCALES:
        gaps = [field for field in source if not read_field(storefront, field)]
        if gaps:
            missing[storefront] = gaps
    return missing


def write_source(source: dict[str, dict]) -> None:
    INPUTS_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    with SOURCE_PATH.open("w", encoding="utf-8") as f:
        json.dump(source, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"Extracted {len(source)} field(s) from {SOURCE_LOCALE} → {SOURCE_PATH}")


def write_manifest(manifest: dict[str, list[str]]) -> None:
    INPUTS_DIR.mkdir(parents=True, exist_ok=True)
    with MANIFEST_PATH.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    pair_count = sum(len(v) for v in manifest.values())
    print(f"Manifest: {len(manifest)} storefront(s), {pair_count} field gap(s) → {MANIFEST_PATH}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--missing",
        action="store_true",
        help="Also write manifest.json of (storefront, field) gaps to fill.",
    )
    args = parser.parse_args(argv)

    if not METADATA_DIR.exists():
        print(f"ERROR: metadata dir not found at {METADATA_DIR}", file=sys.stderr)
        return 1

    source, blank_fields = read_source()
    if not source:
        print(
            f"ERROR: no non-empty translatable fields in {METADATA_DIR / SOURCE_LOCALE}. "
            "Author the English source copy first.",
            file=sys.stderr,
        )
        return 1

    write_source(source)
    if blank_fields:
        print(
            f"  Blank en-US field(s), cleared across all storefronts by merge.py: {blank_fields}"
        )

    if args.missing:
        manifest = find_missing(source)
        write_manifest(manifest)
        if not manifest:
            print("No missing or empty target fields found — nothing to translate.")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
