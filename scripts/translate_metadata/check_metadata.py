#!/usr/bin/env python3
"""
Authoritative pre-submit gate for App Store metadata translations.

Walks the fastlane/metadata/ tree directly (not the tmp/ intermediates) and
verifies two invariants:

  1. For every translatable field the en-US source has authored (non-empty), every
     target storefront has a non-empty .txt file within the character limit.

  2. For every translatable field that is blank in en-US, every target storefront
     also has an empty (or absent) .txt file. A non-empty translation for a blank
     source field means merge.py's clear step did not run; fix with `merge.py`.

Also verifies the passthrough URL files exist per storefront when en-US has them.

Exits 0 if the metadata tree satisfies both invariants; 1 otherwise.
This is the metadata analogue of scripts/check_translations.py.

Usage:
  python3 scripts/translate_metadata/check_metadata.py
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
METADATA_DIR = REPO_ROOT / "fastlane" / "metadata"

sys.path.insert(0, str(Path(__file__).parent))
from metadata_locales import (  # noqa: E402
    FIELD_LIMITS,
    PASSTHROUGH_FIELDS,
    SOURCE_LOCALE,
    STOREFRONT_LOCALES,
    TRANSLATABLE_FIELDS,
)


def read_field(locale: str, field: str) -> str:
    path = METADATA_DIR / locale / f"{field}.txt"
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8").strip()


def main() -> int:
    if not METADATA_DIR.exists():
        print(f"ERROR: metadata dir not found at {METADATA_DIR}", file=sys.stderr)
        return 1

    source_fields = [f for f in TRANSLATABLE_FIELDS if read_field(SOURCE_LOCALE, f)]
    blank_source_fields = [f for f in TRANSLATABLE_FIELDS if not read_field(SOURCE_LOCALE, f)]
    if not source_fields:
        print(f"ERROR: no authored en-US fields under {METADATA_DIR / SOURCE_LOCALE}.", file=sys.stderr)
        return 1

    source_urls = [f for f in PASSTHROUGH_FIELDS if read_field(SOURCE_LOCALE, f)]

    issues: list[str] = []
    for storefront in STOREFRONT_LOCALES:
        for field in source_fields:
            value = read_field(storefront, field)
            if not value:
                issues.append(f"  MISSING  [{storefront}] {field}")
                continue
            limit = FIELD_LIMITS.get(field)
            if limit is not None and len(value) > limit:
                issues.append(f"  TOOLONG  [{storefront}] {field}: {len(value)} > {limit}")
        for field in blank_source_fields:
            if read_field(storefront, field):
                issues.append(
                    f"  NOTEMPTY [{storefront}] {field}: source is blank but translation has content"
                    " — run merge.py to clear"
                )
        for field in source_urls:
            if not read_field(storefront, field):
                issues.append(f"  MISSING  [{storefront}] {field} (URL)")

    if issues:
        print(f"check_metadata: {len(issues)} issue(s) found under {METADATA_DIR.name}/\n")
        for line in issues:
            print(line)
        print(
            "\nRun scripts/translate_metadata/ (extract → dispatch_prompts → "
            "translate → validate → merge) to fill missing metadata before submitting."
        )
        return 1

    blank_note = f", {len(blank_source_fields)} blank" if blank_source_fields else ""
    print(
        f"check_metadata: {len(source_fields)} authored field(s) populated and within limits"
        f"{blank_note} across {len(STOREFRONT_LOCALES)} target storefront(s) (+ {SOURCE_LOCALE} source)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
