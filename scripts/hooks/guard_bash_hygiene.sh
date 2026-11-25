#!/usr/bin/env bash
# PreToolUse(Bash) guard for AGENTS.md §"Bash command hygiene" rules 1-6.
# Input: hook JSON on stdin -> .tool_input.command
# Output: on match, a JSON deny decision + exit 0 (deny is authoritative); else exit 0 silently.
set -euo pipefail

cmd="$(jq -r '.tool_input.command // ""')"

reason=""

# Optional `--set <path>` between simctl and its verb, so a custom device set can't dodge rule 5.
SIMCTL_SET='[[:space:]]+--set[[:space:]]+[^[:space:]]+'

if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])(/private)?(/var)?/tmp/'; then
  reason='Blocked (hygiene rule 1): absolute /tmp/. Use the project-local tmp/ (gitignored, allowlisted). Redirect output to tmp/ rather than piping, since a pipe discards the exit code. For commit messages use `git commit -F tmp/msg`; for PR bodies use `gh pr create --body-file tmp/pr-body.md`.'
elif printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_/])sed +(-[a-zA-Z]*i|--in-place)'; then
  reason='Blocked (hygiene rule 2): do not use `sed -i` — use the Edit or Write tool instead.'
elif printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_/])sed +-[a-zA-Z]*n'; then
  reason='Blocked (hygiene rule 3): do not use `sed -n RANGE_p` to slice a file — use the Read tool with offset/limit instead.'
elif printf '%s' "$cmd" | grep -Eq 'git(\s+-C\s+\S+)?\s+push(\s+--[a-zA-Z-]+)*\s+\S{3,}\s+(main|gh-pages)\b'; then
  reason='Blocked (hygiene rule 4): never push directly to main or gh-pages (both have server-side protection). Push a feature branch and open a PR.'
elif printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_/])(pkill|killall)[[:space:]][^|&;]*(Simulator|DeviceHub|launchd_sim)'; then
  reason='Blocked (hygiene rule 5): never kill Simulator, DeviceHub, or CoreSimulator processes — it hits every simulator on the machine. Use `make sim-shutdown` / `make sim-clean` (this checkout'\''s devices only).'
elif printf '%s' "$cmd" | grep -Eq "simctl(${SIMCTL_SET})?[[:space:]]+((shutdown|erase|delete)[[:space:]]+all|delete[[:space:]]+unavailable)([^[:alnum:]_]|\$)"; then
  reason='Blocked (hygiene rule 5): machine-wide `simctl ... all`/`delete unavailable` is not allowed — scoped `simctl <verb> <udid>` stays allowed; otherwise use `make sim-shutdown` / `make sim-clean`.'
elif printf '%s' "$cmd" | grep -oE "simctl(${SIMCTL_SET})?[[:space:]]+[a-z_]+[^|&;]*[[:space:]][\"']?booted([^[:alnum:]_]|\$)" \
    | grep -Eqv "simctl(${SIMCTL_SET})?[[:space:]]+list([^[:alnum:]_]|\$)"; then
  reason='Blocked (hygiene rule 5): `simctl ... booted` acts on whichever device is booted, possibly another checkout'\''s. Target this checkout'\''s device by UDID instead.'
elif printf '%s' "$cmd" | grep -Eq '(^|;|\|&)[[:space:]]*nohup[[:space:]]'; then
  reason='Blocked (hygiene rule 6): do not use `nohup` — it shifts the leading command token and breaks allowlist matching. Use the Bash tool'\''s run_in_background:true instead.'
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
