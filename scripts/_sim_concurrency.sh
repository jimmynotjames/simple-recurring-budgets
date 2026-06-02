#!/usr/bin/env bash
# Sourceable helper: turns the SRB_SIM_MAX knob into xcodebuild parallel-testing
# flags and prints a resource-use reminder. Sourced by scripts/_destination.sh,
# so SIM_PARALLEL_FLAGS is defined wherever the destination is resolved.
#
# SRB_SIM_MAX = max simulators this repo's test run may use at once.
#   1  -> serial, single sim (lightest). Same as the historical default.
#   2  -> default. xcodebuild parallel testing with up to 2 sim clones.
#   3  -> only with headroom (RAM-heavy). Default of 2 assumes a ~16 GB
#         Apple-silicon laptop; adjust for the machine actually running.
# Out-of-range values are clamped to 1..3 with a warning.
#
# After sourcing, the following are available:
#   SIM_PARALLEL_FLAGS          — bash array of xcodebuild flags (use "${SIM_PARALLEL_FLAGS[@]}")
#   SRB_SIM_MAX                 — the effective (clamped) value
#   print_sim_concurrency_reminder — function; call it once per test script (writes to stderr)
#
# NOTE on clones: the unit suite (Swift Testing) parallelizes *in-process* and
# does not need clones; clones mainly speed the XCUITest (UI) pass. AGENTS.md
# documents that UI clones can time out on a fresh per-repo device — if the UI
# pass flakes, downshift with `SRB_SIM_MAX=1`.

# Effective value, default 2, clamped to 1..3.
_srb_sim_max_raw="${SRB_SIM_MAX:-2}"
if ! [[ "${_srb_sim_max_raw}" =~ ^[0-9]+$ ]]; then
    echo "sim-concurrency: warning: SRB_SIM_MAX='${_srb_sim_max_raw}' is not a number — using 2" >&2
    SRB_SIM_MAX=2
elif (( _srb_sim_max_raw < 1 )); then
    echo "sim-concurrency: warning: SRB_SIM_MAX=${_srb_sim_max_raw} below range — clamping to 1" >&2
    SRB_SIM_MAX=1
elif (( _srb_sim_max_raw > 3 )); then
    echo "sim-concurrency: warning: SRB_SIM_MAX=${_srb_sim_max_raw} above range — clamping to 3" >&2
    SRB_SIM_MAX=3
else
    SRB_SIM_MAX="${_srb_sim_max_raw}"
fi
unset _srb_sim_max_raw

# xcodebuild flags for the chosen concurrency.
# When parallel (>=2), retry a failed test once: the accessibility-audit UI tests
# are timing-sensitive and occasionally flake under CPU contention (the audit
# fires mid-render). The retry absorbs that flake while a genuine failure still
# fails on both attempts. Serial runs are deterministic and need no retry.
if (( SRB_SIM_MAX <= 1 )); then
    SIM_PARALLEL_FLAGS=(-parallel-testing-enabled NO)
else
    SIM_PARALLEL_FLAGS=(-parallel-testing-enabled YES
        -maximum-concurrent-test-simulator-destinations "${SRB_SIM_MAX}"
        -retry-tests-on-failure
        -test-iterations 2)
fi

# Always-on reminder. Printed by the test scripts (not build.sh) so the user is
# reminded of the resource cost on every test run.
print_sim_concurrency_reminder() {
    {
        echo "────────────────────────────────────────────────────────────"
        if (( SRB_SIM_MAX <= 1 )); then
            echo " sim concurrency: SRB_SIM_MAX=1  (parallel testing DISABLED)"
            echo " Serial, 1 simulator — lightest on resources."
            echo "   Upshift (only with headroom): SRB_SIM_MAX=2 make test"
        else
            echo " sim concurrency: SRB_SIM_MAX=${SRB_SIM_MAX}  (parallel testing ENABLED)"
            echo " ⚠ Up to ${SRB_SIM_MAX} simulators may run at once — RAM-heavy."
            echo "   Downshift (lightest): SRB_SIM_MAX=1 make test"
            echo "   Upshift  (only with headroom): SRB_SIM_MAX=3 make test"
        fi
        echo "────────────────────────────────────────────────────────────"
    } >&2
}
