#!/usr/bin/env bash
# Bare compile step: catches build errors quickly without running the test suite.
# Uses the same simulator destination as scripts/test.sh so derived-data caches are shared.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "${ROOT}/scripts/_destination.sh"

exec xcodebuild build \
	-project simple-recurring-budgets.xcodeproj \
	-scheme simple-recurring-budgets \
	-destination "${DESTINATION}" \
	-destination-timeout 300 \
	-quiet
