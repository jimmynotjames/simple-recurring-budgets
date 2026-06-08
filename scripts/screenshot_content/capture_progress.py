#!/usr/bin/env python3
"""Report App Store screenshot *capture* progress (done vs. pending locales).

Read-only. Scans ``fastlane/screenshots/`` while (or after) ``fastlane
screenshots`` runs and prints which runtime locales have finished capturing and
which are still pending — without tailing the noisy xcodebuild/snapshot log.

A locale counts as **done** once its folder holds the final shot of the 5-shot
story (``05_settings``) for *every* capture device. Devices and the expected
locale set are both discovered, not hard-coded:

* expected locales  = the ``ScreenshotSeeds/*.json`` catalog (what gets seeded),
* device count      = the ``devices([...])`` list in ``fastlane/Snapfile``.

Folders are compared by their on-disk name. During capture these are runtime
codes (``de``, ``nb``, ``ar``) matching the seed catalog; after the
``screenshots`` lane renames them to storefront codes this script will show
everything pending (expected — run it before the rename).

Exit status: 0 when all locales are done, 1 otherwise — so it doubles as a
condition in a wait loop. ``--quiet`` prints only the one-line summary.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEEDS_DIR = ROOT / "simple-recurring-budgetsUITests" / "ScreenshotSeeds"
SHOTS_DIR = ROOT / "fastlane" / "screenshots"
SNAPFILE = ROOT / "fastlane" / "Snapfile"
FINAL_SHOT = "05_settings"  # last shot in the marketing story → locale complete


def device_count() -> int:
    """Number of devices captured per locale, read from the Snapfile."""
    try:
        text = SNAPFILE.read_text(encoding="utf-8")
    except OSError:
        return 1
    block = re.search(r"devices\(\[(.*?)\]\)", text, re.S)
    if not block:
        return 1
    return len(re.findall(r'"[^"]+"', block.group(1))) or 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--quiet", action="store_true", help="print only the summary line"
    )
    args = parser.parse_args()

    locales = sorted(p.stem for p in SEEDS_DIR.glob("*.json"))
    if not locales:
        print(f"No seed catalog found under {SEEDS_DIR}", file=sys.stderr)
        return 1

    ndev = device_count()
    done, pending = [], []
    for loc in locales:
        folder = SHOTS_DIR / loc
        finals = len(list(folder.glob(f"*-{FINAL_SHOT}.png"))) if folder.is_dir() else 0
        (done if finals >= ndev else pending).append(loc)

    print(
        f"Screenshot capture: {len(done)}/{len(locales)} locales done "
        f"({ndev} device(s) each)."
    )
    if not args.quiet:
        print(f"  done    ({len(done)}): {' '.join(done) or '—'}")
        print(f"  pending ({len(pending)}): {' '.join(pending) or '—'}")

    return 0 if not pending else 1


if __name__ == "__main__":
    sys.exit(main())
