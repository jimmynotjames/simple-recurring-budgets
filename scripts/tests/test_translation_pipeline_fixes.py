"""Metadata merge, gate, audit and validate, and catalog update_keys behave as documented."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_catalog"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_metadata"))


def _load(name: str, relative: str):
    # By path: merge.py and validate.py exist in both pipelines, so a bare import
    # would pick up whichever a sibling test module imported first.
    spec = importlib.util.spec_from_file_location(name, REPO_ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


metadata_merge = _load("translate_metadata_merge", "scripts/translate_metadata/merge.py")
metadata_audit = _load("translate_metadata_audit", "scripts/translate_metadata/audit.py")
metadata_validate = _load("translate_metadata_validate_fixes", "scripts/translate_metadata/validate.py")
catalog_validate = _load("translate_catalog_validate_fixes", "scripts/translate_catalog/validate.py")
metadata_extract = _load("translate_metadata_extract_fixes", "scripts/translate_metadata/extract.py")
check_metadata = _load("translate_metadata_check_metadata", "scripts/translate_metadata/check_metadata.py")
update_keys = _load("translate_catalog_update_keys", "scripts/translate_catalog/update_keys.py")


@contextlib.contextmanager
def _patched(module, **values):
    original = {name: getattr(module, name) for name in values}
    for name, value in values.items():
        setattr(module, name, value)
    try:
        yield
    finally:
        for name, value in original.items():
            setattr(module, name, value)


class MetadataMergeBlankFieldTests(unittest.TestCase):
    """A field blank in en-US ends up with no file at all, which `prepare` accepts."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        root = Path(self._tmp.name)
        self.metadata = root / "metadata"
        self.outputs = root / "outputs"
        (self.metadata / "en-US").mkdir(parents=True)
        self.outputs.mkdir()
        (self.metadata / "en-US" / "subtitle.txt").write_text("Reusable checklists\n", encoding="utf-8")
        (self.metadata / "en-US" / "release_notes.txt").write_text("\n", encoding="utf-8")
        (self.metadata / "en-US" / "name.txt").write_text("reChecklist\n", encoding="utf-8")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    # A passthrough-name app with one storefront override, whatever this repo's i18n/app.json says.
    CONFIG = {
        "TRANSLATABLE_FIELDS": ["subtitle", "promotional_text", "keywords", "description", "release_notes"],
        "PASSTHROUGH_FIELDS": ["name", "marketing_url", "privacy_url", "support_url"],
        "PASSTHROUGH_OVERRIDES": {"ja": frozenset({"name"})},
    }

    def _merge(self, storefront: str, output: dict) -> None:
        (self.outputs / f"{storefront}.json").write_text(json.dumps(output), encoding="utf-8")
        with _patched(metadata_merge, METADATA_DIR=self.metadata, OUTPUTS_DIR=self.outputs, **self.CONFIG), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(metadata_merge.main([storefront]), 0)

    def test_blank_source_field_file_is_deleted(self) -> None:
        folder = self.metadata / "de-DE"
        folder.mkdir()
        (folder / "release_notes.txt").write_text("Alte Notizen\n", encoding="utf-8")
        self._merge("de-DE", {"subtitle": "Wiederverwendbare Checklisten"})
        self.assertFalse((folder / "release_notes.txt").exists())
        self.assertEqual((folder / "subtitle.txt").read_text(encoding="utf-8"), "Wiederverwendbare Checklisten\n")

    def test_existing_empty_file_for_blank_source_field_is_deleted(self) -> None:
        folder = self.metadata / "fr-FR"
        folder.mkdir()
        (folder / "release_notes.txt").write_text("\n", encoding="utf-8")
        self._merge("fr-FR", {"subtitle": "Listes réutilisables"})
        self.assertFalse((folder / "release_notes.txt").exists())

    def test_absent_file_for_blank_source_field_stays_absent(self) -> None:
        self._merge("it", {"subtitle": "Liste riutilizzabili"})
        self.assertFalse((self.metadata / "it" / "release_notes.txt").exists())

    def test_blank_translated_value_never_replaces_an_authored_field(self) -> None:
        folder = self.metadata / "ja"
        folder.mkdir()
        (folder / "subtitle.txt").write_text("再利用できるチェックリスト\n", encoding="utf-8")
        self._merge("ja", {"subtitle": "  "})
        self.assertEqual((folder / "subtitle.txt").read_text(encoding="utf-8"), "再利用できるチェックリスト\n")

    def test_name_is_copied_as_passthrough(self) -> None:
        self._merge("es-ES", {"subtitle": "Listas reutilizables"})
        self.assertEqual((self.metadata / "es-ES" / "name.txt").read_bytes(), b"reChecklist\n")

    def test_overridden_passthrough_field_is_left_alone(self) -> None:
        folder = self.metadata / "ja"
        folder.mkdir()
        (folder / "name.txt").write_text("reChecklist - 繰り返しチェックリスト\n", encoding="utf-8")
        self._merge("ja", {"subtitle": "再利用できるチェックリスト"})
        self.assertEqual(
            (folder / "name.txt").read_text(encoding="utf-8"), "reChecklist - 繰り返しチェックリスト\n"
        )


