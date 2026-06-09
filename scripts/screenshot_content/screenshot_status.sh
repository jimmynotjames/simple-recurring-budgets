#!/usr/bin/env bash
#
# One-shot, read-only status for the App Store screenshot capture+upload job.
#
# Run this instead of ad-hoc `ps aux | grep`, `find … | wc -l`, log-tailing
# pipelines, etc. Because it's invoked as `bash scripts/...` (allowlisted), the
# pipes / command-substitution / ps / sed inside it are NOT individually
# permission-checked — so it never prompts mid-job. Safe to run any time:
# touches nothing, just reports.
#
# Reports: local capture progress, any running capture/upload processes, the
# upload controller's recent log, and per-storefront upload confirmation derived
# from the newest fastlane push log (full or subset).

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1   # repo root
SHOTS="fastlane/screenshots"

echo "==== screenshot job status ($(date '+%Y-%m-%d %H:%M:%S')) ===="

echo "-- local capture (on disk) --"
if [ -d "$SHOTS" ]; then
  folders=$(ls -d "$SHOTS"/*/ 2>/dev/null | wc -l | tr -d ' ')
  pngs=$(find "$SHOTS" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
  echo "  $folders storefront folder(s), $pngs png(s)"
else
  echo "  (no $SHOTS yet)"
fi
if [ -f scripts/screenshot_content/capture_progress.py ]; then
  python3 scripts/screenshot_content/capture_progress.py 2>/dev/null | sed 's/^/  /' || true
fi

echo "-- running processes --"
procs=$(ps aux | grep -E "[f]astlane|[d]eliver|[u]pload_with_retry|[c]apture_screenshots|[s]napshot" | awk '{print "  pid "$2": "$11" "$12" "$13" "$14}')
if [ -n "$procs" ]; then echo "$procs"; else echo "  none running"; fi

echo "-- upload controller (tmp/upload-controller.log) --"
if [ -f tmp/upload-controller.log ]; then
  tail -10 tmp/upload-controller.log | sed 's/^/  /'
else
  echo "  (no controller log)"
fi

echo "-- per-storefront confirmation (newest push log) --"
latest=$(ls -t tmp/fastlane-push-full-*.log tmp/fastlane-push-subset-*.log tmp/fastlane-push-final.log 2>/dev/null | head -1)
if [ -n "${latest:-}" ] && [ -d "$SHOTS" ]; then
  echo "  log: $latest"
  confirmed=0; missing=""
  for d in "$SHOTS"/*/; do
    name=$(basename "$d")
    total=$(find "$d" -name '*.png' | wc -l | tr -d ' ')
    ok=$(grep ': Uploaded ' "$latest" 2>/dev/null | grep -c "/$name/")
    if [ "$ok" -ge "$total" ] && [ "$total" -gt 0 ]; then
      confirmed=$((confirmed + 1))
    else
      missing="$missing $name($ok/$total)"
    fi
  done
  echo "  fully uploaded in that pass: $confirmed storefront(s)"
  echo "  not fully in that pass:${missing:- none}"
  echo "  (note: a storefront may have completed in an earlier pass or a subset"
  echo "   retry; cross-check tmp/upload-controller.log for the SUCCESS line.)"
else
  echo "  (no push log yet)"
fi
