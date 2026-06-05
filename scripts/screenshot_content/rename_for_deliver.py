#!/usr/bin/env python3
"""
Rename captured screenshot folders from runtime codes to App Store storefront codes.

fastlane `snapshot` writes screenshots into fastlane/screenshots/<lang>/ where
<lang> is the `-AppleLanguages` string from the Snapfile — i.e. the app *runtime*
locale code (de, nb, ar, ...). `deliver` / `upload_to_app_store`, however, expects
folders named with App Store Connect *storefront* codes (de-DE, no, ar-SA, ...).

This step renames each runtime folder to its storefront code using the mapping in
content_locales.py (which reuses metadata_locales.RUNTIME_TO_STOREFRONT). Folders
already named with a storefront code (en-US, en-GB, en-AU, en-CA, and codes that
are identical in both systems) are left as-is.

Run after `fastlane screenshots` and before `fastlane push_screenshots`.

Usage:
  python3 scripts/screenshot_content/rename_for_deliver.py [--dry-run]
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from content_locales import (  # noqa: E402
    REPO_ROOT,
    RUNTIME_TO_STOREFRONT,
    SOURCE_LOCALE,
)

SCREENSHOTS_DIR = REPO_ROOT / "fastlane" / "screenshots"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="Print planned renames without moving anything.")
    args = parser.parse_args(argv)

    if not SCREENSHOTS_DIR.exists():
        print(f"ERROR: no screenshots dir at {SCREENSHOTS_DIR}. Run `fastlane screenshots` first.", file=sys.stderr)
        return 1

    # runtime -> storefront for the targets; en-US is already a valid storefront.
    mapping = dict(RUNTIME_TO_STOREFRONT)
    mapping[SOURCE_LOCALE] = SOURCE_LOCALE

    renamed = 0
    for runtime, storefront in mapping.items():
        if runtime == storefront:
            continue  # already a valid deliver folder name
        src = SCREENSHOTS_DIR / runtime
        if not src.is_dir():
            continue
        dst = SCREENSHOTS_DIR / storefront
        print(f"  {runtime}/ -> {storefront}/")
        if args.dry_run:
            renamed += 1
            continue
        if dst.exists():
            shutil.rmtree(dst)
        src.rename(dst)
        renamed += 1

    verb = "Would rename" if args.dry_run else "Renamed"
    print(f"\n{verb} {renamed} folder(s) to storefront codes under {SCREENSHOTS_DIR}.")

    # fastlane generates screenshots.html BEFORE this rename runs, so its image
    # paths still point at the old runtime-coded folders (e.g. ./ar/...), which
    # now 404. Rewrite those references so the inspection report stays valid.
    # Idempotent: re-running finds no stale `./<runtime>/` paths to replace.
    html = SCREENSHOTS_DIR / "screenshots.html"
    if html.exists():
        text = html.read_text(encoding="utf-8")
        fixed = 0
        for runtime, storefront in mapping.items():
            if runtime == storefront:
                continue
            old = f"./{runtime}/"
            count = text.count(old)
            if count:
                fixed += count
                if not args.dry_run:
                    text = text.replace(old, f"./{storefront}/")
        if fixed:
            if not args.dry_run:
                html.write_text(text, encoding="utf-8")
            print(f"{'Would rewrite' if args.dry_run else 'Rewrote'} {fixed} stale path ref(s) in screenshots.html")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
