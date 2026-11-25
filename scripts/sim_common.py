#!/usr/bin/env python3
"""The checkout slug that names this checkout's simulators, and the matching helper.

The slug is the first 8 hex chars of sha1 over the checkout's physical path, so a symlinked path
and its target name the same devices. Every script derives it here: AGENTS.md §"Simulator sandbox".

Usage: python3 scripts/sim_common.py slug [ROOT]   # ROOT defaults to this checkout
"""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def slug_from_root(root: Path | str = ROOT) -> str:
    physical = Path(root).resolve()
    return hashlib.sha1(str(physical).encode("utf-8")).hexdigest()[:8]


def matching_devices(simctl_json: dict, slug: str) -> list[dict]:
    """Devices from `simctl list devices -j` output (any set, runtime, or state) named with [slug].

    Covers the sandbox device, its Screenshots sibling, and xcodebuild's "Clone N of ..." copies.
    """
    needle = f"[{slug}]"
    return [
        device
        for runtime_devices in simctl_json.get("devices", {}).values()
        for device in runtime_devices
        if needle in device.get("name", "")
    ]


def main(argv: list[str]) -> int:
    if not argv or argv[0] != "slug" or len(argv) > 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    print(slug_from_root(argv[1] if len(argv) == 2 else ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
