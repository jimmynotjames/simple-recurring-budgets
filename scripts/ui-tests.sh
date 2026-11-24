#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# UI test pass only (no unit tests), all of CI's shards unless UI_SHARD=<name> (scripts/ci/ui_shards.py
# names) picks one; for iterating on UI failures after `make unit-tests`
# or `make test` is green. The simulator must have hosted a prior app lifecycle before
# the XCUITest IPC socket is reliable, so run `make unit-tests` once per fresh simulator.
#
# Concurrency (AGENTS.md §"Simulator slots"): with the shared pool, asks for SRB_SIM_MAX
# slots (default 2) and runs that many clones; without it, SRB_SIM_MAX if set, else the
# scheme decides.
source "${ROOT}/scripts/_destination.sh"

# Guard: unit-tests.sh writes this sentinel after a successful unit run (the app lifecycle
# the XCUITest IPC socket needs). `make sim-clean` wipes .build/sim/, clearing it.
WARM_SENTINEL="${ROOT}/.build/sim/warmed"
if [[ ! -f "${WARM_SENTINEL}" ]]; then
    echo "error: simulator not warmed up." >&2
    echo "  Run 'make tests' (or 'make unit-tests') before 'make ui-tests'." >&2
    echo "  If you just ran make sim-clean / make initialize-sims, run 'make unit-tests' first." >&2
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

slots_parallel_args "$(ui_slots_wanted)" ui-tests

# The suite selection lives in ui_shards.py, shared with CI; it leaves out testExample,
# testLaunchPerformance and the screenshot captures on purpose.
SUITE_ARGS=()
while IFS= read -r line; do
    SUITE_ARGS+=("$line")
done < <(python3 "${ROOT}/scripts/ci/ui_shards.py" args "${UI_SHARD:-all}")

xcodebuild test-without-building "${COMMON_ARGS[@]}" \
    -resultBundlePath "${RESULT_BUNDLE}" \
    ${SLOTS_PARALLEL_ARGS[@]+"${SLOTS_PARALLEL_ARGS[@]}"} \
    "${SUITE_ARGS[@]}"
