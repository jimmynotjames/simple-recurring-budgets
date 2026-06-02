#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# DESTINATION, SIM_DERIVED, and SIM_RESULTS_DIR are set by _destination.sh
# (which sources _sim_sandbox.sh). See those files for env-var overrides.
source "${ROOT}/scripts/_destination.sh"

# Unit tests are ALWAYS serial: Swift Testing parallelizes the suite in-process
# on one sim, so SRB_SIM_MAX (which controls UI-pass sim clones) does not apply
# here. This run also serves as the warm-up that `make test-ui` depends on.
echo "sim concurrency: unit tests run serially on 1 sim (Swift Testing parallelizes in-process); SRB_SIM_MAX affects the UI pass only." >&2

RESULT_BUNDLE="${SIM_RESULTS_DIR}/$(date +%Y%m%d_%H%M%S)-unit.xcresult"

# Unit tests only — skips the accessibility UI test suite.
# Use `make test` to run both unit and accessibility UI tests.
exec xcodebuild test \
    -project simple-recurring-budgets.xcodeproj \
    -scheme simple-recurring-budgets \
    -destination "${DESTINATION}" \
    -destination-timeout 300 \
    -derivedDataPath "${SIM_DERIVED}" \
    -resultBundlePath "${RESULT_BUNDLE}" \
    -parallel-testing-enabled NO \
    -skip-testing:simple-recurring-budgetsUITests
