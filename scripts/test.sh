#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# DESTINATION, SIM_DERIVED, SIM_RESULTS_DIR, and SIM_PARALLEL_FLAGS are set by
# _destination.sh (which sources _sim_sandbox.sh and _sim_concurrency.sh). See
# those files for env-var overrides (SIMULATOR_NAME, SIMULATOR_UDID, SRB_SIM_MAX).
source "${ROOT}/scripts/_destination.sh"

print_sim_concurrency_reminder

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Step 1 — Unit tests (fast, always reliable). ALWAYS serial:
#   - Swift Testing already parallelizes the unit suite *in-process* on one sim,
#     so clones add boot cost with no benefit.
#   - Running serially on the base device hosts an app lifecycle, which the UI
#     pass below relies on for a reliable XCUITest IPC socket. Cloning step 1
#     would leave the base device cold and break that warm-up.
# -skip-testing:UITests: the UI runner is started in pass 2 once the sim is warm.
xcodebuild test \
    -project simple-recurring-budgets.xcodeproj \
    -scheme simple-recurring-budgets \
    -destination "${DESTINATION}" \
    -destination-timeout 300 \
    -derivedDataPath "${SIM_DERIVED}" \
    -resultBundlePath "${SIM_RESULTS_DIR}/${TIMESTAMP}-unit.xcresult" \
    -parallel-testing-enabled NO \
    -skip-testing:simple-recurring-budgetsUITests

# Step 2 — Accessibility and user-journey UI tests. Honors SRB_SIM_MAX via
# SIM_PARALLEL_FLAGS (default 2 → up to 2 sim clones; 1 → serial). Runs after the
# unit pass so the base sim has hosted an app lifecycle before clones are made.
# NOTE: clones of a per-repo device have historically timed out for the UI pass;
# if this flakes, downshift with `SRB_SIM_MAX=1`.
# testExample and testLaunchPerformance are intentionally excluded from scripted runs.
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
    -only-testing:simple-recurring-budgetsUITests/ClearAmountButtonUITests
