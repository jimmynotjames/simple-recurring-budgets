from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "appstore_metadata.py"
SPEC = importlib.util.spec_from_file_location("appstore_metadata", SCRIPT)
assert SPEC and SPEC.loader
metadata = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = metadata
SPEC.loader.exec_module(metadata)


class AppStoreMetadataTests(unittest.TestCase):
    def setUp(self) -> None:
        (REPO_ROOT / "tmp").mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=REPO_ROOT / "tmp")
        self.root = Path(self.temporary.name)
        self.source = self.root / "metadata"
        shutil.copytree(REPO_ROOT / "fastlane" / "metadata", self.source)
        # Release notes are per version: between releases an app may have none authored yet,
        # which `validate` rightly refuses. The fixture needs a complete tree either way.
        notes = self.source / "en-US" / "release_notes.txt"
        if not notes.is_file():
            notes.write_text("Bug fixes and improvements.\n", encoding="utf-8")
        self.manifest = self.root / "metadata-locales.json"
        shutil.copyfile(REPO_ROOT / "fastlane" / "metadata-locales.json", self.manifest)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_repository_metadata_validates_without_authentication(self) -> None:
        if not (REPO_ROOT / "fastlane" / "metadata" / "en-US" / "release_notes.txt").is_file():
            self.skipTest("no en-US release notes authored for the next version yet; validate runs before upload")
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "validate"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("50 App Store locales", result.stdout)

    def test_prepare_expands_fallback_and_per_field_override(self) -> None:
        # fr-FR ships transcreated overrides, so the fixture already has the
        # directory; this test only cares that an override beats the fallback.
        french = self.source / "fr-FR"
        french.mkdir(exist_ok=True)
        (french / "name.txt").write_text("reListe", encoding="utf-8")
        (french / "description.txt").unlink(missing_ok=True)
        # de-DE authors no name of its own here, whether or not this app localizes the name.
        (self.source / "de-DE" / "name.txt").unlink(missing_ok=True)
        output = self.root / "stage"

        prepared, count = metadata.prepare_metadata(output, self.source, self.manifest)

        self.assertEqual(count, 50)
        self.assertEqual((prepared / "fr-FR" / "name.txt").read_text(), "reListe")
        self.assertEqual(
            (prepared / "fr-FR" / "description.txt").read_text(),
            (self.source / "en-US" / "description.txt").read_text(),
        )
        self.assertEqual(
            (prepared / "de-DE" / "name.txt").read_text(),
            (self.source / "en-US" / "name.txt").read_text(),
        )
        self.assertEqual(
            (prepared / "copyright.txt").read_text(),
            (self.source / "copyright.txt").read_text(),
        )
        self.assertEqual(
            (prepared / metadata.STAGING_MARKER).read_text(),
            metadata.STAGING_MARKER_CONTENT,
        )

    def test_missing_optional_field_is_omitted_from_every_fallback_locale(self) -> None:
        # An optional field absent from the source must not be invented anywhere
        # that falls back to it. Clear every storefront's subtitle so the fallback
        # path is the one under test.
        for existing in self.source.glob("*/subtitle.txt"):
            existing.unlink()
        output = self.root / "stage"

        metadata.prepare_metadata(output, self.source, self.manifest)

        self.assertFalse((output / "en-US" / "subtitle.txt").exists())
        self.assertFalse((output / "de-DE" / "subtitle.txt").exists())

    def test_explicit_empty_optional_value_is_rejected(self) -> None:
        french = self.source / "fr-FR"
        french.mkdir(exist_ok=True)
        (french / "marketing_url.txt").write_text("  \n", encoding="utf-8")

        with self.assertRaisesRegex(metadata.MetadataError, "explicit empty values"):
            metadata.validate_metadata(self.source, self.manifest)

    def test_missing_required_fallback_is_rejected(self) -> None:
        (self.source / "en-US" / "description.txt").unlink()

        with self.assertRaisesRegex(metadata.MetadataError, "required field"):
            metadata.validate_metadata(self.source, self.manifest)

    def test_limits_use_characters_except_keywords_use_utf8_bytes(self) -> None:
        (self.source / "en-US" / "name.txt").write_text("x" * 31, encoding="utf-8")
        with self.assertRaisesRegex(metadata.MetadataError, "30-character limit"):
            metadata.validate_metadata(self.source, self.manifest)

        (self.source / "en-US" / "name.txt").write_text("Valid Name", encoding="utf-8")
        (self.source / "en-US" / "keywords.txt").write_text("ééé," + "a" * 95, encoding="utf-8")
        with self.assertRaisesRegex(metadata.MetadataError, "100-byte limit"):
            metadata.validate_metadata(self.source, self.manifest)

    def test_invalid_url_is_rejected(self) -> None:
        (self.source / "en-US" / "support_url.txt").write_text(
            "jimmynotjames.github.io/support", encoding="utf-8"
        )

        with self.assertRaisesRegex(metadata.MetadataError, "complete http"):
            metadata.validate_metadata(self.source, self.manifest)

    def test_validation_matches_deliver_stripping_but_staging_preserves_source(self) -> None:
        # Staging must hand deliver the source bytes, trailing newline included,
        # rather than the stripped form validation compares. Drop the per-locale
        # copies so fr-FR resolves through the fallback this test is about.
        url = "https://example.com/support\n"
        (self.source / "en-US" / "support_url.txt").write_text(url, encoding="utf-8")
        for override in self.source.glob("*/support_url.txt"):
            if override.parent.name != "en-US":
                override.unlink()
        output = self.root / "stage"

        metadata.prepare_metadata(output, self.source, self.manifest)

        self.assertEqual((output / "fr-FR" / "support_url.txt").read_text(), url)

    def test_copyright_accepts_a_single_year_or_a_range(self) -> None:
        copyright_file = self.source / "copyright.txt"
        for accepted in ("2020 Jimmy Ho", "2019-2026 Jimmy Ho", "2026-2026 Jimmy Ho"):
            copyright_file.write_text(accepted, encoding="utf-8")
            metadata.validate_metadata(self.source, self.manifest)

    def test_malformed_copyright_is_rejected(self) -> None:
        copyright_file = self.source / "copyright.txt"
        for rejected in ("Jimmy Ho", "20 Jimmy Ho", "2026", "2019-26 Jimmy Ho"):
            copyright_file.write_text(rejected, encoding="utf-8")
            with self.assertRaisesRegex(metadata.MetadataError, "four-digit year"):
                metadata.validate_metadata(self.source, self.manifest)

    def test_reversed_copyright_year_range_is_rejected(self) -> None:
        (self.source / "copyright.txt").write_text("2026-2019 Jimmy Ho", encoding="utf-8")
        with self.assertRaisesRegex(metadata.MetadataError, "ends before it starts"):
            metadata.validate_metadata(self.source, self.manifest)

    def test_unknown_field_and_locale_are_rejected(self) -> None:
        (self.source / "en-US" / "surprise.txt").write_text("value", encoding="utf-8")
        with self.assertRaisesRegex(metadata.MetadataError, "unknown metadata field"):
            metadata.validate_metadata(self.source, self.manifest)

        (self.source / "en-US" / "surprise.txt").unlink()
        (self.source / "en-XX").mkdir()
        with self.assertRaisesRegex(metadata.MetadataError, "unknown metadata entry"):
            metadata.validate_metadata(self.source, self.manifest)

    def test_locale_manifest_must_match_fastlane_list(self) -> None:
        document = json.loads(self.manifest.read_text())
        document["locales"].remove("ja")
        self.manifest.write_text(json.dumps(document), encoding="utf-8")

        with self.assertRaisesRegex(metadata.MetadataError, "missing: ja"):
            metadata.validate_metadata(self.source, self.manifest)

    def test_prepare_removes_stale_output_and_rejects_unscoped_output(self) -> None:
        output = self.root / "stage"
        output.mkdir()
        (output / metadata.STAGING_MARKER).write_text(
            metadata.STAGING_MARKER_CONTENT, encoding="utf-8"
        )
        (output / "stale.txt").write_text("stale", encoding="utf-8")

        metadata.prepare_metadata(output, self.source, self.manifest)

        self.assertFalse((output / "stale.txt").exists())
        with self.assertRaisesRegex(metadata.MetadataError, "output must be a child"):
            metadata.prepare_metadata(REPO_ROOT / "fastlane" / "stage", self.source, self.manifest)

    def test_prepare_rejects_unmarked_output_and_input_overlap(self) -> None:
        output = self.root / "some-existing-directory"
        output.mkdir()
        with self.assertRaisesRegex(metadata.MetadataError, "unmarked directory"):
            metadata.prepare_metadata(output, self.source, self.manifest)

        with self.assertRaisesRegex(metadata.MetadataError, "must not overlap input"):
            metadata.prepare_metadata(self.root, self.source, self.manifest)


if __name__ == "__main__":
    unittest.main()
