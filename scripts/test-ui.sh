#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# UI test pass only (no unit tests); for iterating on UI failures after `make test-unit`
# or `make test` is green. The simulator must have hosted a prior app lifecycle before
# the XCUITest IPC socket is reliable, so run `make test-unit` once per fresh simulator.
#
# Concurrency (AGENTS.md §"Simulator slots"): with the shared pool, asks for SRB_SIM_MAX
# slots (default 2) and runs that many clones; without it, SRB_SIM_MAX if set, else the
# scheme decides.
source "${ROOT}/scripts/_destination.sh"

# Guard: test-unit.sh writes this sentinel after a successful unit run (the app lifecycle
# the XCUITest IPC socket needs). `make sim-clean` wipes .build/sim/, clearing it.
WARM_SENTINEL="${ROOT}/.build/sim/warmed"
if [[ ! -f "${WARM_SENTINEL}" ]]; then
    echo "error: simulator not warmed up." >&2
    echo "  Run 'make test' (or 'make test-unit') before 'make test-ui'." >&2
    echo "  If you just ran make sim-clean / make initialize-sims, run 'make test-unit' first." >&2
    exit 1
fi

RESULT_BUNDLE="${SIM_RESULTS_DIR}/$(date +%Y%m%d_%H%M%S)-ui.xcresult"
COMMON_ARGS=(
    -project simple-recurring-budgets.xcodeproj
    -scheme simple-recurring-budgets
    -destination "${DESTINATION}"
    -destination-timeout 300
    -derivedDataPath "${SIM_DERIVED}"
)

# Build first, so the build never holds a simulator slot.
xcodebuild build-for-testing "${COMMON_ARGS[@]}"

slots_parallel_args "$(ui_slots_wanted)" test-ui

# testExample and testLaunchPerformance are excluded from scripted runs on purpose.
xcodebuild test-without-building "${COMMON_ARGS[@]}" \
    -resultBundlePath "${RESULT_BUNDLE}" \
    ${SLOTS_PARALLEL_ARGS[@]+"${SLOTS_PARALLEL_ARGS[@]}"} \
    -only-testing:simple-recurring-budgetsUITests/AccessibilityAuditTests \
    -only-testing:simple-recurring-budgetsUITests/UserJourneyTests \
    -only-testing:simple-recurring-budgetsUITests/ClearAmountButtonUITests \
    -only-testing:simple-recurring-budgetsUITests/AllocationFirstTapUITests
