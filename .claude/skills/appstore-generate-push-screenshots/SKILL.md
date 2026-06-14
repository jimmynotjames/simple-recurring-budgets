---
name: appstore-generate-push-screenshots
description: Capture localized App Store screenshots with fastlane (Simulator) and upload them to App Store Connect via the self-healing retry controller. Runs the full capture → review → upload phase; if capture is already done, asks whether to re-capture (overwrite) or reuse the existing shots. Asks one choice (pause for inspection vs upload immediately) unless pre-authorized by an argument. Precondition: check_content.py exits 0. Use after /appstore:generate-screenshot-seeding. Invoked via /appstore:generate-push-screenshots.
---

# Capture and push App Store screenshots

Drives the **capture → review → upload** phase of the App Store screenshot
workflow. The seed catalog must already be complete
(`python3 scripts/screenshot_content/check_content.py` exits 0); generate it with
`/appstore:generate-screenshot-seeding` first if it is not.

This skill does two long-running things back to back:

1. **Capture** — `fastlane screenshots` drives the `AppStoreScreenshots` UI test
   on the Simulator (50 locales × 2 devices, ~2 h), then renames the captured
   runtime-code folders to App Store storefront codes
   (`rename_for_deliver.py`, run automatically by the lane).
2. **Upload** — `upload_with_retry.sh` pushes the captured shots to App Store
   Connect, working around ASC's HTTP 500s. Nothing goes live
   (`submit_for_review:false`); shots stage into the "Prepare for Submission"
   version.

Both phases run **in the background** with 20-minute progress ticks, so the whole
skill runs unattended apart from (at most) two choices: whether to re-capture when
shots already exist (step 2, only asked if capture is already complete) and the
pause-vs-upload choice (step 3). Both are skippable via arguments.

## Preflight — orchestrator model (before anything else)

Before any other step, run the **orchestrator-model preflight** (canonical:
`AGENTS.md` → "Orchestrator-model preflight"). This skill is tuned to orchestrate on
**Sonnet**; if the current session model is **not** Sonnet, **stop and confirm**
(`AskUserQuestion` on Claude Code, a markdown block on Cursor) before running
anything. This skill has no subagents — it's pure capture/upload mechanics — so the
only concern is that a model weaker than Sonnet may handle the tick-loop and
success-verification steps unreliably; Opus works but is pricier for no gain.

## Arguments — how to run fully unattended

The invocation may carry optional arguments that **pre-answer the prompts**, so
there is *zero* prompting. Arguments are space-separated and order-independent;
they fall on two independent axes.

**Capture axis (pre-answers the step-2 re-capture prompt, only relevant when shots
already exist):**

- **`recapture`** (also accepts `fresh`, `overwrite`) → clear the existing shots
  and re-capture from scratch (the ~2 h job), even if capture is already complete.
- **`keep`** (also accepts `reuse`, `skip-capture`) → reuse the existing shots and
  skip capture.
- **no capture argument** → if capture is already complete, ask the step-2 prompt
  once (the safe default; recapture is a ~2 h job that overwrites already-inspected
  shots). If capture is missing or partial, capture runs regardless — no prompt.

**Upload axis (pre-answers the step-3 choice):**

- **`upload-now`** (also accepts `b`, `no-pause`, `auto`) → Option **B**: capture,
  then upload immediately; review page opens for post-upload review.
- **`pause`** (also accepts `a`, `inspect`) → Option **A**: capture, open the
  review page, and pause for an explicit "proceed" before uploading.
- **no upload argument** → ask the step-3 choice once (the safe default; uploading
  to ASC is outward-facing, so absent explicit authorization, confirm first).

If the user's surrounding message already authorizes the action (e.g. "re-capture
everything" → `recapture`; "keep the existing shots" → `keep`; "push them without
stopping" / "upload as autonomously as possible" → `upload-now`), treat that as the
matching argument and do **not** prompt for that axis.

## Autonomy

Apart from the step-2 re-capture prompt (only asked when shots already exist, and
skippable via the capture-axis argument above) and the step-3 choice (skippable via
the upload-axis argument), run **end to end without pausing**: do not ask "shall I
proceed?" between steps, do not ask before re-capturing failed locales, and do not
ask before retrying a failed upload subset — all of that is routine and pre-approved
in `.claude/settings.json`. The only other time you stop is a hard failure you
cannot self-heal (e.g. the capture lane fails to build) — surface the log tail and
stop.

## Progress checklist

Print this checklist unchecked at the start, then re-print it (compact, one line
per step) with `- [x]` as each step completes:

0. **Model preflight** — confirm session is Sonnet (else confirm before proceeding)
1. **Precondition** — seed catalog complete (`check_content.py` exits 0)
2. **Capture status** — is capture already done? (`capture_progress.py`); if done,
   ask re-capture vs reuse (unless pre-answered by argument)
