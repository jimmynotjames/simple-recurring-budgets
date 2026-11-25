#!/usr/bin/env bash
# Sourceable helper: manages this checkout's simulator in the default CoreSimulator device set.
# Callers must set ROOT before sourcing (absolute path to repo root).
#
# Takes the per-checkout simulator lock first and holds it for the caller's whole run. Never
# opens a GUI; `make sim-show` does. See AGENTS.md §"Simulator sandbox".
#
# Sets, for downstream scripts:
#   SIM_UDID        — UDID of this checkout's booted simulator
#   SIM_DERIVED     — path for xcodebuild -derivedDataPath
#   SIM_RESULTS_DIR — parent directory for -resultBundlePath
# SIMULATOR_NAME picks a different base device; SIMULATOR_UDID pins one and skips
# sandbox management (the lock is still taken: DerivedData and results stay shared).

: "${ROOT:?ROOT must be set before sourcing _sim_sandbox.sh}"

source "${ROOT}/scripts/_sim_common.sh"
sim_lock_acquire || exit $?

SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"

# Scoped output paths — inside .build/ which is already gitignored
SIM_DERIVED="${ROOT}/.build/sim/DerivedData"
SIM_RESULTS_DIR="${ROOT}/.build/sim/results"
_UDID_FILE="${ROOT}/.build/sim/device.udid"

_SIM_DEVICE_NAME="${SIMULATOR_NAME} [${SIM_SLUG}]"

_pick_sim() {
    # $1: "Booted" or "any"
    python3 "${ROOT}/scripts/resolve_booted_sim_udid.py" \
        --name "${_SIM_DEVICE_NAME}" \
        --state "$1"
}

# Keeps the software keyboard on screen. iOS can minimize it to just below the screen mid-run (by
# community reports, once it thinks a hardware keyboard is around); turning automatic minimization
# off in the booted device's live preferences stopped that here, and xcodebuild's parallel-testing
# clones, copied from this device, carry the setting. `HardwareKeyboardLastSeen` is cleared along
# with it on the same reports, unproven on its own. $1: UDID of a booted device.
_keep_keyboard_on_screen() {
    local key
    for key in AutomaticMinimizationEnabled HardwareKeyboardLastSeen; do
        xcrun simctl spawn "$1" defaults write com.apple.keyboard.preferences "${key}" -bool false >&2 \
            || echo "sim-sandbox: warning: could not set ${key}; the software keyboard may hide mid-run" >&2
    done
}

# Every boot starts an unwarmed session; the sentinel's meaning is in ui-tests.sh's header.
_invalidate_warm_sentinel() {
    rm -f "${ROOT}/.build/sim/warmed"
}

_ensure_sim_booted() {
    if [[ -n "${SIMULATOR_UDID:-}" ]]; then
        echo "sim-sandbox: SIMULATOR_UDID pinned — skipping sandbox management" >&2
        SIM_UDID="${SIMULATOR_UDID}"
        return
    fi

    mkdir -p "${ROOT}/.build/sim" "${SIM_DERIVED}" "${SIM_RESULTS_DIR}"

    # 0. Behind the newest installed iOS that hosts its device type (e.g. after an Xcode upgrade) —
    #    delete it so step 3 recreates it on the new runtime instead of reusing the old one forever
    python3 "${ROOT}/scripts/sim_retire_stale.py" --name "${_SIM_DEVICE_NAME}"

    # 1. Already booted — reuse it (still call bootstatus to confirm UI services ready)
    local udid
    udid="$(_pick_sim Booted)"
    if [[ -n "${udid}" ]]; then
        echo "sim-sandbox: reusing booted ${_SIM_DEVICE_NAME} (${udid})" >&2
        _wait_for_ready "${udid}"
        SIM_UDID="${udid}"
        printf '%s' "${SIM_UDID}" > "${_UDID_FILE}"
        return
    fi

    # 2. Exists but shutdown — boot and wait for full readiness
    udid="$(_pick_sim any)"
    if [[ -n "${udid}" ]]; then
        echo "sim-sandbox: booting existing ${_SIM_DEVICE_NAME} (${udid})" >&2
        _boot_and_wait "${udid}"
        _invalidate_warm_sentinel
        SIM_UDID="${udid}"
        printf '%s' "${SIM_UDID}" > "${_UDID_FILE}"
        return
    fi

    # 3. No device yet — create one in the default set and boot it
    echo "sim-sandbox: resolving spec for ${SIMULATOR_NAME}..." >&2
    local spec device_type runtime
    spec="$(python3 "${ROOT}/scripts/resolve_sim_spec.py" --name "${SIMULATOR_NAME}")" || {
        echo "sim-sandbox: error: could not resolve device spec for '${SIMULATOR_NAME}'" >&2
        echo "sim-sandbox: install an iOS runtime that offers this device, pick another with SIMULATOR_NAME, or set SIMULATOR_UDID to an existing device" >&2
        exit 1
    }
    device_type="$(printf '%s\n' "${spec}" | head -1)"
    runtime="$(printf '%s\n' "${spec}" | tail -1)"

    echo "sim-sandbox: creating ${_SIM_DEVICE_NAME} (first-run, ~30–90s)" >&2
    udid="$(xcrun simctl create "${_SIM_DEVICE_NAME}" "${device_type}" "${runtime}")"
    echo "sim-sandbox: booting new ${_SIM_DEVICE_NAME} (${udid})" >&2
    _boot_and_wait "${udid}"
    _invalidate_warm_sentinel
    SIM_UDID="${udid}"
    printf '%s' "${SIM_UDID}" > "${_UDID_FILE}"
}

# Boot the device if not booted, then block until it's fully ready (SpringBoard,
# accessibility services, etc.). `simctl boot` alone returns as soon as boot
# starts — UI tests will time out trying to talk to a half-booted simulator.
# bootstatus's progress goes to stderr so `sim.sh udid` keeps stdout to the UDID alone.
_boot_and_wait() {
    xcrun simctl bootstatus "$1" -b >&2
}

# Wait for an already-booted device to finish coming up. Idempotent and fast
# when the device is already ready; blocks otherwise.
_wait_for_ready() {
    xcrun simctl bootstatus "$1" >&2
}

_ensure_sim_booted
if [[ -z "${SIMULATOR_UDID:-}" ]]; then
    _keep_keyboard_on_screen "${SIM_UDID}"
fi
