"""sync_catalog.py feeds xcstringstool only current app sources."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_catalog"))

from sync_catalog import select_stringsdata  # noqa: E402


def _stringsdata(directory: Path, name: str, source: str) -> Path:
    path = directory / f"{name}.stringsdata"
    path.write_text(json.dumps({"source": source, "tables": {}, "version": 2}), encoding="utf-8")
    return path


class SelectStringsdataTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        root = Path(self._tmp.name)
        self.src = root / "src"
        self.excluded = self.src / "DesignExplorations"
        self.data = root / "data"
        for directory in (self.src, self.excluded, self.data):
            directory.mkdir(parents=True, exist_ok=True)
        (self.src / "Live.swift").touch()
        (self.excluded / "Scratch.swift").touch()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_keeps_live_and_generated_sources_only(self) -> None:
        live = _stringsdata(self.data, "Live", str(self.src / "Live.swift"))
        shortcuts = _stringsdata(self.data, "ExtractedAppShortcutsMetadata", "ExtractedAppShortcutsMetadata")
        _stringsdata(self.data, "Deleted", str(self.src / "Deleted.swift"))
        _stringsdata(self.data, "Scratch", str(self.excluded / "Scratch.swift"))
        _stringsdata(self.data, "GeneratedStringSymbols_Localizable", "/elsewhere/GeneratedStringSymbols_Localizable.swift")
        selected, unbuilt = select_stringsdata(self.data, self.src, self.excluded)
        self.assertEqual(selected, sorted([live, shortcuts]))
        self.assertEqual(unbuilt, [])

    def test_reports_a_source_the_build_has_not_extracted(self) -> None:
        _, unbuilt = select_stringsdata(self.data, self.src, self.excluded)
        self.assertEqual(unbuilt, [(self.src / "Live.swift").resolve()])


if __name__ == "__main__":
    unittest.main()
