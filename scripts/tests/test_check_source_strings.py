"""Unkeyed copy must be caught wherever it hides, not only at the UI call site."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import check_source_strings as checker  # noqa: E402


def _errors_for(swift: str) -> list[str]:
    with tempfile.TemporaryDirectory(dir=REPO_ROOT / "tmp") as tmp:
        path = Path(tmp) / "Sample.swift"
        path.write_text(swift, encoding="utf-8")
        errors, _warnings = checker.check([path])
    return [e["message"].split(" — ")[0] for e in errors]


class TernaryLiteralTests(unittest.TestCase):
    """A ternary between two capitalized literals is copy parked in a local.

    `let title = flag ? "Discard Checklist" : "Delete Checklist"` never hands a
    literal to a UI call on the line the checker reads.
    """

    def test_single_line_ternary_reports_both_branches(self) -> None:
        errors = _errors_for('let title = flag ? "Discard Checklist" : "Delete Checklist"\n')
        self.assertEqual(errors, ["'Discard Checklist'", "'Delete Checklist'"])

    def test_multiline_ternary_reports_each_continuation(self) -> None:
        errors = _errors_for(
            "let message = flag\n"
            '  ? "Discard this checklist? This cannot be undone."\n'
            '  : "Are you sure? This cannot be undone."\n'
        )
        self.assertEqual(
            errors,
            ["'Discard this checklist? This cannot be undone.'", "'Are you sure? This cannot be undone.'"],
        )

    def test_lowercase_identifier_ternary_is_ignored(self) -> None:
        # Identifier switches are everywhere and are not copy.
        self.assertEqual(_errors_for('let name = flag ? "trash" : "ellipsis.circle"\n'), [])

    def test_dictionary_entry_is_not_a_ternary_continuation(self) -> None:
        self.assertEqual(_errors_for('  "Title": "Hello there",\n'), [])

    def test_keyed_ternary_is_clean(self) -> None:
        self.assertEqual(
            _errors_for("let title = flag ? Self.discardChecklistMenuTitle : Self.deleteChecklistMenuTitle\n"),
            [],
        )


class ExistingPatternTests(unittest.TestCase):
    def test_bare_text_literal_is_reported(self) -> None:
        self.assertEqual(_errors_for('Text("Settings")\n'), ["'Settings'"])

    def test_verbatim_and_keyed_are_clean(self) -> None:
        swift = (
            'Text(verbatim: "")\n'
            'Text(String(localized: "settings.title", defaultValue: "Settings", comment: "Screen title."))\n'
        )
        self.assertEqual(_errors_for(swift), [])

    def test_suppression_marker_silences_a_line(self) -> None:
        self.assertEqual(_errors_for(f'Text("Build 42")  {checker.SUPPRESS_MARKER}\n'), [])


if __name__ == "__main__":
    unittest.main()
