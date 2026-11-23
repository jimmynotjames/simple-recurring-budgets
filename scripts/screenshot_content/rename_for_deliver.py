#!/usr/bin/env python3
"""
Rename captured screenshot folders from runtime codes to App Store storefront codes.

fastlane `snapshot` writes fastlane/screenshots/<lang>/ where <lang> is the
Snapfile `-AppleLanguages` string, i.e. the app *runtime* locale code (de, nb,
ar, ...). `deliver` / `upload_to_app_store` expects App Store Connect *storefront*
codes (de-DE, no, ar-SA, ...).

Renames each runtime folder to its storefront code via content_locales.py
(metadata_locales.RUNTIME_TO_STOREFRONT). Folders already storefront-named
(en-US, en-GB, en-AU, en-CA, codes identical in both systems) are left as-is.

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

    # runtime -> storefront; en-US is already a valid storefront.
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

    # fastlane generates screenshots.html BEFORE this rename, so its image paths
    # still point at runtime-coded folders (./ar/...) that now 404; rewrite them.
    # Idempotent: a re-run finds no stale `./<runtime>/` paths.
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
