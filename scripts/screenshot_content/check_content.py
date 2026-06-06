#!/usr/bin/env python3
"""
Authoritative gate for the screenshot demo-content catalog.

Walks the UI-test-bundled catalog (simple-recurring-budgetsUITests/ScreenshotSeeds/)
directly and verifies that every expected runtime locale (en-US source + all 49
target runtimes) has a non-empty file with a well-formed `budgets` array that
includes the mandatory `everyday-food` budget and stays within MAX_BUDGETS.

Exits 0 if the catalog is complete and well-formed; 1 otherwise. This is the
screenshot-content analogue of check_metadata.py.

Usage:
  python3 scripts/screenshot_content/check_content.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from content_locales import (  # noqa: E402
    CATALOG_DIR,
    MAX_BUDGETS,
    REQUIRED_ROLES,
    SOURCE_LOCALE,
    STOREFRONT_LOCALES,
    runtime_for_storefront,
)


def expected_runtimes() -> list[str]:
    runtimes = [SOURCE_LOCALE] + [runtime_for_storefront(s) for s in STOREFRONT_LOCALES]
    # De-dupe while preserving order.
    seen: dict[str, None] = {}
    for r in runtimes:
        seen.setdefault(r, None)
    return list(seen)


def main() -> int:
    issues: list[str] = []
    runtimes = expected_runtimes()

    for runtime in runtimes:
        path = CATALOG_DIR / f"{runtime}.json"
        if not path.exists() or not path.read_text(encoding="utf-8").strip():
            issues.append(f"  MISSING  {runtime}.json")
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            issues.append(f"  BADJSON  {runtime}.json: {exc}")
            continue
        budgets = data.get("budgets")
        if not isinstance(budgets, list) or not budgets:
            issues.append(f"  EMPTY    {runtime}.json: no budgets")
            continue
        if len(budgets) > MAX_BUDGETS:
            issues.append(f"  TOOMANY  {runtime}.json: {len(budgets)} budgets > {MAX_BUDGETS}")
        roles = {b.get("role") for b in budgets}
        for required in REQUIRED_ROLES:
            if required not in roles:
                issues.append(f"  NOROLE   {runtime}.json: missing {required!r}")

    if issues:
        print(f"check_content: {len(issues)} issue(s) under {CATALOG_DIR.relative_to(CATALOG_DIR.parents[1])}/\n")
        for line in issues:
            print(line)
        print(
            "\nRun the screenshot_content pipeline (extract --missing → dispatch_prompts → "
            "fan out screenshot-content-locale subagents → validate → merge) to fill the catalog."
        )
        return 1

    print(f"check_content: all {len(runtimes)} runtime locale(s) present and well-formed in the catalog.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
