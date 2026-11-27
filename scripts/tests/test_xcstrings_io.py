"""The catalog writer produces the same bytes Xcode 27 does, so neither side reorders the other's keys."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_catalog"))

from paths import CATALOG_PATH as CATALOG  # noqa: E402
from xcstrings_io import is_xcode_format, write_xcstrings, xcode_key_order  # noqa: E402


# Sorted by Swift's `localizedStandardCompare`, the comparison Xcode's catalog editor imports.
LOCALIZED_STANDARD_ORDER = [
    "0", "00", "1", "a.alpha", "a.Beta", "a.Zed", "a1", "a01", "A1", "ab", "aB", "Ab", "checklist",
    "checklist.2", "checklist.menu", "checklist.Menu", "checklist2", "checklistMenu", "checklists",
    "item1", "item1.notes", "item2", "item9.notes", "item10", "item10.notes", "sample.preTrip.item9",
    "sample.preTrip.item9.notes", "sample.preTrip.item10", "upper", "Upper", "v1.2.9", "v1.2.10",
    "v1.10.0", "x.y9.z", "x.y10", "x.y10.z", "x9", "x10", "x10a", "z.z", "zz", "ZZ.a",
]
# Same source; `_` sorts before `.` there, unlike ASCII.
UNDERSCORE_ORDER = [
    "a", "a__b", "a_.b", "a_1", "a_b", "a_B", "a_c", "a._b", "a.1", "a.b", "a.B", "a.c", "a0", "a1_b", "ab",
]


class KeyOrderTests(unittest.TestCase):
    def test_matches_localized_standard_compare(self) -> None:
        for expected in (LOCALIZED_STANDARD_ORDER, UNDERSCORE_ORDER):
            shuffled = sorted(expected, key=lambda key: key[::-1])
            self.assertEqual(sorted(shuffled, key=xcode_key_order), expected)


class WriteTests(unittest.TestCase):
    def test_rewriting_the_committed_catalog_changes_no_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "Localizable.xcstrings"
            write_xcstrings(json.loads(CATALOG.read_text(encoding="utf-8")), out)
            self.assertEqual(out.read_bytes(), CATALOG.read_bytes())

    def test_format_check_rejects_code_point_order(self) -> None:
        self.assertTrue(is_xcode_format(CATALOG))
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        # Keys whose code-point and Xcode orders differ, whatever keys this catalog has.
        catalog["strings"].update({"zz.item10": {}, "zz.item9": {}})
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "Localizable.xcstrings"
            out.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True), encoding="utf-8")
            self.assertFalse(is_xcode_format(out))

    def test_no_committed_key_is_manual(self) -> None:
        # Xcode never syncs a `manual` key's comment from Swift.
        strings = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
        self.assertEqual([k for k, v in strings.items() if v.get("extractionState") == "manual"], [])

    def test_nested_objects_use_plain_sorted_order(self) -> None:
        catalog = {"version": "1.0", "strings": {"k": {"localizations": {"zh-HK": {}, "zh-Hans": {}}}}, "sourceLanguage": "en"}
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "c.xcstrings"
            write_xcstrings(catalog, out)
            text = out.read_text(encoding="utf-8")
        self.assertLess(text.index('"sourceLanguage"'), text.index('"strings"'))
        self.assertLess(text.index('"zh-HK"'), text.index('"zh-Hans"'))
        self.assertFalse(text.endswith("\n"))

    def test_quote_then_colon_inside_a_value_survives(self) -> None:
        value = 'Read it as "Checklist 18% complete": the share done.'
        catalog = {"strings": {"k": {"comment": value}}}
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "c.xcstrings"
            write_xcstrings(catalog, out)
            text = out.read_text(encoding="utf-8")
        self.assertEqual(json.loads(text)["strings"]["k"]["comment"], value)
        self.assertIn('"comment" : ', text)


if __name__ == "__main__":
    unittest.main()
