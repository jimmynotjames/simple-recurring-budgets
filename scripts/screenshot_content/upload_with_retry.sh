#!/usr/bin/env bash
#
# Autonomous, self-healing uploader for App Store screenshots.
#
# `fastlane push_screenshots` (deliver) occasionally jams in its finalization
# phase when App Store Connect returns HTTP 500s — it retries forever instead of
# exiting, so a plain background run can hang indefinitely. This controller wraps
# it with:
#   * hang detection — if no new "Uploaded" line appears for HANG_SECS while the
#     log tail shows ASC 500s, the attempt is killed (it won't self-recover),
#   * a hard per-attempt timeout,
#   * bounded retries with linear backoff (lets a transient ASC incident clear),
#   * a fallback that re-uploads ONLY the storefronts that never confirmed, by
#     staging a pruned screenshots dir and calling the push_screenshots_subset
#     lane (deliver only touches languages present in the path).
#
# Nothing goes live: the lanes set submit_for_review:false. Exits 0 once an
# upload attempt completes cleanly (fastlane exit 0), non-zero if all attempts
# are exhausted. Designed to be launched once as a background task and left alone.
#
# All paths are repo-relative; logs land in tmp/. Idempotent (overwrite_screenshots).

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1   # repo root

SHOTS_DIR="fastlane/screenshots"
STAMP="tmp/upload-controller.log"          # high-level controller progress
MAX_FULL_ATTEMPTS=4
MAX_SUBSET_ATTEMPTS=5
HANG_SECS=240                              # no upload progress + 500s => hung
ATTEMPT_TIMEOUT=2700                       # 45 min hard cap per attempt
POLL=20

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$STAMP"; }

# Run one upload attempt with hang/timeout watchdog.
#   $1 = log file, $2 = lane, $3 = optional SUBSET_PATH env
# Returns: 0 fastlane exited cleanly; 2 hard timeout; 3 killed (hung on 500s);
#          other = fastlane non-zero exit.
run_attempt() {
  local logf="$1" lane="$2" subset="${3:-}"
  : > "$logf"
  if [ -n "$subset" ]; then
    SUBSET_PATH="$subset" fastlane "$lane" > "$logf" 2>&1 &
  else
    fastlane "$lane" > "$logf" 2>&1 &
  fi
  local pid=$! start now cur last_cnt=-1 last_change
  start=$(date +%s); last_change=$start
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$POLL"
    now=$(date +%s)
    if [ $(( now - start )) -gt "$ATTEMPT_TIMEOUT" ]; then
      log "  attempt exceeded ${ATTEMPT_TIMEOUT}s — killing pid $pid"
      kill "$pid" 2>/dev/null; sleep 3; kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null; return 2
    fi
    cur=$(grep -c ': Uploaded ' "$logf" 2>/dev/null || echo 0)
    if [ "$cur" != "$last_cnt" ]; then
      last_cnt=$cur; last_change=$now
    elif [ $(( now - last_change )) -gt "$HANG_SECS" ]; then
      if tail -5 "$logf" 2>/dev/null | grep -q 'Server error got 500'; then
        log "  no progress ${HANG_SECS}s + ASC 500s — killing pid $pid (uploaded so far: $cur)"
        kill "$pid" 2>/dev/null; sleep 3; kill -9 "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null; return 3
      fi
    fi
  done
  wait "$pid"; return $?
}

# Print storefront folder names whose pngs are not all confirmed in $1 (a log).
remaining_storefronts() {
  local logf="$1" d name total ok
  for d in "$SHOTS_DIR"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    total=$(find "$d" -name '*.png' | wc -l | tr -d ' ')
    ok=$(grep ': Uploaded ' "$logf" 2>/dev/null | grep -c "/$name/")
    [ "$ok" -lt "$total" ] && echo "$name"
  done
}

