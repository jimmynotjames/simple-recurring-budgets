"""The metadata transcreation pipeline must agree with the validator that gates the upload."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_catalog"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_metadata"))

import appstore_metadata  # noqa: E402
import metadata_locales as meta  # noqa: E402

# Loaded by path: `validate.py` exists in both translate_catalog/ and
# translate_metadata/, and a bare import would pick up whichever a sibling test
# module imported first.
_spec = importlib.util.spec_from_file_location(
    "translate_metadata_validate", REPO_ROOT / "scripts" / "translate_metadata" / "validate.py"
)
metadata_validate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(metadata_validate)


class MetadataLocaleTests(unittest.TestCase):
    def test_limits_come_from_the_shipping_validator(self) -> None:
        for field, limit in meta.FIELD_LIMITS.items():
            if field in meta.FIELD_BYTE_LIMITS:
                continue
            expected = appstore_metadata.FIELD_BY_FILENAME[f"{field}.txt"].max_characters
            self.assertEqual(limit, expected, field)

    def test_keywords_are_limited_in_utf8_bytes(self) -> None:
        self.assertEqual(
            meta.FIELD_BYTE_LIMITS["keywords"],
            appstore_metadata.FIELD_BY_FILENAME["keywords.txt"].max_utf8_bytes,
        )

    def test_name_follows_the_name_mode(self) -> None:
        # passthrough: the store name is the bare brand, copied from en-US; descriptor: the
        # descriptor after the brand is transcreated.
        if meta.NAME_MODE == "passthrough":
            self.assertIn("name", meta.PASSTHROUGH_FIELDS)
            self.assertNotIn("name", meta.TRANSLATABLE_FIELDS)
        else:
            self.assertEqual(meta.TRANSLATABLE_FIELDS[0], "name")
            self.assertNotIn("name", meta.PASSTHROUGH_FIELDS)

    def test_passthrough_overrides_name_real_storefronts_and_fields(self) -> None:
        for storefront, fields in meta.PASSTHROUGH_OVERRIDES.items():
            self.assertIn(storefront, meta.STOREFRONT_LOCALES)
            self.assertLessEqual(fields, set(meta.PASSTHROUGH_FIELDS))

    def test_storefronts_exclude_the_source_and_cover_every_target(self) -> None:
        self.assertNotIn(meta.SOURCE_LOCALE, meta.STOREFRONT_LOCALES)
        self.assertEqual(len(meta.STOREFRONT_LOCALES), 49)


class KeywordByteLimitTests(unittest.TestCase):
    """A CJK keyword list well under 100 characters can still blow the 100-byte cap."""

    def _validate_keywords(self, value: str) -> list[str]:
        source = {"keywords": {"value": "checklist,list", "charLimit": 100}}
        with tempfile.TemporaryDirectory() as tmp:
            outputs = Path(tmp)
            (outputs / "ja.json").write_text(
                json.dumps({"keywords": value}), encoding="utf-8"
            )
            original = metadata_validate.OUTPUTS_DIR
            metadata_validate.OUTPUTS_DIR = outputs
            try:
                errors, _warnings, _pending = metadata_validate.validate_storefront(
                    "ja", source, subset=True
                )
            finally:
                metadata_validate.OUTPUTS_DIR = original
        return errors

    def test_three_byte_script_over_budget_is_rejected(self) -> None:
        value = ",".join(["チェックリスト"] * 5)  # 39 chars, 109 bytes
        self.assertGreater(len(value.encode("utf-8")), 100)
        self.assertLess(len(value), 100)
        errors = self._validate_keywords(value)
        self.assertTrue(any("UTF-8 bytes" in e for e in errors), errors)

    def test_latin_within_budget_is_accepted(self) -> None:
        value = "checklist,packing,shopping,routine,reset,repeat"
        self.assertLessEqual(len(value.encode("utf-8")), 100)
        self.assertEqual(
            [e for e in self._validate_keywords(value) if "bytes" in e or "chars" in e], []
        )


class MetadataGlossaryTests(unittest.TestCase):
    def setUp(self) -> None:
        # Pin one listing term, whatever this repo's i18n/app.json pins.
        self._pinned = meta.METADATA_GLOSSARY_TERMS
        meta.METADATA_GLOSSARY_TERMS = ("Checklist",)

    def tearDown(self) -> None:
        meta.METADATA_GLOSSARY_TERMS = self._pinned

    def _glossary(self, translations: dict[str, str]) -> Path:
        tmp = Path(tempfile.mkdtemp())
        path = tmp / "glossary.json"
        terms = {
            "Checklist": {"translations": translations},
            "Reset": {"translations": {"nb": "Nullstill"}},
        }
        path.write_text(json.dumps({"terms": terms}), encoding="utf-8")
        return path

    def test_storefront_maps_to_the_runtime_locale(self) -> None:
        path = self._glossary({"nb": "Sjekkliste", "de": "Checkliste"})
        self.assertEqual(meta.glossary_terms("no", path), [("Checklist", "Sjekkliste")])
        self.assertEqual(meta.glossary_terms("de-DE", path), [("Checklist", "Checkliste")])

    def test_only_pinned_terms_reach_the_listing(self) -> None:
        path = self._glossary({"nb": "Sjekkliste"})
        self.assertNotIn("Nullstill", meta.glossary_lines("no", path))

    def test_untranslated_storefront_renders_no_section(self) -> None:
        path = self._glossary({"nb": "Sjekkliste"})
        self.assertEqual(meta.glossary_lines("en-US", path), "")
        self.assertEqual(meta.glossary_lines("no", Path(tempfile.mkdtemp()) / "missing.json"), "")

    def test_every_target_storefront_has_the_pinned_terms(self) -> None:
        meta.METADATA_GLOSSARY_TERMS = self._pinned  # this repo's real pins, against its real glossary
        for storefront in meta.STOREFRONT_LOCALES:
            with self.subTest(storefront=storefront):
                self.assertEqual(
                    [en for en, _ in meta.glossary_terms(storefront)],
                    list(meta.METADATA_GLOSSARY_TERMS),
                )


if __name__ == "__main__":
    unittest.main()
