#!/usr/bin/env bash
# Full suite: the unit pass, then the UI pass, as two scripts so each holds simulator slots
# only while it tests (AGENTS.md §"Simulator slots").
#   1. unit-tests.sh — serial on this checkout's device; warms it for XCUITest and writes the
#      `warmed` sentinel.
#   2. ui-tests.sh — every UI shard (scripts/ci/ui_shards.py); its build-for-testing reuses the
#      unit build where it can.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "${ROOT}/scripts/unit-tests.sh"
bash "${ROOT}/scripts/ui-tests.sh"
