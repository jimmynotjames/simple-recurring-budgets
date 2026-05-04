#!/usr/bin/env python3
"""Print UDID of a simulator matching criteria, or print nothing.

Exits 0 always (caller treats empty stdout as no match). simctl is capped
with a timeout so a wedged CoreSimulatorService cannot hang CI or agents.

Usage (legacy, env-var-based):
    SIMULATOR_NAME=<name> python3 resolve_booted_sim_udid.py

Usage (explicit args, used by _sim_sandbox.sh):
    python3 resolve_booted_sim_udid.py --name <name> [--state <Booted|any>]
"""
import argparse
import json
import os
import subprocess
import sys

SIMCTL_TIMEOUT_SEC = 8


def main() -> None:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--name", default=None)
    parser.add_argument("--state", default="Booted")  # "Booted" or "any"
    args, _ = parser.parse_known_args()

    name = args.name or os.environ.get("SIMULATOR_NAME", "")
    if not name:
        return

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
