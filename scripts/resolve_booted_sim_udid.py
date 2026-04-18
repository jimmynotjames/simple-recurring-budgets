#!/usr/bin/env python3
"""Print UDID of a booted simulator matching SIMULATOR_NAME, or print nothing.

Exits 0 always (caller treats empty stdout as no match). simctl is capped
with a timeout so a wedged CoreSimulatorService cannot hang CI or agents.
"""
import json
import os
import subprocess
import sys

SIMCTL_TIMEOUT_SEC = 8


def main() -> None:
    name = os.environ.get("SIMULATOR_NAME", "")
    if not name:
        return

    try:
        out = subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "booted", "-j"],
            text=True,
            timeout=SIMCTL_TIMEOUT_SEC,
        )
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        return

    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return

    best = None
    for devices in data.get("devices", {}).values():
        for d in devices:
            if d.get("state") != "Booted":
                continue
            dn = d.get("name") or ""
            if dn == name or dn.startswith(name + " "):
                rank = 0 if dn == name else 1
                cand = (rank, dn, d["udid"])
                if best is None or cand < best:
                    best = cand

    if best:
        print(best[2], end="")


if __name__ == "__main__":
    main()
    sys.exit(0)
