#!/usr/bin/env python3
"""
Sync the `primaryLocale` field into every screenshot demo-content catalog file.

Each catalog file (simple-recurring-budgetsUITests/ScreenshotSeeds/<runtime>.json)
carries a top-level `primaryLocale` — the region-qualified ICU locale identifier
(de_DE, ja_JP, nb_NO, …) the AppStoreScreenshots UI test launches that locale with
via `-AppleLocale`. fastlane `snapshot` only sets `-AppleLanguages`, leaving
language-only locales region-less, which makes `Locale.currency` nil and the
Settings currency-display example fall back to USD; this field fixes that without
touching production code (the production ScreenshotSeed decoder ignores the key).

`merge.py` already writes this field when (re)generating the catalog from per-locale
subagent output. This script is the deterministic backfill/sync path that operates
on the committed catalog directly — no tmp outputs or LLM regeneration needed. Run
it after editing REGION_BY_STOREFRONT or adding a locale.

Idempotent: re-running produces no diff once every file is in sync.

Usage:
  python3 scripts/screenshot_content/set_primary_locales.py [--check] [runtime ...]
  # --check: report files that are missing/stale and exit non-zero; write nothing.
  # No runtimes -> all catalog files present on disk.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from content_locales import (  # noqa: E402
    CATALOG_DIR,
    SOURCE_LOCALE,
    STOREFRONT_LOCALES,
    primary_locale_for_runtime,
    runtime_for_storefront,
)


def all_runtimes() -> list[str]:
    runtimes = [SOURCE_LOCALE] + [runtime_for_storefront(s) for s in STOREFRONT_LOCALES]
    seen: dict[str, None] = {}
    for r in runtimes:
        seen.setdefault(r, None)
    return list(seen)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="Report stale/missing files and exit non-zero; write nothing.")
    parser.add_argument("runtimes", nargs="*", help="Runtime locales to sync (default: all present on disk).")
    args = parser.parse_args(argv)

    runtimes = args.runtimes if args.runtimes else all_runtimes()
    changed: list[str] = []
    stale: list[str] = []
    missing: list[str] = []

    for runtime in runtimes:
        path = CATALOG_DIR / f"{runtime}.json"
        if not path.exists() or not path.read_text(encoding="utf-8").strip():
            missing.append(runtime)
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        expected = primary_locale_for_runtime(runtime)
        if data.get("primaryLocale") == expected and list(data.keys())[0] == "primaryLocale":
            continue
        stale.append(runtime)
        if args.check:
            continue
        # Canonical key order: primaryLocale first, then budgets (matches merge.py).
        payload = {"primaryLocale": expected, "budgets": data["budgets"]}
        with path.open("w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
            f.write("\n")
        changed.append(runtime)

    if args.check:
        if stale or missing:
            if stale:
                print(f"primaryLocale stale/absent in {len(stale)} file(s): {stale}")
            if missing:
                print(f"catalog file missing for {len(missing)} runtime(s): {missing}")
            print("Run: python3 scripts/screenshot_content/set_primary_locales.py")
            return 1
        print(f"primaryLocale in sync across {len(runtimes)} catalog file(s).")
        return 0

    print(f"Synced primaryLocale: {len(changed)} updated, {len(runtimes) - len(changed) - len(missing)} already current.")
    if missing:
        print(f"Skipped (no catalog file): {missing}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