3. **Choice** — Option A (pause) or B (upload now), or pre-answered by argument
4. **Capture** — `fastlane screenshots` (skipped if step 2 says done)
5. **Review page** — open `fastlane/screenshots/screenshots.html`
6. **Gate** — [A] pause for "proceed"; [B] continue immediately
7. **Upload** — `upload_with_retry.sh` running in background
8. **Done** — verify all storefronts confirmed; [B] remind review page is open

Omit steps that provably won't run (e.g. skip step 4 when capture is already
complete and you chose to keep the existing shots) and say why.

## Recipe

### 1. Precondition — seed catalog complete

```bash
python3 scripts/screenshot_content/check_content.py
```

- **Exit 0:** continue.
- **Exit non-zero:** stop. The seed catalog has gaps — tell the user to run
  `/appstore:generate-screenshot-seeding` first. Do not capture against an
  incomplete catalog.

### 2. Capture status — is capture already done?

```bash
python3 scripts/screenshot_content/capture_progress.py
```

Reports `N/M locales done` and exits 0 only when **every** locale has its full
5-shot story for every device. It accepts both runtime-code folders (mid-capture)
and storefront-code folders (post-rename), so it reads correctly whether capture
just finished or never ran.

- **Exit non-zero:** capture is needed (or partial). Step 4 runs it — no re-capture
  prompt (there is nothing to overwrite).
- **Exit 0:** capture is already complete. **Do not silently skip — ask whether to
  re-capture or reuse**, unless the capture-axis argument (or the surrounding
  message) already pre-answered it (see **Arguments**). Ask once with
  `AskUserQuestion`:

  **Question:** "Screenshots are already captured (N/M locales, 2 devices each).
  Re-capture and overwrite them, or keep the existing ones?"

  - **Keep existing** (recommended): skip capture (step 4) and go straight to the
    review/upload steps. Recapture is a ~2 h job that would overwrite the
    already-captured (possibly already-inspected) shots.
  - **Re-capture (overwrite)**: clear the old shots and run the full capture.

  > **Cursor / no-AskUserQuestion:** present the choice as a markdown block and
  > wait for the reply (unless pre-authorized).

  Then branch:
  - **Keep / `keep`:** **skip step 4.** Note this in the checklist.
  - **Re-capture / `recapture`:** clear the existing shots so `capture_progress.py`
    no longer reports "done", then run step 4:
    ```bash
    rm -rf fastlane/screenshots/*
    ```
    (This is the only path that wipes `fastlane/screenshots/`. It is gated behind
    the explicit re-capture choice — never clear shots on the "keep" path.)

### 3. Choice — the one human input (skip if pre-authorized)

If an argument or the surrounding message already pre-answered this (see
**Arguments**), skip the prompt and record the chosen option. Otherwise ask once,
**before the long capture**, with `AskUserQuestion`:

**Question:** "Capture + upload screenshots. How would you like to proceed?"

- **A — Pause for inspection** (recommended): after capture, open the review page
  and pause; you say "proceed" when ready to upload.
- **B — Upload without pausing**: after capture, start the upload immediately; the
  review page opens so you can look while it uploads.

> **Cursor / no-AskUserQuestion:** present the choice as a markdown block and wait
> for the reply (unless pre-authorized).

Record the answer (A or B) — it determines step 6.

### 4. Capture — `fastlane screenshots`

**Skip entirely if step 2 was already complete and you chose "keep".** Run it when
capture was missing/partial, or when you chose "re-capture" in step 2 (the old
shots are already cleared at that point). Run in the background
(`run_in_background: true`):

```bash
fastlane screenshots 2>&1 | tee tmp/screenshots-capture.log
```

This is the ~2 h capture; the lane renames folders to storefront codes when it
finishes. Track it on **20-minute ticks**:

1. Launch `sleep 1200` as a background Bash task (`run_in_background: true`).
2. On its completion notification, run
   `python3 scripts/screenshot_content/capture_progress.py`, report the
   done/pending diff in one line, then re-arm the next `sleep 1200`.
3. Stop re-arming when the `fastlane screenshots` background task exits.

**Judge capture success by `capture_progress.py`, not by the task's exit code.**
The command is piped through `tee`, so the reported exit status is `tee`'s, not
fastlane's — it is unreliable. When the capture task exits, run
`capture_progress.py` and branch on **its** exit:

- **Exit 0** (all locales done): go to step 5.
- **Exit non-zero with some locales done** (partial capture — a few locales
  flaked): **self-heal, don't stop.** Re-capture only the pending runtime codes it
  lists, then re-rename, then re-check:
  ```bash
  fastlane snapshot --languages <pending runtime codes, comma-separated> --clear_previous_screenshots false 2>&1 | tee tmp/screenshots-recapture.log
  python3 scripts/screenshot_content/rename_for_deliver.py
  python3 scripts/screenshot_content/capture_progress.py
  ```
  **`--clear_previous_screenshots false` is mandatory here** — the `Snapfile` sets
  `clear_previous_screenshots(true)` for full runs, so without this override
  `snapshot` would wipe the entire `fastlane/screenshots/` tree (every
  already-good locale) before recapturing just these few. (`snapshot` reuses the
  device list from `fastlane/Snapfile`; the pending codes are exactly what
  `capture_progress.py` prints under "pending".) Loop until `capture_progress.py`
  exits 0. Run the recapture in the background with the same 20-minute ticks.