class CheckMetadataEmptyFileTests(unittest.TestCase):
    """The gate fails on an empty storefront file, which `prepare` would reject at upload."""

    def _check(self, empty_file: str | None) -> tuple[int, list[str]]:
        with tempfile.TemporaryDirectory() as tmp:
            metadata = Path(tmp) / "metadata"
            shutil.copytree(REPO_ROOT / "fastlane" / "metadata", metadata)
            if empty_file:
                (metadata / empty_file).write_text("\n", encoding="utf-8")
            out = io.StringIO()
            with _patched(check_metadata, METADATA_DIR=metadata), contextlib.redirect_stdout(out):
                code = check_metadata.main(["--json"])
        return code, json.loads(out.getvalue())["issues"]

    def test_committed_tree_passes(self) -> None:
        self.assertEqual(self._check(None), (0, []))

    def test_empty_file_for_a_field_blank_in_en_us_fails_and_is_named(self) -> None:
        blank = next(f for f in check_metadata.TRANSLATABLE_FIELDS
                     if not check_metadata.read_field(check_metadata.SOURCE_LOCALE, f))
        code, issues = self._check(f"de-DE/{blank}.txt")
        self.assertEqual(code, 1)
        self.assertEqual(len(issues), 1)
        self.assertIn(f"de-DE/{blank}.txt", issues[0])
        self.assertIn("delete", issues[0])


