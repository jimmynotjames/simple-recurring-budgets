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
- **Don't delete the screenshots** until the user okays it (Step 4).

## Recipe

### 1. Warn, then confirm
Tell the user, before doing anything: *"This spins up ~N simulator clones in parallel and will saturate
CPU/RAM for a while — close other heavy apps first. Proceed?"* (N = `WORKERS`, default 7.) Wait for an
explicit yes. Mention the knobs if relevant: `WORKERS`, `SIMULATOR_NAME` (a compact device stresses
truncation more), `MAX_PX` (downscale).

### 2. Run the capture
```bash
bash scripts/translation-accessibility-size-check/run.sh --yes
```
This builds, runs `LocalizationScreenshotCapture` across 7 locales @ xxxLarge in parallel, and writes
downscaled PNGs to `tmp/loc-size-check/<lang>__<screen>.png`. (It refuses without `--yes`.)

### 3. Inspect every screenshot — this is the check
`ls tmp/loc-size-check/`, then **Read each PNG**. For each, judge:
- **Truncation / clipping** — any label cut off or "…"; any control overflowing its row.
- **Overlap / overflow** — text colliding with other elements or running off-screen.
- **RTL (ar, he)** — layout mirrored, text right-aligned, Latin tokens (iCloud) / currency / `%@`
  arguments placed correctly.
- **Sanity** — confirm the text actually looks **xxxLarge** (if it looks default-size, the size hook
  didn't engage — flag it; see README "How the size is forced").
Report findings grouped by `language → screen` with a clear verdict (clean vs. specific issue + which
element/locale), and for any real issue note whether the fix is UI layout vs. translation length.

### 4. Offer cleanup
The screenshots are large and left in place for the user. After reporting, **ask whether to delete
`tmp/loc-size-check/`**, and delete it (`rm -rf tmp/loc-size-check`) only on an explicit green light.

## Notes
- Forced size uses the `FORCE_DYNAMIC_TYPE` env hook (launch arg was flaky on iOS 26.x); inert in prod.
- v1 covers 7 screens/states; extend per the README (more languages = trivial; richer states like the
  orphan-warning plural alert need seed enrichment).
