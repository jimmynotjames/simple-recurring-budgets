# Architecture Audit

| Field           | Value      |
|-----------------|------------|
| **Date**        | 2026-06-10 |
| **Codebase**    | 91 source files, 62 unit-test files (Swift Testing), 15 UI-test files (XCUITest) |
| **Stack**       | SwiftUI + SwiftData + CloudKit + Mixpanel, Swift 6 (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), iOS 26.5 deployment target, iPhone + iPad |
| **Prior audit** | [`architecture-audit-2026-04-30.md`](architecture-audit-2026-04-30.md) — 155 commits ago (43 source files at the time) |

> This document is a durable reference for AI agents and human developers working in this repo. It is framed around an imminent App Store launch: §3 lists issues that should be settled **before publishing**, §4 lists structural issues that will bite **after** launch (extensibility / testability / performance), §5 lists the top 7 minor issues without dwelling on them. §2 records the disposition of every concern from the 2026-04-30 audit.

---

## 1. Executive Summary

The codebase has more than doubled since the last audit and is in **substantially better architectural shape**, not worse. The five things to know:

1. **The persistence-risk cluster from the last audit is gone.** All production saves route through `ModelContext.saveChanges(operation:analytics:)` which logs, fires a `persistence_save_failed` analytics event, and throws a typed `PersistenceError`; interactive screens present the standard `.saveErrorAlert` with retry. Container-creation failure presents `ContainerFailureView` instead of `fatalError`. Both store configurations are pinned to one explicit store URL (no split-brain).

2. **The lifecycle architecture was rewritten from persisted state to event-sourced recompute.** `Budget` no longer stores `carryOverAmount` / processed-date fields. Allocation history lives in `AllocationChange` rows and pause/resume history in `LifecycleEvent` rows; `BudgetCalculator.snapshot` plus `CarryOverWalker` recompute everything from history on every read (pure functions). `BudgetLifecycleService` is now a thin read adapter plus explicit throwing write paths (`applyAllocationEdit`, `resetCarryOver`, `resetBudget`, `pauseBudget`, `resumeBudget`), each saving exactly once. This eliminated the crash-mid-save / double-roll inconsistency class entirely — at the cost of an O(periods × expenses) walk on every read (§4.1).

3. **CloudKit-merge staleness is solved by `Budget.recomputeToken`.** Views cache `BudgetLifecycleResult` in `@State` and refresh on `.task(id:)`, `scenePhase`, and `.onChange(of: budget.recomputeToken)` — an `Equatable` snapshot of `lastModified`, `lastResetDate`, and each child collection's count + max child `lastModified`. New screens displaying lifecycle data must wire up the same three triggers.

