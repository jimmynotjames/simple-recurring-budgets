#!/usr/bin/env bash
# Full suite: the unit pass, then the UI pass, as two scripts so each holds simulator slots
# only while it tests (AGENTS.md §"Simulator slots").
#   1. test-unit.sh — serial on this checkout's device; warms it for XCUITest and writes the
#      `warmed` sentinel.
#   2. test-ui.sh — AccessibilityAuditTests, UserJourneyTests, ClearAmountButtonUITests,
#      AllocationFirstTapUITests; its build-for-testing reuses the unit build where it can.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "${ROOT}/scripts/test-unit.sh"
bash "${ROOT}/scripts/test-ui.sh"
