#!/usr/bin/env bash
# Sourceable helper (sourced by _destination.sh, after _sim_sandbox.sh): how many simulators a
# test run uses, whether failed UI tests get a retry, and the device warm-up. AGENTS.md
# §"Simulator slots" has the full picture. This file is identical in checklists and
# simple-recurring-budgets; repo-specific values come from _destination.sh.
#
# The caller sets, before sourcing:
#   ROOT          the repo root
#   WARM_UP_ONLY  the -only-testing id of one small unit suite (warm_up_if_needed)
#
# The pool is opt-in per machine: on only where the simulator-slots master exists
# (${SIMULATOR_SLOTS_MASTER:-~/dev/simulator-slots}). With it on, a run asks for up to N slots,
# gets what is free (at least 1), and holds them until the calling script exits; a failed hold
# fails the run. With it off, nothing is held and a run gets what it asks for.
#
# Settings:
#   UI_WORKERS=1|2|3            simulators for the UI pass. Default 1 (serial), so one run never
#                               takes the whole pool from other agents; the pool can grant fewer
#                               than asked. Clamped to 1..3.
#   UI_RETRY_ON_FAILURE=auto|1|0
#                               auto (default): retry a failed UI test once when 2+ workers are
#                               granted (CPU contention flakes). 1: always retry once (CI). 0: never.
#   SIMULATOR_SLOTS_FEWER=N     (pool on) leave N free slots unused.
#   SIMULATOR_SLOTS_TIMEOUT=S   (pool on) give up after S seconds (exit 75).
# Unit and focused runs are always serial on one slot.

: "${ROOT:?ROOT must be set to the repo root before sourcing _sim_concurrency.sh}"
: "${WARM_UP_ONLY:?WARM_UP_ONLY must be set before sourcing _sim_concurrency.sh}"

# Renamed settings fail loudly, so an old one is never silently ignored.
for _old_setting in SRB_SIM_MAX SIMULATOR_WORKERS_WITHOUT_POOL; do
    if [[ -n "${!_old_setting:-}" ]]; then
        echo "error: ${_old_setting} was renamed to UI_WORKERS (1..3); see AGENTS.md §\"Simulator slots\"" >&2
        exit 2
    fi
done
unset _old_setting

SIMULATOR_SLOTS_HOME="${ROOT}/scripts/simulator-slots"
source "${SIMULATOR_SLOTS_HOME}/simulator_slots.sh"

if [[ -d "${SIMULATOR_SLOTS_MASTER:-${HOME}/dev/simulator-slots}" ]]; then
    SIMULATOR_SLOTS_ENABLED=1
else
    SIMULATOR_SLOTS_ENABLED=0
fi

pool_is_on() {
    [[ "${SIMULATOR_SLOTS_ENABLED}" -eq 1 ]]
}

# Prints how many simulators the UI pass asks for: UI_WORKERS clamped to 1..3, or the default.
ui_workers_wanted() {
    local default=1 value="${UI_WORKERS:-}"
    if [[ -z "${value}" ]]; then
        echo "${default}"
    elif ! [[ "${value}" =~ ^[0-9]+$ ]]; then
        echo "sim-concurrency: warning: UI_WORKERS='${value}' is not a number; using ${default}" >&2
        echo "${default}"
    elif (( value < 1 )); then
        echo "sim-concurrency: warning: UI_WORKERS=${value} is below 1; using 1" >&2
        echo 1
    elif (( value > 3 )); then
        echo "sim-concurrency: warning: UI_WORKERS=${value} is above 3; using 3" >&2
        echo 3
    else
        echo "${value}"
    fi
}

# Takes up to $1 slots for a run labelled $2 and sets SIMULATOR_SLOTS_GRANTED. With the pool off,
# takes none and grants $1. Call after building and before testing, so builds never hold a slot.
take_slots() {
    if ! pool_is_on; then
        echo "simulator-slots: no shared pool on this machine (normal outside the maintainer's); using $1 simulator(s). AGENTS.md §\"Simulator slots\"." >&2
        SIMULATOR_SLOTS_GRANTED="$1"
        return 0
    fi
    simulator_slots_hold "$1" "$2" "${ROOT}" "${SIM_UDID}" "[${SIM_SLUG}]"
}

