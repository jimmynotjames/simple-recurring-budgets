#!/usr/bin/env python3
"""
Merge per-storefront transcreation JSON files into the fastlane metadata tree.

For each target storefront, reads tmp/metadata-outputs/{storefront}.json and
writes each field to fastlane/metadata/{storefront}/{field}.txt. Also copies the
PASSTHROUGH_FIELDS (URLs) verbatim from en-US into each storefront folder, since
`deliver` expects every metadata key to exist per-locale.

Idempotent: re-running with identical inputs produces identical files.
Refuses to overwrite an existing non-empty .txt with an empty value.

Usage:
  python3 scripts/translate_metadata/merge.py [storefront ...]
  # No storefronts given -> merge all target storefronts.
  # --skip-urls: do not copy the passthrough URL files.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
METADATA_DIR = REPO_ROOT / "fastlane" / "metadata"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "metadata-outputs"

sys.path.insert(0, str(Path(__file__).parent))
from metadata_locales import (  # noqa: E402
    PASSTHROUGH_FIELDS,
    SOURCE_LOCALE,
    STOREFRONT_LOCALES,
)


def write_field(storefront: str, field: str, value: str) -> bool:
    """Write metadata/<storefront>/<field>.txt. Returns True if written."""
    folder = METADATA_DIR / storefront
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{field}.txt"
    if not value.strip():
        if path.exists() and path.read_text(encoding="utf-8").strip():
            print(f"  WARN [{storefront}] {field}: empty value would clobber existing — skipping", file=sys.stderr)
            return False
    path.write_text(value.rstrip() + "\n", encoding="utf-8")
    return True


def copy_passthrough(storefront: str) -> int:
    """Copy URL files verbatim from en-US into the storefront folder."""
    copied = 0
    for field in PASSTHROUGH_FIELDS:
        src = METADATA_DIR / SOURCE_LOCALE / f"{field}.txt"
        if not src.exists():
            continue
        value = src.read_text(encoding="utf-8").strip()
        if not value:
            continue
        if write_field(storefront, field, value):
            copied += 1
    return copied


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--skip-urls", action="store_true", help="Do not copy passthrough URL files from en-US.")
    parser.add_argument("storefronts", nargs="*", help="Storefronts to merge (default: all targets).")
    args = parser.parse_args(argv)

    storefronts = args.storefronts if args.storefronts else STOREFRONT_LOCALES
    merged = 0
    urls_copied = 0
    skipped: list[str] = []

    for storefront in storefronts:
        path = OUTPUTS_DIR / f"{storefront}.json"
        if not path.exists():
            print(f"  SKIP {storefront}: output file not found at {path}", file=sys.stderr)
            skipped.append(storefront)
            continue
        with path.open(encoding="utf-8") as f:
            fields: dict = json.load(f)

        count = 0
        for field, value in fields.items():
            if field.startswith("_"):
                continue
            if isinstance(value, dict):
                value = value.get("value", "")
            if not isinstance(value, str):
                print(f"  WARN [{storefront}] {field}: non-string value — skipping", file=sys.stderr)
                continue
            if write_field(storefront, field, value):
                count += 1

        if not args.skip_urls:
            urls_copied += copy_passthrough(storefront)

        print(f"  Merged {count} field(s) for {storefront}")
        merged += count

    print(f"\nMerge complete: {merged} field(s) written across {len(storefronts) - len(skipped)} storefront(s).")
    if urls_copied:
        print(f"Copied {urls_copied} passthrough URL file(s) from {SOURCE_LOCALE}.")
    if skipped:
        print(f"Skipped (no output file): {skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
