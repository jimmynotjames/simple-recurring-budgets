#!/usr/bin/env bash
# Ad-hoc subset test run.
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
# The UI test target is skipped by default; pass --ui when an identifier targets it.
# Exists so subset runs go through one allowlisted command (`bash scripts/*`) with
# the sandboxed simulator + DerivedData, instead of a hand-built
# `source scripts/_destination.sh && xcodebuild ...` (the `source` segment prompts).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Sets DESTINATION, SIM_DERIVED, SIM_RESULTS_DIR.
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
COMMON_ARGS=(
    -project simple-recurring-budgets.xcodeproj
    -scheme simple-recurring-budgets
    -destination "${DESTINATION}"
    -destination-timeout 300
    -derivedDataPath "${SIM_DERIVED}"
)

# Build first, so the build never holds a simulator slot.
xcodebuild build-for-testing "${COMMON_ARGS[@]}"

# Subset runs are always serial on one slot; clones are for the full UI pass. No `exec`
# below: the slot holder's EXIT trap records this run's result.
take_slots 1 test-only

xcodebuild test-without-building "${COMMON_ARGS[@]}" \
    -resultBundlePath "${RESULT_BUNDLE}" \
    -parallel-testing-enabled NO \
    "${only_args[@]}" \
    ${extra[@]+"${extra[@]}"}
