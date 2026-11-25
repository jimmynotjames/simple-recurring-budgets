#!/usr/bin/env python3
"""Print UDID of a simulator matching criteria, or print nothing.

Exits 0 whether or not a device matches (caller treats empty stdout as no match). simctl is capped
with a timeout so a wedged CoreSimulatorService cannot hang CI or agents.

Usage:
    python3 resolve_booted_sim_udid.py --name <name> [--state <Booted|any>]
"""
import argparse
import json
import subprocess
import sys

SIMCTL_TIMEOUT_SEC = 8


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    parser.add_argument("--state", default="Booted")  # "Booted" or "any"
    args = parser.parse_args()
    name = args.name

    cmd = ["xcrun", "simctl", "list", "devices", "-j"]
    if args.state == "Booted":
        cmd += ["booted"]

    try:
        out = subprocess.check_output(cmd, text=True, timeout=SIMCTL_TIMEOUT_SEC)
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        return

    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return

    best = None
    for devices in data.get("devices", {}).values():
        for d in devices:
            if args.state == "Booted" and d.get("state") != "Booted":
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
