#!/usr/bin/env python3
"""Resolve device-type ID and runtime ID for a simulator name.

Outputs two lines: <device-type-id>\n<runtime-id>
Exits 0 on success, 1 on failure.

Usage:
    python3 resolve_sim_spec.py --name "iPhone 17"
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys


def simctl_json(*args: str) -> dict:
    out = subprocess.check_output(
        ["xcrun", "simctl", *args, "-j"],
        text=True,
        timeout=10,
    )
    return json.loads(out)


def selected_sdk_version() -> str | None:
    """The selected Xcode's iOS Simulator SDK version, or None if it can't be read."""
    try:
        out = subprocess.check_output(
            ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
            text=True,
            timeout=10,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return None
    return out.strip() or None


def newest_ios_runtime(
    runtimes: list[dict],
    sdk_version: str | None = None,
    device_type_id: str | None = None,
) -> dict | None:
    """The highest-versioned available iOS runtime from `simctl list runtimes -j`.

    Runtimes above `sdk_version` (major.minor) come from another installed Xcode, such as a
    beta, that the selected one can't target, so they are skipped. So are runtimes that don't
    list `device_type_id` among their `supportedDeviceTypes`: a runtime can ship with only some
    devices, and `simctl create` rejects the rest.
    """
    cap = runtime_version(sdk_version)[:2] if sdk_version else None
    ios = [
        r
        for r in runtimes
        if r.get("isAvailable")
        and "iOS" in r.get("name", "")
        and (cap is None or runtime_version(r["version"])[:2] <= cap)
        and (device_type_id is None or supports(r, device_type_id))
    ]
    return max(ios, key=lambda r: runtime_version(r["version"]), default=None)


def supports(runtime: dict, device_type_id: str) -> bool:
    """Whether `runtime` can host `device_type_id`; true when simctl lists no device types."""
    types = runtime.get("supportedDeviceTypes")
    return types is None or any(t.get("identifier") == device_type_id for t in types)


def runtime_version(version: str) -> tuple[int, ...]:
    return tuple(int(x) for x in version.split("."))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    args = parser.parse_args()
    name: str = args.name

    # -- Device type resolution --
    device_type_id: str | None = None
    try:
        types = simctl_json("list", "devicetypes").get("devicetypes", [])
        # 1. Exact name match
        for t in types:
            if t.get("name") == name:
                device_type_id = t["identifier"]
                break
        # 2. Name-prefix match (e.g. "iPhone 17" → "iPhone 17 Pro")
        if device_type_id is None:
            for t in types:
                if t.get("name", "").startswith(name):
                    device_type_id = t["identifier"]
                    break
        # 3. Family fallback (any iPhone / iPad), preferring the newest
        if device_type_id is None:
            family = name.split()[0]
            for t in reversed(types):
                if t.get("name", "").startswith(family):
                    device_type_id = t["identifier"]
                    break
    except Exception as e:
        print(f"error: could not list device types: {e}", file=sys.stderr)
        sys.exit(1)

    if device_type_id is None:
        print(f"error: no device type found for '{name}'", file=sys.stderr)
        sys.exit(1)

    # -- Runtime resolution (newest available iOS that hosts the device type) --
    runtime_id: str | None = None
    try:
        newest = newest_ios_runtime(
            simctl_json("list", "runtimes").get("runtimes", []), selected_sdk_version(), device_type_id
        )
        if newest:
            runtime_id = newest["identifier"]
    except Exception as e:
        print(f"error: could not list runtimes: {e}", file=sys.stderr)
        sys.exit(1)

    if runtime_id is None:
        print(f"error: no available iOS runtime hosts {device_type_id}", file=sys.stderr)
        sys.exit(1)

    print(device_type_id)
    print(runtime_id)


if __name__ == "__main__":
    main()
