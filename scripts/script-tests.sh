#!/usr/bin/env bash
# Unit tests for the tooling: scripts/tests and scripts/simulator-slots/tests (Python).
# Offline; touches no simulator. `make script-tests` and CI's tooling job both run this.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 -m unittest discover -s scripts/tests -q
py_rc=$?
# The pool tool is macOS-only (kqueue, simctl); elsewhere (CI's ubuntu tooling job) its tests skip.
if [[ "$(uname -s)" == Darwin ]]; then
  python3 -m unittest discover -s scripts/simulator-slots/tests -q || py_rc=1
else
  echo "script-tests: scripts/simulator-slots/tests skipped (macOS only)" >&2
fi

[[ $py_rc -eq 0 ]]
