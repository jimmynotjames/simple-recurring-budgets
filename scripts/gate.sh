#!/usr/bin/env bash
# Single-command form of the gate; the step list is AGENTS.md §"Build and test".
#
# One script so the whole gate is a single allowlisted command (a subshell or trailing
# ; echo splits into segments that prompt). `bash scripts/gate.sh` matches `Bash(bash scripts/*)`.
#
# Format and lint are scoped to changed Swift files (AGENTS.md §"Lint policy"). The tooling
# tests run here; the app's unit and UI suites run in CI, not in the gate, so the gate never
# boots a simulator (AGENTS.md §"Build and test").
#
# Logs everything to tmp/gate.log and stops at the first failing step. Exit code is
# that step's exit code (0 = every step passed). Run it in the background to get
# re-invoked on completion:  Bash(bash scripts/gate.sh, run_in_background=true)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG="tmp/gate.log"
mkdir -p tmp
: > "$LOG"

run_step() {
  local target="$1"
  local rc
  printf '=== make %s ===\n' "$target" | tee -a "$LOG"
  # Run first, capture $? immediately, THEN test. Do NOT write this as
  # `if ! make "$target"; then rc=$?; ...` — the `!` negation resets $? to 0, so the
  # failing step's real exit code is lost.
  make "$target" >>"$LOG" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '\nGATE FAILED at `make %s` (exit %d). Tail of %s:\n' "$target" "$rc" "$LOG"
    tail -40 "$LOG"
    exit "$rc"
  fi
}

run_step tool-versions-check
run_step format-changed
run_step lint-changed
# The vendored simulator-slots copy must match its master, or repos would share one pool
# with different code (skipped where the master doesn't exist). Touches no simulator.
run_step simulator-slots-check
# Offline unit tests of the CI/helper scripts (scripts/tests); quick, no simulator.
run_step script-tests
run_step build

printf '\nGATE PASSED (tool-versions-check, format-changed, lint-changed, simulator-slots-check, script-tests, build). Full log: %s\n' "$LOG"
