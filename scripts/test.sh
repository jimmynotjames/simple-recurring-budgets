#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# DESTINATION, SIM_DERIVED, and SIM_RESULTS_DIR are set by _destination.sh
# (which sources _sim_sandbox.sh). See those files for env-var overrides.
source "${ROOT}/scripts/_destination.sh"

RESULT_BUNDLE="${SIM_RESULTS_DIR}/$(date +%Y%m%d_%H%M%S).xcresult"

# -parallel-testing-enabled NO: the scheme has parallelizable=YES for IDE runs,
# but scripted runs use serial execution on the single warm base sim. Reasons:
#   1. Clones inflate runtime — each clone re-boots from the base sim (~30–90s).
#   2. With multiple agents across repo clones, dozens of clones spawn at once
#      and CoreSimulator races during teardown, causing the UI runner to die with
#      "Test crashed with signal kill".
#
# -skip-testing:simple-recurring-budgetsUITests: XCUITest requires the sim to
# have hosted at least one real app lifecycle before its IPC socket becomes
# reliable. On a fresh per-repo sim (which agents create on first run), the UI
# test runner times out "while preparing to run tests" every time. The UI bundle
# only contains testExample (trivial launch) and testLaunchPerformance (perf
# baseline) — not business-logic tests. Run them manually in Xcode when needed.
exec xcodebuild test \
    -project simple-recurring-budgets.xcodeproj \
    -scheme simple-recurring-budgets \
    -destination "${DESTINATION}" \
    -destination-timeout 300 \
    -derivedDataPath "${SIM_DERIVED}" \
    -resultBundlePath "${RESULT_BUNDLE}" \
    -parallel-testing-enabled NO \
    -skip-testing:simple-recurring-budgetsUITests
