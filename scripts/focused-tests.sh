#!/usr/bin/env bash
# One or more classes or tests, serially on this checkout's device, holding one simulator slot: the
# isolated rerun of AGENTS.md §"Reading a test result".
#
#   bash scripts/focused-tests.sh "<target>/<Class>[/<test>] [more ids...]" [iterations]   (default 1)
#   make focused-tests ONLY="<target>/<Class>[/<test>]" [ITERATIONS=3]
#
# Ids are whitespace-separated in the first argument, so `make` can pass test names with "()".
# The test target is read from each id: a UI-target id warms the device up first.
# XCTESTRUN=<path> runs a prebuilt build instead of building (prepare_test_args in _destination.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
    echo "usage: scripts/focused-tests.sh \"<target>/<Class>[/<test>] [more ids...]\" [iterations]" >&2
    exit 2
}
for arg in "$@"; do
    if [[ "${arg}" == --ui ]]; then
        echo "error: drop --ui; the target is detected from the id" >&2
        exit 2
    fi
done
[[ $# -ge 1 && $# -le 2 ]] || usage
read -r -a IDS <<<"$1"
[[ ${#IDS[@]} -ge 1 ]] || usage
ITERATIONS="${2:-1}"
if ! [[ "${ITERATIONS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: iterations must be a positive number, got '${ITERATIONS}'" >&2
    exit 2
fi

source "${ROOT}/scripts/_destination.sh"

ONLY_ARGS=()
NEEDS_WARM_UP=0
for id in "${IDS[@]}"; do
    ONLY_ARGS+=(-only-testing:"${id}")
    [[ "${id}" == "${UI_TEST_TARGET}/"* ]] && NEEDS_WARM_UP=1
done

RESULT_BUNDLE="${SIM_RESULTS_DIR}/$(date +%Y%m%d_%H%M%S)-$$-focused.xcresult"

prepare_test_args
take_slots 1 focused-tests

if (( NEEDS_WARM_UP )); then
    warm_up_if_needed
fi

# xcodebuild rejects `-test-iterations 1`, so the flag goes in only for a repeat run.
ITERATION_ARGS=()
if (( ITERATIONS > 1 )); then
    ITERATION_ARGS=(-test-iterations "${ITERATIONS}")
fi

# `|| RC=$?` so `set -e` doesn't skip the failure listing below.
RC=0
xcodebuild test-without-building "${TEST_ARGS[@]}" \
    -resultBundlePath "${RESULT_BUNDLE}" \
    -parallel-testing-enabled NO \
    -collect-test-diagnostics never \
    "${ONLY_ARGS[@]}" \
    ${ITERATION_ARGS[@]+"${ITERATION_ARGS[@]}"} || RC=$?

report_test_failures "${RC}" "${RESULT_BUNDLE}"

echo "result-bundle: ${RESULT_BUNDLE}"
exit "${RC}"
