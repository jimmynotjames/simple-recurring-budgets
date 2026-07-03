# App Store release checklist

The master checklist for shipping a Wren release to the App Store, written for a
future Jimmy (or agent) who may not have touched this repo in months or years.
Work top to bottom — phases are ordered by dependency.

**How this is used:** the `/appstore:prepare-for-release` skill copies the checklist body
into a per-release snapshot at `releases/vX.Y.Z.md`, then works through it with
you across as many sessions as the release takes. The snapshot is the state;
this file is the template. Related: [`RELEASES.md`](../RELEASES.md) (append-only
log of what shipped) gets its entry filled in at close-out (P7.5).

**Conventions**

- `🖱️ MANUAL` — only a human can do it (App Store Connect UI, physical device).
- `(optional)` — judgment call; skip with a reason noted in the snapshot.
- Item IDs (`P2.4`) are stable — never renumber; append new items at the end of a phase.
- In snapshots: `- [x]` done, `- [-]` skipped (note why), `- [ ]` pending.
- If a release reveals a missing, wrong, or useless step, **edit this file** as
  part of the close-out PR (P7.6). This checklist only stays trustworthy if each
  release corrects it.

---

## Phase 0 — Re-orientation (start here, especially after a long gap)

- [ ] **P0.1** Read the newest entry in `RELEASES.md` and the newest snapshot in
      `releases/` — what shipped last, and whether a previous release was left
      half-finished.
- [ ] **P0.2** Skim what changed since the last release: `git log --oneline
      vLAST..main` (releases are tagged per P6.3; for v1.0 there is no earlier
      tag — skim `docs/product-features-planning.md` statuses instead).
- [ ] **P0.3** Toolchain sanity: `make build` succeeds on the current Xcode.
      Apple periodically raises the minimum SDK/Xcode required for submissions —
      check https://developer.apple.com/news/ for an active deadline before
      investing in anything else.
- [ ] **P0.4** Auth sanity: `fastlane ios verify_auth` (ASC API key in
      `fastlane/.env`); confirm the Apple Distribution certificate hasn't
      expired (Xcode → Settings → Accounts, or ASC → Certificates). See
      `fastlane/SETUP.md` for key setup if anything is broken.
- [ ] **P0.5** 🖱️ ASC housekeeping: no unaccepted agreements (ASC → Business →
      Agreements), no pending compliance requests or account warnings.
- [ ] **P0.6** 🖱️ Decide the new App Store version number — a product decision
      the agent must always **prompt for, never pick silently**.
      `MARKETING_VERSION` in `project.pbxproj` is the **single source of
      truth** for the user-facing version: `Info.plist` maps it to
      `CFBundleShortVersionString`, which is what SettingsView displays and
      the rating prompt tracks — so the one bump in P4.2 covers the app,
      SettingsView, and the binary ASC receives (build numbers are automated —
      `fastlane/SETUP.md` "Build numbers"). Verify it matches the version
      string ASC expects for this submission. The actual bump happens in P4.2.
- [ ] **P0.7** Create the snapshot `releases/vX.Y.Z.md` (the skill does this)
      and record version + start date in its header.

## Phase 1 — Code & docs readiness

- [ ] **P1.1** Everything intended for this release is merged to `main`;
      working tree clean; `git pull --ff-only` done.
- [ ] **P1.2** Full gate green: `make format && make lint-fix && make build &&
      make test` (log to `tmp/gate.log`).
- [ ] **P1.3** Audit & optional-test due-diligence: analyze the repo, don't
      just eyeball dates. For each audit in `docs/audits/` (date is in the
      filename) and each optional test with a run log (e.g.
      `scripts/translation-accessibility-size-check/AUDIT_LOG.md`), measure the
      git churn in that area since it last ran and recommend re-run / skip per
      area. Rule of thumb: **>6 months stale AND meaningful churn in that area
      → re-run**; record the recommendation table and decisions in the
      snapshot. (The `/appstore:prepare-for-release` skill runs this analysis — see its
      "Executing P1.3" recipe.)
