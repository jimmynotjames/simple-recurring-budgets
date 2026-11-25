#!/usr/bin/env bash
# This checkout's simulator, one verb per `make sim-*` target. AGENTS.md §"Simulator sandbox".
#
#   init      boot or create the device
#   udid      boot if needed; print only the UDID on stdout (logs go to stderr)
#   show      boot if needed; open DeviceHub on the device
#   run       build the app, install it on the device, and launch it
#   status    device, lock holder, and checkout path (takes no lock)
#   shutdown  shut down every booted device carrying this checkout's slug (sandbox, Screenshots, clones)
#   clean     delete every device and clone carrying this checkout's slug, and .build/sim
#
# Every verb but `status` holds the checkout's simulator lock while it runs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

UDID_FILE="${ROOT}/.build/sim/device.udid"
CAPTURE_LOCK="${ROOT}/.build/screenshots/capture.lock"

usage() {
    echo "usage: scripts/sim.sh {init|udid|show|run|status|shutdown|clean}" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage

case "$1" in
init)
    source "${ROOT}/scripts/_sim_sandbox.sh"
    echo "sim: ${SIM_UDID}" >&2
    ;;
udid)
    source "${ROOT}/scripts/_sim_sandbox.sh"
    printf '%s\n' "${SIM_UDID}"
    ;;
show)
    source "${ROOT}/scripts/_sim_sandbox.sh"
    # DeviceHub ignores -CurrentDeviceUDID and follows CoreSimulator state, so boot first, then
    # point it at the device. The full path keeps LaunchServices from picking another Xcode's copy.
    DEVICE_HUB="$(xcode-select -p)/../Applications/DeviceHub.app"
    if [[ ! -d "${DEVICE_HUB}" ]]; then
        echo "sim: DeviceHub.app not found at ${DEVICE_HUB} (needs Xcode 27+)" >&2
        exit 1
    fi
    open -a "${DEVICE_HUB}" "devices://device/open?id=${SIM_UDID}"
    echo "sim: opened DeviceHub on ${SIM_UDID}" >&2
    ;;
run)
    source "${ROOT}/scripts/_destination.sh"
    # Signing stays the project default; build.sh's header says why.
    xcodebuild build \
        -project "${XCODE_PROJECT}" \
        -scheme "${XCODE_SCHEME}" \
        -destination "${DESTINATION}" \
        -derivedDataPath "${SIM_DERIVED}" \
        -quiet
    APP="${SIM_DERIVED}/Build/Products/Debug-iphonesimulator/${APP_PRODUCT}"
    BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Info.plist")"
    xcrun simctl install "${SIM_UDID}" "${APP}"
    xcrun simctl launch --terminate-running-process "${SIM_UDID}" "${BUNDLE_ID}" >&2
    echo "sim: launched ${BUNDLE_ID} on ${SIM_UDID}" >&2
    ;;
status)
    echo "checkout: ${ROOT}"
    if [[ -f "${UDID_FILE}" ]]; then
        udid="$(cat "${UDID_FILE}")"
        xcrun simctl list devices | grep "${udid}" || echo "device: ${udid} not found in default set"
    else
        echo "device: not initialized — run make initialize-sims"
    fi
    echo "lock: $(python3 "${ROOT}/scripts/sim_lock.py" status --path "${ROOT}/.build/sim.lock")"
    ;;
shutdown)
    source "${ROOT}/scripts/_sim_common.sh"
    sim_lock_acquire || exit $?
    capture="$(python3 "${ROOT}/scripts/sim_lock.py" status --path "${CAPTURE_LOCK}")"
    if [[ "${capture}" != "free" ]]; then
        echo "sim: a screenshot capture is running in this checkout; not shutting down" >&2
        exit 1
    fi
    python3 "${ROOT}/scripts/sim_clean.py" --shutdown-only
    ;;
clean)
    source "${ROOT}/scripts/_sim_common.sh"
    sim_lock_acquire || exit $?
    capture="$(python3 "${ROOT}/scripts/sim_lock.py" status --path "${CAPTURE_LOCK}")"
    if [[ "${capture}" != "free" ]]; then
        echo "sim: a screenshot capture is running in this checkout; not cleaning" >&2
        exit 1
    fi
    python3 "${ROOT}/scripts/sim_clean.py" || true
    rm -rf "${ROOT}/.build/sim"
    echo "sim: .build/sim removed"
    ;;
*)
    usage
    ;;
esac
