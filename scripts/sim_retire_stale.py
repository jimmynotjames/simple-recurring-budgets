#!/usr/bin/env python3
"""Delete a named simulator unless it runs the newest iOS the selected Xcode can target that
hosts its device type.

Devices get their runtime only at creation, so the caller recreates them after an Xcode switch.
Also retires a device whose runtime is uninstalled; leaves one whose runtime is merely
unavailable. Exact-name match only. Always exits 0 (best-effort under `set -e`).

Usage: python3 sim_retire_stale.py --name "iPhone 17 [a1b2c3d4]"
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

from resolve_sim_spec import newest_ios_runtime, runtime_version, selected_sdk_version

SIMCTL_TIMEOUT_SEC = 15


def simctl(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["xcrun", "simctl", *args],
        capture_output=True,
        text=True,
        timeout=SIMCTL_TIMEOUT_SEC,
    )


def stale_devices(
    name: str,
    devices: dict[str, list[dict]],
    runtimes: list[dict],
    sdk_version: str | None = None,
) -> list[tuple[dict, str]]:
    """Devices named `name` that are not on the target iOS runtime, with the reason.

    `devices` and `runtimes` are the parsed `simctl list devices -j` / `runtimes -j` bodies.
    The target is the newest runtime that hosts the device's own type. Leaves a device alone when
    no target runtime is installed: there is nothing to rebuild onto.
    """
    by_id = {r["identifier"]: r for r in runtimes}
    found = []
    for runtime_id, runtime_devices in devices.items():
        for d in runtime_devices:
            if d.get("name") != name:
                continue
            device_type = d.get("deviceTypeIdentifier")
            if device_type is None:
                continue
            target = newest_ios_runtime(runtimes, sdk_version, device_type)
            if target is None:
                continue
            runtime = by_id.get(runtime_id)
            if runtime is None:
                found.append((d, f"its runtime {runtime_id} is no longer installed"))
            elif not runtime.get("isAvailable"):
                continue
            elif runtime_version(runtime["version"]) != runtime_version(target["version"]):
                found.append((d, f"it runs iOS {runtime['version']}, target is iOS {target['version']}"))
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    args = parser.parse_args()

    try:
        devices = json.loads(simctl("list", "devices", "-j").stdout).get("devices", {})
        runtimes = json.loads(simctl("list", "runtimes", "-j").stdout).get("runtimes", [])
        stale = stale_devices(args.name, devices, runtimes, selected_sdk_version())
    except Exception as e:  # noqa: BLE001 — best-effort: never fail the caller's run
        print(f"sim-retire: could not check simulators ({e}); leaving devices alone", file=sys.stderr)
        return 0

    for d, reason in stale:
        udid = d["udid"]
        print(f"sim-retire: replacing {args.name} ({udid}): {reason}", file=sys.stderr)
        try:
            if d.get("state") == "Booted":
                simctl("shutdown", udid)
            result = simctl("delete", udid)
        except subprocess.TimeoutExpired as e:
            print(f"sim-retire: warning: {e}", file=sys.stderr)
            continue
        if result.returncode != 0:
            print(f"sim-retire: warning: delete failed: {result.stderr.strip()}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