4. **Concurrency is enforced module-wide.** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` under Swift 6 means the old "implicit main-actor assumption" class of bug is now a compile error. The flip side: there is no background-processing story at all — every walk, sort, and save is on the main thread (§4.1).

5. **The schema is still `SchemaV1`, edited in place, with an empty migration plan — deliberately, because the app has not shipped.** The day the app is submitted, that habit must stop forever (CloudKit fields can never be deleted; every change becomes additive + migrated). This is the single most important launch-gate item (§3.1).

The architecture remains "View + Services, ViewModels on demand," and the escalation criteria in `tech-design-doc.md` §2.1 still hold. Do not add a ViewModel reflexively.

---

## 2. Disposition of 2026-04-30 Concerns

| # | 2026-04-30 concern | Status | Disposition |
|---|--------------------|--------|-------------|
| 1 | Silent save failures (`try?` on all saves) | ✅ Resolved | `saveChanges(operation:analytics:)` helper (#133); one DEBUG-only `try?` remains in `deleteAllBudgets` (intentional) |
| 2 | Lifecycle staleness after CloudKit merge | ✅ Resolved | `Budget.recomputeToken` (#128, issue #127) |
| 3 | `BudgetLifecycleService` implicit main-actor assumption | ✅ Resolved | Module-wide default `@MainActor` isolation (Swift 6) makes it compiler-enforced |
| 4 | No user-facing error surface | ✅ Resolved | `SaveErrorState` + `.saveErrorAlert` (Cancel / Retry / Send Feedback) used across interactive screens |
| 5 | `fatalError` on container creation | ✅ Resolved | `AppStartup` + `ContainerFailureView` (#135, issue #132) |
| 6 | View actions tested by algorithm duplication | ✅ Mostly resolved | `resetBudget` / `resetCarryOver` / pause / resume moved into `BudgetLifecycleService` and tested directly. `deleteExpense` remains view-owned (§5.2) |
| 7 | No `NavigationSplitView` for iPad/Mac | ⚠️ Re-scoped, decision still open | tech-design-doc §3 now says "iPad/Mac can use adaptive layout without requiring a full split view," but the PRD still claims iPadOS **and macOS**, while the project targets iPhone + iPad only (§3.3, §4.5) |
| 8 | Dense `sortOrder` rewrites on reorder | ⏳ Open, mitigated | `move` now mutates only rows whose `sortOrder` actually changed (§5.6) |
| 9 | Route enums hold object references | ✅ Resolved | Routes carry `UUID`s, resolved at the destination via `ModelContext.budget(id:)` / `.expenseItem(id:)` (#224, §4.2) |
| 10 | No async coordination pattern for AI features | ⏳ Open, deferred | No AI feature has shipped; still no precedent to follow when one does |

Other prior pitfalls that aged out: persisted carry-over state (the whole mechanism was replaced, see §1.2); "no UI tests" (UserJourneyTests, accessibility audit suite, screen objects now exist); ViewModel file inconsistency (`AddEditExpenseViewModel` extracted to its own file in #214).

---

## 3. Major Issues for Launch

These are the items to settle before submitting to the App Store, ordered by risk.

### 3.1 Schema-freeze discipline and the unexercised migration plan

`SchemaV1.swift` says it is "updated in-place (no SchemaV2) because the app has not shipped." That is fine today and **becomes data-loss-grade wrong the moment build 1 is on a user's device**. Specifically:

- `BudgetMigrationPlan.stages` is empty and has never been exercised. The first post-launch schema change must add `SchemaV2`, a `MigrationStage`, and a migration test — none of which have a precedent in this repo yet.
- CloudKit constraints (additive-only, no field deletion, all relationships optional) bind every future change to the four deployed record types (`Budget`, `ExpenseItem`, `AllocationChange`, `LifecycleEvent`).
- The CloudKit **production** container schema must be deployed (CloudKit Console → Deploy Schema Changes) before release; a TestFlight/App Store build talks to the production CK environment, which does not auto-create record types the way development does. There is no record of this step in the repo's launch tooling (fastlane handles metadata/screenshots/build, not CK schema).

**Action:** add a pre-submission checklist item: deploy CK schema to production, then treat `SchemaV1` as frozen — update the comment in `SchemaV1.swift` to say so on launch day.

### 3.2 App-level privacy manifest and App Store privacy disclosures

The app target has **no `PrivacyInfo.xcprivacy`**. Only Mixpanel's SDK-bundled manifest ships. The app itself collects analytics (events, super properties including locale/region, people properties), so:

- App Store Connect's privacy "nutrition label" must declare the Mixpanel collection (product interaction, identifiers if `distinctId` counts, diagnostics via `persistence_save_failed`), consistent with the consent flow (`AnalyticsConsentSheet`, `ConsentJurisdiction`).
- An app-level privacy manifest declaring `NSPrivacyCollectedDataTypes` is Apple's strongly recommended (and increasingly enforced) practice for apps that collect data, even when the SDK declares its own.
- `Info.plist` lacks `ITSAppUsesNonExemptEncryption` — not blocking, but every submission will stall on the export-compliance question until it's added (`false` for this app).

**Action:** add `PrivacyInfo.xcprivacy` to the app target, fill in the ASC privacy questionnaire from `docs/analytics-spec.md`, add the encryption key. The `/app-store-review` skill covers the exact required entries.

### 3.3 Platform story: PRD claims macOS, the project doesn't build for it

`docs/main-prd.md` §6.1 still lists "iOS, iPadOS, macOS"; `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone, iPad), no Mac destination, no Catalyst. iPad runs the iPhone-style single `NavigationStack` full-screen — acceptable for review, but it is a product decision, not an accident, and the PRD should say what's true at launch. Submitting with iPad support also means iPad screenshots, iPad review pass (keyboard, multitasking sizes), and the existing accessibility/UI-test suites have run primarily on iPhone simulators.

