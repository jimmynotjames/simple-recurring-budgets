# App Store release checklist

The master checklist for shipping a Wren release to the App Store. Audience: a
future developer or agent who may not have touched this repo in months or years.
Work top to bottom — phases are ordered by dependency.

**How this is used:** the `/appstore:prepare-for-release` skill copies the checklist body
into a per-release snapshot at `releases/app-store-release-checklist--vX.Y.Z.md`, then works through it with
you across as many sessions as the release takes. The snapshot is the state;
this file is the template. Related: [`RELEASES.md`](../RELEASES.md) (append-only
log of what shipped) gets its entry filled in at close-out (P7.5).

**Conventions**

- 🎈 `MANUAL` — only a human can do it (App Store Connect UI, physical device).
- 🤔 `(optional)` — judgment call; decide explicitly and record the decision in
  the item's Note.
- Item IDs (`P2.4`) are stable — never renumber; append new items at the end of a phase.
- Checkboxes are binary: `- [ ]` not handled yet, `- [x]` handled. Every item
  carries a `> Note:` field — record the outcome there ("Done", "Skipped —
  reason", "N/A", dates, build numbers). A checked box can mean done *or*
  deliberately skipped; the Note says which.
- If a release reveals a missing, wrong, or useless step, **edit this file** as
  part of the close-out PR (P7.6). This checklist only stays trustworthy if each
  release corrects it.

---

## Phase 0 — Re-orientation (start here, especially after a long gap)

- [ ] **P0.1** Read the newest entry in `RELEASES.md` and the newest snapshot in
      `releases/` — what shipped last, and whether a previous release was left
      half-finished.
      > Note:
- [ ] **P0.2** Skim what changed since the last release: `git log --oneline
      vLAST..main` (releases are tagged per P6.3; for v1.0 there is no earlier
      tag — skim `docs/product-features-planning.md` statuses instead).
      > Note:
- [ ] **P0.3** Toolchain current: update to the **latest release Xcode**
      (App Store or https://developer.apple.com/download/applications/ —
      compare `xcodebuild -version` against the newest at
      https://developer.apple.com/news/releases/) and let Software Update
      bring the Command Line Tools along (`softwareupdate --list` should show
      nothing pending). Then confirm `make build` succeeds on it. Being on
      the latest Xcode automatically satisfies Apple's minimum-SDK submission
      requirements.
      > Note:
- [ ] **P0.4** Auth sanity — two **independent** credentials; a pass on one
      says nothing about the other, so check both explicitly:
      1. `fastlane ios verify_auth` (ASC API key in `fastlane/.env`) — only
         exercises REST auth, never code signing. If `fastlane/.env` or the
         `.p8` key file is missing (new machine), recover per
         `fastlane/SETUP.md` — the key itself is in ASC → Users and Access →
         Integrations, and app secrets live in `config/Secrets.local.xcconfig`
         (`CONTRIBUTING.md § B`).
      2. 🎈 Apple Distribution certificate (code-signing identity) exists and
         hasn't expired: Xcode → Settings → Accounts → Manage Certificates
         (flags expired/expiring; simply absent from the list if it doesn't
         exist yet), or ASC → Certificates. If missing, create it there (or
         let Xcode generate one via automatic signing).
      > Note:
- [ ] **P0.5** 🎈 ASC housekeeping: **Apple Developer Program membership
      active and all agreements are accepted**.
      > Note:
- [ ] **P0.6** 🎈 Decide the new App Store version number — a product decision
      the agent must always **prompt for, never pick silently**.
      `MARKETING_VERSION` in `project.pbxproj` is the **single source of
      truth** for the user-facing version: `Info.plist` maps it to
      `CFBundleShortVersionString`, which is what SettingsView displays and
      the rating prompt tracks — so the one bump in P4.1 covers the app,
      SettingsView, and the binary ASC receives (build numbers are automated —
      `fastlane/SETUP.md` "Build numbers"). Verify it matches the version
      string ASC expects for this submission. The actual bump happens in P4.1.
      > Note:
- [ ] **P0.7** Create the checklist snapshot `releases/app-store-release-checklist--vX.Y.Z.md` (the skill does this)
      and record version + start date in its header.
      > Note:

## Phase 1 — Code & docs readiness

- [ ] **P1.1** Everything intended for this release is merged to `main`;
      working tree clean; `git pull --ff-only` done.
      > Note:
- [ ] **P1.2** Full gate green: `make format && make lint-fix && make build &&
      make test` (log to `tmp/gate.log`).
      > Note:
- [ ] **P1.3** 🎈 Review recent audits: look through `docs/audits/` (date is
      in the filename) and the optional-test run logs (e.g.
      `scripts/translation-accessibility-size-check/AUDIT_LOG.md`) and decide
      whether any audits are due for another round this release. Record the
      decision in the Note.
      > Note:
- [ ] **P1.4** No unarchived OpenSpec changes for work that's shipping:
      `openspec list` — verify/archive anything complete.
      > Note:
- [ ] **P1.5** Docs match reality: `docs/main-prd.md` Release Status,
      `docs/product-features-planning.md` feature statuses,
      `docs/tech-design-doc.md` for any new subsystem.
      > Note:
- [ ] **P1.6** 🎈 Open GitHub issues reviewed: the agent runs `gh issue list
      --state open` and summarizes every issue **not** labeled `deferred`,
      then **prompts you** to decide each one: fix before release, defer (add
      the `deferred` label + a comment), or accept as known for this release —
      no silent passes, the disposition is always your call. Record the
      disposition list in the Note.
      > Note:
- [ ] **P1.7** Dependency bump review — one last look before freezing the
      binary. Dependabot only watches GitHub Actions, so **SPM packages are
      manual**: read the pins in
      `simple-recurring-budgets.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
      and compare each against its upstream latest (`gh api
      repos/{owner}/{repo}/releases/latest`). Judgment rule: take patch/minor
      bumps of SDKs that talk to live services (Mixpanel especially — stale
      analytics SDKs rot against API changes); **skip major bumps** this close
      to a release unless something is broken. Any bump must land before the
      P1.2 gate re-run. Record bump/skip per package.
      > Note:
- [ ] **P1.8** Apple platform review: check `SWIFT_VERSION` and
      `IPHONEOS_DEPLOYMENT_TARGET` in `project.pbxproj` against the current
      Xcode/SDK and decide deliberately whether to move either. Raising the
      deployment target **drops users on older iOS — a product decision, ask
      Developer**; raising the Swift version is a code decision (gate must stay
      green). If either moves, audit the tagged version workarounds:
      `grep -rn "iOS-COMPAT" simple-recurring-budgets/` — each tag names the
      version it exists for and can be deleted once the target passes it.
      (P0.3 already put us on the latest Xcode, covering Apple's
      *submission minimums*; this item is about what *we choose* to target.)
      > Note:

## Phase 2 — Localization & App Store content

- [ ] **P2.1** Source strings clean: `python3 scripts/check_source_strings.py`.
      > Note:
- [ ] **P2.2** Translations complete: `python3 scripts/check_translations.py`;
      if new/stale keys exist, run `/translate-new-strings`.
      > Note:
- [ ] **P2.3** 🤔 (optional) Translation-quality audit: if many strings were added
      since the newest `translation-quality-audit-*` in `docs/audits/`, run
      `/audit-translations` and act on the manifest. **Intensive** — fans out
      an Opus subagent per locale (49 locales); heavy token/time cost.
      > Note:
- [ ] **P2.4** Metadata current **and pushed**: review
      `fastlane/metadata/en-US/*.txt` (description, keywords, promotional
      text) against the app as it is now; **write `release_notes.txt` for this
      version**; then `/appstore:translate-metadata` until
      `python3 scripts/translate_metadata/check_metadata.py` exits 0.
      Then upload: `fastlane ios push_metadata` — it stages into the editable
      ("Prepare for Submission") version in ASC, so if none exists yet, create
      version X.Y.Z in ASC first (that's the start of P5.1 — just do that bit
      early). Known gotchas are in `fastlane/SETUP.md` (e.g. the v1.0
      "No data" crash: one-time save of ASC → App Review Information, then
      re-run).
      > Note:
- [ ] **P2.5** 🎈 Screenshots update? A developer judgment call — the agent
      **prompts you**: should the App Store screenshots be updated for this
      release? Compare `fastlane/screenshots/` against the current UI to
      inform the call. If yes: `/appstore:generate-push-screenshots`
      (re-capture from the existing seed catalog); only regenerate seed
      content (`/appstore:generate-screenshot-seeding`) if locales or demo
      content themselves changed. Record the decision in the Note.
      > Note:
- [ ] **P2.6** App icon still right? Check `AppIcon` in the asset catalog:
      light / dark / tinted variants all render correctly on a home screen in
      both appearances; icon still matches current branding; the 1024px
      marketing icon in ASC is consistent with it.
      > Note:
- [ ] **P2.7** 🎈 URLs alive: the privacy policy URL and support URL configured
      in ASC still resolve; copyright string has the current year.
      > Note:

## Phase 3 — Pre-submission verification

- [ ] **P3.1** 🤔 (optional, recommended before any submission) Localized-layout
      visual check: `/translation-accessibility-size-check` — truncation,
      overflow, RTL mirroring at forced `.xxxLarge`. Resource-heavy and ad-hoc
      by design; it is **not** part of `make test`, so a release is the moment
      to run it.
      > Note:
- [ ] **P3.2** 🤔 (optional) VoiceOver + Dynamic Type spot-check of screens that
      are new or changed in this release (PRD §6.8.1).
      > Note:
- [ ] **P3.3** Review-compliance sweep with the `app-store-review` skill:
      privacy manifest (`PrivacyInfo.xcprivacy`), required-reason APIs, and
      guideline pitfalls for anything new in this release.
      > Note:
- [ ] **P3.4** 🎈 Privacy nutrition labels: ASC → App Privacy answers still
      match what the app actually collects (Mixpanel events behind consent) —
      update if the analytics surface changed (`docs/analytics-spec.md`).
      While there: the **Accessibility Nutrition Label** answers (ASC → App
      Store → Accessibility) — fill in on first release, re-check if
      accessibility support changed.
      > Note:
- [ ] **P3.5** Cross-cutting concerns confirmed per PRD §6.8 — accessibility,
      Dark Mode, localization (record the storefront-locale count), analytics.
      This feeds the `RELEASES.md` entry directly.
      > Note:
- [ ] **P3.6** Mixpanel ready to observe the release: prod boards live, consent
      flow verified, no unshipped event-schema changes.
      > Note:
- [ ] **P3.7** 🎈 CloudKit **Production** schema deployed: if the SwiftData
      model changed since the last release (any file under
      `simple-recurring-budgets/Models/` — or first release), deploy the
      schema to Production **before** cutting the release candidate. Dev-signed
      builds use the Development environment, but **TestFlight and App Store
      builds use Production** — an undeployed schema means sync silently fails
      for exactly the builds that matter. Constraints in
      `docs/tech-design-doc.md` §4.3 (CloudKit cannot delete deployed record
      fields). The P4.3 iCloud round-trip on the TestFlight build is the
      verification. **Use the `/cloudkit-deploy-schema` skill** to drive this
      (preflight checks, stale-field handling, mandatory confirmation gates
      before anything destructive) — run it on Opus-tier (see that skill's own
      Model preference section), not inline on whatever model is orchestrating
      the rest of the checklist.
      > Note:

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
      > Note:
- [ ] **P4.2** 🎈 Wait for the build to finish processing (~30 min); check
      email for ITMS post-processing warnings.
      > Note:
- [ ] **P4.3** 🎈 Final manual test on that exact TestFlight build, on a
      **physical device** — this is the pre-submission device test: the build
      you exercise here is the build you submit. Delete any previous install
      first so this doubles as the fresh-install smoke test. Install build N
      via TestFlight and check the Settings screen version row first —
      - it shows **vX.Y.Z (N)** (the new version and the TestFlight build
        number), and
      - it does **NOT** show the word **"Debug"** — that badge only renders in
        Debug builds (`SettingsView.debugBadge`), so seeing it means you're
        running a local dev build, not the TestFlight release candidate.
      Then run through onboarding, create a budget, log spending, an iCloud
      sync round-trip (this exercises the **Production** CloudKit environment
      and verifies P3.7), and anything new in this release. Record the build
      number tested in the snapshot; it is the one to attach in P5.1.
      > Note:
- [ ] **P4.4** 🎈 Upgrade smoke test (skip for v1.0): on a device holding real
      data from the **current App Store build**, update to build N via
      TestFlight — existing data intact (SwiftData migration is the risk
      here).
      > Note:
- [ ] **P4.5** 🎈 **Two-device iCloud sync verification.** P4.3's round-trip is
      single-device and can't rule out a false positive (SwiftData's local
      cache can make sync look fine even if CloudKit itself is broken). This
      item is the real test: install build N via TestFlight on **two separate
      physical devices**, both signed into the **same** iCloud account.
      - On Device A: create a budget, log an expense. Wait ~30–60s, then
        confirm it appears on Device B (may need to background/foreground
        the app, or pull-to-refresh the Budgets list, to trigger a fetch).
      - On Device B: edit something (e.g. log another expense, or edit the
        budget's allocation). Confirm the change propagates back to Device A.
      - If sync doesn't propagate either direction, this is a **hard
        blocker** — do not proceed to P5.1 — the most likely cause is an
        undeployed or incomplete Production schema (back to P3.7 /
        `/cloudkit-deploy-schema`); check both devices' Settings iCloud
        status row shows "iCloud Sync is Active" first, to rule out an
        account-level problem before suspecting the schema.
      > Note:

## Phase 5 — Submit for review 🚀 MAJOR CHECKPOINT

- [ ] **P5.1** 🎈 In ASC: create/select version X.Y.Z, attach build N — the
      exact build tested in P4.3 — proof the metadata + screenshots preview,
      and choose the release option (manual / automatic / **phased** — phased
      recommended once there is an existing user base). Export compliance is
      pre-answered in code: `Info.plist` sets
      `ITSAppUsesNonExemptEncryption = false` (exempt HTTPS/OS crypto only),
      so ASC won't ask per-build — just confirm that claim is still true if
      networking/crypto usage changed.
      **First release only** (persistent ASC setup; confirm still sane on
      later releases):
      - Pricing & Availability — price tier (free) and territory list.
      - Age rating questionnaire completed.
      - Primary category (Finance) + optional secondary.
      - App Review Information — contact info + reviewer notes (no demo
        account needed; the app has no login). Saving this section once is
        also the fix for the `push_metadata` v1.0 "No data" crash (P2.4).
      > Note:
- [ ] **P5.2** 🎈 Click **Submit for Review**. (fastlane *can* do this —
      `deliver` with `submit_for_review: true` — but the repo default is the
      manual click; at a years-between-releases cadence the button is more
      robust than a rusty automation path.) If timing matters, note App Review
      slows around major holidays (late December especially).
      > Note:
- [ ] **P5.3** Record in the snapshot: submitted date, build number, and that
      ASC shows **Waiting for Review**. *(Re-invoke the skill when the review
      state changes — Apple emails on transitions.)*
      > Note:

## Phase 6 — Review outcome & release

- [ ] **P6.1** If rejected: read the Resolution Center message, use the
      `app-store-review` skill to interpret the guideline cited, fix, and
      resubmit (rejections often only need a reply or metadata tweak, not a new
      build — but if the fix requires a binary change, loop back to P4.1 for a
      fresh candidate: new build number, same version). Log each rejection +
      resolution in the snapshot.
      > Note:
- [ ] **P6.2** 🎈 On approval: release per the P5.1 choice; confirm the new
      version is actually live on the App Store.
      > Note:
- [ ] **P6.3** Record the release date in the snapshot and tag the repo:
      `git tag vX.Y.Z <release-merge-sha> && git push origin vX.Y.Z`
      (this is what makes P0.2 work next time).
      > Note:

## Phase 7 — Post-release monitoring (~1 week) 🏁 FINAL CHECKPOINT

- [ ] **P7.1** Analytics: Mixpanel shows events arriving from the new app
      version; adoption ramping; no event or funnel obviously broken vs. the
      pre-release baseline. Start soon after release; re-check through the
      monitoring window.
      > Note:
- [ ] **P7.2** Stability: crash reports in Xcode → Organizer → Crashes (and
      ASC → Analytics → Metrics). Expect near-zero; any crash cluster on the
      new version is a drop-everything signal. If the release is **phased**
      (P5.1), a bad signal can be contained: ASC → the version → pause the
      phased release while you diagnose.
      > Note:
- [ ] **P7.3** 🎈 Ratings & reviews: check App Store ratings and written
      reviews during the monitoring window; respond where a reply would help.
      > Note:
- [ ] **P7.4** End-of-window verdict: final look at all three (crashes,
      reviews, funnels); decide explicitly — healthy, or does something
      warrant a patch release?
      > Note:
- [ ] **P7.5** Close out: fill in the `RELEASES.md` entry (features shipped +
      cross-cutting confirmations from P3.5), set the snapshot header to
      `Status: complete`, and PR both together.
      > Note:
- [ ] **P7.6** Retro on this checklist: add/fix/remove steps in
      `docs/app-store-release-checklist.md` in the same PR, so the next release
      — possibly years away — starts from a corrected map.
      > Note:
