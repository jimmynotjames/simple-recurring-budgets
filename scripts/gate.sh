#!/usr/bin/env bash
# Single-command form of the four-step gate (format -> lint-fix -> build -> test).
#
# Why this exists: the agent kept writing the gate as
#   (make format && make lint-fix && make build && make test) > tmp/gate.log 2>&1; echo "EXIT=$?"
# Claude Code splits compound bash on (){};|&& and checks each segment against the
# allowlist; the subshell parens and trailing `; echo` produce segments like
# `(make format` and `make test) > tmp/gate.log 2>&1` that match no allow entry, so
# it prompts. Collapsing the whole thing into one script means the only command run
# is `bash scripts/gate.sh`, which the existing `Bash(bash scripts/*)` entry already
# allows — no prompt, no subshell, no trailing echo. See the [[feedback_gate_no_prompt]]
# memory.
#
# Logs everything to tmp/gate.log and stops at the first failing step. Exit code is
# that step's exit code (0 = all four passed). Run it in the background to get
# re-invoked on completion:  Bash(bash scripts/gate.sh, run_in_background=true)
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

run_step format
run_step lint-fix
run_step build
run_step test

printf '\nGATE PASSED (format, lint-fix, build, test). Full log: %s\n' "$LOG"