- [ ] **P1.4** No unarchived OpenSpec changes for work that's shipping:
      `openspec list` — verify/archive anything complete.
- [ ] **P1.5** Docs match reality: `docs/main-prd.md` Release Status,
      `docs/product-features-planning.md` feature statuses,
      `docs/tech-design-doc.md` for any new subsystem.
- [ ] **P1.6** Open GitHub issues reviewed: `gh issue list --state open` and
      summarize every issue **not** labeled `deferred`. Decide each one
      explicitly: fix before release, defer (add the `deferred` label + a
      comment), or accept as known for this release — no silent passes. Record
      the disposition list in the snapshot.

## Phase 2 — Localization & App Store content

- [ ] **P2.1** Source strings clean: `python3 scripts/check_source_strings.py`.
- [ ] **P2.2** Translations complete: `python3 scripts/check_translations.py`;
      if new/stale keys exist, run `/translate-new-strings`.
- [ ] **P2.3** (optional) Translation-quality audit: if many strings were added
      since the newest `translation-quality-audit-*` in `docs/audits/`, run
      `/audit-translations` and act on the manifest.
- [ ] **P2.4** Metadata current: review `fastlane/metadata/en-US/*.txt`
      (description, keywords, promotional text) against the app as it is now;
      **write `release_notes.txt` for this version**; then
      `/appstore:translate-metadata`. Done when
      `python3 scripts/translate_metadata/check_metadata.py` exits 0.
- [ ] **P2.5** Screenshots current? Compare `fastlane/screenshots/` against the
      current UI. If any captured screen changed visibly:
      `/appstore:generate-push-screenshots` (re-capture from the existing seed
      catalog). Only regenerate seed content
      (`/appstore:generate-screenshot-seeding`) if locales or demo content
      themselves changed.
- [ ] **P2.6** App icon still right? Check `AppIcon` in the asset catalog:
      light / dark / tinted variants all render correctly on a home screen in
      both appearances; icon still matches current branding; the 1024px
      marketing icon in ASC is consistent with it.
- [ ] **P2.7** 🖱️ URLs alive: the privacy policy URL and support URL configured
      in ASC still resolve; copyright string has the current year.

## Phase 3 — Pre-submission verification

- [ ] **P3.1** (optional, recommended before any submission) Localized-layout
      visual check: `/translation-accessibility-size-check` — truncation,
      overflow, RTL mirroring at forced `.xxxLarge`. Resource-heavy and ad-hoc
      by design; it is **not** part of `make test`, so a release is the moment
      to run it.
- [ ] **P3.2** (optional) VoiceOver + Dynamic Type spot-check of screens that
      are new or changed in this release (PRD §6.8.1).
- [ ] **P3.3** Review-compliance sweep with the `app-store-review` skill:
      privacy manifest (`PrivacyInfo.xcprivacy`), required-reason APIs, and
      guideline pitfalls for anything new in this release.
- [ ] **P3.4** 🖱️ Privacy nutrition labels: ASC → App Privacy answers still
      match what the app actually collects (Mixpanel events behind consent) —
      update if the analytics surface changed (`docs/analytics-spec.md`).
- [ ] **P3.5** Cross-cutting concerns confirmed per PRD §6.8 — accessibility,
      Dark Mode, localization (record the storefront-locale count), analytics.
      This feeds the `RELEASES.md` entry directly.
- [ ] **P3.6** 🖱️ Fresh-install smoke test on a real device: onboarding, create
      a budget, log spending, iCloud sync round-trip.
- [ ] **P3.7** 🖱️ Upgrade smoke test (skip for v1.0): install the **current App
      Store build**, then upgrade to the release candidate — existing data
      intact (SwiftData migration is the risk here).
- [ ] **P3.8** Mixpanel ready to observe the release: prod boards live, consent
      flow verified, no unshipped event-schema changes.

## Phase 4 — Build & upload

