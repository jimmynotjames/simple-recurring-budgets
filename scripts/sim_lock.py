#!/usr/bin/env python3
"""The per-checkout simulator lock, taken by `_sim_common.sh`'s `sim_lock_acquire`.

The lock is a BSD flock on an open file description the calling shell owns (fd 9). flock
belongs to the description, not to this process, so the lock outlives this helper and is
released by the kernel when the last copy of the fd closes: on any exit, including SIGKILL.
Nothing is ever stale. The holder record written into the file is for display only; it never
decides ownership.

Usage:
  sim_lock.py owns    --fd 9 --path P   # exit 0 when fd 9 is already open on P (nested caller)
  sim_lock.py acquire --fd 9 --path P [--root R]   # block until fd 9 holds the lock, then record the holder
  sim_lock.py status  --path P          # print "free" or the holder record

SIM_LOCK_TIMEOUT (seconds, default 0 = wait forever) makes `acquire` give up with exit 75.
"""

from __future__ import annotations

import argparse
import datetime
import fcntl
import os
import subprocess
import sys
import time

EXIT_TIMEOUT = 75
POLL_SEC = 1.0
REPORT_EVERY_SEC = 60.0


def format_holder(pid: int, started: str, command: str, root: str) -> str:
    return f"pid={pid}\nstarted={started}\ncommand={command}\nroot={root}\n"


def parse_holder(text: str) -> dict[str, str]:
    fields = {}
    for line in text.splitlines():
        key, sep, value = line.partition("=")
        if sep:
            fields[key] = value
    return fields


def describe(fields: dict[str, str]) -> str:
    if not fields.get("pid"):
        return "holder unknown"
    return f"pid {fields['pid']} ({fields.get('command', '?')}) since {fields.get('started', '?')}"


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def read_holder(path: str) -> dict[str, str]:
    try:
        with open(path, encoding="utf-8") as f:
            return parse_holder(f.read())
    except OSError:
        return {}


def owns(fd: int, path: str) -> bool:
    try:
        held, target = os.fstat(fd), os.stat(path)
    except OSError:
        return False
    return (held.st_dev, held.st_ino) == (target.st_dev, target.st_ino)


def try_lock(fd: int) -> bool:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return False
    return True


def waiting_message(path: str) -> str:
    fields = read_holder(path)
    message = f"sim-lock: waiting for {path}: held by {describe(fields)}"
    pid = fields.get("pid", "")
    if pid.isdigit() and not pid_alive(int(pid)):
        message += f"\nsim-lock: pid {pid} is gone; a process it started still holds the lock: lsof {path}"
    return message


def command_of(pid: int) -> str:
    result = subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True)
    return result.stdout.strip() or "?"


def record_holder(fd: int, root: str) -> None:
    holder = os.getppid()
    started = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    record = format_holder(holder, started, command_of(holder), root)
    os.ftruncate(fd, 0)
    os.write(fd, record.encode("utf-8"))


def acquire(fd: int, path: str, timeout: float, root: str) -> int:
    start = time.monotonic()
    last_report = None
    if not try_lock(fd):
        time.sleep(0.2)  # rides out a `status` probe's brief shared lock
    while not try_lock(fd):
        now = time.monotonic()
        if timeout and now - start >= timeout:
            if last_report is None:
                print(waiting_message(path), file=sys.stderr)
            print(f"sim-lock: gave up after {timeout:g}s (SIM_LOCK_TIMEOUT)", file=sys.stderr)
            return EXIT_TIMEOUT
        if last_report is None or now - last_report >= REPORT_EVERY_SEC:
            print(waiting_message(path), file=sys.stderr)
            last_report = now
        time.sleep(POLL_SEC)
    if last_report is not None:
        print("sim-lock: acquired", file=sys.stderr)
    record_holder(fd, root)
    return 0


def status(path: str) -> str:
    try:
        fd = os.open(path, os.O_RDONLY)
    except FileNotFoundError:
        return "free"
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            fields = read_holder(path)
            root = fields.get("root")
            return f"held by {describe(fields)}" + (f" in {root}" if root else "")
        fcntl.flock(fd, fcntl.LOCK_UN)
        return "free"
    finally:
        os.close(fd)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("action", choices=["owns", "acquire", "status"])
    parser.add_argument("--fd", type=int, default=9)
    parser.add_argument("--path", required=True)
    parser.add_argument("--root", default=os.getcwd(), help="checkout recorded in the holder record")
    args = parser.parse_args(argv)

    if args.action == "owns":
        return 0 if owns(args.fd, args.path) else 1
    if args.action == "status":
        print(status(args.path))
        return 0
    timeout = float(os.environ.get("SIM_LOCK_TIMEOUT") or 0)
    return acquire(args.fd, args.path, timeout, args.root)


if __name__ == "__main__":
    sys.exit(main())
