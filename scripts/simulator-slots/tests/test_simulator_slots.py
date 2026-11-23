"""The slot pool grants, waits, and releases as documented, and the vendored-copy check is exact."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HOME = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HOME))

import simulator_slots as slots  # noqa: E402

TOOL = HOME / "simulator_slots.py"
CLONES = "/Users/x/Library/Developer/XCTestDevices"
DEFAULT_SET = "/Users/x/Library/Developer/CoreSimulator/Devices"
UDID_A = "11111111-2222-3333-4444-555555555555"
UDID_B = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"


class GrantSizeTests(unittest.TestCase):
    def test_takes_what_is_free_up_to_want(self) -> None:
        self.assertEqual(slots.grant_size(want=4, free=4, fewer=0), 4)
        self.assertEqual(slots.grant_size(want=4, free=2, fewer=0), 2)
        self.assertEqual(slots.grant_size(want=1, free=3, fewer=0), 1)

    def test_fewer_leaves_free_slots_unused(self) -> None:
        self.assertEqual(slots.grant_size(want=4, free=4, fewer=2), 2)
        self.assertEqual(slots.grant_size(want=1, free=2, fewer=1), 1)

    def test_nothing_left_means_wait(self) -> None:
        self.assertEqual(slots.grant_size(want=4, free=0, fewer=0), 0)
        self.assertEqual(slots.grant_size(want=4, free=1, fewer=1), 0)
        self.assertEqual(slots.grant_size(want=4, free=1, fewer=3), 0)


class HolderRecordTests(unittest.TestCase):
    def test_round_trip(self) -> None:
        fields = {"pid": "42", "label": "test-ui", "root": "/a b/c", "udid": UDID_A, "run": "abc"}
        self.assertEqual(slots.parse_holder(slots.format_holder(fields)), fields)

    def test_missing_slot_is_free(self) -> None:
        self.assertIsNone(slots.slot_holder(Path("/nonexistent/slot-1.lock")))


class BootedSimulatorTests(unittest.TestCase):
    def rows(self) -> list[tuple[int, int, str]]:
        return [
            (10, 1, f"launchd_sim {DEFAULT_SET}/{UDID_A}/data/var/run/launchd_bootstrap.plist"),
            (11, 1, f"launchd_sim /Users/x/Library/Developer/Xcode/UserData/Previews/Simulator Devices/{UDID_B}/data/var/run/launchd_bootstrap.plist"),
            (12, 10, "/usr/libexec/something launchd_sim unrelated"),
        ]

    def test_finds_every_set_including_paths_with_spaces(self) -> None:
        found = slots.booted_simulators(self.rows())
        self.assertEqual([(s["udid"], s["set"]) for s in found], [
            (UDID_A, DEFAULT_SET),
            (UDID_B, "/Users/x/Library/Developer/Xcode/UserData/Previews/Simulator Devices"),
        ])
        self.assertEqual(slots.set_label(found[1]["set"]), "Xcode Previews")

    def test_idle_excludes_held_devices_and_clones_of_running_runs(self) -> None:
        booted = [
            {"udid": UDID_A, "set": DEFAULT_SET, "name": "a"},
            {"udid": UDID_B, "set": DEFAULT_SET, "name": "b"},
            {"udid": "C", "set": CLONES, "name": "Clone 1 of c"},
        ]
        held = [{"udid": UDID_A}, None]
        self.assertEqual([s["udid"] for s in slots.idle_simulators(booted, held)], [UDID_B])
        self.assertEqual([s["udid"] for s in slots.idle_simulators(booted, [None, None])], [UDID_A, UDID_B, "C"])

    def test_owns_claims_devices_by_name(self) -> None:
        booted = [
            {"udid": UDID_A, "set": DEFAULT_SET, "name": "iPhone 17 Screenshots [abcd1234]"},
            {"udid": UDID_B, "set": DEFAULT_SET, "name": "iPhone 17 [ffff0000]"},
        ]
        held = [{"owns": "[abcd1234]"}]
        self.assertEqual([s["udid"] for s in slots.idle_simulators(booted, held)], [UDID_B])


class StateTests(unittest.TestCase):
    def test_first_use_writes_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(slots.prepare_state(Path(tmp) / "state"), slots.DEFAULT_MAX)
            self.assertEqual((Path(tmp) / "state" / "protocol").read_text().strip(), str(slots.PROTOCOL))

    def test_other_protocol_refuses(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "protocol").write_text("999\n")
            with self.assertRaises(slots.ConfigError):
                slots.prepare_state(Path(tmp))


class SyncTests(unittest.TestCase):
    def test_differences_and_sync(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            master, copy = Path(tmp) / "master", Path(tmp) / "copy"
            (master / "tests").mkdir(parents=True)
            (master / "VERSION").write_text("1\n")
            (master / "tests" / "t.py").write_text("x\n")
            (master / ".git").mkdir()
            (master / ".git" / "HEAD").write_text("ref\n")
            copy.mkdir()
            (copy / "VERSION").write_text("0\n")
            (copy / "stale.py").write_text("y\n")
            self.assertEqual(slots.tree_differences(master, copy), [
                "only in master: tests/t.py", "only in copy: stale.py", "differs: VERSION",
            ])
            args = ["--into", str(copy), "--master", str(master)]
            self.assertEqual(slots.main(["sync", *args]), 0)
            self.assertEqual(slots.tree_differences(master, copy), [])
            self.assertFalse((copy / ".git").exists())
            self.assertEqual(slots.main(["sync-check", *args]), 0)

    def test_a_git_master_syncs_its_last_commit_not_its_working_tree(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            master, copy = Path(tmp) / "master", Path(tmp) / "copy"
            master.mkdir()
            (master / "VERSION").write_text("1\n")
            git = ["git", "-C", str(master), "-c", "user.name=t", "-c", "user.email=t@t"]
            subprocess.run([*git, "init", "-q"], check=True)
            subprocess.run([*git, "add", "VERSION"], check=True)
            subprocess.run([*git, "commit", "-q", "-m", "v1"], check=True)
            (master / "VERSION").write_text("2-uncommitted\n")
            (master / ".pytest_cache").mkdir()
            (master / ".pytest_cache" / "x").write_text("cache\n")
            args = ["--into", str(copy), "--master", str(master)]
            self.assertEqual(slots.main(["sync", *args]), 0)
            self.assertEqual((copy / "VERSION").read_text(), "1\n")
            self.assertFalse((copy / ".pytest_cache").exists())
            self.assertEqual(slots.main(["sync-check", *args]), 0)

    def test_check_skips_without_master(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(slots.main(["sync-check", "--into", tmp, "--master", f"{tmp}/none"]), 0)


class HoldTests(unittest.TestCase):
    """Real holders against a temporary state directory, each watching a `sleep` it can outlive."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.state = Path(self._tmp.name)
        slots.prepare_state(self.state)
        (self.state / "max").write_text("2\n")
        self.procs: list[subprocess.Popen] = []

    def tearDown(self) -> None:
        for proc in self.procs:
            if proc.poll() is None:
                proc.kill()
            proc.wait()
            if proc.stdout:
                proc.stdout.close()
        self._tmp.cleanup()

    def env(self, **extra: str) -> dict[str, str]:
        return {**os.environ, "SIMULATOR_SLOTS_STATE_DIR": str(self.state), **extra}

    def watched(self) -> subprocess.Popen:
        proc = subprocess.Popen(["sleep", "60"])
        self.procs.append(proc)
        return proc

    def hold(self, want: int, watch: subprocess.Popen, **extra: str) -> subprocess.Popen:
        proc = subprocess.Popen(
            [sys.executable, str(TOOL), "hold", "--watch-pid", str(watch.pid), "--want", str(want), "--label", "t"],
            env=self.env(**extra), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        )
        self.procs.append(proc)
        return proc

    def granted(self, proc: subprocess.Popen) -> int:
        return int(proc.stdout.readline().split()[0])

    def free(self) -> int:
        return sum(1 for fields in slots.holders(self.state, 2) if fields is None)

    def test_grants_what_is_free_and_releases_when_the_watched_process_exits(self) -> None:
        first_owner = self.watched()
        first = self.hold(2, first_owner)
        self.assertEqual(self.granted(first), 2)
        self.assertEqual(self.free(), 0)

        second = self.hold(1, self.watched())
        time.sleep(1)
        self.assertIsNone(second.poll(), "should wait while the pool is full")

        first_owner.kill()
        first.wait(timeout=10)
        self.assertEqual(self.granted(second), 1)
        self.assertEqual(self.free(), 1)

    def test_fewer_leaves_slots_free(self) -> None:
        proc = self.hold(2, self.watched(), SIMULATOR_SLOTS_FEWER="1")
        self.assertEqual(self.granted(proc), 1)
        self.assertEqual(self.free(), 1)

    def test_fewer_than_the_pool_is_refused(self) -> None:
        proc = self.hold(1, self.watched(), SIMULATOR_SLOTS_FEWER="2")
        self.assertEqual(proc.wait(timeout=10), slots.EXIT_CONFIG)

    def test_timeout_gives_up(self) -> None:
        self.assertEqual(self.granted(self.hold(2, self.watched())), 2)
        late = self.hold(1, self.watched(), SIMULATOR_SLOTS_TIMEOUT="1")
        self.assertEqual(late.wait(timeout=15), slots.EXIT_TIMEOUT)

    def test_killed_holder_frees_its_slots(self) -> None:
        proc = self.hold(2, self.watched())
        self.assertEqual(self.granted(proc), 2)
        proc.kill()
        proc.wait()
        self.assertEqual(self.free(), 2)

    def test_run_log_pairs_start_and_release(self) -> None:
        owner = self.watched()
        proc = self.hold(1, owner)
        self.granted(proc)
        owner.kill()
        proc.wait(timeout=10)
        run = slots.recent_runs(self.state, 1)[0]
        self.assertEqual(run["granted"], 1)
        self.assertIn("held_sec", run)


class ShellWrapperTests(unittest.TestCase):
    def test_wrapper_grants_and_records_the_exit_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            slots.prepare_state(Path(tmp))
            (Path(tmp) / "max").write_text("4\n")
            env = {**os.environ, "SIMULATOR_SLOTS_STATE_DIR": tmp, "SIMULATOR_SLOTS_HOME": str(HOME)}
            script = 'source "$SIMULATOR_SLOTS_HOME/simulator_slots.sh"; simulator_slots_hold 3 t /r; echo "$SIMULATOR_SLOTS_GRANTED"; exit 7'
            result = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 7)
            self.assertEqual(result.stdout.strip(), "3")
            time.sleep(0.5)
            run = slots.recent_runs(Path(tmp), 1)[0]
            self.assertEqual((run["granted"], run["rc"]), (3, 7))
            self.assertEqual(sum(1 for f in slots.holders(Path(tmp), 4) if f is None), 4)


if __name__ == "__main__":
    unittest.main()
