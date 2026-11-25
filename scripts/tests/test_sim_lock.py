"""The per-checkout simulator lock serializes holders and is released by the kernel on any exit."""

from __future__ import annotations

import os
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from sim_lock import format_holder, parse_holder, status  # noqa: E402


class HolderRecordTests(unittest.TestCase):
    def test_round_trip(self) -> None:
        record = format_holder(42, "2026-10-03T12:00:00-04:00", "bash scripts/unit-tests.sh", "/a b/c")
        self.assertEqual(
            parse_holder(record),
            {"pid": "42", "started": "2026-10-03T12:00:00-04:00", "command": "bash scripts/unit-tests.sh", "root": "/a b/c"},
        )

    def test_missing_file_is_free(self) -> None:
        self.assertEqual(status("/nonexistent/sim.lock"), "free")


class LockTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name).resolve()
        (self.root / "scripts").symlink_to(REPO_ROOT / "scripts")
        self.lock = self.root / ".build" / "sim.lock"
        self.procs: list[subprocess.Popen] = []

    def tearDown(self) -> None:
        for proc in self.procs:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):  # group already gone
                pass
            proc.wait()
        self._tmp.cleanup()

    def _script(self, body: str) -> str:
        return f'ROOT="{self.root}"; source "$ROOT/scripts/_sim_common.sh"; sim_lock_acquire || exit $?; {body}'

    def _start(self, body: str, timeout: float | None = None) -> subprocess.Popen:
        env = dict(os.environ)
        env.pop("SIM_LOCK_TIMEOUT", None)
        if timeout is not None:
            env["SIM_LOCK_TIMEOUT"] = str(timeout)
        proc = subprocess.Popen(
            ["bash", "-c", self._script(body)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            start_new_session=True,
        )
        self.procs.append(proc)
        return proc

    def _hold(self) -> subprocess.Popen:
        """A holder whose `sleep` child also keeps fd 9, as xcodebuild would."""
        holder = self._start("sleep 30 & echo ready; wait")
        self.assertEqual(holder.stdout.readline().strip(), "ready")
        return holder

    def test_second_acquirer_times_out_naming_the_holder(self) -> None:
        holder = self._hold()
        waiter = self._start("echo acquired", timeout=1)
        out, err = waiter.communicate(timeout=10)
        self.assertEqual(waiter.returncode, 75)
        self.assertNotIn("acquired", out)
        self.assertIn(f"pid {holder.pid}", err)
        self.assertIn(str(self.root), status(str(self.lock)))

    def _await_stderr(self, proc: subprocess.Popen, needle: str, timeout: float = 30) -> None:
        """Reads the raw fd, not `proc.stderr`, so nothing sits in a text buffer `communicate` skips."""
        fd, seen = proc.stderr.fileno(), b""
        deadline = time.monotonic() + timeout
        while needle.encode() not in seen:
            ready, _, _ = select.select([fd], [], [], max(deadline - time.monotonic(), 0))
            chunk = os.read(fd, 4096) if ready else b""
            if not chunk:
                self.fail(f"no {needle!r} on stderr within {timeout:g}s: {seen.decode(errors='replace')!r}")
            seen += chunk

    def test_waiter_proceeds_when_the_holder_exits(self) -> None:
        holder = self._hold()
        waiter = self._start("echo acquired")
        self._await_stderr(waiter, "sim-lock: waiting")
        self.assertIsNone(waiter.poll())
        os.killpg(holder.pid, signal.SIGTERM)
        out, _ = waiter.communicate(timeout=10)
        self.assertEqual(out.strip(), "acquired")

    def test_sigkill_of_the_whole_holder_releases_it(self) -> None:
        holder = self._hold()
        os.killpg(holder.pid, signal.SIGKILL)
        holder.wait()
        waiter = self._start("echo acquired", timeout=5)
        out, err = waiter.communicate(timeout=10)
        self.assertEqual(out.strip(), "acquired", err)
        self.assertEqual(status(str(self.lock)), "free")

    def test_a_surviving_child_keeps_it_and_the_waiter_says_so(self) -> None:
        holder = self._hold()
        os.kill(holder.pid, signal.SIGKILL)
        holder.wait()
        waiter = self._start("echo acquired", timeout=1)
        _, err = waiter.communicate(timeout=10)
        self.assertEqual(waiter.returncode, 75)
        self.assertIn(f"pid {holder.pid} is gone", err)

    def test_nested_acquire_is_immediate_and_keeps_the_record(self) -> None:
        inner = self._script("echo nested-ok")
        holder = self._start(f"bash -c '{inner}'")
        out, _ = holder.communicate(timeout=10)
        self.assertEqual(out.strip(), "nested-ok")
        self.assertEqual(parse_holder(self.lock.read_text())["pid"], str(holder.pid))


if __name__ == "__main__":
    unittest.main()
