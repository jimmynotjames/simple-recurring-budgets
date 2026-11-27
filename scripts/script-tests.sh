#!/usr/bin/env bash
# Unit tests for the tooling: scripts/tests and scripts/simulator-slots/tests (Python) and
# fastlane/tests (Ruby minitest).
# Both are offline and touch no simulator. The Ruby tests need Ruby 3+ (the system 2.6 can't
# parse them); Homebrew fastlane's Ruby is used when present, and without one they are skipped
# with a warning rather than failing a machine that has no fastlane.
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

RUBY="${RUBY:-}"
if [[ -z "$RUBY" ]]; then
  for candidate in /opt/homebrew/opt/ruby/bin/ruby /usr/local/opt/ruby/bin/ruby ruby; do
    if command -v "$candidate" >/dev/null 2>&1 \
      && "$candidate" -e 'exit(RUBY_VERSION.to_i >= 3 ? 0 : 1)' 2>/dev/null; then
      RUBY="$candidate"
      break
    fi
  done
fi

rb_rc=0
if [[ -z "$RUBY" ]]; then
  echo "script-tests: WARNING: no Ruby 3+ found (brew install fastlane) — fastlane/tests SKIPPED" >&2
else
  "$RUBY" -e 'Dir["fastlane/tests/*_test.rb"].sort.each { |f| require File.expand_path(f) }'
  rb_rc=$?
fi

[[ $py_rc -eq 0 && $rb_rc -eq 0 ]]
