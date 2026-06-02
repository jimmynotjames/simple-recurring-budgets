#!/usr/bin/env bash
# Sourceable helper: resolves the xcodebuild -destination string.
# Callers must set ROOT before sourcing (absolute path to repo root).
#
# After sourcing, DESTINATION is set for use with xcodebuild -destination.
# SIM_DERIVED and SIM_RESULTS_DIR are also available (set by _sim_sandbox.sh).
#
# Override SIMULATOR_NAME to select a different device (default: iPhone 17).
# Override SIMULATOR_UDID to pin a specific device and skip sandbox management.
# Override SRB_SIM_MAX (1..3, default 2) to set per-repo simulator concurrency.

: "${ROOT:?ROOT must be set to the repo root before sourcing _destination.sh}"

source "${ROOT}/scripts/_sim_sandbox.sh"

# Defines SIM_PARALLEL_FLAGS (from the SRB_SIM_MAX knob) and
# print_sim_concurrency_reminder, used by the test scripts.
source "${ROOT}/scripts/_sim_concurrency.sh"

# Always pin by UDID so xcodebuild never resolves to an unintended device.
DESTINATION="platform=iOS Simulator,id=${SIM_UDID}"