# Stage the given storefronts into a pruned dir and run the subset-upload retry
# loop against them. $* = space-separated storefront names. Returns 0 on a clean
# upload (fastlane exit 0), 1 if all subset attempts are exhausted.
subset_upload_loop() {
  local rem; rem=$(echo "$*" | xargs)
  [ -z "$rem" ] && { log "subset_upload_loop: nothing to do"; return 0; }
  local stage="tmp/screenshots-subset" name
  rm -rf "$stage"; mkdir -p "$stage"
  for name in $rem; do
    if [ -d "$SHOTS_DIR/$name" ]; then cp -R "$SHOTS_DIR/$name" "$stage/$name"
    else log "  WARN: $SHOTS_DIR/$name not found on disk — skipping"; fi
  done
  log "staged $(echo "$rem" | wc -w | tr -d ' ') storefront(s) under $stage: $rem"
  local s=1 rc backoff
  while [ "$s" -le "$MAX_SUBSET_ATTEMPTS" ]; do
    log "subset attempt $s/$MAX_SUBSET_ATTEMPTS for: $rem"
    run_attempt "tmp/fastlane-push-subset-$s.log" push_screenshots_subset "./$stage"; rc=$?
    if [ "$rc" -eq 0 ]; then log "SUCCESS — subset upload completed on attempt $s ($rem)"; return 0; fi
    log "subset attempt $s failed (rc=$rc)"
    backoff=$(( s * 180 )); log "backing off ${backoff}s"; sleep "$backoff"
    s=$(( s + 1 ))
  done
  log "EXHAUSTED subset attempts; still unconfirmed: $rem"
  return 1
}

log "=== screenshot upload controller start ($(find "$SHOTS_DIR" -name '*.png' | wc -l | tr -d ' ') pngs on disk) ==="

# ---- Phase 0: subset-only mode -------------------------------------------
# `SUBSET_ONLY="kn-IN ru" bash scripts/screenshot_content/upload_with_retry.sh`
# skips the full uploads and (re)uploads only the named storefronts. Used to
# re-push a couple of locales that needed a retry, and to verify them (a clean
# fastlane exit 0 means ASC accepted all their shots).
if [ -n "${SUBSET_ONLY:-}" ]; then
  log "SUBSET_ONLY mode for: $SUBSET_ONLY"
  if subset_upload_loop "$SUBSET_ONLY"; then exit 0; else exit 1; fi
fi

# ---- Phase 1: full uploads with retry ------------------------------------
attempt=1
last_log=""
while [ "$attempt" -le "$MAX_FULL_ATTEMPTS" ]; do
  last_log="tmp/fastlane-push-full-$attempt.log"
  log "full attempt $attempt/$MAX_FULL_ATTEMPTS"
  run_attempt "$last_log" push_screenshots; rc=$?
  if [ "$rc" -eq 0 ]; then
    log "SUCCESS — full upload completed on attempt $attempt"
    exit 0
  fi
  log "full attempt $attempt failed (rc=$rc); $(grep -c ': Uploaded ' "$last_log" 2>/dev/null || echo 0) imgs confirmed"
  backoff=$(( attempt * 120 ))
  log "backing off ${backoff}s before next attempt"
  sleep "$backoff"
  attempt=$(( attempt + 1 ))
done

# ---- Phase 2: subset fallback (only unconfirmed storefronts) --------------
rem=$(remaining_storefronts "$last_log" | sort -u | tr '\n' ' ')
rem=$(echo "$rem" | xargs)   # trim
if [ -z "$rem" ]; then
  log "full uploads never exited 0 but every storefront looks confirmed; one final full attempt"
  run_attempt "tmp/fastlane-push-final.log" push_screenshots && { log "SUCCESS on final full attempt"; exit 0; }
  log "EXHAUSTED — giving up"; exit 1
fi

log "falling back to SUBSET upload of unconfirmed storefronts: $rem"
if subset_upload_loop "$rem"; then exit 0; fi
log "EXHAUSTED all full + subset attempts; remaining unconfirmed: $rem"
exit 1
