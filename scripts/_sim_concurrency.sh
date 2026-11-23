#!/usr/bin/env bash
# Sourceable helper (sourced by _destination.sh, after _sim_sandbox.sh): decides how many
# simulators a test run uses. AGENTS.md §"Simulator slots" has the full picture.
#
# Two modes, picked by whether the simulator-slots master exists on this machine
# (${SIMULATOR_SLOTS_MASTER:-~/dev/simulator-slots}):
#
#   Pool on  (the maintainer's machine): every test run takes slots from a machine-wide pool
#            shared with other opted-in repos (scripts/simulator-slots, a vendored copy).
#            A run asks for up to WANT, gets what is free (at least 1), and holds it until
#            the calling script exits. A failed hold fails the run; it never falls back.
#   Pool off (everyone else): takes nothing and prints one notice. Concurrency is the
#            dev's call: SRB_SIM_MAX (1..3) if set, otherwise no flags (the scheme decides).
#
# After sourcing, call once per test script, after building and before testing:
#   slots_parallel_args WANT LABEL   — sets SIMULATOR_SLOTS_GRANTED and the bash array
#                                      SLOTS_PARALLEL_ARGS (xcodebuild flags)
# Knobs (pool on): SRB_SIM_MAX sets WANT for the UI pass; SIMULATOR_SLOTS_FEWER=N leaves N
# free slots unused; SIMULATOR_SLOTS_TIMEOUT=S gives up (exit 75) after S seconds.

: "${ROOT:?ROOT must be set to the repo root before sourcing _sim_concurrency.sh}"

SIMULATOR_SLOTS_HOME="${ROOT}/scripts/simulator-slots"
source "${SIMULATOR_SLOTS_HOME}/simulator_slots.sh"

_slots_master="${SIMULATOR_SLOTS_MASTER:-${HOME}/dev/simulator-slots}"
if [[ -d "${_slots_master}" ]]; then
    SIMULATOR_SLOTS_ENABLED=1
else
    SIMULATOR_SLOTS_ENABLED=0
fi

# SRB_SIM_MAX, clamped to 1..3 with a warning. Empty means unset.
SRB_SIM_MAX="${SRB_SIM_MAX:-}"
if [[ -n "${SRB_SIM_MAX}" ]]; then
    if ! [[ "${SRB_SIM_MAX}" =~ ^[0-9]+$ ]]; then
        echo "sim-concurrency: warning: SRB_SIM_MAX='${SRB_SIM_MAX}' is not a number — using 2" >&2
        SRB_SIM_MAX=2
    elif (( SRB_SIM_MAX < 1 )); then
        echo "sim-concurrency: warning: SRB_SIM_MAX=${SRB_SIM_MAX} below range — clamping to 1" >&2
        SRB_SIM_MAX=1
    elif (( SRB_SIM_MAX > 3 )); then
        echo "sim-concurrency: warning: SRB_SIM_MAX=${SRB_SIM_MAX} above range — clamping to 3" >&2
        SRB_SIM_MAX=3
    fi
fi

# How many slots the UI pass asks for: SRB_SIM_MAX, default 2 (the pool decides the grant).
ui_slots_wanted() {
    echo "${SRB_SIM_MAX:-2}"
}

_print_no_pool_notice() {
    local concurrency="${SRB_SIM_MAX:-unset → xcodebuild/scheme default}"
    {
        echo "simulator-slots: no shared pool at ${_slots_master} (expected outside the maintainer's machine)."
        echo "simulator-slots: running without machine-wide coordination; concurrency: SRB_SIM_MAX=${concurrency}."
        echo "simulator-slots: see AGENTS.md §\"Simulator slots\"."
    } >&2
}

# Pool on: takes up to $1 slots for a run labelled $2 (blocks while none are free).
# Pool off: takes none; SIMULATOR_SLOTS_GRANTED is min($1, SRB_SIM_MAX), or empty when
# SRB_SIM_MAX is unset (no opinion).
take_slots() {
    if [[ "${SIMULATOR_SLOTS_ENABLED}" -eq 0 ]]; then
        _print_no_pool_notice
        if [[ -n "${SRB_SIM_MAX}" ]]; then
            SIMULATOR_SLOTS_GRANTED=$(( $1 < SRB_SIM_MAX ? $1 : SRB_SIM_MAX ))
        else
            SIMULATOR_SLOTS_GRANTED=""
        fi
        return 0
    fi
    simulator_slots_hold "$1" "$2" "${ROOT}" "${SIM_UDID}" "[${SIM_SLUG}]"
}

# take_slots, then sets SLOTS_PARALLEL_ARGS for the grant: serial on this checkout's device
# for 1; that many clones for more (with one retry, since the accessibility audits flake under
# CPU contention); nothing when the pool is off and SRB_SIM_MAX is unset. Orphaned clones from
# a crashed run are left to `make sim-clean`: this checkout has no lock, so deleting clones here
# could kill a concurrent run's.
slots_parallel_args() {
    take_slots "$1" "$2" || return $?
    local granted="${SIMULATOR_SLOTS_GRANTED}"
    if [[ -z "${granted}" ]]; then
        SLOTS_PARALLEL_ARGS=()
    elif (( granted <= 1 )); then
        SLOTS_PARALLEL_ARGS=(-parallel-testing-enabled NO)
    else
        SLOTS_PARALLEL_ARGS=(-parallel-testing-enabled YES
            -parallel-testing-worker-count "${granted}"
            -maximum-parallel-testing-workers "${granted}"
            -retry-tests-on-failure
            -test-iterations 2)
    fi
}
