#!/usr/bin/env bash
# Sourceable bash wrapper around `simulator_slots.py hold`. Set SIMULATOR_SLOTS_HOME to the
# directory holding this file before sourcing.
#
#   simulator_slots_hold WANT LABEL ROOT [UDID] [OWNS]
#
# UDID and OWNS (text in device names) mark this run's devices, so `status` shows them in use.
#
# Blocks until the pool grants this shell at least one slot (up to WANT), then sets
# SIMULATOR_SLOTS_GRANTED and SIMULATOR_SLOTS_RUN. The slots stay held until this shell exits,
# however it exits. It installs an EXIT trap that records the exit code in runs.log, replacing
# any EXIT trap the caller set. Returns nonzero, holding nothing, when no slot was granted.

: "${SIMULATOR_SLOTS_HOME:?SIMULATOR_SLOTS_HOME must be set before sourcing simulator_slots.sh}"

simulator_slots_hold() {
    local want="$1" label="$2" root="$3" udid="${4:-}" owns="${5:-}"
    local fifo line="" rc=0
    fifo="$(mktemp -u "${TMPDIR:-/tmp}/simulator-slots.XXXXXX")"
    mkfifo "${fifo}"
    # The holder watches this shell's pid ($$, even from the background job) and releases on its exit.
    python3 "${SIMULATOR_SLOTS_HOME}/simulator_slots.py" hold \
        --watch-pid $$ --want "${want}" --label "${label}" --root "${root}" --udid "${udid}" --owns "${owns}" > "${fifo}" &
    SIMULATOR_SLOTS_HOLDER=$!
    read -r line < "${fifo}" || true
    rm -f "${fifo}"
    if [[ -z "${line}" ]]; then
        wait "${SIMULATOR_SLOTS_HOLDER}" || rc=$?
        [[ "${rc}" -ne 0 ]] || rc=1
        echo "simulator-slots: no slot granted (exit ${rc})" >&2
        return "${rc}"
    fi
    SIMULATOR_SLOTS_GRANTED="${line%% *}"
    SIMULATOR_SLOTS_RUN="${line#* }"
    trap '_simulator_slots_release $?' EXIT
    echo "simulator-slots: ${label}: granted ${SIMULATOR_SLOTS_GRANTED} of ${want} wanted (run ${SIMULATOR_SLOTS_RUN})" >&2
}

_simulator_slots_release() {
    python3 "${SIMULATOR_SLOTS_HOME}/simulator_slots.py" result --run "${SIMULATOR_SLOTS_RUN}" --rc "$1" || true
    kill "${SIMULATOR_SLOTS_HOLDER}" 2>/dev/null || true
}