- [ ] **P4.1** Release-candidate build — **one binary serves both the final
      TestFlight test and the App Store submission**.
      `/appstore:push-release-build` confirms checklist prep, prompts for the
      version number (decided in P0.6), bumps `MARKETING_VERSION` on a release
      branch, uploads a TestFlight build of it (`fastlane ios beta`), then
      PR → CI → merge. The build it produces is the submission candidate: what
      you test in P4.3 is byte-for-byte what you attach in P5.1.
      Reuse analysis first — a valid candidate may already exist: if
      `MARKETING_VERSION` already equals the new version and there are no
      app-affecting changes since the newest `chore(release): set build number
      to N` commit (`git log <that-sha>..main --oneline --
      simple-recurring-budgets/` is empty), reuse that build instead of
      cutting another.
- [ ] **P4.2** 🖱️ Wait for the build to finish processing (~30 min); check
      email for ITMS post-processing warnings.
- [ ] **P4.3** 🖱️ Final manual test on that exact TestFlight build: install
      build N and check the Settings screen version row first —
      - it shows **vX.Y.Z (N)** (the new version and the TestFlight build
        number), and
      - it does **NOT** show the word **"Debug"** — that badge only renders in
        Debug builds (`SettingsView.debugBadge`), so seeing it means you're
        running a local dev build, not the TestFlight release candidate.
      Then run through onboarding, core budget flows, and anything new in this
      release. Record the build number tested in the snapshot; it is the one
      to attach in P5.1.

## Phase 5 — Submit for review ⭑ MAJOR CHECKPOINT

- [ ] **P5.1** 🖱️ In ASC: create/select version X.Y.Z, attach build N — the
      exact build tested in P4.3 — and proof
      the metadata + screenshots preview, answer export compliance (standard
      HTTPS/OS crypto only — verify this is still true), choose the release
      option (manual / automatic / **phased** — phased recommended once there
      is an existing user base).
- [ ] **P5.2** 🖱️ Click **Submit for Review**. (fastlane *can* do this —
      `deliver` with `submit_for_review: true` — but the repo default is the
      manual click; at a years-between-releases cadence the button is more
      robust than a rusty automation path.)
- [ ] **P5.3** Record in the snapshot: submitted date, build number, and that
      ASC shows **Waiting for Review**. *(Re-invoke the skill when the review
      state changes — Apple emails on transitions.)*

## Phase 6 — Review outcome & release

- [ ] **P6.1** If rejected: read the Resolution Center message, use the
      `app-store-review` skill to interpret the guideline cited, fix, and
      resubmit (rejections often only need a reply or metadata tweak, not a new
      build). Log each rejection + resolution in the snapshot.
- [ ] **P6.2** 🖱️ On approval: release per the P5.1 choice; confirm the new
      version is actually live on the App Store.
- [ ] **P6.3** Record the release date in the snapshot and tag the repo:
      `git tag vX.Y.Z <release-merge-sha> && git push origin vX.Y.Z`
      (this is what makes P0.2 work next time).

## Phase 7 — Post-release monitoring, 7 days ⭑ FINAL CHECKPOINT

- [ ] **P7.1** Day 0–1 — analytics: Mixpanel shows events arriving from the new
      app version; adoption ramping; no event or funnel obviously broken vs.
      the pre-release baseline.
- [ ] **P7.2** Day 0–1 — stability: crash reports in Xcode → Organizer →
      Crashes (and ASC → Analytics → Metrics). Expect near-zero; any crash
      cluster on the new version is a drop-everything signal.
- [ ] **P7.3** 🖱️ Day ~3 — mid-week check: crash-free rate, App Store ratings &
      reviews (respond if needed), key funnels vs. baseline.
- [ ] **P7.4** Day 7 — final check of the same three (crashes, reviews,
      funnels); decide explicitly: healthy, or does something warrant a patch
      release?
- [ ] **P7.5** Close out: fill in the `RELEASES.md` entry (features shipped +
      cross-cutting confirmations from P3.5), set the snapshot header to
      `Status: complete`, and PR both together.
- [ ] **P7.6** Retro on this checklist: add/fix/remove steps in
      `docs/app-store-release-checklist.md` in the same PR, so the next release
      — possibly years away — starts from a corrected map.
