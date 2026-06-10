#!/usr/bin/env python3
"""Shut down and delete this repo's simulator and any leftover xcodebuild clones.

The base device for this repo has a unique slug suffix in its name, e.g.
"iPhone 17 [a1b2c3d4]". xcodebuild's parallel testing creates short-lived clones
named "Clone N of <base name>" — these are usually torn down automatically, but
crashes (e.g. "Test crashed with signal kill") can leave them orphaned. This
script finds every device whose name contains the slug and deletes them all,
then removes .build/sim/.

Safe by design: only matches devices containing this repo's unique slug, so it
cannot touch other repos' simulators or Xcode's own devices.

Usage:
    python3 sim_clean.py --slug-from-file .build/sim/device.udid
    python3 sim_clean.py --slug a1b2c3d4
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

SIMCTL_TIMEOUT_SEC = 15


def simctl(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["xcrun", "simctl", *args],
        capture_output=True,
        text=True,
        timeout=SIMCTL_TIMEOUT_SEC,
    )


def slug_from_udid(udid: str) -> str | None:
    """Look up a booted/shutdown device by UDID and extract the slug from its name."""
    try:
        out = simctl("list", "devices", "-j").stdout
        data = json.loads(out)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return None
    for runtime_devices in data.get("devices", {}).values():
        for d in runtime_devices:
            if d.get("udid") == udid:
                m = re.search(r"\[([a-f0-9]{8})\]", d.get("name", ""))
                if m:
                    return m.group(1)
    return None


def find_matching_devices(slug: str) -> list[dict]:
    """Return all devices (any runtime, any state) whose name contains [slug]."""
    needle = f"[{slug}]"
    try:
        out = simctl("list", "devices", "-j").stdout
        data = json.loads(out)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return []
    found = []
    for runtime_devices in data.get("devices", {}).values():
        for d in runtime_devices:
            if needle in d.get("name", ""):
                found.append(d)
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--slug", help="8-char repo slug (the [....] suffix)")
    group.add_argument("--slug-from-file", help="Path to file containing the device UDID")
    args = parser.parse_args()

    if args.slug:
        slug = args.slug
    else:
        udid_path = Path(args.slug_from_file)
        if not udid_path.exists():
            print(f"sim-clean: no UDID file at {udid_path} — nothing to clean", file=sys.stderr)
            return 0
        udid = udid_path.read_text().strip()
        if not udid:
            print("sim-clean: UDID file is empty", file=sys.stderr)
            return 0
        slug = slug_from_udid(udid)
        if not slug:
            # Device may already be deleted; fall back to deleting just by UDID
            print(f"sim-clean: device {udid} not found in default set — already gone", file=sys.stderr)
            return 0

    devices = find_matching_devices(slug)
    if not devices:
        print(f"sim-clean: no devices found with slug [{slug}]")
        return 0

    print(f"sim-clean: found {len(devices)} device(s) with slug [{slug}]")
    for d in devices:
        name = d.get("name", "?")
        udid = d.get("udid", "?")
        state = d.get("state", "?")
        print(f"  - {name} ({udid}) [{state}]")
        if state == "Booted":
            simctl("shutdown", udid)
        result = simctl("delete", udid)
        if result.returncode != 0:
            print(f"    warning: delete failed: {result.stderr.strip()}", file=sys.stderr)

    print(f"sim-clean: deleted {len(devices)} device(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
