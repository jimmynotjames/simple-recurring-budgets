"""glossary_lines() in translate_catalog/dispatch_prompts.py: which glossary terms reach a prompt."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_catalog"))

# Loaded by path: `dispatch_prompts.py` exists in both translate_catalog/ and translate_metadata/.
_spec = importlib.util.spec_from_file_location(
    "translate_catalog_dispatch_prompts", REPO_ROOT / "scripts" / "translate_catalog" / "dispatch_prompts.py"
)
catalog_dispatch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(catalog_dispatch)


class GlossaryLinesTests(unittest.TestCase):
    def setUp(self) -> None:
        self._saved = catalog_dispatch._GLOSSARY_CACHE
        catalog_dispatch._GLOSSARY_CACHE = {
            "terms": {
                "Checklist": {"translations": {"pl": "Lista"}},
                "Reset": {"translations": {"pl": "Resetuj"}},
            }
        }

    def tearDown(self) -> None:
        catalog_dispatch._GLOSSARY_CACHE = self._saved

    def test_plural_only_string_still_gets_the_term(self) -> None:
        lines = catalog_dispatch.glossary_lines(["Your checklists are saved on this device."], "pl")
        self.assertEqual(lines, '- "Checklist" → "Lista"')

    def test_singular_still_matches(self) -> None:
        self.assertIn("Lista", catalog_dispatch.glossary_lines(["Delete Checklist"], "pl"))

    def test_a_longer_word_does_not_match(self) -> None:
        self.assertEqual(catalog_dispatch.glossary_lines(["Resetting soon"], "pl"), "")

    def test_brand_does_not_count_as_the_term(self) -> None:
        self.assertEqual(catalog_dispatch.glossary_lines(["About reChecklist"], "pl"), "")


if __name__ == "__main__":
    unittest.main()
