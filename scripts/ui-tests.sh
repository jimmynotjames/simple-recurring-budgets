#!/usr/bin/env bash
# UI tests only (simple-recurring-budgetsUITests). Does NOT re-run unit tests. Opt-in: AGENTS.md §"Build and test".
#
# IMPORTANT: the simulator must have hosted at least one prior app lifecycle before
# the XCUITest IPC socket is reliable. unit-tests.sh writes the `warmed` sentinel
# after a successful run, and every boot clears it (`make sim-clean` too). A serial run without
# it warms the device up first with one small unit suite (`warm_up_if_needed`). A parallel run
# doesn't: its clones boot fresh, and xcodebuild shuts this device down to clone it.
#
# UI_WORKERS (1..3) is how many simulators the run uses: default 2 with the slot pool on (it takes
# what is free), 1 with it off. 2+ splits the test classes across that many clones (AGENTS.md
# §"Simulator slots", _sim_concurrency.sh).
#
# UI_SHARD=<name> runs one of CI's shards instead of the whole target (scripts/ci/ui_shards.py).
# XCTESTRUN=<path> runs a prebuilt build instead of building (prepare_test_args in _destination.sh).
# UI_RETRY_ON_FAILURE=auto|1|0 reruns a failed test once: auto (default) when 2+ workers run, 1
# always (CI's shards), 0 never. A pass that needed the retry is reported (report_test_failures).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# The selection first, so a bad shard name fails before any build. Skips the screenshot captures,
# which have their own drivers (fastlane, translation-accessibility-size-check).
SELECTION=()
while IFS= read -r arg; do
    SELECTION+=("$arg")
done < <(python3 "${ROOT}/scripts/ci/ui_shards.py" args "${UI_SHARD:-all}")
if [[ ${#SELECTION[@]} -eq 0 ]]; then
    echo "error: no UI test selection for shard '${UI_SHARD:-all}'" >&2
    exit 2
fi

source "${ROOT}/scripts/_destination.sh"

RESULT_BUNDLE="${SIM_RESULTS_DIR}/$(date +%Y%m%d_%H%M%S)-$$-ui${UI_SHARD:+-${UI_SHARD}}.xcresult"

prepare_test_args
slots_parallel_args "$(ui_workers_wanted)" ui-tests

if [[ "${SIMULATOR_SLOTS_GRANTED}" -le 1 ]]; then
    warm_up_if_needed
fi

retry_args

# `|| RC=$?` so `set -e` doesn't skip the tagging below; never `if ! xcodebuild` (see gate.sh).
RC=0
# `-collect-test-diagnostics never`: nothing here reads the simulator diagnostics, and collecting
# them once hung for its full 600 s timeout after a passing run.
xcodebuild test-without-building "${TEST_ARGS[@]}" \
    -resultBundlePath "${RESULT_BUNDLE}" \
    ${SLOTS_PARALLEL_ARGS[@]+"${SLOTS_PARALLEL_ARGS[@]}"} \
    ${RETRY_ARGS[@]+"${RETRY_ARGS[@]}"} \
    -collect-test-diagnostics never \
    "${SELECTION[@]}" || RC=$?

report_test_failures "${RC}" "${RESULT_BUNDLE}"

echo "result-bundle: ${RESULT_BUNDLE}"
exit "${RC}"
