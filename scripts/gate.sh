#!/usr/bin/env bash
# Gate (tool versions -> format -> lint-fix -> build -> tests) as one command.
#
# Exists so the allowlist matches: Claude Code checks each segment of a compound
# command, and `(make format && ...) > tmp/gate.log; echo` yields segments that match
# no allow entry (prompt). `bash scripts/gate.sh` matches `Bash(bash scripts/*)`.
#
# Logs to tmp/gate.log; stops at the first failing step and exits with its code
# (0 = all passed). Run with run_in_background=true to be re-invoked on completion.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG="tmp/gate.log"
mkdir -p tmp
: > "$LOG"

run_step() {
  local target="$1"
  printf '=== make %s ===\n' "$target" | tee -a "$LOG"
  if ! make "$target" >>"$LOG" 2>&1; then
    local rc=$?
    printf '\nGATE FAILED at `make %s` (exit %d). Tail of %s:\n' "$target" "$rc" "$LOG"
    tail -40 "$LOG"
    exit "$rc"
  fi
}

run_step tool-versions-check
run_step format
run_step lint-fix
# The vendored simulator-slots copy must match its master, or repos would share one pool
# with different code (skipped where the master doesn't exist). Touches no simulator.
run_step simulator-slots-check
# Offline unit tests of the CI/helper scripts (scripts/tests); quick, no simulator.
run_step script-tests
run_step build
run_step tests

printf '\nGATE PASSED (tool-versions-check, format, lint-fix, simulator-slots-check, script-tests, build, tests). Full log: %s\n' "$LOG"
