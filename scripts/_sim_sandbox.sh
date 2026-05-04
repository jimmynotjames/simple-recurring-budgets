#!/usr/bin/env bash
# Sourceable helper: manages a per-repo simulator in the default CoreSimulator device set.
# Callers must set ROOT before sourcing (absolute path to repo root).
#
# Each clone of this repo gets its own dedicated simulator, identified by a unique
# device name derived from the repo path (e.g. "iPhone 17 [a1b2c3d4]"). The device
# lives in the default set so xcodebuild can see it, but the name collision risk is
# eliminated — other repos and Xcode's own devices have different names/UDIDs.
#
# After sourcing, the following are exported for downstream scripts:
#   SIM_UDID        — UDID of a booted simulator for this repo
#   SIM_DERIVED     — path for xcodebuild -derivedDataPath
#   SIM_RESULTS_DIR — parent directory for -resultBundlePath
#
# Environment variables respected:
#   SIMULATOR_UDID  — if set, skip sandbox management entirely (pin this device)
#   SIMULATOR_NAME  — base device name to create/select (default: iPhone 17)
#
# NEVER use `pkill Simulator`, `killall Simulator`, or bare `simctl shutdown all` /
# `simctl erase all` — those affect all simulators on the machine. Use
# `make sim-shutdown` or `make sim-clean` instead (they operate on this repo's
# device UDID only).

: "${ROOT:?ROOT must be set before sourcing _sim_sandbox.sh}"

SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"

# Scoped output paths — inside .build/ which is already gitignored
SIM_DERIVED="${ROOT}/.build/sim/DerivedData"
SIM_RESULTS_DIR="${ROOT}/.build/sim/results"
_UDID_FILE="${ROOT}/.build/sim/device.udid"

# Unique device name: base name + 8-char hash of the repo path.
# Ensures no two clones of this repo share a simulator, even on the same Mac.
_REPO_SLUG="$(printf '%s' "${ROOT}" | shasum | cut -c1-8)"
_SIM_DEVICE_NAME="${SIMULATOR_NAME} [${_REPO_SLUG}]"

_pick_sim() {
    # $1: "Booted" or "any"
    python3 "${ROOT}/scripts/resolve_booted_sim_udid.py" \
        --name "${_SIM_DEVICE_NAME}" \
        --state "$1"
}

_ensure_sim_booted() {
    if [[ -n "${SIMULATOR_UDID:-}" ]]; then
        echo "sim-sandbox: SIMULATOR_UDID pinned — skipping sandbox management" >&2
        SIM_UDID="${SIMULATOR_UDID}"
        return
    fi

    mkdir -p "${ROOT}/.build/sim" "${SIM_DERIVED}" "${SIM_RESULTS_DIR}"

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

    # 2. Exists but shutdown — boot it and wait for full readiness
    udid="$(_pick_sim any)"
    if [[ -n "${udid}" ]]; then
        echo "sim-sandbox: booting existing ${_SIM_DEVICE_NAME} (${udid})" >&2
        _boot_and_wait "${udid}"
        SIM_UDID="${udid}"
        printf '%s' "${SIM_UDID}" > "${_UDID_FILE}"
        return
    fi

    # 3. No device yet — create one in the default set and boot it
    echo "sim-sandbox: resolving spec for ${SIMULATOR_NAME}..." >&2
    local spec device_type runtime
    spec="$(python3 "${ROOT}/scripts/resolve_sim_spec.py" --name "${SIMULATOR_NAME}")" || {
        echo "sim-sandbox: error: could not resolve device spec for '${SIMULATOR_NAME}'" >&2
        echo "sim-sandbox: install the latest iOS runtime in Xcode, or set SIMULATOR_UDID to an existing device" >&2
        exit 1
    }
    device_type="$(printf '%s\n' "${spec}" | head -1)"
    runtime="$(printf '%s\n' "${spec}" | tail -1)"

    echo "sim-sandbox: creating ${_SIM_DEVICE_NAME} (first-run, ~30–90s)" >&2
    udid="$(xcrun simctl create "${_SIM_DEVICE_NAME}" "${device_type}" "${runtime}")"
    echo "sim-sandbox: booting new ${_SIM_DEVICE_NAME} (${udid})" >&2
    _boot_and_wait "${udid}"
    SIM_UDID="${udid}"
    printf '%s' "${SIM_UDID}" > "${_UDID_FILE}"
}

# Boot the device if not booted, then block until it's fully ready (SpringBoard,
# accessibility services, etc.). `simctl boot` alone returns as soon as boot
# starts — UI tests will time out trying to talk to a half-booted simulator.
_boot_and_wait() {
    xcrun simctl bootstatus "$1" -b
}

# Wait for an already-booted device to finish coming up. Idempotent and fast
# when the device is already ready; blocks otherwise.
_wait_for_ready() {
    xcrun simctl bootstatus "$1"
}

_ensure_sim_booted
