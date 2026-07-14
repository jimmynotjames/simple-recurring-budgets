# Release v1.0 — checklist snapshot

Master: docs/app-store-release-checklist.md @ 4e583fb
Status: in-flight
Version: 1.0 · Build: 17
Started: 2026-07-12 · Submitted: 2026-07-13 · Released: — · Monitoring ends: —

---

## Phase 0 — Re-orientation (start here, especially after a long gap)

- [x] **P0.1** Read the newest entry in `RELEASES.md` and the newest snapshot in
      `releases/` — what shipped last, and whether a previous release was left
      half-finished.
      > Note: 2026-07-12 — RELEASES.md's only entry is the v1.0 stub (nothing
      > shipped yet — this is the first release). No prior snapshot existed
      > in `releases/` before this one, so nothing was left half-finished.
- [x] **P0.2** Skim what changed since the last release: `git log --oneline
      vLAST..main` (releases are tagged per P6.3; for v1.0 there is no earlier
      tag — skim `docs/product-features-planning.md` statuses instead).
      > Note: 2026-07-12 — First release, no tag to diff against. Skimmed
      > product-features-planning.md: core features (F-1.x, F-2.x, F-3.x,
      > F-5.01, F-6.01, F-6.03, F-7.04-07, F-8.01, F-8.02)
      > are Implemented. Intentionally open/deferred: F-4.01/F-4.02 (color
      > themes), F-6.02 (expense type editor, schema-only), F-7.01-03
      > (receipt scan / voice input), F-8.03 (Mixpanel Phase 2). F-4.04
      > (photo icons) is Canceled/descoped. Nothing here blocks v1.0.
