#!/usr/bin/env python3
"""Shut down and delete every simulator whose name contains this checkout's `[slug]`.

That covers the sandbox device and this checkout's Screenshots device in the default set, and
the "Clone N of ..." copies parallel testing leaves in XCTestDevices. Devices are deleted one
UDID at a time, so another checkout's are never touched. `--shutdown-only` shuts the booted ones
down and deletes nothing.

Usage: python3 scripts/sim_clean.py [--clones-only | --shutdown-only]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from sim_common import matching_devices, slug_from_root

SIMCTL_TIMEOUT_SEC = 15
CLONE_SET = Path.home() / "Library" / "Developer" / "XCTestDevices"


def simctl(device_set: Path | None, *args: str) -> subprocess.CompletedProcess:
    prefix = ["--set", str(device_set)] if device_set else []
    return subprocess.run(
        ["xcrun", "simctl", *prefix, *args],
        capture_output=True,
        text=True,
        timeout=SIMCTL_TIMEOUT_SEC,
    )


def find_matching_devices(slug: str, device_set: Path | None = None) -> list[dict]:
    """Devices in `device_set` (None = the default set) whose name contains [slug]."""
    try:
        data = json.loads(simctl(device_set, "list", "devices", "-j").stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError):
        return []
    return matching_devices(data, slug)


def delete_all(slug: str, device_set: Path | None, label: str) -> None:
    devices = find_matching_devices(slug, device_set)
    if not devices:
        print(f"sim-clean: no {label} with slug [{slug}]")
        return
    print(f"sim-clean: deleting {len(devices)} {label} with slug [{slug}]")
    for d in devices:
        udid = d.get("udid", "?")
        print(f"  - {d.get('name', '?')} ({udid}) [{d.get('state', '?')}]")
        if d.get("state") == "Booted":
            simctl(device_set, "shutdown", udid)
        result = simctl(device_set, "delete", udid)
        if result.returncode != 0:
            print(f"    warning: delete failed: {result.stderr.strip()}", file=sys.stderr)


def shutdown_all(slug: str, device_set: Path | None) -> None:
    for d in find_matching_devices(slug, device_set):
        if d.get("state") == "Booted":
            result = simctl(device_set, "shutdown", d.get("udid", "?"))
            outcome = "shut down" if result.returncode == 0 else f"could not shut down: {result.stderr.strip()}"
            print(f"sim: {outcome} {d.get('name', '?')} ({d.get('udid', '?')})")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--clones-only", action="store_true", help="only parallel-testing clones")
    mode.add_argument("--shutdown-only", action="store_true", help="shut down, delete nothing")
    args = parser.parse_args(argv)

    slug = slug_from_root()
    if args.shutdown_only:
        shutdown_all(slug, None)
        if CLONE_SET.is_dir():
            shutdown_all(slug, CLONE_SET)
        return 0
    if not args.clones_only:
        delete_all(slug, None, "device(s)")
    if CLONE_SET.is_dir():
        delete_all(slug, CLONE_SET, "parallel-testing clone(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
