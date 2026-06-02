#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Runs only the UI test pass (AccessibilityAuditTests + UserJourneyTests).
# Does NOT re-run unit tests. Use this when iterating on UI test failures
# after `make test-unit` (or `make test`) is already green.
#
# IMPORTANT: This script skips the unit-test warm-up pass that `test.sh` runs
# first. The simulator must have hosted at least one prior app lifecycle before
# the XCUITest IPC socket is reliable. Run `make test-unit` (or
# `make initialize-sims && make build`) at least once per fresh simulator session
# before relying on this script alone.
#
# DESTINATION, SIM_DERIVED, and SIM_RESULTS_DIR are set by _destination.sh.
source "${ROOT}/scripts/_destination.sh"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

xcodebuild test \
    -project simple-recurring-budgets.xcodeproj \
    -scheme simple-recurring-budgets \
    -destination "${DESTINATION}" \
    -destination-timeout 300 \
    -derivedDataPath "${SIM_DERIVED}" \
    -resultBundlePath "${SIM_RESULTS_DIR}/${TIMESTAMP}-ui.xcresult" \
    -parallel-testing-enabled NO \
    -only-testing:simple-recurring-budgetsUITests/AccessibilityAuditTests \
    -only-testing:simple-recurring-budgetsUITests/UserJourneyTests
