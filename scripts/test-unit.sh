#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Sets DESTINATION, SIM_DERIVED, SIM_RESULTS_DIR, slots_parallel_args (env overrides: see
# _sim_sandbox.sh and _sim_concurrency.sh).
source "${ROOT}/scripts/_destination.sh"

RESULT_BUNDLE="${SIM_RESULTS_DIR}/$(date +%Y%m%d_%H%M%S)-unit.xcresult"
COMMON_ARGS=(
    -project simple-recurring-budgets.xcodeproj
    -scheme simple-recurring-budgets
    -destination "${DESTINATION}"
    -destination-timeout 300
    -derivedDataPath "${SIM_DERIVED}"
    -enableCodeCoverage YES
)

# Build first, so the build never holds a simulator slot.
xcodebuild build-for-testing "${COMMON_ARGS[@]}"

# One slot, always serial: Swift Testing parallelizes in-process on one sim, and this run is
# the warm-up `make test-ui` needs (it must host an app lifecycle on the base device).
take_slots 1 test-unit

# Unit tests only; `make test` also runs the UI tests.
xcodebuild test-without-building "${COMMON_ARGS[@]}" \
    -resultBundlePath "${RESULT_BUNDLE}" \
    -parallel-testing-enabled NO \
    -skip-testing:simple-recurring-budgetsUITests

# Warm-up sentinel for test-ui.sh; `make sim-clean` clears it.
touch "${ROOT}/.build/sim/warmed"
