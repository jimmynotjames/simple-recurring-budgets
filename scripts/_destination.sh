#!/usr/bin/env bash
# Sourceable helper: resolves the xcodebuild -destination string for test runs.
# Callers must set ROOT before sourcing. Sources _sim_sandbox.sh, which sets
# SIM_UDID, SIM_DERIVED, and SIM_RESULTS_DIR; this file turns SIM_UDID into DESTINATION.
# Override SIMULATOR_NAME (device) or SIMULATOR_UDID (pin a device, skip sandboxing).
#
# Also sources _sim_concurrency.sh (slots, UI_WORKERS, retries, warm-up; AGENTS.md
# §"Simulator slots") and defines prepare_test_args.

: "${ROOT:?ROOT must be set to the repo root before sourcing _destination.sh}"

source "${ROOT}/scripts/_sim_sandbox.sh"

# Always pin by UDID so xcodebuild never resolves to an unintended device.
DESTINATION="platform=iOS Simulator,id=${SIM_UDID}"

# The UI test target, and the small, already-built unit suite warm_up_if_needed runs.
UI_TEST_TARGET="simple-recurring-budgetsUITests"
WARM_UP_ONLY="simple-recurring-budgetsTests/simple_recurring_budgetsTests"
source "${ROOT}/scripts/_sim_concurrency.sh"

# Sets TEST_ARGS, the xcodebuild arguments for `test-without-building`. Normally builds for testing
# first. With XCTESTRUN set to a prebuilt .xctestrun (CI's `build` job made it), builds nothing and
# runs that build's products on this checkout's device.
# Extra arguments ($@) go to the build and the test run (unit-tests.sh's coverage flag, say).
prepare_test_args() {
    if [[ -n "${XCTESTRUN:-}" ]]; then
        TEST_ARGS=(-xctestrun "${XCTESTRUN}" -destination "${DESTINATION}" -destination-timeout 300)
        return 0
    fi
    local build_args=(
        -project simple-recurring-budgets.xcodeproj
        -scheme simple-recurring-budgets
        -destination "${DESTINATION}"
        -destination-timeout 300
        -derivedDataPath "${SIM_DERIVED}"
        "$@"
    )
    xcodebuild build-for-testing "${build_args[@]}"
    TEST_ARGS=("${build_args[@]}")
}
