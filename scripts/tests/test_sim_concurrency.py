"""scripts/_sim_concurrency.sh: the flags each UI_WORKERS / UI_RETRY_ON_FAILURE setting produces.

Sources the real file in a throwaway root with a stubbed slot pool, so nothing touches a simulator.
This file is identical in checklists and simple-recurring-budgets.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "scripts" / "_sim_concurrency.sh"

# The pool's hold grants min(want, FAKE_FREE); sim_clean.py just records that it ran.
SLOTS_STUB = """
simulator_slots_hold() {
    local free="${FAKE_FREE:-3}"
    SIMULATOR_SLOTS_GRANTED=$(( $1 < free ? $1 : free ))
}
"""
CLEAN_STUB = "import sys\nprint('clean ' + ' '.join(sys.argv[1:]), file=sys.stderr)\n"


class SimConcurrencyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        scripts = self.tmp / "scripts"
        (scripts / "simulator-slots").mkdir(parents=True)
        shutil.copy(SOURCE, scripts / "_sim_concurrency.sh")
        (scripts / "simulator-slots" / "simulator_slots.sh").write_text(SLOTS_STUB)
        (scripts / "sim_clean.py").write_text(CLEAN_STUB)
        self.master = self.tmp / "master"

    def run_bash(self, body: str, pool: bool, **env: str) -> subprocess.CompletedProcess:
        if pool:
            self.master.mkdir(exist_ok=True)
        full_env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.tmp),
            "SIMULATOR_SLOTS_MASTER": str(self.master),
            **env,
        }
        script = (
            f'ROOT="{self.tmp}"; WARM_UP_ONLY=Target/Suite; SIM_UDID=u; SIM_SLUG=s\n'
            f'source "{self.tmp}/scripts/_sim_concurrency.sh"\n{body}'
        )
        return subprocess.run(
            ["bash", "-c", script], capture_output=True, text=True, env=full_env, check=False
        )

    def ui_flags(self, pool: bool, **env: str) -> tuple[str, str]:
        result = self.run_bash(
            'slots_parallel_args "$(ui_workers_wanted)" ui-tests; retry_args\n'
            'echo "${SIMULATOR_SLOTS_GRANTED}|${SLOTS_PARALLEL_ARGS[*]}|${RETRY_ARGS[*]-}"',
            pool,
            **env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip(), result.stderr

    def test_pool_off_defaults_to_serial_without_retry(self) -> None:
        out, _ = self.ui_flags(pool=False)
        self.assertEqual(out, "1|-parallel-testing-enabled NO|")

    def test_pool_on_defaults_to_two_workers_with_retry(self) -> None:
        out, err = self.ui_flags(pool=True)
        self.assertEqual(
            out,
            "2|-parallel-testing-enabled YES -parallel-testing-worker-count 2 "
            "-maximum-parallel-testing-workers 2|-retry-tests-on-failure -test-iterations 2",
        )
        self.assertIn("clean --clones-only", err)

    def test_pool_grants_fewer_than_asked(self) -> None:
        out, _ = self.ui_flags(pool=True, UI_WORKERS="3", FAKE_FREE="1")
        self.assertEqual(out, "1|-parallel-testing-enabled NO|")

    def test_pool_off_honours_ui_workers(self) -> None:
        out, _ = self.ui_flags(pool=False, UI_WORKERS="3")
        self.assertTrue(out.startswith("3|-parallel-testing-enabled YES"), out)
        self.assertTrue(out.endswith("|-retry-tests-on-failure -test-iterations 2"), out)

    def test_clamps_and_warns(self) -> None:
        for value, granted, warning in (("9", "3", "above 3"), ("0", "1", "below 1"), ("x", "1", "not a number")):
            with self.subTest(value=value):
                out, err = self.ui_flags(pool=False, UI_WORKERS=value)
                self.assertTrue(out.startswith(f"{granted}|"), out)
                self.assertIn(warning, err)

    def test_retry_setting(self) -> None:
        out, _ = self.ui_flags(pool=False, UI_RETRY_ON_FAILURE="1")
        self.assertEqual(out, "1|-parallel-testing-enabled NO|-retry-tests-on-failure -test-iterations 2")
        out, _ = self.ui_flags(pool=True, UI_RETRY_ON_FAILURE="0")
        self.assertTrue(out.endswith("|"), out)

    def test_bad_retry_setting_fails(self) -> None:
        result = self.run_bash("take_slots 1 x; retry_args", pool=False, UI_RETRY_ON_FAILURE="yes")
        self.assertEqual(result.returncode, 2)

    def test_unit_runs_take_one_slot(self) -> None:
        result = self.run_bash('take_slots 1 unit-tests; echo "${SIMULATOR_SLOTS_GRANTED}"', pool=True)
        self.assertEqual(result.stdout.strip(), "1")

    def test_old_setting_names_fail(self) -> None:
        for name in ("SRB_SIM_MAX", "SIMULATOR_WORKERS_WITHOUT_POOL"):
            with self.subTest(name=name):
                result = self.run_bash("echo reached", pool=False, **{name: "2"})
                self.assertEqual(result.returncode, 2)
                self.assertIn("renamed to UI_WORKERS", result.stderr)
                self.assertNotIn("reached", result.stdout)

    def test_report_marks_retry_only_passes(self) -> None:
        lister = self.tmp / "scripts" / "list_test_failures.py"
        lister.write_text("print('TEST-FAILED: T/a() f.swift:1 boom')\n")
        green = self.run_bash("report_test_failures 0 b", pool=False)
        self.assertEqual(green.stdout.strip(), "PASSED-ON-RETRY: T/a() f.swift:1 boom")
        on_ci = self.run_bash("report_test_failures 0 b", pool=False, GITHUB_ACTIONS="true")
        self.assertEqual(
            on_ci.stdout.strip(), "::warning title=UI test passed only on retry::T/a() f.swift:1 boom"
        )
        red = self.run_bash("report_test_failures 65 b", pool=False)
        self.assertEqual(red.stdout.strip(), "TEST-FAILED: T/a() f.swift:1 boom")


if __name__ == "__main__":
    unittest.main()
