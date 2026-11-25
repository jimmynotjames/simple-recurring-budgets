"""Every script names this checkout's simulators by one slug, and matches only that slug."""

from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from sim_common import matching_devices, slug_from_root  # noqa: E402


def _device(name: str, udid: str = "U") -> dict:
    return {"name": name, "udid": udid, "state": "Shutdown"}


class SlugTests(unittest.TestCase):
    def test_is_sha1_of_the_physical_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            physical = Path(tmp).resolve()
            link = Path(tmp + "-link")
            link.symlink_to(physical)
            try:
                expected = hashlib.sha1(str(physical).encode()).hexdigest()[:8]
                self.assertEqual(slug_from_root(physical), expected)
                self.assertEqual(slug_from_root(link), expected)
            finally:
                link.unlink()

    def test_bash_and_python_agree(self) -> None:
        shell = subprocess.run(
            ["bash", "-c", 'ROOT="$1"; source "$1/scripts/_sim_common.sh"; printf %s "$SIM_SLUG"', "_", str(REPO_ROOT)],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.assertEqual(shell, slug_from_root(REPO_ROOT))


class MatchingDevicesTests(unittest.TestCase):
    def test_matches_sandbox_screenshots_and_clones_only(self) -> None:
        listing = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                    _device("iPhone 17 [a1b2c3d4]", "1"),
                    _device("iPhone 17 Pro Max Screenshots [a1b2c3d4]", "2"),
                    _device("Clone 1 of iPhone 17 [a1b2c3d4]", "3"),
                    _device("iPhone 17 [ffffffff]", "4"),
                    _device("iPhone 17", "5"),
                    _device("iPhone 17 a1b2c3d4", "6"),
                ]
            }
        }
        self.assertEqual([d["udid"] for d in matching_devices(listing, "a1b2c3d4")], ["1", "2", "3"])

    def test_empty_listing(self) -> None:
        self.assertEqual(matching_devices({}, "a1b2c3d4"), [])


if __name__ == "__main__":
    unittest.main()
