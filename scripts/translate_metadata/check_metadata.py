#!/usr/bin/env python3
"""
Authoritative pre-submit gate for App Store metadata translations.

Walks the fastlane/metadata/ tree directly (not the tmp/ intermediates) and
verifies three invariants:

  1. For every translatable field the en-US source has authored (non-empty), every
     target storefront has a non-empty .txt file within the limit (UTF-8 bytes for
     `keywords`, characters otherwise).

  2. For every translatable field that is blank or absent in en-US, no target
     storefront has content for it.

  3. No locale folder (en-US or a target) holds an empty or whitespace-only .txt,
     which `appstore_metadata.py prepare` rejects. Delete the file instead.

Also verifies the passthrough files (name and URLs) exist per storefront when en-US
has them.

Exits 0 if the metadata tree satisfies all three invariants; 1 otherwise.
This is the metadata analogue of scripts/check_translations.py.

Usage:
  python3 scripts/translate_metadata/check_metadata.py [--json]

  --json   emit {"issues": [...]} instead of the human-readable report
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
METADATA_DIR = REPO_ROOT / "fastlane" / "metadata"
LOCALE_MANIFEST_PATH = REPO_ROOT / "fastlane" / "metadata-locales.json"

sys.path.insert(0, str(Path(__file__).parent))
from metadata_locales import (  # noqa: E402
    FIELD_BYTE_LIMITS,
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


def empty_files(locales: list[str]) -> list[Path]:
    """Every whitespace-only .txt in these locale folders, which prepare rejects."""
    found: list[Path] = []
    for locale in locales:
        folder = METADATA_DIR / locale
        if folder.is_dir():
            found.extend(p for p in sorted(folder.glob("*.txt")) if not p.read_text(encoding="utf-8").strip())
    return found


def assert_registry_matches_fastlane() -> None:
    """Fail loud if the locale registry and the deliver-facing locale list drift apart.

    `appstore_metadata.py` expands the en-US source into one folder per locale in
    fastlane/metadata-locales.json and pins that file to fastlane's own list. This
    pipeline generates those folders from the registry in screenshot-config.json.
    If the two sets ever differ, deliver would either reject a folder or silently
    ship English for a storefront nobody transcreated.
    """
    manifest = set(json.loads(LOCALE_MANIFEST_PATH.read_text(encoding="utf-8"))["locales"])
    registry = set(STOREFRONT_LOCALES) | {SOURCE_LOCALE}
    if manifest != registry:
        only_manifest = sorted(manifest - registry)
        only_registry = sorted(registry - manifest)
        raise SystemExit(
            "check_metadata: locale sets disagree — "
            f"{LOCALE_MANIFEST_PATH.name} only: {only_manifest}; registry only: {only_registry}. "
            "Reconcile fastlane/screenshot-config.json with fastlane/metadata-locales.json."
        )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--json", action="store_true", help='Emit {"issues": [...]} instead of the human report.')
    args = parser.parse_args(argv)

    assert_registry_matches_fastlane()

    if not METADATA_DIR.exists():
        if args.json:
            print(json.dumps({"issues": [f"ERROR: metadata dir not found at {METADATA_DIR}"]}))
        else:
            print(f"ERROR: metadata dir not found at {METADATA_DIR}", file=sys.stderr)
        return 1

    source_fields = [f for f in TRANSLATABLE_FIELDS if read_field(SOURCE_LOCALE, f)]
    blank_source_fields = [f for f in TRANSLATABLE_FIELDS if not read_field(SOURCE_LOCALE, f)]
    if not source_fields:
        print(f"ERROR: no authored en-US fields under {METADATA_DIR / SOURCE_LOCALE}.", file=sys.stderr)
        return 1

    # Not transcreated: the URLs and `name`, copied from en-US unless overridden.
    source_passthrough = [f for f in PASSTHROUGH_FIELDS if read_field(SOURCE_LOCALE, f)]

    issues: list[str] = [
        f"  EMPTY    {path.relative_to(METADATA_DIR)}: empty file — delete it "
        "(prepare rejects explicit empty values)"
        for path in empty_files([SOURCE_LOCALE, *STOREFRONT_LOCALES])
    ]
    for storefront in STOREFRONT_LOCALES:
        for field in source_fields:
            value = read_field(storefront, field)
            if not value:
                issues.append(f"  MISSING  [{storefront}] {field}")
                continue
            # Apple counts `keywords` in UTF-8 bytes and everything else in characters.
            byte_limit = FIELD_BYTE_LIMITS.get(field)
            if byte_limit is not None:
                byte_count = len(value.encode("utf-8"))
                if byte_count > byte_limit:
                    issues.append(
                        f"  TOOLONG  [{storefront}] {field}: {byte_count} bytes > {byte_limit}"
                    )
                continue
            limit = FIELD_LIMITS.get(field)
            if limit is not None and len(value) > limit:
                issues.append(f"  TOOLONG  [{storefront}] {field}: {len(value)} > {limit}")
        for field in blank_source_fields:
            if read_field(storefront, field):
                issues.append(
                    f"  NOTEMPTY [{storefront}] {field}: source is blank but translation has content"
                    " — run merge.py to delete it"
                )
        for field in source_passthrough:
            if not read_field(storefront, field):
                issues.append(f"  MISSING  [{storefront}] {field} (copied from {SOURCE_LOCALE})")

    if args.json:
        print(json.dumps({"issues": issues}, ensure_ascii=False, indent=2))
        return 1 if issues else 0

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
    sys.exit(main(sys.argv[1:]))
