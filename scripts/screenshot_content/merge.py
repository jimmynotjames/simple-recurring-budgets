#!/usr/bin/env python3
"""
Merge per-storefront demo-content JSON into the UI-test-bundled catalog.

For each target storefront, reads tmp/screenshot-content-outputs/{storefront}.json,
strips the optional `_questions` array, and writes the runtime-keyed catalog file
  simple-recurring-budgetsUITests/ScreenshotSeeds/{runtime}.json
(storefront -> runtime mapping owned by content_locales.py). Also writes the en-US
catalog entry verbatim from the staged source.json.

The catalog lives in the UI test target so these marketing fixtures never ship in
the production app bundle. The AppStoreScreenshots UI test loads the file matching
the `-AppleLanguages` value fastlane `snapshot` launches with.

Usage:
  python3 scripts/screenshot_content/merge.py [storefront ...]
  # No storefronts -> merge all targets (+ always refresh en-US from source).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from content_locales import (  # noqa: E402
    CATALOG_DIR,
    INPUTS_DIR,
    OUTPUTS_DIR,
    SOURCE_LOCALE,
    STOREFRONT_LOCALES,
    runtime_for_storefront,
)

SOURCE_PATH = INPUTS_DIR / "source.json"


def write_catalog(runtime: str, data: dict) -> None:
    CATALOG_DIR.mkdir(parents=True, exist_ok=True)
    payload = {"budgets": data["budgets"]}
    path = CATALOG_DIR / f"{runtime}.json"
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")


def main(argv: list[str]) -> int:
    storefronts = argv if argv else list(STOREFRONT_LOCALES)

    # Always (re)write the en-US source entry from the staged source.
    if SOURCE_PATH.exists():
        source = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
        write_catalog(SOURCE_LOCALE, source)
        print(f"  Wrote {SOURCE_LOCALE} catalog from source")
    else:
        print(f"  WARN: {SOURCE_PATH} missing — skipped en-US source entry", file=sys.stderr)

    merged = 0
    skipped: list[str] = []
    for storefront in storefronts:
        path = OUTPUTS_DIR / f"{storefront}.json"
        if not path.exists() or not path.read_text(encoding="utf-8").strip():
            skipped.append(storefront)
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        if "budgets" not in data:
            print(f"  SKIP {storefront}: no 'budgets' key", file=sys.stderr)
            skipped.append(storefront)
            continue
        runtime = runtime_for_storefront(storefront)
        write_catalog(runtime, data)
        merged += 1

    print(f"\nMerged {merged} storefront(s) into {CATALOG_DIR}.")
    if skipped:
        print(f"Skipped (no output): {skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
