#!/usr/bin/env bash
# Sourceable helper: resolves the xcodebuild -destination string.
# Callers must set ROOT before sourcing (absolute path to repo root).
#
# Priority:
#  1. SIMULATOR_UDID env var — pin a booted device
#  2. Any already-booted simulator whose name matches SIMULATOR_NAME
#  3. Fall back to name + OS=latest (may cold-boot a simulator)

: "${ROOT:?ROOT must be set to the repo root before sourcing _destination.sh}"

# Update SIMULATOR_NAME after major Xcode releases if xcodebuild reports "Unable to find a destination".
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"

_pick_destination() {
	if [[ -n "${SIMULATOR_UDID:-}" ]]; then
		printf '%s\n' "platform=iOS Simulator,id=${SIMULATOR_UDID}"
		return
	fi
	local udid
	udid="$(SIMULATOR_NAME="${SIMULATOR_NAME}" python3 "${ROOT}/scripts/resolve_booted_sim_udid.py" || true)"
	if [[ -n "${udid}" ]]; then
		echo "Using already-booted simulator (id=${udid})" >&2
		printf '%s\n' "platform=iOS Simulator,id=${udid}"
		return
	fi
	printf '%s\n' "platform=iOS Simulator,name=${SIMULATOR_NAME},OS=latest"
}

DESTINATION="$(_pick_destination)"
