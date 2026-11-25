#!/usr/bin/env bash
# Fail unless the installed lint and hook tools match config/lint-tools.env exactly, so every
# machine and CI format and lint the same way.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/lint-tools.env
source "$ROOT/config/lint-tools.env"

failed=0

check() {
  local tool="$1" want="$2" have
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: %s not installed; run make system\n' "$tool" >&2
    failed=1
    return
  fi
  have="$("$tool" "${@:3}" 2>/dev/null | head -1 | sed -E 's/^[^0-9]*//; s/[[:space:]].*$//' || true)"
  if [[ "$have" != "$want" ]]; then
    printf 'error: %s is %s, config/lint-tools.env pins %s; run brew upgrade %s (or update the pin)\n' \
      "$tool" "${have:-unknown}" "$want" "$tool" >&2
    failed=1
  fi
}

check swiftformat "$SWIFTFORMAT_VERSION" --version
check swiftlint "$SWIFTLINT_VERSION" version
check gitleaks "$GITLEAKS_VERSION" version
check lefthook "$LEFTHOOK_VERSION" version

exit "$failed"
