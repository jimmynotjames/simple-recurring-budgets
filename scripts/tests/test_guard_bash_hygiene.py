"""The Bash hygiene hook denies exactly the commands AGENTS.md §"Bash command hygiene" names."""

from __future__ import annotations

import json
import shutil
import subprocess
import unittest
from pathlib import Path

HOOK = Path(__file__).resolve().parents[2] / "scripts" / "hooks" / "guard_bash_hygiene.sh"

DENIED = {
    "rule 1": ["cat /tmp/x.log", "ls /private/tmp/claude"],
    "rule 2": ["sed -i '' s/a/b/ f.txt"],
    "rule 3": ["sed -n 1,5p f.txt"],
    "rule 4": ["git push origin main", "git push --set-upstream origin gh-pages"],
    "rule 5 kill": [
        "killall Simulator",
        "pkill -f Simulator",
        "killall DeviceHub",
        "killall com.apple.CoreSimulator.CoreSimulatorService",
        "pkill launchd_sim",
    ],
    "rule 5 machine-wide": [
        "xcrun simctl shutdown all",
        "xcrun simctl erase all",
        "xcrun simctl delete unavailable",
        "xcrun simctl --set ~/Library/Developer/XCTestDevices delete all",
    ],
    "rule 5 booted": [
        "xcrun simctl io booted screenshot x.png",
        "xcrun simctl io 'booted' screenshot x.png",
        'xcrun simctl io "booted" screenshot x.png',
        "xcrun simctl shutdown booted",
        "xcrun simctl launch --console booted com.example.app",
        "xcrun simctl --set ~/sims status_bar booted override --time 9:41",
        "xcrun simctl list devices booted; xcrun simctl erase booted",
    ],
    "rule 6": ["nohup make unit-tests &"],
}

ALLOWED = [
    "xcrun simctl list devices booted",
    "xcrun simctl list devices booted | grep iPhone",
    "xcrun simctl shutdown 1A2B3C4D-0000-0000-0000-000000000000",
    "xcrun simctl delete allmine",
    "xcrun simctl bootstatus 1A2B3C4D-0000-0000-0000-000000000000 -b",
    "grep -n booted scripts/_sim_sandbox.sh",
    "UDID=$(make -s sim-udid) && xcrun simctl io \"$UDID\" screenshot tmp/s.png",
    "make sim-clean",
    "git push origin u/jimmyho/claude-code/x",
]


def decision(command: str) -> str:
    payload = json.dumps({"tool_input": {"command": command}})
    out = subprocess.run(["bash", str(HOOK)], input=payload, capture_output=True, text=True, check=True).stdout
    if not out.strip():
        return "allow"
    return json.loads(out)["hookSpecificOutput"]["permissionDecision"]


@unittest.skipUnless(shutil.which("jq"), "the hook needs jq")
class GuardBashHygieneTests(unittest.TestCase):
    def test_denied(self) -> None:
        for rule, commands in DENIED.items():
            for command in commands:
                with self.subTest(rule=rule, command=command):
                    self.assertEqual(decision(command), "deny")

    def test_allowed(self) -> None:
        for command in ALLOWED:
            with self.subTest(command=command):
                self.assertEqual(decision(command), "allow")


if __name__ == "__main__":
    unittest.main()
