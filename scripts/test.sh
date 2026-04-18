#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Single simulator: one iPhone model + newest *installed* iOS for that device.
# Update SIMULATOR_NAME after major Xcode releases if xcodebuild reports "Unable to find a destination".
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"

# Destination selection (fastest first):
# 1. SIMULATOR_UDID — pin a device; keep it booted (Simulator.app open or `xcrun simctl boot <udid>`).
# 2. Any *already booted* simulator whose name matches SIMULATOR_NAME (see scripts/resolve_booted_sim_udid.py).
# 3. Fall back to name + OS=latest (xcodebuild may cold-boot a simulator; slowest).
#
# To avoid cold boots: leave Simulator running with your device, or once per session:
#   xcrun simctl boot <UDID>
# List UDIDs: xcrun simctl list devices available
#
# -destination-timeout caps how long xcodebuild waits while resolving/booting the destination (avoids indefinite hang).

pick_destination() {
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

DESTINATION="$(pick_destination)"

exec xcodebuild test \
	-project simple-recurring-budgets.xcodeproj \
	-scheme simple-recurring-budgets \
	-destination "${DESTINATION}" \
	-destination-timeout 300
