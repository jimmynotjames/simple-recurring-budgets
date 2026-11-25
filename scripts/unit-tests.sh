#!/usr/bin/env bash
# Unit tests only (simple-recurring-budgetsTests) — skips the UI test target. Opt-in: AGENTS.md §"Build and test".
#
# Suites use in-memory ModelContainers (Helpers/TestModelContainer.swift); nothing touches the
# simulator's real store.
#
# `-parallel-testing-enabled NO` is load-bearing for more than speed: it is also what
# keeps Swift Testing, which parallelizes within the process by default, running the
# suite serially.
#
# XCTESTRUN=<path> runs a prebuilt build instead of building (prepare_test_args in _destination.sh).
# DESTINATION, SIM_DERIVED, and SIM_RESULTS_DIR are set by _destination.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "${ROOT}/scripts/_destination.sh"

RESULT_BUNDLE="${SIM_RESULTS_DIR}/$(date +%Y%m%d_%H%M%S)-$$-unit.xcresult"

prepare_test_args -enableCodeCoverage YES
take_slots 1 unit-tests

# `|| RC=$?` so `set -e` doesn't skip the failure listing below.
RC=0
xcodebuild test-without-building "${TEST_ARGS[@]}" \
    -resultBundlePath "${RESULT_BUNDLE}" \
    -parallel-testing-enabled NO \
    -collect-test-diagnostics never \
    -skip-testing:simple-recurring-budgetsUITests || RC=$?

report_test_failures "${RC}" "${RESULT_BUNDLE}"

# The warm sentinel: ui-tests.sh's header.
if [[ "${RC}" -eq 0 ]]; then
    touch "${ROOT}/.build/sim/warmed"
fi

echo "result-bundle: ${RESULT_BUNDLE}"
exit "${RC}"
