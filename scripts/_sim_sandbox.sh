#!/usr/bin/env bash
# Sourceable helper: manages a per-repo simulator in the default CoreSimulator device
# set. Callers set ROOT (repo root) first.
#
# Each clone gets its own simulator, named from a hash of the repo path (e.g.
# "iPhone 17 [a1b2c3d4]"), so it never collides with other repos or Xcode's devices.
#
# Exports: SIM_UDID (booted device), SIM_DERIVED (-derivedDataPath),
# SIM_RESULTS_DIR (parent of -resultBundlePath).
# Env: SIMULATOR_UDID (skip sandbox management, pin this device),
# SIMULATOR_NAME (base name, default iPhone 17).
#
# NEVER use `pkill Simulator`, `killall Simulator`, or bare `simctl shutdown all` /
# `simctl erase all`: they hit every simulator on the machine. Use
# `make sim-shutdown` / `make sim-clean` (this repo's UDID only).

: "${ROOT:?ROOT must be set before sourcing _sim_sandbox.sh}"

SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"

# Output paths under gitignored .build/
SIM_DERIVED="${ROOT}/.build/sim/DerivedData"
SIM_RESULTS_DIR="${ROOT}/.build/sim/results"
_UDID_FILE="${ROOT}/.build/sim/device.udid"

# Device name = base name + 8-char hash of the repo path (one simulator per clone).
_REPO_SLUG="$(printf '%s' "${ROOT}" | shasum | cut -c1-8)"
_SIM_DEVICE_NAME="${SIMULATOR_NAME} [${_REPO_SLUG}]"
# The slug, for the simulator-slots pool to mark this checkout's devices (_sim_concurrency.sh).
SIM_SLUG="${_REPO_SLUG}"

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

    # 1. Already booted: reuse (bootstatus still confirms UI services are ready)
    local udid
    udid="$(_pick_sim Booted)"
    if [[ -n "${udid}" ]]; then
        echo "sim-sandbox: reusing booted ${_SIM_DEVICE_NAME} (${udid})" >&2
        _wait_for_ready "${udid}"
        SIM_UDID="${udid}"
        printf '%s' "${SIM_UDID}" > "${_UDID_FILE}"
        return
    fi

    # 2. Exists but shut down: boot and wait
    udid="$(_pick_sim any)"
    if [[ -n "${udid}" ]]; then
        echo "sim-sandbox: booting existing ${_SIM_DEVICE_NAME} (${udid})" >&2
        _boot_and_wait "${udid}"
        SIM_UDID="${udid}"
        printf '%s' "${SIM_UDID}" > "${_UDID_FILE}"
        return
    fi

    # 3. No device: create and boot
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

# Boot and block until fully ready (SpringBoard, accessibility services).
# `simctl boot` alone returns when boot starts; UI tests time out on a half-booted sim.
_boot_and_wait() {
    xcrun simctl bootstatus "$1" -b
}

# Wait for an already-booted device to finish coming up (fast if already ready).
_wait_for_ready() {
    xcrun simctl bootstatus "$1"
}

_ensure_sim_booted
