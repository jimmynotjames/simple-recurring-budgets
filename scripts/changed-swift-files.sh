#!/usr/bin/env bash
# Print the existing Swift files this branch touched, one per line: committed vs the merge-base
# with main, uncommitted, and untracked (a new file is invisible to `git diff` until staged).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_BRANCH="${BASE_BRANCH:-main}"

{
  # Only compare against the base branch if it actually exists (a fresh clone or a
  # detached checkout may not have it); otherwise fall back to working-tree changes.
  if git rev-parse --verify --quiet "${BASE_BRANCH}" >/dev/null; then
    git diff --name-only --diff-filter=d "${BASE_BRANCH}...HEAD" -- '*.swift'
  fi
  git diff --name-only --diff-filter=d HEAD -- '*.swift'
  git ls-files --others --exclude-standard -- '*.swift'
} | sort -u | while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  printf '%s\n' "$f"
done
