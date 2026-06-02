#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# DESTINATION, SIM_DERIVED, and SIM_RESULTS_DIR are set by _destination.sh
# (which sources _sim_sandbox.sh). See those files for env-var overrides.
source "${ROOT}/scripts/_destination.sh"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# -parallel-testing-enabled NO: the scheme has parallelizable=YES for IDE runs,
# but scripted runs use serial execution on the single warm base sim. Reasons:
#   1. Clones inflate runtime — each clone re-boots from the base sim (~30–90s).
#   2. With multiple agents across repo clones, dozens of clones spawn at once
#      and CoreSimulator races during teardown, causing the UI runner to die with
#      "Test crashed with signal kill".

# Step 1 — Unit tests (fast, always reliable).
# -skip-testing:UITests: the UI runner is started in a second pass below so the
# sim has hosted at least one app lifecycle before the XCUITest IPC socket opens.
xcodebuild test \
    -project simple-recurring-budgets.xcodeproj \
    -scheme simple-recurring-budgets \
    -destination "${DESTINATION}" \
    -destination-timeout 300 \
    -derivedDataPath "${SIM_DERIVED}" \
    -resultBundlePath "${SIM_RESULTS_DIR}/${TIMESTAMP}-unit.xcresult" \
    -parallel-testing-enabled NO \
    -skip-testing:simple-recurring-budgetsUITests

# Step 2 — Accessibility UI tests (AccessibilityAuditTests).
# Run after unit tests so the simulator has hosted at least one app lifecycle,
# making the XCUITest IPC socket reliable. -parallel-testing-enabled NO prevents
# xcodebuild from cloning the sim; the clone path consistently times out on a
# fresh per-repo device even after the app has been installed.
xcodebuild test \
    -project simple-recurring-budgets.xcodeproj \
    -scheme simple-recurring-budgets \
    -destination "${DESTINATION}" \
    -destination-timeout 300 \
    -derivedDataPath "${SIM_DERIVED}" \
    -resultBundlePath "${SIM_RESULTS_DIR}/${TIMESTAMP}-ui.xcresult" \
    -parallel-testing-enabled NO \
    -only-testing:simple-recurring-budgetsUITests/AccessibilityAuditTests
