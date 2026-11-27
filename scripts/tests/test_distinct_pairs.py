"""Keys that share a screen must not collapse to the same words in any locale."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_audit"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_catalog"))

import distinct_pairs  # noqa: E402


def _catalog(values: dict[str, dict[str, str]]) -> dict:
    return {
        "strings": {
            key: {
                "localizations": {
                    lang: {"stringUnit": {"state": "translated", "value": text}}
                    for lang, text in by_lang.items()
                }
            }
            for key, by_lang in values.items()
        }
    }


class DistinctPairTests(unittest.TestCase):
    def setUp(self) -> None:
        self._pairs = distinct_pairs.DISTINCT_PAIRS
        distinct_pairs.DISTINCT_PAIRS = [("a.discard", "a.cancel", "same alert")]

    def tearDown(self) -> None:
        distinct_pairs.DISTINCT_PAIRS = self._pairs

    def test_identical_translation_is_a_collision(self) -> None:
        # The shape of the real finding: Arabic rendered both as إلغاء.
        catalog = _catalog({
            "a.discard": {"en": "Discard", "ar": "إلغاء", "de": "Verwerfen"},
            "a.cancel": {"en": "Cancel", "ar": "إلغاء", "de": "Abbrechen"},
        })
        found = distinct_pairs.find_collisions(catalog)
        self.assertEqual([(c["locale"], c["value"]) for c in found], [("ar", "إلغاء")])

    def test_comparison_ignores_case_and_spacing(self) -> None:
        catalog = _catalog({
            "a.discard": {"en": "Discard", "de": "Verwerfen "},
            "a.cancel": {"en": "Cancel", "de": "verwerfen"},
        })
        self.assertEqual(len(distinct_pairs.find_collisions(catalog)), 1)

    def test_english_source_is_never_compared(self) -> None:
        # English is the one language where the author chose the words on purpose.
        catalog = _catalog({"a.discard": {"en": "Same"}, "a.cancel": {"en": "Same"}})
        self.assertEqual(distinct_pairs.find_collisions(catalog), [])

    def test_missing_pair_key_is_reported_not_swallowed(self) -> None:
        with self.assertRaises(KeyError):
            distinct_pairs.find_collisions(_catalog({"a.discard": {"en": "Discard"}}))


class RepositoryPairsTest(unittest.TestCase):
    def test_declared_pairs_exist_in_the_catalog(self) -> None:
        import json
        catalog = json.loads(distinct_pairs.CATALOG_PATH.read_text(encoding="utf-8"))
        for first, second, _reason in distinct_pairs.DISTINCT_PAIRS:
            self.assertIn(first, catalog["strings"])
            self.assertIn(second, catalog["strings"])


if __name__ == "__main__":
    unittest.main()
