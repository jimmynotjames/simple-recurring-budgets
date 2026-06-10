#!/usr/bin/env bash
# Report-only coverage summary for the app target (audit 2026-06-10, A1).
# Reads the newest *-unit.xcresult under .build/sim/results/ (or the bundle
# passed as $1) and prints a line-coverage report via coverage_report.py.
# This is NOT a gate — it never fails on low coverage, only on missing data.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RESULTS_DIR="${ROOT}/.build/sim/results"

if [[ $# -ge 1 ]]; then
    BUNDLE="$1"
else
    BUNDLE="$(ls -td "${RESULTS_DIR}"/*-unit.xcresult 2>/dev/null | head -1 || true)"
fi

if [[ -z "${BUNDLE}" || ! -e "${BUNDLE}" ]]; then
    echo "coverage: no unit .xcresult found under ${RESULTS_DIR}" >&2
    echo "coverage: run \`make test-unit\` first (coverage is collected on the unit pass)" >&2
    exit 1
fi

echo "coverage: reading ${BUNDLE}" >&2

if ! JSON="$(xcrun xccov view --report --json "${BUNDLE}" 2>/dev/null)"; then
    echo "coverage: ${BUNDLE} has no coverage data" >&2
    echo "coverage: it likely predates -enableCodeCoverage — re-run \`make test-unit\`" >&2
    exit 1
fi

printf '%s' "${JSON}" | python3 "${ROOT}/scripts/coverage_report.py"
