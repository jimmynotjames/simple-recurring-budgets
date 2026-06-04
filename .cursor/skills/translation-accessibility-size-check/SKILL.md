---
name: translation-accessibility-size-check
description: Ad-hoc visual check for localized truncation / overflow / RTL-mirroring at large Dynamic Type. Renders the app in 7 locales at forced .xxxLarge, captures screenshots of the key screens, and has Claude eyeball them. Run on demand (e.g., before an App Store submission) — NOT part of make test / CI / pre-commit. Use when the user asks to check localized layouts, translation truncation, RTL, or large-text rendering before release.
---

# Translation accessibility size check (ad-hoc, Claude-eyeballed)

Visual localized-layout check. Tooling captures screenshots; **the check is Claude reading them.**
Authoritative reference: `scripts/translation-accessibility-size-check/README.md`. Issue: #171.

## Hard rules
- **Resource-heavy + ad-hoc.** It spins up many simulator clones in parallel and saturates the machine.
  **Always warn the user and get an explicit go-ahead before running** (Step 1). Never run it as part of
  a routine flow / commit / CI.
- **Don't write ad-hoc Python/shell** to capture or rename — that's all in `run.sh`.
- **Consult the audit log** (`scripts/translation-accessibility-size-check/AUDIT_LOG.md`) before reporting,
  and **append a Run-history entry** to it after (Steps 3 & 5). It's the durable record — screenshots aren't.
- **Don't delete the screenshots** until the user okays it (Step 5).

## Recipe

### 1. Warn, then confirm
Tell the user, before doing anything: *"This spins up ~N simulator clones in parallel and will saturate
CPU/RAM for a while — close other heavy apps first. Proceed?"* (N = `WORKERS`, default 10.) Wait for an
explicit yes. Mention the knobs if relevant: `WORKERS`, `SIMULATOR_NAME` (a compact device stresses
truncation more), `MAX_PX` (downscale).

### 2. Run the capture
```bash
bash scripts/translation-accessibility-size-check/run.sh --yes
```
This builds, runs `LocalizationScreenshotCapture` across 10 locales @ xxxLarge in parallel, and writes
downscaled PNGs to `tmp/loc-size-check/<lang>__<screen>.png`. (It refuses without `--yes`.)

### 3. Inspect every screenshot — this is the check
**First read `AUDIT_LOG.md`'s "Known issues / decisions"** so you can tell new findings from acknowledged
ones. Then `ls tmp/loc-size-check/` and **Read each PNG**. For each, judge:
- **Truncation / clipping** — any label cut off or "…"; any control overflowing its row.
- **Overlap / overflow** — text colliding with other elements or running off-screen.
- **RTL (ar, he)** — layout mirrored, text right-aligned, Latin tokens (iCloud) / currency / `%@`
  arguments placed correctly.
- **Sanity** — confirm the text actually looks **xxxLarge** (if it looks default-size, the size hook
  didn't engage — flag it; see README "How the size is forced").
Report findings grouped by `language → screen` with a clear verdict. **Match each finding against the log:**
an acknowledged known issue (e.g. KI-1) gets a one-line "as expected (KI-N)" mention; a **new/delta** finding
gets flagged prominently, noting whether the fix is UI layout vs. translation length.

### 4. Log the run
Append a dated **Run history** entry to `AUDIT_LOG.md` (date · run label · device/iOS · scope · `git rev-parse
--short HEAD` · one-line verdict + any new findings). If the user **accepts a new finding as won't-fix /
defer**, promote it into the **Known issues / decisions** section with its rationale and "first seen" date.

### 5. Offer cleanup
The screenshots are large and left in place for the user. After reporting **and logging**, **ask whether to
delete `tmp/loc-size-check/`**, and delete it (`rm -rf tmp/loc-size-check`) only on an explicit green light.

## Notes
- Forced size uses the `FORCE_DYNAMIC_TYPE` env hook (launch arg was flaky on iOS 26.x); inert in prod.
- 10 languages × 7 screens (≈80 shots): **Add Budget yields two** (`03` + `03b-add-budget-lower`) — the
  capture dismisses the auto-focused keyboard and scrolls to show the full period selector + lower cards.
- Extend per the README (more languages = trivial; richer states like the orphan-warning plural alert
  need seed enrichment).
