#!/usr/bin/env python3
"""The UI-test shards: which simple-recurring-budgetsUITests classes each CI `ui-tests` job runs.

The one place shards are defined. ci.yml's `ui-tests` matrix lists the same names (a test in
scripts/tests/test_ui_shards.py keeps them equal), and scripts/ui-tests.sh asks this script for
its xcodebuild selection.

Each named shard runs the classes listed for it. The last shard, `rest`, runs every other class in
the target, so a new UI test class lands in `rest` without anyone editing this file. The
screenshot captures and the Xcode template classes are skipped everywhere: the captures have
their own drivers (fastlane, translation-accessibility-size-check).

Balance shards by CI job time, not test count: move a class between named shards, or name a new
shard, when one `ui-tests` job runs well over the others.

    ui_shards.py names          the shard names, one per line, in matrix order
    ui_shards.py args [SHARD]   xcodebuild -only-testing/-skip-testing flags, one per line;
                                no SHARD (or `all`) selects the whole target
"""

from __future__ import annotations

import sys

TARGET = "simple-recurring-budgetsUITests"

# Never part of a test run: the screenshot captures (opt-in; they have their own drivers) and the
# Xcode template classes, whose testExample / testLaunchPerformance are excluded on purpose.
ALWAYS_SKIPPED = (
    "AppStoreScreenshots",
    "LocalizationScreenshotCapture",
    "simple_recurring_budgetsUITests",
    "simple_recurring_budgetsUITestsLaunchTests",
)

NAMED_SHARDS: dict[str, tuple[str, ...]] = {
    # The slowest suite (~8 min).
    "accessibility": ("AccessibilityAuditTests",),
    "user-journey": ("UserJourneyTests",),
}
REST = "rest"


def names() -> list[str]:
    return [*NAMED_SHARDS, REST]


def args(shard: str = "all") -> list[str]:
    if shard in NAMED_SHARDS:
        return [f"-only-testing:{TARGET}/{cls}" for cls in NAMED_SHARDS[shard]]
    if shard not in (REST, "all"):
        raise ValueError(f"unknown UI shard {shard!r}; one of: {', '.join(names())}")
    skipped = list(ALWAYS_SKIPPED)
    if shard == REST:
        skipped += [cls for classes in NAMED_SHARDS.values() for cls in classes]
    return [f"-only-testing:{TARGET}"] + [f"-skip-testing:{TARGET}/{cls}" for cls in skipped]


def main(argv: list[str]) -> int:
    if argv[:1] == ["names"] and len(argv) == 1:
        print("\n".join(names()))
        return 0
    if argv[:1] == ["args"] and len(argv) <= 2:
        try:
            print("\n".join(args(argv[1] if len(argv) == 2 else "all")))
        except ValueError as error:
            print(f"error: {error}", file=sys.stderr)
            return 2
        return 0
    print("usage: ui_shards.py names | ui_shards.py args [SHARD]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