class MetadataAuditKeywordBytesTests(unittest.TestCase):
    """audit.py measures keywords in UTF-8 bytes, the unit Apple limits them in."""

    def _audit(self, keywords: str) -> dict:
        with tempfile.TemporaryDirectory() as tmp:
            outputs = Path(tmp)
            (outputs / "ja.json").write_text(json.dumps({"keywords": keywords}), encoding="utf-8")
            with _patched(metadata_audit, OUTPUTS_DIR=outputs):
                return metadata_audit.audit_storefront("ja")

    def test_multibyte_keywords_under_100_chars_but_over_100_bytes_are_over(self) -> None:
        value = ",".join(["チェックリスト"] * 5)
        self.assertLess(len(value), 100)
        info = self._audit(value)
        self.assertEqual(info["status"], "OVER")
        self.assertEqual(info["fields"]["keywords"]["unit"], "bytes")
        self.assertEqual(info["fields"]["keywords"]["len"], len(value.encode("utf-8")))

    def test_ascii_keywords_at_the_limit_pass(self) -> None:
        info = self._audit("a" * 100)
        self.assertEqual(info["status"], "PASS")

    def test_questions_mode_exits_zero_even_when_outputs_are_pending(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, _patched(metadata_audit, OUTPUTS_DIR=Path(tmp)), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(metadata_audit.main(["--questions", "ja"]), 0)


class MetadataValidateNameTests(unittest.TestCase):
    """`name` is passthrough: an output carrying it is rejected, never brand-checked."""

    def test_name_in_an_output_is_an_unexpected_field(self) -> None:
        source = {"subtitle": {"value": "Reusable checklists", "charLimit": 30}}
        with tempfile.TemporaryDirectory() as tmp:
            outputs = Path(tmp)
            (outputs / "de-DE.json").write_text(
                json.dumps({"subtitle": "Checklisten", "name": "reChecklist"}), encoding="utf-8"
            )
            with _patched(metadata_validate, OUTPUTS_DIR=outputs):
                errors, _warnings, _pending = metadata_validate.validate_storefront("de-DE", source)
        self.assertEqual(len(errors), 1)
        self.assertIn("Unexpected extra field", errors[0])


class CatalogSpecifierReorderTests(unittest.TestCase):
    """Plain `%@` may be numbered to reorder; anything else that changes the arguments fails."""

    def test_numbering_plain_specifiers_to_reorder_matches(self) -> None:
        source = catalog_validate.specifier_multiset("From %@ to %@, %lld left")
        self.assertEqual(source, catalog_validate.specifier_multiset("%3$lld übrig, %2$@ bis %1$@"))

    def test_dropped_or_retyped_specifier_fails(self) -> None:
        source = catalog_validate.specifier_multiset("From %@ to %@")
        self.assertNotEqual(source, catalog_validate.specifier_multiset("bis %1$@"))
        self.assertNotEqual(source, catalog_validate.specifier_multiset("%1$@ bis %1$@"))
        self.assertNotEqual(source, catalog_validate.specifier_multiset("%1$lld bis %2$@"))

    def test_literal_percent_passes_through(self) -> None:
        self.assertEqual(
            catalog_validate.specifier_multiset("%lld%% done"),
            catalog_validate.specifier_multiset("%1$lld %% erledigt"),
        )


class MetadataExtractStorefrontsTests(unittest.TestCase):
    """--fields --storefronts forces the fields for just the named storefronts."""

    SOURCE = {"description": {"value": "x", "charLimit": 4000}}

    def test_storefronts_limit_the_forced_manifest(self) -> None:
        targets = metadata_extract.STOREFRONT_LOCALES[:2]
        manifest = metadata_extract.force_fields(self.SOURCE, ["description"], targets)
        self.assertEqual(manifest, {s: ["description"] for s in targets})

    def test_no_storefronts_means_every_storefront(self) -> None:
        manifest = metadata_extract.force_fields(self.SOURCE, ["description"])
        self.assertEqual(sorted(manifest), sorted(metadata_extract.STOREFRONT_LOCALES))

    def test_unknown_storefront_exits(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            metadata_extract.force_fields(self.SOURCE, ["description"], ["xx-XX"])


class UpdateKeysPluralTests(unittest.TestCase):
    """update_keys.py refuses plural keys instead of flattening their English forms."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        root = Path(self._tmp.name)
        self.catalog_path = root / "Localizable.xcstrings"
        self.input_path = root / "updates.json"
        catalog = {
            "sourceLanguage": "en",
            "version": "1.0",
            "strings": {
                "checklist.items.count": {
                    "localizations": {
                        "en": {"variations": {"plural": {
                            "one": {"stringUnit": {"state": "translated", "value": "%lld item"}},
                            "other": {"stringUnit": {"state": "translated", "value": "%lld items"}},
                        }}},
                    },
                },
                "checklist.action.reset": {
                    "localizations": {
                        "en": {"stringUnit": {"state": "translated", "value": "Reset"}},
                        "de": {"stringUnit": {"state": "translated", "value": "Zurücksetzen"}},
                    },
                },
            },
        }
        self.catalog_path.write_text(json.dumps(catalog), encoding="utf-8")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _run(self, updates: dict) -> int:
        self.input_path.write_text(json.dumps(updates), encoding="utf-8")
        with _patched(update_keys, CATALOG_PATH=self.catalog_path), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return update_keys.main([str(self.input_path)])

    def test_plural_key_is_refused_and_nothing_is_written(self) -> None:
        before = self.catalog_path.read_bytes()
        code = self._run({
            "checklist.items.count": {"value": "%lld things"},
            "checklist.action.reset": {"value": "Reset Checklist"},
        })
        self.assertEqual(code, 1)
        self.assertEqual(self.catalog_path.read_bytes(), before)

    def test_flat_key_is_updated_and_translations_invalidated(self) -> None:
        self.assertEqual(self._run({"checklist.action.reset": {"value": "Reset Checklist"}}), 0)
        entry = json.loads(self.catalog_path.read_text(encoding="utf-8"))["strings"]["checklist.action.reset"]
        self.assertEqual(entry["localizations"]["en"]["stringUnit"]["value"], "Reset Checklist")
        self.assertEqual(entry["localizations"]["de"]["stringUnit"]["state"], "needs_review")


if __name__ == "__main__":
    unittest.main()
