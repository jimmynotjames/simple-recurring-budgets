"""The locale registry (fastlane/screenshot-config.json) is the one source of truth; every
other locale list in the repo must agree with it."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_catalog"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_audit"))

import appstore_metadata  # noqa: E402
import locales  # noqa: E402
from plural_rules import PLURAL_RULES  # noqa: E402

METADATA_LOCALES_PATH = REPO_ROOT / "fastlane" / "metadata-locales.json"


class LocaleRegistryTests(unittest.TestCase):
    def test_target_count_and_source(self) -> None:
        self.assertEqual(len(locales.LOCALES), 49)
        self.assertNotIn(locales.SOURCE_RUNTIME, locales.LOCALES)
        self.assertEqual(locales.RUNTIME_TO_STOREFRONT[locales.SOURCE_RUNTIME], "en-US")

    def test_names_cover_every_locale(self) -> None:
        for runtime in locales.LOCALES + [locales.SOURCE_RUNTIME]:
            self.assertTrue(locales.LOCALE_NAMES.get(runtime), runtime)

    def test_storefronts_match_metadata_locales_and_fastlane_tuple(self) -> None:
        registry = set(locales.RUNTIME_TO_STOREFRONT.values())
        manifest = set(json.loads(METADATA_LOCALES_PATH.read_text(encoding="utf-8"))["locales"])
        self.assertEqual(registry, manifest)
        self.assertEqual(registry, set(appstore_metadata.FASTLANE_LOCALES))

    def test_plural_rules_cover_every_target(self) -> None:
        self.assertEqual(set(locales.LOCALES), set(PLURAL_RULES))

    def test_every_target_has_one_register_call(self) -> None:
        self.assertEqual(set(locales.REGISTER), set(locales.LOCALES))
        for runtime, register in locales.REGISTER.items():
            if not register.get("form"):
                self.assertEqual(register["level"], "neutral", f"{runtime}: only a neutral register may omit its form")

    def test_register_line_states_form_and_level(self) -> None:
        for runtime, register in locales.REGISTER.items():
            line = locales.register_line(runtime)
            if register.get("form"):
                self.assertEqual(line, f"{register['form']} ({register['level']})")
            else:
                self.assertEqual(line, "", runtime)
        self.assertEqual(locales.register_line(locales.SOURCE_RUNTIME), "")

    def test_storefront_map_round_trips(self) -> None:
        for runtime, storefront in locales.RUNTIME_TO_STOREFRONT.items():
            self.assertEqual(locales.STOREFRONT_TO_RUNTIME[storefront], runtime)


if __name__ == "__main__":
    unittest.main()
