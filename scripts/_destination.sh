#!/usr/bin/env bash
# Sourceable helper: sets DESTINATION (xcodebuild -destination); SIM_DERIVED and
# SIM_RESULTS_DIR come from _sim_sandbox.sh. Callers set ROOT (repo root) first.
# Overrides: SIMULATOR_NAME (default iPhone 17), SIMULATOR_UDID (pin a device, skip
# sandbox), SRB_SIM_MAX (1..3; see _sim_concurrency.sh and AGENTS.md §"Simulator slots").

: "${ROOT:?ROOT must be set to the repo root before sourcing _destination.sh}"

source "${ROOT}/scripts/_sim_sandbox.sh"

# Defines slots_parallel_args / ui_slots_wanted for the test scripts.
source "${ROOT}/scripts/_sim_concurrency.sh"

# Pin by UDID so xcodebuild can't resolve to a different device.
DESTINATION="platform=iOS Simulator,id=${SIM_UDID}"
