#!/usr/bin/env bash
# Poll a GitHub Actions run (and optionally a PR's checks) until it finishes, then
# print a step-level breakdown. Replaces hand-written `until ...; do sleep 30; done`
# loops, whose segments can't be allowlisted (always prompt) and whose foreground
# `sleep` the Bash tool blocks.
#
# Usage:  bash scripts/wait_ci.sh <run-id> [pr-number] [poll-seconds]
# Run in the background so the harness re-invokes the agent when CI is done:
#   Bash(bash scripts/wait_ci.sh 27147053894 214, run_in_background=true)
set -uo pipefail

RUN_ID="${1:?usage: wait_ci.sh <run-id> [pr-number] [poll-seconds]}"
PR="${2:-}"
POLL="${3:-30}"
MAX_POLLS="${WAIT_CI_MAX_POLLS:-160}"  # ~80 min at 30s; guards against a typo'd run-id

s=""
for ((i = 0; i < MAX_POLLS; i++)); do
  s="$(gh run view "$RUN_ID" --json status,conclusion --jq '.status+" "+.conclusion' 2>/dev/null || true)"
  case "$s" in
    completed*) break ;;
  esac
  sleep "$POLL"
done

case "$s" in
  completed*) ;;
  *) echo "TIMEOUT after $MAX_POLLS polls; last status: '${s:-<none>}'"; exit 1 ;;
esac

echo "DONE: $s"
echo "=== step breakdown ==="
gh run view "$RUN_ID" --json jobs \
  --jq '.jobs[].steps[] | select(.conclusion != "skipped" and .conclusion != "") | .name + ": " + .conclusion' 2>&1

if [ -n "$PR" ]; then
  echo "=== pr #$PR checks ==="
  gh pr checks "$PR" 2>&1 || true
  echo "=== pr #$PR mergeability ==="
  gh pr view "$PR" --json mergeable,mergeStateStatus --jq '.mergeable + " " + .mergeStateStatus' 2>&1 || true
fi