# take_slots, then sets SLOTS_PARALLEL_ARGS to the xcodebuild flags for the grant: serial on this
# checkout's device for 1, that many clones for more.
slots_parallel_args() {
    take_slots "$1" "$2" || return $?
    if (( SIMULATOR_SLOTS_GRANTED <= 1 )); then
        SLOTS_PARALLEL_ARGS=(-parallel-testing-enabled NO)
    else
        SLOTS_PARALLEL_ARGS=(-parallel-testing-enabled YES
            -parallel-testing-worker-count "${SIMULATOR_SLOTS_GRANTED}"
            -maximum-parallel-testing-workers "${SIMULATOR_SLOTS_GRANTED}")
        # Clones an interrupted run left behind; safe under the checkout lock _sim_sandbox.sh holds.
        python3 "${ROOT}/scripts/sim_clean.py" --clones-only >&2
    fi
}

# Sets RETRY_ARGS from UI_RETRY_ON_FAILURE and the grant (call after slots_parallel_args).
retry_args() {
    local mode="${UI_RETRY_ON_FAILURE:-auto}" retry=0
    case "${mode}" in
        1) retry=1 ;;
        0) retry=0 ;;
        auto) (( SIMULATOR_SLOTS_GRANTED > 1 )) && retry=1 ;;
        *)
            echo "error: UI_RETRY_ON_FAILURE='${mode}' must be auto, 1 or 0" >&2
            return 2
            ;;
    esac
    if (( retry )); then
        RETRY_ARGS=(-retry-tests-on-failure -test-iterations 2)
    else
        RETRY_ARGS=()
    fi
}

# A UI test run on this checkout's own device needs the `warmed` sentinel: XCUITest's IPC socket
# is unreliable until the device has hosted one app lifecycle. unit-tests.sh writes the sentinel
# and every boot clears it. Without it, runs WARM_UP_ONLY here first. Call after taking a slot;
# uses the caller's TEST_ARGS. A parallel run skips this: its clones boot fresh.
warm_up_if_needed() {
    [[ -f "${ROOT}/.build/sim/warmed" ]] && return 0
    echo "sim: device not warmed up; running one unit suite on it first" >&2
    xcodebuild test-without-building "${TEST_ARGS[@]}" \
        -resultBundlePath "${SIM_RESULTS_DIR}/$(date +%Y%m%d_%H%M%S)-$$-warmup.xcresult" \
        -parallel-testing-enabled NO \
        -collect-test-diagnostics never \
        -only-testing:"${WARM_UP_ONLY}" >&2 || {
        echo "error: the warm-up unit suite failed; run 'make unit-tests' to see why." >&2
        return 1
    }
    touch "${ROOT}/.build/sim/warmed"
}

# Prints a run's failures as TEST-FAILED lines ($1: xcodebuild's exit code, $2: the .xcresult).
# A green run with failures passed them only on retry: on CI each becomes a warning annotation,
# locally a PASSED-ON-RETRY line, so the flake gets noticed. With TEST_REPORT_JSON set (CI), also
# writes the run's test report there for the summary comment (scripts/ci/ci_summary.py), labelled
# TEST_REPORT_JOB. Report-only; never fails.
report_test_failures() {
    local rc="$1" bundle="$2" failures line
    local json_args=()
    if [[ -n "${TEST_REPORT_JSON:-}" ]]; then
        json_args=(--json "${TEST_REPORT_JSON}" --rc "${rc}" --job "${TEST_REPORT_JOB:-}")
    fi
    failures="$(python3 "${ROOT}/scripts/list_test_failures.py" ${json_args[@]+"${json_args[@]}"} "${bundle}" || true)"
    [[ -z "${failures}" ]] && return 0
    if [[ "${rc}" -ne 0 ]]; then
        echo "${failures}"
        return 0
    fi
    while IFS= read -r line; do
        if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
            echo "::warning title=UI test passed only on retry::${line#TEST-FAILED: }"
        else
            echo "PASSED-ON-RETRY: ${line#TEST-FAILED: }"
        fi
    done <<<"${failures}"
}
