#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Destination selection logic lives in scripts/_destination.sh (shared with scripts/build.sh).
# See that file for priority order and the SIMULATOR_UDID / SIMULATOR_NAME env vars.
# -destination-timeout caps how long xcodebuild waits while resolving/booting the destination.
source "${ROOT}/scripts/_destination.sh"

exec xcodebuild test \
	-project simple-recurring-budgets.xcodeproj \
	-scheme simple-recurring-budgets \
	-destination "${DESTINATION}" \
	-destination-timeout 300
