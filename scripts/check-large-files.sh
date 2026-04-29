#!/usr/bin/env bash
# Reject staged files larger than 1 MiB (accidental binaries, huge fixtures).
set -euo pipefail

MAX_BYTES=$((1024 * 1024))
failed=0

if [[ $# -eq 0 ]]; then
  exit 0
fi

file_size() {
  local path="$1"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    stat -f%z "$path"
  else
    stat -c%s "$path"
  fi
}

for path in "$@"; do
  [[ -f "$path" ]] || continue
  size="$(file_size "$path")"
  if (( size > MAX_BYTES )); then
    printf 'error: file exceeds 1 MiB (%s bytes): %s\n' "$size" "$path" >&2
    failed=1
  fi
done

exit "$failed"
