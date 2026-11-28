"""ci.yml skips its macOS work only when every changed path is docs-only."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))

from docs_only import has_code  # noqa: E402


class DocsOnlyTests(unittest.TestCase):
    def test_docs_paths_alone_are_not_code(self) -> None:
        for path in (
            "AGENTS.md",
            "README.md",
            "fastlane/SETUP.md",
            "docs/main-prd.md",
            "docs/images/screen.png",
            "openspec/changes/archive/2026-01-01-x/proposal.md",
            "releases/2.0.md",
            ".claude/skills/merge-pr/SKILL.md",
            ".claude/settings.json",
            ".github/pull_request_template.md",
        ):
            with self.subTest(path=path):
                self.assertFalse(has_code([path]))

    def test_code_paths_are_code(self) -> None:
        for path in (
            "simple-recurring-budgets/Views/BudgetsView.swift",
            "simple-recurring-budgetsTests/FooTests.swift",
            "simple-recurring-budgetsUITests/NOTES.md",
            "Makefile",
            "LICENSE",
            "scripts/build.sh",
            "scripts/translate_catalog/PROMPT_TEMPLATE.md",
            "i18n/brief.md",
            "fastlane/Fastfile",
            ".github/workflows/ci.yml",
            "lefthook.yml",
            ".swiftlint.yml",
        ):
            with self.subTest(path=path):
                self.assertTrue(has_code([path]))

    def test_one_code_file_among_docs_is_code(self) -> None:
        self.assertTrue(has_code(["AGENTS.md", "simple-recurring-budgets/A.swift", "README.md"]))

    def test_a_rename_out_of_the_app_folder_is_code(self) -> None:
        self.assertTrue(has_code(["simple-recurring-budgets/NOTES.md", "docs/NOTES.md"]))

    def test_no_known_files_is_code(self) -> None:
        self.assertTrue(has_code([]))
        self.assertTrue(has_code(["", "  "]))


if __name__ == "__main__":
    unittest.main()