**Action:** either (a) launch iPhone+iPad and amend the PRD to defer macOS, or (b) restrict to iPhone (`TARGETED_DEVICE_FAMILY = 1`) for v1. Decide explicitly; don't let the build setting decide.

### 3.4 Offline-first-launch sessions stay local until relaunch

Carried forward from 2026-04-30 §3.5, now with a sharper launch framing: `makeProductionModelContainer` falls back to `cloudKitDatabase: .none` on **any** CloudKit container-init error — including transient ones at first launch (no iCloud account yet, network down). `SyncStatus.containerBacking` is immutable for the session, so the user runs local-only until the next cold launch. Both configs share one store URL, so no data is lost and the store is promoted in place on relaunch — the design is sound. But "signed into iCloud mid-session → Settings still shows local / no sync until relaunch" is the kind of first-day review/user report worth pre-empting.

**Action (cheap):** verify the sign-in-later flow end-to-end once on device before submission. No architecture change needed for v1.

*Copy review (2026-06-10):* the Settings copy for this state already exists — `SyncStatus.rowState == .paused` renders a dedicated row ("iCloud Sync Paused", orange `exclamationmark.icloud`) with the footer "Your budgets are saved on this device only. Restart the app to retry iCloud sync." plus a descriptive VoiceOver label, and the row live-updates from Unavailable → Paused when the user signs in mid-session. Wording was reviewed and deliberately kept as-is; the on-device verification above is the only remaining action for this item.

### 3.5 Pre-launch performance sanity check on the carry-over walk

The full structural analysis is §4.1; the launch-sized slice of it: nobody has measured `BudgetCalculator.snapshot` against a worst-case-realistic dataset (e.g., a daily budget 2 years old with 1,500 expenses, in a list of 10 budgets). The walk is recomputed per row on every recompute-token change, synchronously on the main actor. It is almost certainly fine for new users (launch cohort starts at zero history), so this is a **measure, don't refactor** item.

**Action:** one synthetic-data Instruments pass (or a `measure` test on `snapshot`) before launch to confirm there's no day-one cliff; the structural fix can wait (§4.1).

---

## 4. Major Issues for Extensibility / Testability / Performance

Not launch gates — these determine how painful the next year of features is.

> **Status (2026-06-10, same-day follow-up):** §4.2, §4.3, and §4.4 were fixed in three sequential PRs merged the day of this audit — #221 (analytics seam), #222 (feature folders), #224 (UUID routes). Per-section resolution notes below. §4.1, §4.5, §4.6 remain open as written.

### 4.1 The recompute-from-history walk grows without bound, on the main thread

The event-sourced rewrite (§1.2) trades the old staleness/inconsistency risk for compute: `walkCarryOver` iterates every completed period since `max(effectiveStartDate, lastResetDate)` and, **per period**, filters the entire expense array — O(P × E) per budget per read. A daily budget alive for two years is ~730 periods; with 1,500 expenses that's ~1.1M predicate evaluations per refresh, per row, on the main actor. There is no caching (deliberately — "pure function, no cached state"), no incremental checkpointing, no data archival story, and no `ModelActor`/background precedent in the codebase to offload it to.

Mitigations when it's time (in increasing order of effort): pre-bucket expenses by period once per walk (drops to O(P + E log E)); checkpoint the walk result per `(recomputeToken, periodStart)` in memory; persist a walk checkpoint row (carefully — this reintroduces the consistency problem the rewrite solved, so prefer the first two). The walker's pure-function contract makes all of these straightforward to test. Flag this the moment a "my list scrolls janky" report or a slow `snapshot` measurement appears.

