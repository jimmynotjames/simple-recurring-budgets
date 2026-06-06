#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# ────────────────────────────────────────────────────────────────────────────────────────────────
# Ad-hoc localized-layout screenshot capture (issue #171). NOT part of `make test` / any hook.
# Runs LocalizationScreenshotCapture across 13 locales at forced .xxxLarge, exports the screenshots
# to tmp/loc-size-check/, downscales them, and leaves them for visual inspection (Claude eyeballs).
#
# Heavy: it spins up many simulator clones in parallel and saturates CPU/RAM for a while.
# Requires explicit confirmation: pass --yes to proceed.
#
# Knobs (env):
#   WORKERS         parallel simulator clones (default 7). Need NOT equal the language count — xcodebuild
#                   distributes the 13 test methods across the workers. Each clone is a full simulator
#                   (~1.5-2 GB resident) plus app + runner, so on a 16 GB machine keep this around 6-7;
#                   higher will swap. Lower it on smaller RAM; raise it only with headroom to spare.
#   SIMULATOR_NAME  base device to clone (default: repo default via _destination.sh). A compact model
#                   (narrow width) is the worst case for truncation; set e.g. SIMULATOR_NAME="iPhone SE (3rd generation)".
#   MAX_PX          downscale longest screenshot edge to this many px (default 1000) to cut read cost.
# ────────────────────────────────────────────────────────────────────────────────────────────────

WORKERS="${WORKERS:-7}"
MAX_PX="${MAX_PX:-1000}"
OUT="${ROOT}/tmp/loc-size-check"

if [[ "${1:-}" != "--yes" ]]; then
  cat <<EOF
⚠  Localized-layout screenshot capture — RESOURCE WARNING
   This spins up ${WORKERS} simulator clones in parallel and will saturate CPU/RAM for a while.
   Close other heavy apps first. Then re-run to proceed:

       bash scripts/translation-accessibility-size-check/run.sh --yes

   (Override WORKERS / SIMULATOR_NAME / MAX_PX via env — see the header of this script.)
EOF
  exit 2
fi

source "${ROOT}/scripts/_destination.sh"   # sets DESTINATION, SIM_DERIVED, SIM_RESULTS_DIR

echo "→ Warming the simulator (build) …"
bash scripts/build.sh >/dev/null

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULT="${SIM_RESULTS_DIR}/${TIMESTAMP}-loc-size.xcresult"

echo "→ Capturing screenshots across 13 locales @ xxxLarge with ${WORKERS} parallel clones …"
# Bypass the SRB_SIM_MAX clamp deliberately for this ad-hoc run (explicit override, not a default change).
xcodebuild test \
  -project simple-recurring-budgets.xcodeproj \
  -scheme simple-recurring-budgets \
  -destination "${DESTINATION}" \
  -destination-timeout 300 \
  -derivedDataPath "${SIM_DERIVED}" \
  -resultBundlePath "${RESULT}" \
  -parallel-testing-enabled YES \
  -parallel-testing-worker-count "${WORKERS}" \
  -only-testing:simple-recurring-budgetsUITests/LocalizationScreenshotCapture

echo "→ Exporting + downscaling screenshots into ${OUT} …"
rm -rf "${OUT}" && mkdir -p "${OUT}"
RAW="$(mktemp -d)"
xcrun xcresulttool export attachments --path "${RESULT}" --output-path "${RAW}" >/dev/null 2>&1

# Rename exported UUID files to <lang>__<screen>.png using the manifest, then downscale.
# The exporter appends `_<index>_<UUID>.png` to the attachment name we set (e.g.
# `de__02-list-several_0_<UUID>.png`); strip that suffix back to our `<lang>__<screen>` name.
jq -r '.[] | .attachments[]? | select((.suggestedHumanReadableName // "") | test("__"))
        | "\(.exportedFileName)\t\(.suggestedHumanReadableName | sub("_[0-9]+_[0-9A-Fa-f-]+\\.png$"; ""))"' \
        "${RAW}/manifest.json" \
| while IFS=$'\t' read -r file name; do
    [[ -f "${RAW}/${file}" ]] || continue
    cp "${RAW}/${file}" "${OUT}/${name}.png"
    sips -Z "${MAX_PX}" "${OUT}/${name}.png" >/dev/null 2>&1 || true
  done
rm -rf "${RAW}"

COUNT="$(find "${OUT}" -name '*.png' | wc -l | tr -d ' ')"
echo "✓ ${COUNT} screenshot(s) → ${OUT}/ (downscaled to ${MAX_PX}px max edge)"
echo "  Next: inspect them (the localized-layout check is the visual review). They are left in place;"
echo "  delete with: rm -rf ${OUT}"