- [x] **P0.3** Toolchain current: update to the **latest release Xcode**
      (App Store or https://developer.apple.com/download/applications/ —
      compare `xcodebuild -version` against the newest at
      https://developer.apple.com/news/releases/) and let Software Update
      bring the Command Line Tools along (`softwareupdate --list` should show
      nothing pending). Then confirm `make build` succeeds on it. Being on
      the latest Xcode automatically satisfies Apple's minimum-SDK submission
      requirements.
      > Note: 2026-07-12 — `xcodebuild -version` → Xcode 26.5 (17F42);
      > `softwareupdate --list` shows nothing pending. `make build` exit 0.
- [x] **P0.4** Auth sanity — two **independent** credentials; a pass on one
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
      > Note: 2026-07-12 — (1) `fastlane ios verify_auth` passed: "Auth OK.
      > Latest TestFlight build number: 16" (version 0.1) — confirms the ASC
      > API key. (2) The Apple Distribution certificate did **not** exist yet
      > — Jimmy checked Xcode → Manage Certificates and created it on the
      > spot. Confirmed present now.
- [x] **P0.5** 🎈 ASC housekeeping: **Apple Developer Program membership
      active and all agreements are accepted**.
      > Note: 2026-07-12 — Jimmy confirmed: membership active, agreements
      > accepted.
- [x] **P0.6** 🎈 Decide the new App Store version number — a product decision
      the agent must always **prompt for, never pick silently**.
      `MARKETING_VERSION` in `project.pbxproj` is the **single source of
      truth** for the user-facing version: `Info.plist` maps it to
      `CFBundleShortVersionString`, which is what SettingsView displays and
      the rating prompt tracks — so the one bump in P4.1 covers the app,
      SettingsView, and the binary ASC receives (build numbers are automated —
      `fastlane/SETUP.md` "Build numbers"). Verify it matches the version
      string ASC expects for this submission. The actual bump happens in P4.1.
      > Note: 2026-07-12 — Prompted Jimmy; current MARKETING_VERSION is 0.1,
      > RELEASES.md has a v1.0 stub. Confirmed: ship as **1.0**.
- [x] **P0.7** Create the checklist snapshot `releases/app-store-release-checklist--vX.Y.Z.md` (the skill does this)
      and record version + start date in its header.
      > Note: 2026-07-12 — Created this snapshot. Model: Sonnet 5 (latest
      > Sonnet-tier), Effort: high (default) — both confirmed at session
      > start via /model and /effort, matches skill preference.

## Phase 1 — Code & docs readiness

- [x] **P1.1** Everything intended for this release is merged to `main`;
      working tree clean; `git pull --ff-only` done.
      > Note: 2026-07-12 — Working tree clean; `git pull --ff-only` reported
      > already up to date (includes the just-merged Phase 0 PR #308).
- [x] **P1.2** Full gate green: `make format && make lint-fix && make build &&
      make test` (log to `tmp/gate.log`).
      > Note: 2026-07-12 — First run failed at `make format`/`make lint-fix`:
      > SwiftFormat/SwiftLint were scanning the gitignored top-level `build/`
      > dir (stale `ci-repro*` scratch dirs with full SPM checkouts from
      > 2026-06-22), timing out formatting and finding 375 lint violations in
      > vendored dependency source. Only `.build` was excluded, not `build`.
      > Fixed by adding `--exclude build` to `.swiftformat` and `build` to
      > `.swiftlint.yml`'s `excluded:` list (PR #308, already merged). Re-run
      > after the fix: exit 0, all steps green (log in `tmp/gate.log`).
- [x] **P1.3** 🎈 Review recent audits: look through `docs/audits/` (date is
      in the filename) and the optional-test run logs (e.g.
      `scripts/translation-accessibility-size-check/AUDIT_LOG.md`) and decide
      whether any audits are due for another round this release. Record the
      decision in the Note.
      > Note: 2026-07-12 — Presented the list (architecture, code-vs-doc-drift,
      > general-code, localization+voiceover, test-coverage, ui-testing,
      > translation-quality — all 6-9 weeks old; accessibility size-check log
      > last run 2026-06-06). Jimmy: skip all, recent enough.
- [x] **P1.4** No unarchived OpenSpec changes for work that's shipping:
      `openspec list` — verify/archive anything complete.
      > Note: 2026-07-12 — `openspec list` → "No active changes found."
- [x] **P1.5** Docs match reality: `docs/main-prd.md` Release Status,
      `docs/product-features-planning.md` feature statuses,
      `docs/tech-design-doc.md` for any new subsystem.
      > Note: 2026-07-12 — main-prd.md Release Status still correctly says
      > "not yet released / greenfield" (true pre-submission; update at
      > close-out P7.5/P7.6). product-features-planning.md statuses match
      > shipped code (see P0.2). tech-design-doc.md rev 0.22 documents the
      > newest subsystem (rating-prompt/F-6.03) — current.
- [x] **P1.6** 🎈 Open GitHub issues reviewed: the agent runs `gh issue list
      --state open` and summarizes every issue **not** labeled `deferred`,
      then **prompts you** to decide each one: fix before release, defer (add
      the `deferred` label + a comment), or accept as known for this release —
      no silent passes, the disposition is always your call. Record the
      disposition list in the Note.
      > Note: 2026-07-12 — 8 issues already labeled `deferred` (skipped, not
      > re-litigated). 2 non-deferred open issues, both inherently post-launch
      > (need the app to actually be live): #304 "Post-launch checklist after
      > first version publishes" (README App Store link/badges, release
      > status) — Jimmy: accept as known. #270 "Add App Store download link
      > to gh-pages support site" (needs real ASC app ID) — Jimmy: accept as
      > known. Neither blocks this release.
- [x] **P1.7** Dependency bump review — one last look before freezing the
      binary. Dependabot only watches GitHub Actions, so **SPM packages are
      manual**: read the pins in
      `simple-recurring-budgets.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
      and compare each against its upstream latest (`gh api
      repos/{owner}/{repo}/releases/latest`). Judgment rule: take patch/minor
      bumps of SDKs that talk to live services (Mixpanel especially — stale
      analytics SDKs rot against API changes); **skip major bumps** this close
      to a release unless something is broken. Any bump must land before the
      P1.2 gate re-run. Record bump/skip per package.
      > Note: 2026-07-12 — `json-logic-swift` 1.2.4 already latest tag; no
      > bump. `mixpanel-swift-common` 1.0.1 already latest; no bump.
      > `mixpanel-swift` 6.4.1 → 6.5.0 (feature-only release, 5 days old,
      > talks to a live service) — Jimmy approved. Xcode's cached SPM
      > checkout/DerivedData were stale (didn't have the 6.5.0 tag/pin), so
      > bumping required: `git fetch --tags` in the cached repo
      > (`~/Library/Caches/org.swift.swiftpm/repositories/mixpanel-swift-*`),
      > clearing `DerivedData/*/SourcePackages`, and hand-writing the correct
      > pin (revision `3a12d5057c8701d39e3559141aa9f433bea4ff7b`, confirmed via
      > a throwaway `swift package resolve` probe) into `Package.resolved`
      > since `xcodebuild -resolvePackageDependencies` alone wouldn't advance
      > past the existing lock. Re-ran the full P1.2 gate afterward: exit 0.
      > Note:
- [x] **P1.8** Apple platform review: check `SWIFT_VERSION` and
      `IPHONEOS_DEPLOYMENT_TARGET` in `project.pbxproj` against the current
      Xcode/SDK and decide deliberately whether to move either. Raising the
      deployment target **drops users on older iOS — a product decision, ask
      Developer**; raising the Swift version is a code decision (gate must stay
      green). If either moves, audit the tagged version workarounds:
      `grep -rn "iOS-COMPAT" simple-recurring-budgets/` — each tag names the
      version it exists for and can be deleted once the target passes it.
      (P0.3 already put us on the latest Xcode, covering Apple's
      *submission minimums*; this item is about what *we choose* to target.)
      > Note: 2026-07-12 — `SWIFT_VERSION` = 6.0 (current for Xcode 26.5,
      > nothing newer available). `IPHONEOS_DEPLOYMENT_TARGET` = 26.5 (exact
      > newest iOS), no prior documented rationale in main-prd.md /
      > tech-design-doc.md. Flagged to Jimmy as a deliberate product decision
      > for v1.0's first release (excludes users not yet on 26.5) — decision:
      > **keep 26.5**. Neither value moves, so no iOS-COMPAT audit needed.
      > Note:

## Phase 2 — Localization & App Store content

- [x] **P2.1** Source strings clean: `python3 scripts/check_source_strings.py`.
      > Note: 2026-07-12 — "check_source_strings: 103 file(s) clean."
- [x] **P2.2** Translations complete: `python3 scripts/check_translations.py`;
      if new/stale keys exist, run `/translate-new-strings`.
      > Note: 2026-07-12 — "check_translations: all 263 strings fully
      > translated across source (en) + 49 target locales." No stale keys;
      > `/translate-new-strings` not needed.
- [x] **P2.3** 🤔 (optional) Translation-quality audit: if many strings were added
      since the newest `translation-quality-audit-*` in `docs/audits/`, run
      `/audit-translations` and act on the manifest. **Intensive** — fans out
      an Opus subagent per locale (49 locales); heavy token/time cost.
      > Note: 2026-07-12 — Jimmy: skip for this release (decided ahead of
      > reaching this item).
- [x] **P2.4** Metadata current **and pushed**: review
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
      > Note: 2026-07-12 — Reviewed en-US: `description`/`keywords` already
      > match shipped features (carry-over, iCloud sync, specific-dates
      > budgets, etc.), no edits needed. `promotional_text` blank — Jimmy:
      > leave blank for v1.0. `release_notes.txt` — initially wrote "First
      > release. Welcome!" per Jimmy, but the `appstore-translate-metadata`
      > skill documents that ASC has no "What's New" field for a first
      > version at all (deliver silently skips it) — flagged this and Jimmy
      > chose to revert to blank, matching the skill's first-version
      > convention (author release notes starting at v1.1). `check_metadata`
      > passed clean (0 issues) after the revert, so no translation pipeline
      > run was needed. Confirmed App Review Information already saved in ASC
      > (avoids the v1.0 "No data" crash). `fastlane ios push_metadata` ran
      > successfully — all 50 locales (en-US + 49 storefronts) uploaded.
      > Note:
- [x] **P2.5** 🎈 Screenshots update? A developer judgment call — the agent
      **prompts you**: should the App Store screenshots be updated for this
      release? Compare `fastlane/screenshots/` against the current UI to
      inform the call. If yes: `/appstore:generate-push-screenshots`
      (re-capture from the existing seed catalog); only regenerate seed
      content (`/appstore:generate-screenshot-seeding`) if locales or demo
      content themselves changed. Record the decision in the Note.
      > Note: 2026-07-12 — Screenshots last touched 2026-06-14; UI changes
      > since include an explicit root accent tint (#299), Recents-visibility
      > change in Edit mode (#287), and an in-form Start of Week picker
      > (#269). Flagged to Jimmy — decision: current screenshots are fine, no
      > re-capture for v1.0.
- [x] **P2.6** App icon still right? Check `AppIcon` in the asset catalog:
      light / dark / tinted variants all render correctly on a home screen in
      both appearances; icon still matches current branding; the 1024px
      marketing icon in ASC is consistent with it.
      > Note: 2026-07-12 — Structurally checked: modern Icon Composer format
      > (`AppIcon.icon`) with separate light/dark layer sets and an
      > automatic-gradient fill (auto-generates the tinted variant). Jimmy
      > visually confirmed light/dark/tinted rendering and ASC marketing-icon
      > consistency — all good.
- [x] **P2.7** 🎈 URLs alive: the privacy policy URL and support URL configured
      in ASC still resolve; copyright string has the current year.
      > Note: 2026-07-12 — Privacy URL (termsfeed.com) resolves, shows a full
      > privacy policy. Support URL (GitHub Pages) resolves, shows the Wren
      > landing page (still says "upcoming" — expected, covered by issue #270,
      > already dispositioned as known post-launch work in P1.6).
      > `copyright.txt` = "© 2026 Jimmy Ho" — already current year.

## Phase 3 — Pre-submission verification

- [x] **P3.1** 🤔 (optional, recommended before any submission) Localized-layout
      visual check: `/translation-accessibility-size-check` — truncation,
      overflow, RTL mirroring at forced `.xxxLarge`. Resource-heavy and ad-hoc
      by design; it is **not** part of `make test`, so a release is the moment
      to run it.
      > Note: 2026-07-12 — Skipped. Last checks a few weeks ago are
      > sufficient.
- [x] **P3.2** 🤔 (optional) VoiceOver + Dynamic Type spot-check of screens that
      are new or changed in this release (PRD §6.8.1).
      > Note: 2026-07-12 — Skipped. Last checks a few weeks ago are
      > sufficient.
- [x] **P3.3** Review-compliance sweep with the `app-store-review` skill:
      privacy manifest (`PrivacyInfo.xcprivacy`), required-reason APIs, and
      guideline pitfalls for anything new in this release.
      > Note: 2026-07-12 — Clean: ATT correctly absent (no cross-app
      > tracking); entitlements justified (iCloud/CloudKit +
      > `aps-environment`, standard CloudKit companion, no push code); no
      > IAP/StoreKit purchase surface; metadata format compliant (name 28/30,
      > subtitle 30/30, keywords 90/100, no dupes); screenshots use correct
      > device classes (iPhone 17 Pro Max = 6.9", iPad Pro 13-inch).
      > **Finding, fixed:** app target had **no** `PrivacyInfo.xcprivacy` at
      > all (Mixpanel ships its own SDK-level one, but the app's own analytics
      > collection — Mixpanel events keyed to a self-generated UUIDv4
      > `distinct_id`, no PII, per `analytics-spec.md` §5 — was undeclared).
      > Added `simple-recurring-budgets/Resources/PrivacyInfo.xcprivacy`:
      > `NSPrivacyTracking=false`, one `NSPrivacyCollectedDataTypes` entry
      > (ProductInteraction, linked, not-tracking, purpose=Analytics), no
      > required-reason APIs (none used directly in app code). Project uses
      > Xcode's synchronized-folder groups, so no pbxproj edit was needed;
      > confirmed present in the built `.app` bundle after `make build`.
      > Must match the ASC Privacy nutrition label answers at P3.4.
- [x] **P3.4** 🎈 Privacy nutrition labels: ASC → App Privacy answers still
      match what the app actually collects (Mixpanel events behind consent) —
      update if the analytics surface changed (`docs/analytics-spec.md`).
      While there: the **Accessibility Nutrition Label** answers (ASC → App
      Store → Accessibility) — fill in on first release, re-check if
      accessibility support changed.
      > Note: 2026-07-12 — App Privacy set: Usage Data → Product Interaction,
      > linked to user, not used for tracking, purpose Analytics (matches the
      > P3.3 `PrivacyInfo.xcprivacy` declaration). Accessibility Nutrition
      > Label filled in (VoiceOver, Larger Text, etc., matching F-3.01/F-3.02
      > shipped support). Both confirmed done by Jimmy.
- [x] **P3.5** Cross-cutting concerns confirmed per PRD §6.8 — accessibility,
      Dark Mode, localization (record the storefront-locale count), analytics.
      This feeds the `RELEASES.md` entry directly.
      > Note: 2026-07-12 — **Accessibility:** F-3.01/F-3.02 initial build-outs
      > Implemented (Dynamic Type, VoiceOver); ASC Accessibility Nutrition
      > Label filled (P3.4); P3.1/P3.2 spot-checks skipped this release
      > (recent enough, per Jimmy). **Dark Mode:** F-3.05 Implemented.
      > **Localization:** 49 storefront locales (in-app strings and metadata
      > both confirmed at 49 — P2.1/P2.2/P2.4). **Analytics:** Mixpanel Phase
      > 1 (F-8.02) Implemented, consent flow locale-aware, no PII (P3.6 checks
      > readiness in detail next).
- [x] **P3.6** Mixpanel ready to observe the release: prod boards live, consent
      flow verified, no unshipped event-schema changes.
      > Note: 2026-07-12 — Documented: all 10 Phase 1 boards (30 report
      > tiles) built in Wren App - Prod as of 2026-06-22
      > (analytics-spec.md rev 0.23). Mixpanel MCP was disconnected this
      > session so couldn't query live; Jimmy confirmed boards still live,
      > consent flow working, no unshipped event-schema changes.
- [x] **P3.7** 🎈 CloudKit **Production** schema deployed: if the SwiftData
      model changed since the last release (any file under
      `simple-recurring-budgets/Models/` — or first release), deploy the
      schema to Production **before** cutting the release candidate. Dev-signed
      builds use the Development environment, but **TestFlight and App Store
      builds use Production** — an undeployed schema means sync silently fails
      for exactly the builds that matter. Constraints in
      `docs/tech-design-doc.md` §4.3 (CloudKit cannot delete deployed record
      fields). The P4.5 two-device sync test on the TestFlight build is the
      verification. **Use the `/cloudkit-deploy-schema` skill** to drive this
      (preflight checks, stale-field handling, mandatory confirmation gates
      before anything destructive) — run it on Opus-tier (see that skill's own
      Model preference section), not inline on whatever model is orchestrating
      the rest of the checklist.
      > Note: 2026-07-12 — **Done.** First-ever/greenfield deploy for this
      > container (`iCloud.com.jimmyho.simple-recurring-budgets`, team
      > `EDMB3Z5KAY`) — Production previously had only the system `Users`
      > type. Drove this via the new `/cloudkit-deploy-schema` skill (created
      > this session). Development had accumulated stale fields from earlier
      > iterations (`resetCadence`, `carryOverAmount`,
      > `carryOverLastProcessedDate`, `carryOverLastResetDate` — all removed
      > from `Budget` per git history, tied to the deleted Reset Cadences
      > feature and the carry-over rework); Jimmy ran **Reset Environment**
      > on Development (safe since Production was confirmed empty) to clear
      > them. Regenerated a clean Development schema via a throwaway branch
      > (`throwaway/cloudkit-schema-seed-v1.0`, never merged) with a
      > temporary `#if DEBUG` seed button wired to `DebugData.seed(into:)` +
      > an explicit `lastResetDate` stamp (the one field that fixture set
      > never wrote a non-nil value for). Ran on a physical device signed
      > into a real iCloud account. Full bidirectional field audit against
      > the current model source (all 4 `@Model` types: `Budget`,
      > `ExpenseItem`, `AllocationChange`, `LifecycleEvent`) found every
      > stored property present with no gaps and no stale cruft. Jimmy
      > deployed via the CloudKit Console's Deploy Schema Changes button
      > (confirmed: `cktool import-schema --environment production` is not
      > actually supported by the API despite accepting the flag value —
      > documented in the skill). Verified: `export-schema` on both
      > environments now diffs identical.

## Phase 4 — Build & upload

- [x] **P4.1** Release-candidate build — **one binary serves both the final
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
      > Note: 2026-07-12 — No reusable candidate (MARKETING_VERSION was still
      > 0.1). Ran `/appstore:push-release-build`: bumped MARKETING_VERSION to
      > 1.0, `fastlane ios beta` uploaded **build 17** (build 94s, upload
      > 66s). PR #313 merged. This build is the one to test in P4.3 and
      > attach in P5.1.
- [x] **P4.2** 🎈 Wait for the build to finish processing (~30 min); check
      email for ITMS post-processing warnings.
      > Note: 2026-07-12 — Build 17 processed on ASC. No warnings reported by
      > Jimmy.
- [x] **P4.3** 🎈 Final manual test on that exact TestFlight build, on a
      **physical device** — this is the pre-submission device test: the build
      you exercise here is the build you submit. Default to **updating over
      your existing install** via TestFlight (the real upgrade path virtually
      all users take) rather than deleting first — deleting destroys any
      local data that hasn't yet synced to CloudKit, a real risk on a device
      with genuine data. (The fresh-install angle is covered by P4.5's
      Device B.) Install build N via TestFlight and check
      the Settings screen version row first —
      - it shows **vX.Y.Z (N)** (the new version and the TestFlight build
        number), and
      - it does **NOT** show the word **"Debug"** — that badge only renders in
        Debug builds (`SettingsView.debugBadge`), so seeing it means you're
        running a local dev build, not the TestFlight release candidate.
      Then create a budget, log spending, and anything new in this release.
      Sync itself is verified separately in P4.5 — a single device can't
      confirm data actually round-tripped through CloudKit. Record the build
      number tested in the snapshot; it is the one to attach in P5.1.
      > Note: 2026-07-12 — Jimmy updated over his existing install to build
      > 17 (1.0), no delete/reinstall. Version row confirmed 1.0 (17), no
      > Debug badge. Created a budget, logged spending — all fine.
- [x] **P4.4** 🎈 Upgrade smoke test (skip for v1.0): on a device holding real
      data from the **current App Store build**, update to build N via
      TestFlight — existing data intact (SwiftData migration is the risk
      here).
      > Note: 2026-07-12 — Skipped, as anticipated for v1.0: no prior App
      > Store build exists to upgrade from (this is the first release).
- [x] **P4.5** 🎈 (added after snapshot; redefined mid-release to fold in the
      fresh-install check — see Note) **Two-device iCloud sync
      verification** — also doubles as the fresh-install smoke test. A
      single-device check can't rule out a false positive (SwiftData's local
      cache can make sync look fine even if CloudKit itself is broken).
      - Device A: already updated to build N over your existing install (P4.3).
      - Device B: delete the app completely, then fresh-install build N via
        TestFlight, signed into the **same** iCloud account as Device A.
        Confirm it populates with Device A's existing data.
      - Make a change on either device and confirm it propagates to the other.
      - If sync doesn't propagate either direction, this is a **hard
        blocker** — do not proceed to P5.1 — the most likely cause is an
        undeployed or incomplete Production schema (back to P3.7 /
        `/cloudkit-deploy-schema`); check both devices' Settings iCloud
        status row shows "iCloud Sync is Active" first, to rule out an
        account-level problem before suspecting the schema.
      > Note: 2026-07-12 — Passed both directions: Device A → Device B and
      > Device B → Device A both synced correctly, using two devices that
      > both already had the app installed (not a fresh-install on B).
      > Confirms P3.7's Production schema deploy is working end-to-end. The
      > combined fresh-install variant (P4.6, folded into this item after the
      > test ran) was judged unnecessary for v1.0 — Jimmy decided the
      > already-completed test was sufficient; the combined recipe becomes
      > standard starting next release.

## Phase 5 — Submit for review 🚀 MAJOR CHECKPOINT

- [x] **P5.1** 🎈 In ASC: create/select version X.Y.Z, attach build N — the
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
      > Note: Version 1.0 created in ASC, build 17 attached (matches the
      > build tested in P4.3/P4.5). Release option: manual. First-release-only
      > setup (Pricing & Availability, age rating questionnaire, primary
      > category Finance, App Review Information contact/notes) all
      > completed.
- [x] **P5.2** 🎈 Click **Submit for Review**. (fastlane *can* do this —
      `deliver` with `submit_for_review: true` — but the repo default is the
      manual click; at a years-between-releases cadence the button is more
      robust than a rusty automation path.) If timing matters, note App Review
      slows around major holidays (late December especially).
      > Note: 2026-07-13 — Submitted for review via the manual ASC click.
- [x] **P5.3** Record in the snapshot: submitted date, build number, and that
      ASC shows **Waiting for Review**. *(Re-invoke the skill when the review
      state changes — Apple emails on transitions.)*
      > Note: Submitted 2026-07-13, build 17 (v1.0). ASC status: Waiting for
      > Review.

## Phase 6 — Review outcome & release

- [ ] **P6.1** Handle any Resolution Center messages (use the
      `app-store-review` skill), then log the outcome in the snapshot.
      > Note:
- [ ] **P6.2** 🎈 On approval: release per the P5.1 choice; confirm the new
      version is actually live on the App Store.
      > Note:
- [ ] **P6.3** Record the release date in the snapshot and tag the repo:
      `git tag vX.Y.Z <release-merge-sha> && git push origin vX.Y.Z`
      (this is what makes P0.2 work next time).
      > Note:
- [ ] **P6.4** Bump `MARKETING_VERSION` to the next minor version (e.g.
      `1.0` → `1.1`, or `1.0.0` → `1.1.0`) — same technique as
      `/appstore:push-release-build` step 4: update every
      `MARKETING_VERSION = …;` occurrence in `project.pbxproj`, branch,
      commit, PR, merge. Keeps any interim TestFlight build pushed before the
      next release cycle formally starts tagged as a future version rather
      than reusing the one just released. P4.1's reusable-candidate check
      already skips re-bumping when `MARKETING_VERSION` matches the intended
      next version.
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
