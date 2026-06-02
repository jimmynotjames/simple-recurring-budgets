#!/usr/bin/env bash
# PreToolUse(Bash) guard enforcing AGENTS.md "Bash command hygiene" rules
# deterministically, so the banned patterns can't silently recur:
#
#   rule 1 - no absolute /tmp/ (use project-local, gitignored tmp/)
#   rule 2 - no `sed -i` mutation (use the Edit / Write tools)
#   rule 3 - no `sed -n RANGE_p` slicing (use the Read tool with offset/limit)
#   rule 4 - no direct push to main (create a branch + PR instead)
#
# Input: PreToolUse hook JSON on stdin -> .tool_input.command
# Output: on match, a JSON deny decision + exit 0 (the deny is authoritative).
#         on no match, exit 0 silently (no opinion -> normal permission flow).
set -euo pipefail

cmd="$(jq -r '.tool_input.command // ""')"

reason=""

if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])(/private)?(/var)?/tmp/'; then
  reason='Blocked (hygiene rule 1): this command touches absolute /tmp/. Use the project-local tmp/ directory instead (gitignored and allowlisted, so it never prompts). For build/test output prefer a pipe: `make build 2>&1 | tail -50`. For commit messages use multiple -m flags or `git commit -F tmp/msg`; for PR bodies use `gh pr create --body-file tmp/pr-body.md`.'
elif printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_/])sed +(-[a-zA-Z]*i|--in-place)'; then
  reason='Blocked (hygiene rule 2): do not use `sed -i` to mutate files — it is non-portable (BSD vs GNU), unsafe to allowlist, and bypasses the file-state tracker. Use the Edit tool (replace_all for find/replace) or Write for a full rewrite.'
elif printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_/])sed +-[a-zA-Z]*n'; then
  reason='Blocked (hygiene rule 3): do not use `sed -n RANGE_p FILE` to slice a file. Use the Read tool with offset and limit instead.'
elif printf '%s' "$cmd" | grep -Eq 'git(\s+-C\s+\S+)?\s+push(\s+--[a-zA-Z-]+)*\s+\S{3,}\s+main\b'; then
  reason='Blocked (hygiene rule 4): never push directly to main. Create a feature branch (u/jimmyho/claude-code/<description>), push the branch, and open a PR instead. See AGENTS.md §"Never push directly to main".'
fi

if [ -n "$reason" ]; then
  jq -nc --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
fi

exit 0
