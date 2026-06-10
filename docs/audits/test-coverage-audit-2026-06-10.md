# Test Coverage Audit — 2026-06-10

> **Static-only audit.** No tests were executed and the Xcode scheme was not modified. No production or test code was changed by this audit. Recommendations are proposals for follow-up work. Follow-up to [test-coverage-audit-2026-04-30.md](test-coverage-audit-2026-04-30.md); see also [ui-testing-audit-2026-05-31.md](ui-testing-audit-2026-05-31.md), which drove most of the UI-test build-out assessed here.

## Summary

Since the 2026-04-30 audit the test surface has been transformed. The suite has grown from a strong-Domain/weak-everywhere-else profile to **64 unit-test files (633 `@Test` functions) plus a real UI-test target (15 files, 55 XCTest methods)** covering accessibility audits, fourteen user-journey flows, and two regression suites for known-fragile input fields. The three top issues from April are materially resolved: **CI exists** ([.github/workflows/ci.yml](../../.github/workflows/ci.yml) — lint, secrets, i18n gates, build, unit tests, plus an on-demand `/test-full` full-suite workflow), **the bootstrap path is testable and tested** (`AppStartup` recovery seam with injected container factory, `ContainerFailureView` instead of `fatalError`, `PersistentStoreURLTests` pinning the single-store-URL invariant), and **the UI-test target is no longer empty** (`AccessibilityAuditTests`, `UserJourneyTests`, `ClearAmountButtonUITests`, `AllocationFirstTapUITests`, all wired into `make test` and `scripts/test.sh`). New feature areas shipped since April — the budget-calculations rewrite, pause/resume, Specific Dates, budget icons, the rating prompt, Mixpanel Phase 1, recents — all arrived **with** dedicated unit suites; the Mixpanel §18.1 test contracts (#1–#10) are individually implemented as named suites.

Three significant gaps remain, all carried over from April. **Code coverage is still not instrumented anywhere** — no `-enableCodeCoverage` in any script or workflow, no coverage flag in the shared scheme, so this audit (like the last one) can only reason about coverage structurally, not numerically. **DST and non-UTC time zones are still essentially untested** — every date-math suite injects a fixed-UTC calendar (one test file uses `America/New_York`), while production runs on `Calendar.autoupdatingCurrent`; the stakes are higher than in April because `CarryOverWalker` now accumulates carry-over across *every* completed period boundary since the walk-window start. And **the two macOS CI jobs (build, unit-tests) are temporarily disabled** (`if: false`, issue #228, June 2026 Actions budget) — until ~2026-07-01, compile/test verification is local-only again (the four-step gate plus a build-only pre-push hook), which is exactly the state finding A1 of the April audit was raised to eliminate.

### Top issues, ordered by impact

1. **Code coverage is still not instrumented** (April A2, unresolved) — no `-enableCodeCoverage YES`, no `.xcresult`-based `xccov` reporting, no threshold gate, in either [scripts/test.sh](../../scripts/test.sh) / [test-unit.sh](../../scripts/test-unit.sh) or CI. Two audits in a row have had to substitute file-level reading for line-level data.
2. **macOS CI jobs paused for June 2026** — `build` and `unit-tests` in [ci.yml](../../.github/workflows/ci.yml) carry `if: false` guards (#228). Tests currently run nowhere unbypassable. Time-boxed and deliberate, but it is the top operational risk until the guards are deleted (~2026-07-01).
3. **DST / non-UTC time zones untested** (April E1, unresolved) — `PeriodCalculator`, `CarryOverWalker`, `BudgetCalculator`, and `LifecycleClassification` are verified only against fixed-UTC calendars. A spring-forward boundary inside a walk window is the kind of input none of the 633 tests constructs.
4. **`makeProductionModelContainer` CloudKit→local fallback branch still uncovered** (April B1, narrowed but open) — the recovery seam around it (`AppStartup`) is well tested, and the shared-store-URL invariant is pinned by `PersistentStoreURLTests`, but the actual try-CloudKit-else-local selection in [simple_recurring_budgetsApp.swift](../../simple-recurring-budgets/App/simple_recurring_budgetsApp.swift) still has no test for either branch outcome.
5. **`MockKeyValueStore` still ships in the production target** (April J2, unresolved) — defined in [Settings/KeyValueStore.swift](../../simple-recurring-budgets/Settings/KeyValueStore.swift) with no `#if DEBUG` guard; now referenced by eight test files, so moving it is still a one-file mechanical change.
6. **Drag-to-reorder wiring has no test at any layer** — `BudgetsViewMoveTests` still inlines the move algorithm (April D1), the file still contains the suite's last remaining `Thread.sleep` (April J1), and none of the fourteen UI journeys performs a drag, so a dropped `.onMove` modifier remains invisible to the suite.
7. **SwiftData migration harness still absent** (April B2, unresolved) — [BudgetMigrationPlan.swift](../../simple-recurring-budgets/Models/BudgetMigrationPlan.swift) still ships `stages: []` with no fixture round-trip pattern; four new `@Model` types have landed since April, so the first real migration is closer, not further away.
8. **Settings iCloud status check still hard-wires `CKContainer`** (April I2, unresolved) — `loadICloudStatus()` gained an `IS_TESTING` short-circuit (so UI tests no longer hang, #211) but still cannot be driven through a stubbed account status; only the `accountStatus → rowState` half is unit-tested.
9. **Mirrored-logic unit tests remain** in `SettingsWeekStartConfirmationTests` and `CurrencyPickerTests.filter` (April D3/D4) — lower risk now that `UserJourneyTests.testSettingsRoundTrip` exercises the real Settings screen, but the mirrors still drift silently.
10. **The empty unit-test placeholder still ships** (April C2, half-resolved) — `simple_recurring_budgetsTests.example()` is still an empty body; the UI-target `testExample` is now at least a real launch smoke test.

---

## Method and scope

- **Type of audit:** Static. Production sources under [simple-recurring-budgets/](../../simple-recurring-budgets/) (93 Swift files), unit tests under [simple-recurring-budgetsTests/](../../simple-recurring-budgetsTests/) (64 files), and UI tests under [simple-recurring-budgetsUITests/](../../simple-recurring-budgetsUITests/) (15 files) were inventoried and cross-referenced; type-level reference mapping was machine-assisted and spot-verified. Tooling reviewed: [scripts/test.sh](../../scripts/test.sh), [test-unit.sh](../../scripts/test-unit.sh), [test-ui.sh](../../scripts/test-ui.sh), [Makefile](../../Makefile), [lefthook.yml](../../lefthook.yml), [.github/workflows/ci.yml](../../.github/workflows/ci.yml), [full-test-on-demand.yml](../../.github/workflows/full-test-on-demand.yml), and the shared scheme. Feature acceptance criteria from [docs/product-features-planning.md](../product-features-planning.md) were cross-referenced.
- **Out of scope (deliberately):** No `xcodebuild` runs, no `xccov` data (none exists — see issue 1), no scheme edits, no test execution, no new tests.
- **Doc alignment:** No conflicts found with [docs/main-prd.md](../main-prd.md), [docs/tech-design-doc.md](../tech-design-doc.md), or [docs/product-features-planning.md](../product-features-planning.md). The §6.8 cross-cutting concerns (Dynamic Type, VoiceOver, localization, analytics events) now each have at least one automated tripwire (large-text audits, `performAccessibilityAudit`, the CI i18n gates, and the §18.1 analytics suites respectively) — a clear improvement over April.
- **Severity scale:** **P0** = correctness or release-blocking risk; **P1** = significant gap for the next 1–2 OpenSpec changes; **P2** = polish / drift prevention.
- **Effort scale:** **S** ≤ 1 day, **M** 1–3 days, **L** > 3 days or new infrastructure.

---

## Resolution of the 2026-04-30 findings

| April finding | Status | Evidence |
|---|---|---|
| A1 No CI | **Resolved** (with June caveat) | [ci.yml](../../.github/workflows/ci.yml): `lint` (pinned SwiftFormat/SwiftLint), `secrets` (gitleaks), `i18n-gates`, `build`, `unit-tests`; [full-test-on-demand.yml](../../.github/workflows/full-test-on-demand.yml) runs the full suite on a `/test-full` PR comment. macOS jobs paused June 2026 (#228) — see finding A2 below. |
| A2 Coverage not instrumented | **Open** | No `-enableCodeCoverage` / `xccov` anywhere; scheme has no coverage flag. |
| A3 Pre-push only builds | **Open (accepted)** | [lefthook.yml](../../lefthook.yml) pre-push: main-push guard, two i18n gates, `build.sh`. CI was the designated test gate — currently weakened by the #228 pause. |
| B1 Bootstrap untested | **Mostly resolved** | `AppStartup` (closure-injected factory) + `AppStartupTests` (success / failure / retry-success / retry-failure); `fatalError` replaced by `ContainerFailureView`; `PersistentStoreURLTests` pins the issue-#1 single-store-URL invariant. Remaining: the cloud-vs-local branch itself (finding B1 below). |
| B2 No migration harness | **Open** | `BudgetMigrationPlan.stages == []`, no fixture pattern. |
| C1 UI-test target empty | **Resolved** | 55 tests: `AccessibilityAuditTests` (19, incl. 6 large-text), `UserJourneyTests` (14 flows), `ClearAmountButtonUITests` (5), `AllocationFirstTapUITests` (1), plus screen objects (`BudgetsScreen`, `AddBudgetScreen`, `AddExpenseScreen`, `BudgetDetailScreen`, `SettingsScreen`) and `UITestHelpers` (`makeApp()` with `IS_TESTING=1`, `SEED_BUDGETS` seeding, `largeTextApp()`). Wired into `make test` (two-pass) and `/test-full`. |
| C2 Empty placeholder tests | **Half-resolved** | UI `testExample` now launches the app (smoke). Unit `example()` is still an empty body. |
| D1 BudgetsView move inlined | **Open** | Header comment still documents the trade-off; no `.onMove` coverage at any layer. |
| D2 BudgetDetail actions inlined | **Mostly resolved** | Reset/pause/resume/allocation-edit write paths moved into `BudgetLifecycleService` and are tested there (`BudgetLifecycleServiceResetBudgetTests`, pause/resume suites); `UserJourneyTests` covers delete-expense, pause/resume, delete-budget through the real UI. Residual inlined fragments remain in `BudgetDetailViewActionsTests`. |
| D3 SettingsView week-start mirrored | **Open (mitigated)** | Still mirrors the Binding logic; `testSettingsRoundTrip` UI journey adds real-wiring coverage. |
| D4 CurrencyPicker filter mirrored | **Open** | `filteredCodes` still private; test still re-implements it. |
| E1 DST / non-UTC untested | **Open** | All date suites fixed-UTC; sole exception is one `America/New_York` calendar in `BudgetDisplayTests`. |
| E2 Non-Gregorian calendars | **Open** | No change. |
| E3 Decimal-comma locale parsing | **Resolved** | `EditableAmountConverterTests` and `DecimalInputFieldTests` cover `de_DE` / `fr_FR` paths (the old `OptionalDecimalFormatStyle` was replaced by `EditableAmountConverter` + `DecimalInputField` in the rewrite). |
| E4 Relative-day strings en-only | **Open** | `DateExpenseListFormattingTests` unchanged. |
| F1 Decimal boundary values | **Open** | No max/min-magnitude formatter cases. |
| F2 Negative-currency substring assert | **Open** | `result.first == "-" || result.contains("(42")` still present. |
| G1 Composed a11y labels unasserted | **Partially resolved** | `BudgetSummaryAccessibilityLabelTests` asserts the budget-summary labels; `performAccessibilityAudit()` covers label presence generically. `CarryOverChip` surplus/deficit/zero label variants still unasserted. |
| G2 Dynamic Type / Dark Mode | **Partially resolved** | Six large-text audit tests + the ad-hoc `translation-accessibility-size-check` skill cover Dynamic Type. Dark Mode still has no automated assertion. |
| H1 Router/AppRoute/SheetRoute untested | **Partially resolved** | `ModelContextLookupTests` covers UUID route resolution (architecture-audit 4.2, #224); `ExpenseRowPushNavigationTests` covers route equality; UI journeys exercise push + sheet wiring end-to-end. No direct `Router` path/sheet lifecycle unit test. |
| H2 RootView wiring untested | **Resolved in effect** | Every UI journey traverses RootView's NavigationStack + sheet routing. |
| I1 Yield-based notification tests | **Open** | `AppSettingsTests` still uses single `await Task.yield()` before asserting. |
| I2 CKContainer not stubbable | **Open (mitigated)** | `IS_TESTING` short-circuit added for UI-test stability (#211); seam still not injectable. |
| J1 `Thread.sleep` in tests | **Mostly resolved** | One occurrence left ([BudgetsViewTests.swift:77](../../simple-recurring-budgetsTests/Views/BudgetList/BudgetsViewTests.swift)). |
| J2 MockKeyValueStore in prod target | **Open** | Still in `Settings/KeyValueStore.swift`, unguarded. |
| J3 Per-file helper duplication | **Open** | Fixed-UTC calendar + `d(_:_:_:)` helpers still re-declared per file (e.g. both `BudgetCalculatorTests` and `BudgetCalculatorMomentGranularPauseTests` carry deliberate local copies). |
| K1 Empty state untested | **Resolved** | `AccessibilityAuditTests.testBudgetsListEmpty` + journeys launch into the empty in-memory store. |
| K2 Period labels untested | **Resolved** | `BudgetDisplayTests` covers the display-label surface (incl. `periodDisplayLabel`). |

---

## Inventory snapshot

Counts: **93 production files → 64 unit-test files (633 `@Test`) + 15 UI-test files (55 tests).** The per-file mapping is in Appendix A; highlights below.

### Strongly covered (hits)

- **Domain layer (rewrite)** — `BudgetCalculator` (snapshot states active/preStart/postEnd, carry-over walker, weekly anchoring, start-date edit semantics, moment-granular pause), `BudgetLifecycleService` (pure `result(for:)` + all four write paths), `PeriodCalculator`, `AllocationInEffect`, `CurrentPeriodSpillover`, `LifecycleClassification` (incl. `isPausedAtMoment`), `ModelContext+SaveChanges` (success + failure-mapping seam), enums. This is the deepest-covered area of the codebase and tracks the `rewrite-budget-calculations` spec section-by-section.
- **Models** — defaults/round-trips for all five `@Model` types (`Budget`, `ExpenseItem`, `AllocationChange`, `LifecycleEvent` + kind enum), partition helper, `recomputeToken` (#127 regression guard), icon persistence + curated set, display labels, UUID lookups.
- **Analytics (Mixpanel Phase 1)** — the §18.1 contracts are implemented one-to-one as named suites: jurisdiction (#1), opt-in (#2), distinct-id (#3), lazy init (#4), consent ordering (#5/#6), event constants (#7), PII enforcement (#8), super-properties (#9), token branch (#10); plus logger-boundary structural tests and recents bucketing.
- **Rating prompt (F-6.03)** — coordinator eligibility/request contracts and expense-log signals.
- **ViewModels** — `AddEditBudgetViewModel` (6 suites: core, schedule, icon, orphan warning, edit analytics, cohort refresh) and `AddEditExpenseViewModel` (core, add-funds, recents, date bounds, captions).
- **Input-field regressions** — `EditableAmountConverter`, `DecimalInputField` (fraction capping, begin-editing focus), `SaveErrorState` 3-strikes; backed by the two dedicated UI suites (`ClearAmountButtonUITests`, `AllocationFirstTapUITests`) for the iOS-COMPAT first-responder behavior that unit tests can't reach.
- **UI journeys** — create/edit/delete budget, add/edit/delete expense (both entry points), pause/resume, navigation, settings round-trip, period-chip rules (default carry-over, Specific Dates, all chips selectable, edit-mode lock).
- **Accessibility** — `performAccessibilityAudit()` across 7 screens in default + large-text configurations.

### Partially covered

- [Views/BudgetList/BudgetsView.swift](../../simple-recurring-budgets/Views/BudgetList/BudgetsView.swift) — move algorithm inlined in tests; **no reorder coverage of the actual `.onMove` wiring at any layer** (see D1). Rendering/empty state covered by UI tests.
- [Views/Settings/SettingsView.swift](../../simple-recurring-budgets/Views/Settings/SettingsView.swift) — picker write path + week-start logic (mirrored) + `rowState` half of the iCloud chain unit-tested; Settings screen exercised by UI journeys and a11y audits. `loadICloudStatus()`'s live `CKContainer` query still unreachable (I2).
- [Views/Settings/CurrencyPickerView.swift](../../simple-recurring-budgets/Views/Settings/CurrencyPickerView.swift) — `displayName(for:)` tested; `filteredCodes` mirrored (D4).
- [App/simple_recurring_budgetsApp.swift](../../simple-recurring-budgets/App/simple_recurring_budgetsApp.swift) — recovery seam and store-URL invariant tested; `makeProductionModelContainer`'s branch selection and the Mixpanel provider-closure wiring untested (B1).
- [Logging/Analytics+DomainExtensions.swift](../../simple-recurring-budgets/Logging/Analytics+DomainExtensions.swift) — bucketing helpers tested (`RecentsBucketingTests`, constants suites); the four `analyticsValue` enum mappings asserted only indirectly via super-property suites.
- [Domain/FeedbackMailto.swift](../../simple-recurring-budgets/Domain/FeedbackMailto.swift) — `diagnosticURL` (3-strikes) and `containerFailureURL` (payload allow-list) tested; `plainURL` (Settings "Send Feedback") untested.
- [App/Router.swift](../../simple-recurring-budgets/App/Router.swift), [AppRoute](../../simple-recurring-budgets/App/AppRoute.swift) / [SheetRoute](../../simple-recurring-budgets/App/SheetRoute.swift) — UUID resolution + route equality + journey-level navigation covered; no direct path/sheet lifecycle unit test (H1).

### Uncovered (no test references at any layer)

- **Recovery / consent UI**: [Views/ContainerFailureView.swift](../../simple-recurring-budgets/Views/ContainerFailureView.swift) (Retry / Send Feedback wiring — the logic behind it is tested, the view is not), [Views/Settings/AnalyticsConsentSheet.swift](../../simple-recurring-budgets/Views/Settings/AnalyticsConsentSheet.swift) (jurisdiction/ordering logic tested; sheet itself not reachable by current journeys), [RatingPrompt/RatingPromptPresenter.swift](../../simple-recurring-budgets/RatingPrompt/RatingPromptPresenter.swift) (root-level modifier with a documented environment-ordering crash hazard — see the comment in the app file).
- **Detail-screen presentation components**: `CarryOverChip` (a11y label variants), `InactiveStatusChip`, `StatusChipRow`, `RemainingBar` (decorative, `accessibilityHidden`), `BudgetDetailView+Title/+PauseResume/+ExpenseSection` (logic extracted and tested; SwiftUI composition untested beyond UI journeys).
- **Form composition files**: `AddEditBudgetView+Schedule/+SpecificDates/+AllocationCard`, `AddEditExpenseView+AmountCard/+AddFundsCard/+RatingPrompt` — underlying ViewModels/services tested; the SwiftUI wiring is covered only to the extent the UI journeys traverse it.
- **Shared styling**: `Color+Money`, `AnyShapeStyle+Dimmed`, `AnyShapeStyle+ReadableSecondary` (the #223 contrast token — worth a tripwire given it shipped to fix a flake), `View+AppBackground`, `View+DismissKeyboard`, `CurrencyAmountField`.
- **Previews / tooling** (reasonable to skip): `Previews/*`, `DebugData`, `TestDynamicTypeOverride` (consumed by the screenshot check), `ScreenshotSeed`, `SnapshotHelper`, `AppStoreScreenshots`, `LocalizationScreenshotCapture`.

---

## Findings by area

### A. CI and tooling

- **A1. Code coverage is still not instrumented.** No script or workflow passes `-enableCodeCoverage YES`; the shared scheme has no coverage setting; no `xccov` consumer exists. The result-bundle plumbing (`-resultBundlePath` in all three test scripts) is already in place, so the marginal cost is one flag plus a report step.
  - **Severity:** P1 • **Effort:** S • **Horizon:** Short term
  - **Next step:** Add `-enableCodeCoverage YES` to [scripts/test.sh](../../scripts/test.sh) / [test-unit.sh](../../scripts/test-unit.sh) (unit pass only is fine), and a `make`-reachable `xcrun xccov view --report` step. Record a baseline number in the next audit; gate in CI once A2 is resolved.

- **A2. macOS CI jobs are paused for June 2026.** `build` and `unit-tests` carry `if: false` (#228), so until ~2026-07-01 nothing unbypassable compiles or tests PRs; `/test-full` remains available but bills against the same exhausted budget. This is documented, time-boxed, and tracked — but every prior audit treated "tests run only when a developer runs them" as the top finding, and that is the de-facto state again this month.
  - **Severity:** P1 (time-boxed) • **Effort:** S • **Horizon:** 2026-07-01
  - **Next step:** Execute the #228 re-enable checklist on July 1. Consider a cheaper permanent floor: a `swift build`-style Linux syntax check is not possible for an iOS app target, but a *scheduled* (weekly) macOS unit-test run would cap the regression window at 7 days for ~4% of the per-PR cost.

- **A3. Pre-push still doesn't test.** Accepted in April on the grounds that CI is the real gate; weakened while A2 is in force. No change recommended beyond A2.
  - **Severity:** P2 • **Effort:** — • **Horizon:** —

### B. Bootstrap and persistence

- **B1. `makeProductionModelContainer`'s branch selection is untested.** The function now *throws* instead of crashing (recovery is `AppStartup`'s job, which is tested), and the shared-`storeURL` invariant is pinned. But no test exercises "CloudKit config succeeds → `.cloudKit` backing" vs "CloudKit fails, local succeeds → `.localFallback`" — the branch is chosen by a `try?` on a real `ModelContainer` init, which unit tests can't force to fail.
  - **Severity:** P1 • **Effort:** M • **Horizon:** Short term
  - **Next step:** Same shape as the `AppStartup` fix: inject two factory closures (cloud, local) into a small static helper, defaulting to the real `ModelContainer` inits; test the four outcome combinations with throwing closures and assert the returned backing and (via a spy logger seam or just the backing) the path taken.

- **B2. SwiftData migration harness still absent.** `stages` is still `[]`, and SchemaV1 has grown to five model types since April (`AllocationChange`, `LifecycleEvent` added by the rewrite). The first real migration will be written under pressure without a fixture pattern.
  - **Severity:** P1 (preventive) • **Effort:** M • **Horizon:** Before any SchemaV2
  - **Next step:** As recommended in April: a `MigrationTestSupport` helper that writes a SchemaV1 store to a temp URL and re-opens it through `BudgetMigrationPlan`; ship the V1-open sanity test now.

### C. UI tests

- **C1. No reorder journey.** `UserJourneyTests` covers create/edit/delete/pause/navigation/settings but never drags a row, so the `.onMove` wiring — the exact regression the inlined `BudgetsViewMoveTests` admits it can't catch — has no tripwire. XCUITest's `press(forDuration:thenDragTo:)` works on List reorder handles in edit mode.
  - **Severity:** P1 • **Effort:** S–M (drag gestures flake; budget one retry) • **Horizon:** Short term
  - **Next step:** One journey: seed three budgets via `SEED_BUDGETS`, enter edit mode, drag row 3 to position 1, assert the new order persists after relaunch (relaunch also exercises sortOrder persistence).

- **C2. Unit-target placeholder remains.** `simple_recurring_budgetsTests.example()` is still an empty Xcode-template body.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Short term
  - **Next step:** Delete it or convert it to a schema-loads smoke test.

- **C3. The UI suite's CI exposure is comment-gated.** `/test-full` is the only server-side runner of the 55 UI tests, and it must be remembered per-PR. Fine while macOS minutes are scarce; revisit when A2 lifts.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Long term
  - **Next step:** When re-enabling macOS jobs, consider auto-running the two fast UI regression suites (`ClearAmountButtonUITests`, `AllocationFirstTapUITests`) in the per-PR `unit-tests` job — they exist precisely because unit tests can't catch those regressions.

### D. Mirrored-logic unit tests (residual)

- **D1. `BudgetsViewMoveTests`** — still inlines the move/sortOrder rewrite and still contains the suite's last `Thread.sleep(forTimeInterval: 0.001)`. Pair with C1: extract a `BudgetReorderService.applyMove(rows:from:to:now:)`, pass `now` explicitly, delete the sleep.
  - **Severity:** P2 (P1 if C1 isn't done) • **Effort:** S • **Horizon:** Short term
- **D2. `SettingsWeekStartConfirmationTests`** — still simulates the picker Binding's set-logic in the test body. Extraction (a tiny `pending/select/confirm/cancel` helper) remains the right fix; mitigated by `testSettingsRoundTrip`.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Long term
- **D3. `CurrencyPickerTests.filter`** — still mirrors the private `filteredCodes`. Promote to an internal static and call it.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Long term

### E. Time and locale correctness

- **E1. DST and non-UTC time zones remain the biggest correctness blind spot.** Production date math runs on the user's calendar; tests run on UTC. The rewrite raised the stakes: `walkCarryOver` re-derives **every** period boundary from the walk-window start on every read, so a DST-shifted boundary doesn't just move one period edge — it can re-bucket historical expenses between periods and change the cumulative carry-over. Zero tests construct a DST transition.
  - **Severity:** P0 for DST-region users • **Effort:** S–M • **Horizon:** Short term
  - **Next step:** Parameterize the shared test-calendar helper over `[UTC, America/Los_Angeles, Europe/Berlin]` and run the existing `PeriodCalculator` boundary cases plus one `walkCarryOver` multi-period case across the 2026-03-08 and 2026-11-01 US transitions. The helpers are already centralized enough per-file for this to be mostly mechanical.
- **E2. Non-Gregorian calendars** — unchanged from April; one documented-behavior test would close it.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Long term
- **E3. Relative-day strings still en-US-only** (`DateExpenseListFormattingTests`) — unchanged.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Long term

### F. Money correctness

- **F1. Decimal boundary magnitudes still unasserted** (max-supported / smallest-positive / zero through the formatters). Unchanged from April.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Long term
- **F2. Negative-currency rendering still asserted by substring** (`result.first == "-" || result.contains("(42")`). Unchanged.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Long term

### G. Accessibility and appearance

- **G1. `CarryOverChip` composed labels still unasserted.** The generic audits check label *presence*, not the surplus/deficit/zero wording. `BudgetSummaryAccessibilityLabelTests` is the pattern to copy.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Short term
- **G2. Dark Mode has no automated coverage.** Dynamic Type now has the large-text audits and the ad-hoc localized-layout skill; Dark Mode (incl. the #223 `readableSecondary` contrast token, which shipped to fix a real flake) has nothing.
  - **Severity:** P2 • **Effort:** M–L (snapshot infra) • **Horizon:** Long term
  - **Next step:** Cheapest tripwire: a unit test asserting `AnyShapeStyle+ReadableSecondary` resolves distinct colors per scheme; full fix is the snapshot strategy from April's long-term list.

### H. Routing and app shell

- **H1. `Router` still has no direct unit test** for path/sheet lifecycle, though every journey exercises it and UUID resolution is covered. A 30-line `RouterTests` remains cheap insurance for a navigation refactor.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Long term
- **H2. `RatingPromptPresenter` and `ContainerFailureView` are untested view shells over well-tested logic.** The presenter's environment-ordering constraint ("reordering would crash on launch") is enforced only by a comment; the failure view's Retry/Send-Feedback wiring is unreachable by the normal-launch UI tests.
  - **Severity:** P2 • **Effort:** M (failure view needs a forced-failure launch mode) • **Horizon:** Long term
  - **Next step:** A `FORCE_CONTAINER_FAILURE` DEBUG launch env (mirroring the existing launch-mode pattern) would make a two-test UI suite possible: failure view appears, Retry recovers.

### I. Async / observers

- **I1. Yield-based notification tests** in `AppSettingsTests` — unchanged; replace `await Task.yield()` with Swift Testing `confirmation`.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Long term
- **I2. `CKContainer` seam** — unchanged in unit-testability; the new `IS_TESTING` short-circuit fixed the UI-test hang but is a bypass, not a seam. An injected `() async -> AccountStatus` would let the short-circuit and the tests share one mechanism.
  - **Severity:** P2 • **Effort:** M • **Horizon:** Long term

### J. Test hygiene

- **J1. `MockKeyValueStore` still ships in the app binary.** Now referenced by eight test files; still a single-file move into `simple-recurring-budgetsTests/Helpers/`.
  - **Severity:** P1 • **Effort:** S • **Horizon:** Short term
- **J2. Fixed-UTC calendar helpers duplicated per file.** Now ~10 copies (some deliberately local per their comments). Centralizing is also the prerequisite for the E1 time-zone parameterization.
  - **Severity:** P2 • **Effort:** S • **Horizon:** Short term (fold into E1)

---

## Recommendations — Short term (next 1–2 OpenSpec changes)

1. **Instrument coverage** (A1): `-enableCodeCoverage YES` in the unit-test scripts + an `xccov` report target; record the baseline.
2. **Re-enable macOS CI on July 1** (A2): delete the two `if: false` guards per #228's checklist; consider folding the two fast UI regression suites into the per-PR job (C3).
3. **DST sweep** (E1 + J2): centralize the test-calendar helper, parameterize over three time zones, add the two US-2026 transition cases to `PeriodCalculator` and `walkCarryOver` tests.
4. **Move `MockKeyValueStore` into the test target** (J1).
5. **Add the reorder UI journey** (C1) and, with it, extract the move handler so `BudgetsViewMoveTests` stops inlining and loses the last `Thread.sleep` (D1).
6. **Make the production-container branch testable** (B1): inject cloud/local factory closures, test all four outcomes.
7. **Delete or repurpose `example()`** (C2).
8. **Assert `CarryOverChip` label variants** (G1) using the `BudgetSummaryAccessibilityLabelTests` pattern.

## Recommendations — Long term

1. **Migration harness before SchemaV2** (B2) — the single most valuable piece of not-yet-needed infrastructure.
2. **Snapshot strategy for Dark Mode / appearance** (G2), scoped to top-level screens × light/dark; piggyback on the existing screenshot tooling rather than adding a new dependency if possible.
3. **Forced-container-failure launch mode** (H2) to UI-test the recovery surface.
4. **Seam the iCloud account query** (I2) and retire the `IS_TESTING` bypass.
5. **Retire the remaining mirrored-logic tests** (D2, D3) via small extractions.
6. **Locale/calendar parameterization matrix** for formatter and relative-day tests (E2, E3, F1, F2) — one parameterized sweep closes four P2s.
7. **Coverage floor in CI** once A1 yields a baseline: set 1–2 points below current, ratchet upward.

---

## Appendix A — Per-file test inventory

Production file → covering tests ("none" = no reference at any layer; "UI" = UI-test coverage; "indirect" = exercised through a tested caller).

### `App/`

- `AppRoute.swift` → partial (`ExpenseRowPushNavigationTests`, `ModelContextLookupTests`; UI journeys)
- `AppStartup.swift` → `AppStartupTests` (success / failure / retry × 2)
- `Router.swift` → indirect (instantiated across ViewModel suites; UI journeys) — no direct lifecycle test
- `SheetRoute.swift` → indirect (UI journeys traverse all sheet types)
- `TestDynamicTypeOverride.swift` → UI (localization size-check tooling)
- `simple_recurring_budgetsApp.swift` → partial (`PersistentStoreURLTests` pins the store-URL invariant; `MixpanelTokenBranchTests` covers token selection; `makeProductionModelContainer` branching untested — B1)

### `Domain/`

- `AllocationInEffect.swift` → `AllocationInEffectTests`
- `BudgetCalculator.swift` → `BudgetCalculatorTests` (5 suites), `BudgetCalculatorMomentGranularPauseTests`
- `BudgetLifecycleService.swift` → `BudgetLifecycleServiceTests` (6 suites), `BudgetLifecycleServiceResetBudgetTests`
- `BudgetPeriod.swift`, `RecurringBudgetPeriod.swift`, `Weekday.swift` → `EnumTests`
- `BudgetSnapshot.swift` → indirect (output type of every `BudgetCalculator` test); direct use in `AddEditExpenseDateContextCaptionTests`
- `CarryOverWalker.swift` → indirect (`BudgetCalculatorCarryOverTests` drives it through `snapshot`) — fixed-UTC only (E1)
- `CurrentPeriodSpillover.swift` → `CurrentPeriodSpilloverTests`
- `FeedbackMailto.swift` → partial (`FeedbackMailtoContainerFailureTests`, `SaveErrorStateTests` cover 2 of 3 URL builders; `plainURL` uncovered)
- `LifecycleClassification.swift` → `LifecycleClassificationTests`, `LifecycleClassificationMomentGranularTests`
- `ModelContext+SaveChanges.swift` → `PersistenceSaveHelperTests` (success + failure seam)
- `PeriodCalculator.swift` → `PeriodCalculatorTests` (3 suites) — fixed-UTC only (E1)
- `PersistenceError.swift` → `PersistenceSaveHelperTests`, `SaveErrorStateTests`

### `Models/`

- `AllocationChange.swift` → `ModelTests` (`AllocationChangeModelTests`)
- `Budget.swift` → `ModelTests`, ViewModel suites
- `Budget+Display.swift` → `BudgetDisplayTests`
- `Budget+RecomputeToken.swift` → `BudgetRecomputeTokenTests` (#127 regression)
- `BudgetMigrationPlan.swift` → indirect via `TestModelContainer`; `stages` empty (B2)
- `DebugData.swift` → none (DEBUG fixtures; reasonable to skip)
- `ExpenseItem.swift` → `ModelTests` (`ExpenseItemModelTests`)
- `ExpenseItem+Partition.swift` → `ExpenseItemPartitionTests`
- `LifecycleEvent.swift` / `LifecycleEventKind.swift` → `ModelTests` (`LifecycleEventModelTests`), `EnumTests`
- `ModelContext+Lookup.swift` → `ModelContextLookupTests`
- `SchemaV1.swift` → indirect via `TestModelContainer.make()`

### `Settings/`, `Sync/`

- `AppSettings.swift` → `AppSettingsTests`, `AppSettingsAnalyticsOptInTests`, `AppSettingsAnalyticsDistinctIdTests`
- `ConsentJurisdiction.swift` → `ConsentJurisdictionTests`
- `KeyValueStore.swift` → exercised everywhere via `MockKeyValueStore` (which should move to the test target — J1)
- `SyncStatus.swift` → `SyncStatusTests`, `SettingsICloudNotificationTests` (half — I2)

### `Logging/`

- `AnalyticsClient.swift` → `AnalyticsClientTests`, `AnalyticsClientLoggerBoundaryTests`, `SpyAnalyticsClient`
- `Analytics+DomainExtensions.swift` → partial (`RecentsBucketingTests`, `PIIEnforcementCallSiteTests`, `AnalyticsEventConstantsTests`; `analyticsValue` mappings indirect via `SuperPropertyAttachmentTests`)
- `AnalyticsEnvironment.swift` → indirect (environment-injected spy in every analytics-asserting suite)
- `AppLoggers.swift` → `AppLoggersTests` (structural)
- `ConsoleAnalyticsClient.swift` → `AnalyticsClientTests` (crash safety)
- `MixpanelAnalyticsClient.swift` → `MixpanelLazyInitTests`, `AnalyticsConsentOrderingTests`, `SuperPropertyAttachmentTests` (SDK global untestable; seam-based)
- `MixpanelTokenSource.swift` → `MixpanelTokenBranchTests`

### `RatingPrompt/`

- `RatingPromptCoordinator.swift` → `RatingPromptCoordinatorTests`, `RatingPromptExpenseSignalsTests`
- `RatingPromptState.swift` → `RatingPromptCoordinatorTests`
- `RatingPromptPresenter.swift` → none (H2)

### `Formatting/`

- `BudgetPeriod+Display.swift` → `BudgetDisplayTests`
- `CurrencyDisplayPreference.swift` → `CurrencyDisplayPreferenceTests`, `CurrencyDisplayAffixesTests`
- `EditableAmountConverter.swift` → `EditableAmountConverterTests` (incl. decimal-comma locales)
- `Formatters.swift` → `FormattersTests` (4 suites)

### `Views/`

- `BudgetDetail/BudgetDetailView.swift` (+`ExpenseSection`, `+PauseResume`, `+Title`) → partial: extracted logic in `BudgetDetailViewActionsTests` (6 suites incl. pause/resume toolbar visibility, resume caption), `BudgetInactiveReasonTests`, `ExpenseItemPartitionTests`; wiring via `UserJourneyTests` + a11y audits
- `BudgetDetail/BudgetRemainingSummary.swift` → `BudgetRemainingSummaryTests` (a11y labels)
- `BudgetDetail/BudgetInactiveReason.swift` → `BudgetInactiveReasonTests`
- `BudgetDetail/CarryOverChip.swift`, `InactiveStatusChip.swift`, `StatusChipRow.swift`, `RemainingBar.swift` → none directly (G1; `RemainingBar` decorative); generic a11y audits only
- `BudgetForm/AddEditBudgetView.swift` (+3 extensions) → ViewModel suites (6) + UI journeys; SwiftUI composition itself untested
- `BudgetForm/AddEditBudgetViewModel.swift` → `AddEditBudgetViewModelTests` + Schedule/Icon/OrphanWarning/EditAnalytics/CohortRefresh suites
- `BudgetForm/BudgetIconPicker.swift` → `BudgetIconTests` (`BudgetIconPickerSetTests`)
- `BudgetList/BudgetsView.swift` → partial (`BudgetsViewMoveTests` inlined — D1; empty state + rendering via UI tests; **no reorder wiring coverage** — C1)
- `ContainerFailureView.swift` → none (H2)
- `ExpenseForm/AddEditExpenseView.swift` (+5 extensions) → ViewModel suites (core/AddFunds/Recents) + caption/date-bounds suites + `RecentsAlgorithmTests` + UI journeys & `ClearAmountButtonUITests`
- `RootView.swift` → UI (every journey)
- `Settings/SettingsView.swift` → partial (see I2/D2); UI journeys + a11y audits
- `Settings/AnalyticsConsentSheet.swift` → none directly (logic in `ConsentJurisdictionTests` / `AnalyticsConsentOrderingTests`)
- `Settings/CurrencyPickerView.swift` → partial (`CurrencyPickerTests` — D3)
- `Shared/DecimalInputField.swift` → `DecimalInputFieldTests` + `AllocationFirstTapUITests` / `ClearAmountButtonUITests`
- `Shared/SaveErrorAlert.swift` → `SaveErrorStateTests`
- `Shared/CurrencyAmountField.swift`, `Color+Money.swift`, `AnyShapeStyle+Dimmed.swift`, `AnyShapeStyle+ReadableSecondary.swift`, `View+AppBackground.swift`, `View+DismissKeyboard.swift` → none (G2 note on `ReadableSecondary`)

### `Previews/`

- `BudgetDetailFixtures.swift`, `PreviewContainer.swift`, `PreviewDates.swift` → none (preview-only; reasonable to skip)
- `InMemoryModelContainer.swift`, `ScreenshotSeed.swift` → UI (launch scaffolding for every UI test / screenshot run)

---

## Appendix B — Feature ID → covering tests

- **F-1.01 / F-1.02** — build success; `ModelTests`, `TestModelContainer`.
- **F-2.01 Budgets screen** — unit (move algorithm, display labels) + UI (`AccessibilityAuditTests` list states, journeys). Gap: reorder wiring (C1).
- **F-2.02 Budget screen** — `BudgetDetailViewActionsTests` suites, `BudgetInactiveReasonTests`, `BudgetRemainingSummaryTests`, partition tests + UI journeys (navigate, delete expense, pause/resume). Gap: `CarryOverChip` label variants (G1).
- **F-2.03 Add/Edit Budget** — 6 ViewModel suites + UI journeys (create, edit, period-chip lock). Strong.
- **F-2.04 Add/Edit Expense** — ViewModel core/AddFunds/Recents + date-bounds + captions + UI journeys + `ClearAmountButtonUITests`. Strong.
- **F-2.05 Settings** — unit (pickers, week-start logic, iCloud row-state half) + `testSettingsRoundTrip` + a11y audits. Gaps: I2 seam, Support/About actions.
- **F-2.06 First-run empty state** — `testBudgetsListEmpty` (resolved since April).
- **F-2.07 Carry-over toggle** — `AppSettingsTests`, ViewModel suites, `testAddBudgetDefaultPeriodShowsCarryOver`.
- **F-2.08 Specific Dates** — `BudgetCalculator` postEnd/spillover suites, `AddEditBudgetViewModelScheduleTests`, date-bounds tests, `testAddBudgetSpecificDatesPeriod`.
- **F-3.01 Dynamic Type** — large-text a11y audits + ad-hoc localized size-check skill.
- **F-3.02 VoiceOver** — `performAccessibilityAudit` suites + `BudgetSummaryAccessibilityLabelTests`.
- **F-3.03 / F-3.04 i18n** — CI i18n gates, `FormattersTests`, `CurrencyDisplayPreferenceTests`, `EditableAmountConverterTests`.
- **F-3.05 Dark Mode** — none (G2).
- **F-4.03 Budget icons** — `BudgetIconTests`, `AddEditBudgetViewModelIconTests`, icon-picker a11y audit.
- **F-5.01 Week start** — `AppSettingsTests` + week-start confirmation tests (mirrored — D2); period math fixed-UTC only (E1).
- **F-6.01 Add Funds** — `ExpenseItemModelTests`, `AddEditExpenseViewModelAddFundsTests`.
- **F-6.02 Expense Type** — none (schema-only; unchanged).
- **F-6.03 Rating prompt** — `RatingPromptCoordinatorTests`, `RatingPromptExpenseSignalsTests`. Gap: presenter modifier (H2).
- **F-7.04 Recents** — `RecentsAlgorithmTests`, `AddEditExpenseViewModelRecentsTests`, `RecentsBucketingTests`, `ClearAmountButtonUITests.testRecentsTileFillsAmount`.
- **F-7.05 / F-7.07 Start/End dates** — `BudgetCalculator` anchor/edit suites, `AddEditBudgetViewModelScheduleTests`, orphan-warning tests, date-bounds tests.
- **F-7.06 Pause/Resume** — lifecycle pause/resume suites, moment-granular suites, toolbar-visibility tests, `testPauseAndResumeBudget`.
- **F-8.01 OSLog** — `AppLoggersTests`, `AnalyticsClientLoggerBoundaryTests`.
- **F-8.02 Mixpanel Phase 1** — §18.1 contracts #1–#10, each a named suite. Strong.
- **F-4.01/02, F-7.01/02/03, F-8.03** — open features; no tests expected.
