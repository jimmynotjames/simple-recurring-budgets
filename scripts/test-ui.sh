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
# DESTINATION, SIM_DERIVED, SIM_RESULTS_DIR, and SIM_PARALLEL_FLAGS are set by
# _destination.sh. Honors SRB_SIM_MAX (default 2 → up to 2 sim clones; 1 → serial).
source "${ROOT}/scripts/_destination.sh"

print_sim_concurrency_reminder

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# NOTE: clones of a per-repo device have historically timed out for the UI pass;
# if this flakes, downshift with `SRB_SIM_MAX=1`.
xcodebuild test \
    -project simple-recurring-budgets.xcodeproj \
    -scheme simple-recurring-budgets \
    -destination "${DESTINATION}" \
    -destination-timeout 300 \
    -derivedDataPath "${SIM_DERIVED}" \
    -resultBundlePath "${SIM_RESULTS_DIR}/${TIMESTAMP}-ui.xcresult" \
    "${SIM_PARALLEL_FLAGS[@]}" \
    -only-testing:simple-recurring-budgetsUITests/AccessibilityAuditTests \
    -only-testing:simple-recurring-budgetsUITests/UserJourneyTests \
    -only-testing:simple-recurring-budgetsUITests/ClearAmountButtonUITests \
    -only-testing:simple-recurring-budgetsUITests/AllocationFirstTapUITests