- **Exit non-zero with zero done** (the lane never produced shots — usually a
  build/test failure): surface the tail of `tmp/screenshots-capture.log` and
  stop. This is the one hard-failure case; do not upload nothing.

**Do not use the Monitor tool** for ticks — it prompts on each re-arm. `sleep *`,
`capture_progress.py`, and `screenshot_status.sh` are all allowlisted and never
prompt. See memory `feedback_no_prompt_periodic_progress`.

### 5. Open the review page

```bash
open fastlane/screenshots/screenshots.html
```

Opens in the user's default browser, for both A and B.

### 6. Gate on the step-3 choice

- **Option A — pause:** stop and tell the user:
  > "Review page open at `fastlane/screenshots/screenshots.html`. Let me know when
  > you're ready to upload."

  Wait for an explicit "proceed" (or equivalent) before step 7. Do not
  auto-continue on a timer.
- **Option B — continue:** proceed straight to step 7; the page stays open for
  post-upload review.

### 7. Upload — self-healing retry controller

Never use bare `fastlane push_screenshots` — it hangs indefinitely on ASC HTTP
500s. Use the controller, in the background (`run_in_background: true`):

```bash
bash scripts/screenshot_content/upload_with_retry.sh 2>&1 | tee tmp/screenshots-upload.log
```

Nothing goes live until App Store Connect review; `submit_for_review:false` is
baked into the lanes. Track it on **20-minute ticks**, same pattern as step 4 but
using the status helper:

1. Launch `sleep 1200` as a background Bash task.
2. On its completion notification, run
   `bash scripts/screenshot_content/screenshot_status.sh`, report the status in
   one line, then re-arm the next `sleep 1200`.
3. Stop re-arming when the upload background task exits.

`screenshot_status.sh` reports local capture progress, running processes, the
controller's recent log, and per-storefront upload confirmation — prefer it over
ad-hoc `ps` / `find` / `grep` pipelines, which are not allowlisted and will
prompt.

### 8. Verify completion and self-heal stragglers

When the upload background task exits, **do not trust its exit code** (piped
through `tee`). Determine success from authoritative state:

```bash
bash scripts/screenshot_content/screenshot_status.sh
```

- **All storefronts confirmed** (and `tmp/upload-controller.log` shows a `SUCCESS`
  line): report success — all shots staged in App Store Connect. If **Option B**,
  remind the user the review page is at `fastlane/screenshots/screenshots.html`.
- **Some storefronts unconfirmed** (controller log shows `EXHAUSTED`, or
  `screenshot_status.sh` lists "not fully" storefronts): **re-push just those, no
  prompt.** Take the unconfirmed storefront names and run, in the background:
  ```bash
  SUBSET_ONLY="<storefront codes, space-separated>" bash scripts/screenshot_content/upload_with_retry.sh 2>&1 | tee tmp/screenshots-upload.log
  ```
  A clean controller `SUCCESS` line for the subset confirms ASC accepted them.
  Loop (re-check with `screenshot_status.sh`) until every storefront is confirmed.

### 9. Cleanup — offer to clear tmp working files

After all storefronts are confirmed, offer to clear this run's gitignored tmp
logs/staging (`tmp/screenshots-capture.log`, `tmp/screenshots-recapture.log`,
`tmp/screenshots-upload.log`, `tmp/upload-controller.log`, `tmp/fastlane-push-*.log`,
`tmp/screenshots-subset/`). Ask first; leave `fastlane/screenshots/` (the captured
deliverables) in place unless the user asks to remove them.

## Commands reference

```bash
python3 scripts/screenshot_content/check_content.py          # seed catalog gate
python3 scripts/screenshot_content/capture_progress.py       # capture done vs pending (authoritative)
rm -rf fastlane/screenshots/*                                 # clear shots before a chosen full re-capture (overwrite path only)
fastlane screenshots                                          # capture (~2 h) + auto-rename
fastlane snapshot --languages ja,de,ar --clear_previous_screenshots false  # re-capture a few runtime codes WITHOUT wiping the rest
python3 scripts/screenshot_content/rename_for_deliver.py     # rename runtime→storefront after a snapshot recapture
open fastlane/screenshots/screenshots.html                    # open review page
bash scripts/screenshot_content/upload_with_retry.sh         # full upload with retry
SUBSET_ONLY="kn-IN ru" bash scripts/screenshot_content/upload_with_retry.sh  # re-push stragglers
bash scripts/screenshot_content/screenshot_status.sh         # running jobs + upload confirmation (authoritative)
```

## When NOT to use this skill

- To generate the seed catalog → `/appstore:generate-screenshot-seeding`.
- To transcreate App Store text metadata → `/appstore:translate-metadata`.
