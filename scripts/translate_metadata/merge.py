#!/usr/bin/env python3
"""
Merge per-storefront transcreation JSON files into the fastlane metadata tree.

For each target storefront, reads tmp/metadata-outputs/{storefront}.json and
writes each field to fastlane/metadata/{storefront}/{field}.txt. Also copies the
PASSTHROUGH_FIELDS (name and URLs) verbatim from en-US into each storefront folder,
except fields the storefront authors itself under PASSTHROUGH_OVERRIDES.

A field that is blank or absent in en-US is unused: after merging, its file is
deleted from every target storefront, because `appstore_metadata.py prepare`
rejects an empty file. The signal comes from the en-US folder (the one
check_metadata.py reads), not from tmp/metadata-inputs/source.json.

Idempotent: re-running with identical inputs produces identical files. A blank
translated value is never written.

Usage:
  python3 scripts/translate_metadata/merge.py [storefront ...]
  # No storefronts given -> merge all target storefronts.
  # --skip-urls: do not copy the passthrough files (name and URLs).
  # --skip-clear-blank: do not delete fields that are blank in the en-US source.
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
    PASSTHROUGH_OVERRIDES,
    SOURCE_LOCALE,
    STOREFRONT_LOCALES,
    TRANSLATABLE_FIELDS,
)


def write_field(storefront: str, field: str, value: str) -> bool:
    """Write metadata/<storefront>/<field>.txt. Returns True if written."""
    if not value.strip():
        print(f"  WARN [{storefront}] {field}: empty translated value — skipping", file=sys.stderr)
        return False
    folder = METADATA_DIR / storefront
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{field}.txt").write_text(value.rstrip() + "\n", encoding="utf-8")
    return True


def remove_field(storefront: str, field: str) -> bool:
    """Delete <storefront>/<field>.txt if it exists. Returns True if a file was removed."""
    path = METADATA_DIR / storefront / f"{field}.txt"
    if not path.exists():
        return False
    path.unlink()
    return True


def blank_source_fields() -> list[str]:
    """Translatable fields that are empty (or absent) in the en-US source folder."""
    blanks: list[str] = []
    for field in TRANSLATABLE_FIELDS:
        src = METADATA_DIR / SOURCE_LOCALE / f"{field}.txt"
        value = src.read_text(encoding="utf-8").strip() if src.exists() else ""
        if not value:
            blanks.append(field)
    return blanks


def remove_blank_source_fields(storefronts: list[str]) -> int:
    """Delete every translated copy of a field that is blank in en-US."""
    removed = 0
    for field in blank_source_fields():
        for storefront in storefronts:
            if remove_field(storefront, field):
                print(f"  REMOVED [{storefront}] {field}: source is blank → translation deleted")
                removed += 1
    return removed


def copy_passthrough(storefront: str) -> int:
    """Copy the passthrough files (name and URLs) verbatim from en-US into the storefront folder.

    Byte-for-byte, deliberately: a passthrough field is the English file, so a
    storefront copy that differs from the source even by a trailing newline is a
    divergence nobody asked for, and `appstore_metadata.py prepare` hands the
    source bytes to deliver unchanged.
    """
    copied = 0
    overridden = PASSTHROUGH_OVERRIDES.get(storefront, frozenset())
    for field in PASSTHROUGH_FIELDS:
        if field in overridden:
            continue
        src = METADATA_DIR / SOURCE_LOCALE / f"{field}.txt"
        if not src.exists():
            continue
        raw = src.read_bytes()
        if not raw.strip():
            continue
        folder = METADATA_DIR / storefront
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{field}.txt").write_bytes(raw)
        copied += 1
    return copied


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--skip-urls", action="store_true",
                        help="Do not copy the passthrough files (name and URLs) from en-US.")
    parser.add_argument("--skip-clear-blank", action="store_true",
                        help="Do not delete fields that are blank in the en-US source.")
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
        raw = path.read_text(encoding="utf-8")
        if not raw.strip():
            # Empty stub (cleaned but never filled). Treat as "not produced"
            # rather than crashing on json.load(""). Only locales with real
            # content are merged.
            print(f"  SKIP {storefront}: empty output (subagent not run / produced nothing)", file=sys.stderr)
            skipped.append(storefront)
            continue
        fields: dict = json.loads(raw)

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
        print(f"Copied {urls_copied} passthrough file(s) from {SOURCE_LOCALE}.")
    if skipped:
        print(f"Skipped (no output file): {skipped}")

    if not args.skip_clear_blank:
        removed = remove_blank_source_fields(storefronts)
        if removed:
            print(f"\nRemoved {removed} field file(s) across {len(storefronts)} storefront(s) (blank in en-US source).")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
