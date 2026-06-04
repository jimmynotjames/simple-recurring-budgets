#!/usr/bin/env bash
# Ad-hoc subset test run — run a specific suite or test without the full suite.
#
# Usage:
#   bash scripts/test-only.sh <Target/Suite[/method]> [more identifiers...] [--ui]
#   make test-only ONLY="simple-recurring-budgetsTests/RatingPromptCoordinatorTests"
#
# Each positional arg becomes an `-only-testing:<arg>` filter. Examples:
#   bash scripts/test-only.sh simple-recurring-budgetsTests/RatingPromptCoordinatorTests
#   bash scripts/test-only.sh "simple-recurring-budgetsTests/RatingPromptExpenseSignalsTests/activeNonDeficit()"
#   bash scripts/test-only.sh simple-recurring-budgetsTests/FooTests simple-recurring-budgetsTests/BarTests
#
# By default the UI test target is skipped (unit-only, fast). Pass --ui to allow
# UI tests in the filter set (needed when an -only-testing identifier targets the
# UITests target). This exists so subset runs go through one allowlisted command
# (`bash scripts/*`) with the correct sandboxed simulator + DerivedData, instead
# of a hand-built `source scripts/_destination.sh && xcodebuild ... -only-testing:`
# (the `source` segment is what triggers a permission prompt).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# DESTINATION, SIM_DERIVED, SIM_RESULTS_DIR set by _destination.sh (sandboxed sim).
source "${ROOT}/scripts/_destination.sh"

only_args=()
skip_ui=1
for arg in "$@"; do
  case "$arg" in
    --ui) skip_ui=0 ;;
    --*) echo "test-only.sh: unknown flag '$arg'" >&2; exit 2 ;;
    *) only_args+=( -only-testing:"$arg" ) ;;
  esac
done

if [[ ${#only_args[@]} -eq 0 ]]; then
  echo "usage: test-only.sh <Target/Suite[/method]> [more...] [--ui]" >&2
  exit 2
fi

extra=()
if [[ $skip_ui -eq 1 ]]; then
  extra+=( -skip-testing:simple-recurring-budgetsUITests )
fi

RESULT_BUNDLE="${SIM_RESULTS_DIR}/$(date +%Y%m%d_%H%M%S)-only.xcresult"

# Subset runs are always serial (one sim); SRB_SIM_MAX cloning is for the full UI pass.
exec xcodebuild test \
    -project simple-recurring-budgets.xcodeproj \
    -scheme simple-recurring-budgets \
    -destination "${DESTINATION}" \
    -destination-timeout 300 \
    -derivedDataPath "${SIM_DERIVED}" \
    -resultBundlePath "${RESULT_BUNDLE}" \
    -parallel-testing-enabled NO \
    "${only_args[@]}" \
    ${extra[@]+"${extra[@]}"}