### 4.2 Routes still hold live model objects — the roadmap is blocked on this

`AppRoute.budgetDetail(Budget)` / `SheetRoute.addExpense(Budget)` hold object references, not identifiers. Unchanged since the last audit, but the cost has grown: the roadmap's widgets, App Intents / Siri (F-7.02-03), and any deep-link or notification-tap entry all need serializable routes (`PersistentIdentifier` or `UUID` + fetch-at-destination). Retrofitting later means touching every `router.path.append` / `router.sheet =` call site at once. If any system-surface feature is scheduled next, do the route refactor first, as its own change.

> **✅ Resolved (2026-06-10, #224).** `AppRoute` / `SheetRoute` now carry `UUID`s, resolved at the destination in `RootView` via `ModelContext.budget(id:)` / `.expenseItem(id:)` (`Models/ModelContext+Lookup.swift`). An unresolvable ID (model deleted elsewhere) silently pops the route / dismisses the sheet. Routes are now serializable-ready for deep links, widgets, and App Intents. Convention documented in tech-design-doc §2.2.

### 4.3 The `AnalyticsClient` seam is eroding via concrete downcasts

Four production sites downcast the protocol to reach Mixpanel-only surface: `RatingPromptCoordinator` (×2: `setRatingPromptFirstEligible`, `setRatingPromptLastRequested`) and `AddEditBudgetViewModel` (×2: `refreshSuperProperties`, `refreshCohortPeopleProperties`). Consequences: under `SpyAnalyticsClient` these calls silently no-op, so tests **cannot assert** that super/people properties refresh when they should — exactly the regression class that bit issue #127 for view refreshes. Each new people-property feature will add more downcasts. Fix is mechanical: add optional-requirement-style protocol methods (default no-op implementations in a protocol extension) or a small `AnalyticsPeopleClient` sub-protocol, and have the spy record them. Do this before the Mixpanel surface grows again.

> **✅ Resolved (2026-06-10, #221).** The four methods (plus `BudgetCohortInfo`) moved onto `AnalyticsClient` with default no-op implementations; all production downcasts removed; `SpyAnalyticsClient` records the calls and new tests assert them. The previously unobservable gap this exposed — budget **delete** never refreshed cohort people-properties (analytics-spec §10.3) — was fixed in the same PR.

### 4.4 `Views/` is a flat 37-file folder and the big screens keep absorbing complexity

The prior audit set an informal split threshold of ~20 files; `Views/` is now at 37 with no feature grouping, and the four biggest files are `SettingsView` (612 lines), `BudgetDetailView` (585 + three sibling extension files), `AddEditBudgetView` (530 + three siblings), `AddEditBudgetViewModel` (493). PR #214 **raised the SwiftLint size limits** rather than splitting — a ratchet in the wrong direction. None of this is wrong yet (the extension-file pattern is disciplined, naming is consistent), but discovery cost for agents and humans is climbing, and the next features land in exactly these files. Adopt `Views/Budget/`, `Views/Expense/`, `Views/Settings/` feature folders on the next view-heavy change, and treat any further lint-limit raise as a smell requiring justification in the PR.

> **✅ Partially resolved (2026-06-10, #222).** `Views/` reorganized into `BudgetList/`, `BudgetDetail/`, `BudgetForm/`, `ExpenseForm/`, `Settings/`, `Shared/` (pure `git mv`, tests mirrored; `RootView` / `ContainerFailureView` stay at root). The file-size concern stands: no files were split, and the #214 lint-limit raise remains — treat any further raise as a smell requiring justification in the PR.

### 4.5 iPad/Mac adaptive layout remains an unmade decision

Re-scoped since the last audit (tech-design-doc no longer demands a split view), but the underlying architectural question from 2026-04-30 §3.9 is still open: `Router` assumes a single `NavigationStack` path. If macOS (PRD) or richer iPad layout ever becomes real, `RootView` + `Router` need rework, and every sheet-vs-push decision gets revisited. Keep deferring deliberately — but when §3.3's decision lands on "macOS later," record here that `Router` is the first thing that breaks.

### 4.6 No background-processing or async-coordination precedent

Module-wide `@MainActor` default is the right call for correctness today, and there is no `ModelActor`, no background save path, and no async ViewModel pattern anywhere. Three roadmap pressures will hit this wall: the walker (§4.1), AI features (Vision / Speech, F-7.01-03 — each needs async task lifecycle, loading/error state), and any import/export feature. Carried from the last audit: establish the pattern once, deliberately, with the first such feature — don't let three features invent three patterns.

---

## 5. Top 7 Minor Issues

Flagged, not dwelt on:

1. **`Budget.expenseItems` setter still replaces the whole relationship collection** — dangerous-by-design footgun documented inline; prefer `expense.budget = budget`. (Carried from 2026-04-30 §3.4.)
2. **`deleteExpense` is still a view-owned multi-step write** (`BudgetDetailView+ExpenseSection.swift:102`) while every comparable mutation lives in `BudgetLifecycleService`. It now has proper error handling + analytics, so the remaining cost is consistency and direct testability.
3. **Recents algorithm lives in a view-named file**: `computeRecentCandidates` and its value type are an `AddEditExpenseViewModel` extension inside `Views/AddEditExpenseView+RecentsSection.swift`. An agent hunting VM logic by filename will miss it; it's also pure-domain-shaped code that could live beside the other pure services.
4. **Analytics-taxonomy drift in `PersistenceOperation`**: `lifecycleRollover` is a dead case (no call site), and the DEBUG-only `deleteAllBudgets` saves under `.appLaunchDedup`, which mislabels any failure it ever logs.
5. **`MixpanelAnalyticsClient` is `@unchecked Sendable` with an admittedly redundant `NSLock`** — the class is main-actor-isolated via the module default, so the lock guards nothing the actor doesn't; the annotation asserts a thread-safety contract no test enforces. Either drop the lock and document the main-actor contract, or make the type properly `Sendable`-audited.
6. **Dense `sortOrder` rewrites on reorder** — now mutates only changed rows, but a reorder still fans out O(n) CloudKit record saves. Fine below ~50 budgets. (Carried.)
7. **`BudgetLifecycleResult.carryOverAmount` flattens the specificDates `nil` carry-over to `0`** — self-documented stopgap pending the F-2.08 chip-hiding UI; the doc-comment on the field says exactly how to retire it. Make sure F-2.08 actually does.

---

## 6. Patterns to Preserve (delta since 2026-04-30)

The prior audit's §2 pattern table still applies. New patterns that are now load-bearing and should be followed, not worked around:

- **`saveChanges(operation:analytics:)` for every production save** — never raw `context.save()`, never `try?` outside DEBUG fixtures. New write paths need a `PersistenceOperation` case (registered in `docs/analytics-spec.md`) and a `.saveErrorAlert` surface if interactive.
- **Event-sourced lifecycle history** — never store derived money state on `Budget`; add history rows (`AllocationChange` / `LifecycleEvent` style) and extend `BudgetCalculator.snapshot`. Write paths bump `lastModified` on every touched row (the recompute token depends on it).
- **`Budget.recomputeToken` refresh triad** on any screen showing lifecycle-derived values: `.task(id:)` + `scenePhase` + `.onChange(of: budget.recomputeToken)`.
- **Single-save atomicity in service write paths** — each `BudgetLifecycleService` method saves exactly once; compose by inlining (see `resetBudget`'s inline resume-event insert and its comment explaining why it does not call `resumeBudget`).
- **Pure decision cores with thin shells** — `RatingPromptCoordinator`'s static helpers and the walker/calculator split are the template for new logic: pure, calendar-injected, directly tested; SwiftData and SwiftUI stay at the edges.
