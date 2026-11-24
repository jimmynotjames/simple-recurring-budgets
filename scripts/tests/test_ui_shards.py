"""The UI-test shards cover every class once, and ci.yml's matrix lists the same shards."""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))

import ui_shards  # noqa: E402

UI_TEST_DIR = REPO_ROOT / "simple-recurring-budgetsUITests"
CI_YML = REPO_ROOT / ".github" / "workflows" / "ci.yml"


def declared_classes() -> set[str]:
    found: set[str] = set()
    for source in UI_TEST_DIR.glob("*.swift"):
        found.update(re.findall(r"^\s*(?:final\s+)?class\s+(\w+)\s*:", source.read_text(), re.M))
    return found


class UIShardsTests(unittest.TestCase):
    def test_named_classes_exist(self) -> None:
        classes = declared_classes()
        for shard, listed in ui_shards.NAMED_SHARDS.items():
            for cls in listed:
                self.assertIn(cls, classes, f"shard {shard!r} names {cls}, which no UI test declares")
        for cls in ui_shards.ALWAYS_SKIPPED:
            self.assertIn(cls, classes)
        self.assertIn(ui_shards.WARM_UP, classes)

    def test_no_class_is_in_two_shards(self) -> None:
        listed = [cls for classes in ui_shards.NAMED_SHARDS.values() for cls in classes]
        self.assertEqual(len(listed), len(set(listed)))
        self.assertFalse(set(listed) & set(ui_shards.ALWAYS_SKIPPED))
        self.assertNotIn(ui_shards.WARM_UP, listed)

    def test_named_shard_runs_only_its_classes(self) -> None:
        self.assertEqual(
            ui_shards.args("accessibility"),
            ["-only-testing:simple-recurring-budgetsUITests/AccessibilityAuditTests"],
        )

    def test_rest_skips_every_named_class_and_the_captures(self) -> None:
        rest = ui_shards.args("rest")
        self.assertEqual(rest[0], "-only-testing:simple-recurring-budgetsUITests")
        skipped = {arg.split("/", 1)[1] for arg in rest[1:]}
        named = {cls for classes in ui_shards.NAMED_SHARDS.values() for cls in classes}
        self.assertEqual(skipped, named | set(ui_shards.ALWAYS_SKIPPED) | {ui_shards.WARM_UP})

    def test_all_runs_the_target_minus_the_captures_and_warm_up(self) -> None:
        self.assertEqual(
            ui_shards.args(),
            [
                "-only-testing:simple-recurring-budgetsUITests",
                *[f"-skip-testing:simple-recurring-budgetsUITests/{cls}" for cls in ui_shards.ALWAYS_SKIPPED],
                "-skip-testing:simple-recurring-budgetsUITests/SimulatorWarmUpTests",
            ],
        )

    def test_warm_up_selects_only_the_warm_up_class(self) -> None:
        self.assertEqual(
            ui_shards.warm_up_args(),
            ["-only-testing:simple-recurring-budgetsUITests/SimulatorWarmUpTests"],
        )
        self.assertEqual(ui_shards.main(["warm-up"]), 0)

    def test_unknown_shard_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            ui_shards.args("nope")
        self.assertEqual(ui_shards.main(["args", "nope"]), 2)

    def test_ci_matrix_lists_the_same_shards_in_order(self) -> None:
        match = re.search(r"^\s*shard:\s*\[([^\]]*)\]", CI_YML.read_text(), re.M)
        self.assertIsNotNone(match, "ci.yml's ui-tests matrix needs a one-line `shard: [...]` list")
        matrix = [name.strip().strip("'\"") for name in match.group(1).split(",")]
        self.assertEqual(matrix, ui_shards.names())


if __name__ == "__main__":
    unittest.main()
