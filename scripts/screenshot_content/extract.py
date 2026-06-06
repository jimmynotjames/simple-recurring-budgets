#!/usr/bin/env python3
"""
Stage the English screenshot demo-content source and compute the work manifest.

Reads the hand-authored SOURCE.json (the canonical English budget structure) in
this directory, validates it is well-formed, copies it to
tmp/screenshot-content-inputs/source.json, and writes a manifest of the target
storefronts that still need generating.

Modes:
  (default)   manifest lists ALL 49 target storefronts (full regenerate).
  --missing   manifest lists only storefronts whose runtime catalog file under
              simple-recurring-budgetsUITests/ScreenshotSeeds/ is absent or empty.

Usage:
  python3 scripts/screenshot_content/extract.py [--missing]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from content_locales import (  # noqa: E402
    CATALOG_DIR,
    INPUTS_DIR,
    OUTPUTS_DIR,
    SOURCE_JSON_PATH,
    STOREFRONT_LOCALES,
    VALID_PERIODS,
    runtime_for_storefront,
)

SOURCE_OUT = INPUTS_DIR / "source.json"
MANIFEST_OUT = INPUTS_DIR / "manifest.json"


def load_and_check_source() -> dict:
    if not SOURCE_JSON_PATH.exists():
        raise SystemExit(f"ERROR: source not found at {SOURCE_JSON_PATH}")
    data = json.loads(SOURCE_JSON_PATH.read_text(encoding="utf-8"))
    budgets = data.get("budgets")
    if not isinstance(budgets, list) or not budgets:
        raise SystemExit("ERROR: SOURCE.json must have a non-empty 'budgets' array")
    roles = [b.get("role") for b in budgets]
    if "everyday-food" not in roles:
        raise SystemExit("ERROR: SOURCE.json must include an 'everyday-food' budget")
    for b in budgets:
        if b.get("period") not in VALID_PERIODS:
            raise SystemExit(f"ERROR: SOURCE.json budget {b.get('role')!r} has invalid period {b.get('period')!r}")
        if not isinstance(b.get("expenses"), list):
            raise SystemExit(f"ERROR: SOURCE.json budget {b.get('role')!r} missing 'expenses' array")
    return data


def catalog_present(storefront: str) -> bool:
    runtime = runtime_for_storefront(storefront)
    path = CATALOG_DIR / f"{runtime}.json"
    return path.exists() and bool(path.read_text(encoding="utf-8").strip())


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--missing",
        action="store_true",
        help="Only list storefronts whose runtime catalog file is missing/empty.",
    )
    args = parser.parse_args(argv)

    source = load_and_check_source()

    INPUTS_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    with SOURCE_OUT.open("w", encoding="utf-8") as f:
        json.dump(source, f, ensure_ascii=False, indent=2)
        f.write("\n")

    if args.missing:
        manifest = [s for s in STOREFRONT_LOCALES if not catalog_present(s)]
    else:
        manifest = list(STOREFRONT_LOCALES)

    with MANIFEST_OUT.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Source staged → {SOURCE_OUT} ({len(source['budgets'])} budget(s)).")
    print(f"Manifest: {len(manifest)} storefront(s) to generate → {MANIFEST_OUT}")
    if args.missing and not manifest:
        print("All target storefronts already have a catalog entry — nothing to generate.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
