#!/usr/bin/env bash
# Sourceable: checkout identity and the per-checkout simulator lock. Callers set ROOT first.
#
# Sets ROOT to its physical path and SIM_SLUG (scripts/sim_common.py), and defines
# sim_lock_acquire. Semantics of the lock: AGENTS.md §"Simulator sandbox".

: "${ROOT:?ROOT must be set before sourcing _sim_common.sh}"

ROOT="$(cd "${ROOT}" && pwd -P)"
SIM_SLUG="$(python3 "${ROOT}/scripts/sim_common.py" slug "${ROOT}")"
SIM_LOCK_PATH="${ROOT}/.build/sim.lock"

# Holds SIM_LOCK_PATH on fd 9 until this shell and every child holding fd 9 exit. Outside
# .build/sim/ so `make sim-clean` can't swap the inode under a holder. A nested script inherits
# fd 9, already locked, and returns at once. fd 9 is fixed: /bin/bash 3.2 has no {fd} syntax.
sim_lock_acquire() {
    if python3 "${ROOT}/scripts/sim_lock.py" owns --fd 9 --path "${SIM_LOCK_PATH}"; then
        return 0
    fi
    mkdir -p "${ROOT}/.build"
    exec 9>>"${SIM_LOCK_PATH}"
    python3 "${ROOT}/scripts/sim_lock.py" acquire --fd 9 --path "${SIM_LOCK_PATH}" --root "${ROOT}"
}
