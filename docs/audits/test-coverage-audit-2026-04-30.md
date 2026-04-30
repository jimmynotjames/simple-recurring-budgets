# Test Coverage Audit — 2026-04-30

> **Static-only audit.** No tests were executed and the Xcode scheme was not modified. No production or test code was changed by this audit. Recommendations are proposals for follow-up work.

## Summary

The **unit-test surface is strong on pure-Domain code and weak everywhere else.** All four `Domain/` services (`BudgetCalculator`, `BudgetLifecycleService`, `PeriodCalculator`, plus the `BudgetPeriod` / `ResetCadence` / `Weekday` enums) have thorough, deterministic Swift Testing suites that inject a fixed-UTC calendar and follow the PRD §6.7 / `budget-lifecycle` spec section-by-section. The two ViewModels, the `MockKeyValueStore`-backed `AppSettings`, the `SyncStatus` row-state matrix, the analytics protocol, currency formatting, and the `ExpenseItem` partition helper are all covered to a similar standard.

Coverage drops sharply once you leave that core. The CloudKit-or-local-fallback bootstrap path in [`simple_recurring_budgetsApp.swift`](simple-recurring-budgets/App/simple_recurring_budgetsApp.swift) — including its `fatalError` branch and four analytics events — has zero test coverage; there is no GitHub Actions / CI workflow at all (the only test gate is whichever developer runs `make test` locally); the UI-test target contains nothing but Xcode templates (`testExample`, `testLaunch`, `testLaunchPerformance`); and several SwiftUI screens (`BudgetsView`, `BudgetDetailView`, `SettingsView`, `CurrencyPickerView`) are "tested" by re-implementing the handler algorithm inside the test body rather than invoking the View, so view-wiring regressions (a missing `.onMove`, a stale Binding, a removed action) cannot be caught. Code coverage instrumentation is not enabled in [`scripts/test.sh`](scripts/test.sh).

### Top issues, ordered by impact

1. **No CI** — there is no `.github/workflows/` directory; tests only run when someone types `make test`. The pre-push hook only invokes `make build`.
2. **Bootstrap path untested** — `simple_recurring_budgetsApp.makeProductionModelContainer` (CloudKit→localFallback→`fatalError`) and its four `cloudkit.container.*` analytics emissions have no tests; this is the highest-risk file in the app.
3. **UI-test target is empty** — only the Xcode templates ship; no end-to-end flow (create budget, add expense, edit, delete, settings, week-start change) is exercised against an `XCUIApplication`.
4. **Code coverage is not instrumented** — `xcodebuild test` runs without `-enableCodeCoverage YES`, so nobody has visibility into actual line coverage and there is no threshold gate.
5. **View handlers tested by inlining the algorithm** — `BudgetsViewMoveTests`, `BudgetDetailViewActionsTests`, `SettingsViewTests`, and `CurrencyPickerTests` mirror production logic in the test body (the files openly acknowledge it); a refactor that breaks the View's wiring will pass these tests.
6. **Time-zone / DST untested** — every date-math test uses a fixed-UTC `Calendar`; the production code uses `Calendar.autoupdatingCurrent`, so DST transitions and non-UTC time zones (where users actually live) are unverified.
7. **Schema-migration harness absent** — `BudgetMigrationPlan.stages` is empty today; when V2 lands there is no fixture or pattern to copy.
8. **Two empty placeholder tests still ship** — `simple_recurring_budgetsTests.example()` and `simple_recurring_budgetsUITests.testExample()` are stubs left from the Xcode template and should be deleted.
9. **Accessibility / Dynamic Type / Dark Mode (F-3.01, F-3.02, F-3.05) untested** — composed `accessibilityLabel`s for the budget detail header, expense rows, and `CarryOverChip` (surplus/deficit/zero variants) are not asserted anywhere.
10. **`Thread.sleep(forTimeInterval: 0.001)` used to differentiate timestamps** — appears in `BudgetsViewTests` and `BudgetDetailViewActionsTests`. Better to inject `now: Date` into the algorithm being tested.

---

## Method and scope

- **Type of audit:** Static. Every Swift file under [`simple-recurring-budgets/`](simple-recurring-budgets/), [`simple-recurring-budgetsTests/`](simple-recurring-budgetsTests/), and [`simple-recurring-budgetsUITests/`](simple-recurring-budgetsUITests/) was read; tooling scripts in [`scripts/`](scripts/), the [`Makefile`](Makefile), and [`lefthook.yml`](lefthook.yml) were reviewed; product feature acceptance criteria in [`docs/product-features-planning.md`](docs/product-features-planning.md) and the `budget-lifecycle` / `settings-screen` OpenSpec specs were cross-referenced.
- **Out of scope (deliberately):** No `xcodebuild` runs, no `xccov` data, no scheme edits, no test execution. No new tests written.
- **Doc alignment:** No conflicts with [`docs/main-prd.md`](docs/main-prd.md), [`docs/tech-design-doc.md`](docs/tech-design-doc.md), [`docs/product-features-planning.md`](docs/product-features-planning.md), or [`docs/ux-design-brief.md`](docs/ux-design-brief.md). [`docs/tech-design-doc.md`](docs/tech-design-doc.md) §5.4 ("Domain testability") and §2.1 (View + Services pattern) are reflected in the actual test layout.
- **Severity scale:** **P0** = correctness or release-blocking risk; **P1** = significant gap that should land in the next 1–2 OpenSpec changes; **P2** = polish / drift prevention.
- **Effort scale:** **S** ≤ 1 day, **M** 1–3 days, **L** > 3 days or requires new infrastructure.

---

## Inventory snapshot

### Production -> Tests mapping (hits)

- [`Domain/BudgetCalculator.swift`](simple-recurring-budgets/Domain/BudgetCalculator.swift) → [`BudgetCalculatorTests.swift`](simple-recurring-budgetsTests/Domain/BudgetCalculatorTests.swift) — `remaining`, `rollCarryOver` (single, multi, weekly, negative), `checkScheduledReset` (weekly/monthly/quarterly/biweekly/never/long-gap), and roll-then-reset ordering. Strong.
- [`Domain/BudgetLifecycleService.swift`](simple-recurring-budgets/Domain/BudgetLifecycleService.swift) → [`BudgetLifecycleServiceTests.swift`](simple-recurring-budgetsTests/Domain/BudgetLifecycleServiceTests.swift) — no-op / roll-only / reset-only / roll-then-reset / `lastModified` semantics / biweekly anchor. Strong.
- [`Domain/PeriodCalculator.swift`](simple-recurring-budgets/Domain/PeriodCalculator.swift) → [`PeriodCalculatorTests.swift`](simple-recurring-budgetsTests/Domain/PeriodCalculatorTests.swift) — daily / weekly (Sunday + Monday) / biweekly / monthly for `periodStart` / `periodEnd` / `periodBoundaries`. Fixed-UTC only.
- [`Domain/BudgetPeriod.swift`](simple-recurring-budgets/Domain/BudgetPeriod.swift), [`Domain/ResetCadence.swift`](simple-recurring-budgets/Domain/ResetCadence.swift), [`Domain/Weekday.swift`](simple-recurring-budgets/Domain/Weekday.swift) → [`EnumTests.swift`](simple-recurring-budgetsTests/Domain/EnumTests.swift) — raw values, `Comparable` ordering, `defaultResetCadence`, `validResetCadences(for:)`, `isBroaderThan`, `Weekday.from(calendarFirstWeekday:)`. Thorough.
- [`Models/Budget.swift`](simple-recurring-budgets/Models/Budget.swift), [`Models/ExpenseItem.swift`](simple-recurring-budgets/Models/ExpenseItem.swift) → [`ModelTests.swift`](simple-recurring-budgetsTests/Models/ModelTests.swift) — defaults, custom values, paused-cadence default, `nextSortOrder`, cascade delete, `isAddFunds` / `displayAmount`.
- [`Models/ExpenseItem+Partition.swift`](simple-recurring-budgets/Models/ExpenseItem+Partition.swift) → [`ExpenseItemPartitionTests.swift`](simple-recurring-budgetsTests/Models/ExpenseItemPartitionTests.swift) — boundary inclusivity, descending order in both arrays, edge cases.
- [`Settings/AppSettings.swift`](simple-recurring-budgets/Settings/AppSettings.swift) and [`Settings/KeyValueStore.swift`](simple-recurring-budgets/Settings/KeyValueStore.swift) (`MockKeyValueStore` lives in production) → [`AppSettingsTests.swift`](simple-recurring-budgetsTests/Settings/AppSettingsTests.swift) — defaults / persistence / external-notification reload paths for all three keys.
- [`Sync/SyncStatus.swift`](simple-recurring-budgets/Sync/SyncStatus.swift) → [`SyncStatusTests.swift`](simple-recurring-budgetsTests/Sync/SyncStatusTests.swift) — full `(containerBacking, accountStatus) → rowState` matrix and observable mutation.
- [`Logging/AnalyticsClient.swift`](simple-recurring-budgets/Logging/AnalyticsClient.swift), [`Logging/ConsoleAnalyticsClient.swift`](simple-recurring-budgets/Logging/ConsoleAnalyticsClient.swift) → [`AnalyticsClientTests.swift`](simple-recurring-budgetsTests/Logging/AnalyticsClientTests.swift) and [`SpyAnalyticsClient.swift`](simple-recurring-budgetsTests/Logging/SpyAnalyticsClient.swift) — protocol overload defaults, spy recording, `ConsoleAnalyticsClient` crash safety, event constants.
- [`Formatting/Formatters.swift`](simple-recurring-budgets/Formatting/Formatters.swift) → [`FormattersTests.swift`](simple-recurring-budgetsTests/Formatting/FormattersTests.swift) — `Decimal.formatted(currencyCode:display:locale:)` for USD/EUR/JPY/SAR, `CarryOverFormatter` surplus/deficit/zero, `Date.formattedForExpenseList` Today / Yesterday / older.
- [`Formatting/CurrencyDisplayPreference.swift`](simple-recurring-budgets/Formatting/CurrencyDisplayPreference.swift) → [`CurrencyDisplayPreferenceTests.swift`](simple-recurring-budgetsTests/Formatting/CurrencyDisplayPreferenceTests.swift) — raw values, Codable round-trip, `example(locale:)` matches canonical formatter for en_US / fr_FR / ja_JP / ar_SA.
- [`Views/AddEditBudgetViewModel.swift`](simple-recurring-budgets/Views/AddEditBudgetViewModel.swift) → [`AddEditBudgetViewModelTests.swift`](simple-recurring-budgetsTests/Views/AddEditBudgetViewModelTests.swift) — Add/Edit mode defaults, `canSave`, save (insert + sortOrder), single-/multi-field edits, no-op edit, cancel, delete, cascade delete.
- [`Views/AddEditExpenseView.swift`](simple-recurring-budgets/Views/AddEditExpenseView.swift) (the embedded `AddEditExpenseViewModel`) → [`AddEditExpenseViewModelTests.swift`](simple-recurring-budgetsTests/Views/AddEditExpenseViewModelTests.swift) — Add/Edit defaults, sign-preservation on negative rows, description trim/nullify, sub-minute date drift no-op, delete in Add/Edit, plus the [`Formatting/OptionalDecimalFormatStyle.swift`](simple-recurring-budgets/Formatting/OptionalDecimalFormatStyle.swift) parse / format paths.

### Production -> Tests mapping (partial)

- [`Views/BudgetsView.swift`](simple-recurring-budgets/Views/BudgetsView.swift) → [`BudgetsViewTests.swift`](simple-recurring-budgetsTests/Views/BudgetsViewTests.swift) — only the **inlined** move/sortOrder rewrite algorithm is asserted; the file's own header comment notes "they verify the algorithm is correct but do not catch view-wiring regressions (e.g. a missing `.onMove` modifier)." `@Query` results, empty-state branch, search/sort, and the toolbar Settings entry-point are uncovered.
- [`Views/BudgetDetailView.swift`](simple-recurring-budgets/Views/BudgetDetailView.swift) → [`BudgetDetailViewActionsTests.swift`](simple-recurring-budgetsTests/Views/BudgetDetailViewActionsTests.swift) — inlined `resetBudget`, `resetCarryOver`, `deleteExpense` algorithms; plus three `AppRoute.expenseDetail` Hashable assertions. The 348-line View's status header, `RemainingBar` driving, `CarryOverChip` rendering, period-aware Current/Past sections (the partition is tested separately), confirmation dialogs, lifecycle-refresh `task` / `scenePhase` triggers, and toolbar overflow menu are uncovered.
- [`Views/SettingsView.swift`](simple-recurring-budgets/Views/SettingsView.swift) → [`SettingsViewTests.swift`](simple-recurring-budgetsTests/Views/SettingsViewTests.swift) — currency-display picker write path, week-start cancel/confirm logic (mirrored, not invoked), and the `accountStatus -> rowState` half of the iCloud notification chain. The actual `loadICloudStatus()` / `CKAccountChanged` observer registration, the Support section actions (mailto, `requestReview`, privacy URL), and the About section build-number rendering are uncovered.
- [`Views/CurrencyPickerView.swift`](simple-recurring-budgets/Views/CurrencyPickerView.swift) → [`CurrencyPickerTests.swift`](simple-recurring-budgetsTests/Views/CurrencyPickerTests.swift) — `displayName(for:)` + a mirrored `filter` helper. Catalog enumeration is spot-checked on `["USD", "EUR", "GBP"]`. The actual private `filteredCodes` is not invoked.
- [`Models/SchemaV1.swift`](simple-recurring-budgets/Models/SchemaV1.swift) → exercised indirectly via [`TestModelContainer.swift`](simple-recurring-budgetsTests/Helpers/TestModelContainer.swift) (`SchemaV1.swiftDataSchema` is loaded for every in-memory test container).
- [`Models/BudgetMigrationPlan.swift`](simple-recurring-budgets/Models/BudgetMigrationPlan.swift) → exercised indirectly via `TestModelContainer.make()` but `stages` is empty; no test fixture demonstrates a V1→V2 migration.

### Production -> Tests mapping (none)

- [`App/simple_recurring_budgetsApp.swift`](simple-recurring-budgets/App/simple_recurring_budgetsApp.swift) — including `makeProductionModelContainer` (CloudKit + local fallback + `fatalError`) and the four `cloudkit.container.*` analytics emissions, plus the DEBUG-only `appDatabaseLaunchMode` switch and `deleteAllBudgets`.
- [`App/Router.swift`](simple-recurring-budgets/App/Router.swift) — only instantiated incidentally in `BudgetDetailViewActionsTests`; `path` and `sheet` lifecycle, deep-link append/pop, and observable invalidation are uncovered.
- [`App/AppRoute.swift`](simple-recurring-budgets/App/AppRoute.swift) — only the `.expenseDetail` case has Hashable equality assertions; `.budgetDetail` is uncovered.
- [`App/SheetRoute.swift`](simple-recurring-budgets/App/SheetRoute.swift) — none of the four cases (`addBudget`, `editBudget`, `addExpense`, `settings`) or the `Identifiable` `id` are tested.
- [`Views/RootView.swift`](simple-recurring-budgets/Views/RootView.swift) — no test (composes `Router`, `NavigationStack`, sheet routing).
- [`Views/RemainingBar.swift`](simple-recurring-budgets/Views/RemainingBar.swift) — no test (decorative; `accessibilityHidden(true)`; arithmetic is trivial).
- [`Views/CarryOverChip.swift`](simple-recurring-budgets/Views/CarryOverChip.swift) — no test for the chip's surplus/deficit/zero `accessibilityLabel`, contrast-aware foreground, or the `arrow.up`/`arrow.down` SF Symbol selection. The underlying `CarryOverFormatter` is tested.
- [`Views/Color+Money.swift`](simple-recurring-budgets/Views/Color+Money.swift) — no test (two color constants).
- [`Views/View+AppBackground.swift`](simple-recurring-budgets/Views/View+AppBackground.swift) — no test.
- [`Formatting/BudgetPeriod+Display.swift`](simple-recurring-budgets/Formatting/BudgetPeriod+Display.swift) — no test for `listLabel` / `inlineLabel` localized fallbacks.
- [`Logging/AnalyticsEnvironment.swift`](simple-recurring-budgets/Logging/AnalyticsEnvironment.swift) — no test for the `EnvironmentValues.analytics` `@Entry` default (`ConsoleAnalyticsClient`).
- [`Logging/AppLoggers.swift`](simple-recurring-budgets/Logging/AppLoggers.swift) — no test for the three `Logger` constants and subsystem fallback.
- [`Models/DebugData.swift`](simple-recurring-budgets/Models/DebugData.swift) — DEBUG fixture data; reasonable to skip.
- [`Previews/InMemoryModelContainer.swift`](simple-recurring-budgets/Previews/InMemoryModelContainer.swift), [`Previews/BudgetDetailFixtures.swift`](simple-recurring-budgets/Previews/BudgetDetailFixtures.swift), [`Previews/PreviewContainer.swift`](simple-recurring-budgets/Previews/PreviewContainer.swift) — preview-only; reasonable to skip.

### Feature (F-x.xx) -> Tests mapping

- **F-1.01 App Scaffolding** — implementation-only; trivially covered by the build succeeding.
- **F-1.02 Data Architecture** — covered by `ModelTests` (Budget/ExpenseItem defaults, cascade delete) and `TestModelContainer` smoke test.
- **F-2.01 Budgets screen** — drag-to-reorder algorithm covered by `BudgetsViewMoveTests` (inlined). Empty-state branch / `@Query` wiring not covered.
- **F-2.02 Budget screen** — Reset Budget / Reset Carry-Over / Delete Expense algorithms covered by `BudgetDetailViewActionsTests` (inlined). Status header, period-aware sections (partition tested separately), lifecycle-refresh triggers, swipe-to-delete wiring, VoiceOver header labels not covered.
- **F-2.03 Add/Edit Budget screen** — `AddEditBudgetViewModelTests` covers seeding, validation, save/delete in both modes; cascade-delete via Delete Budget covered. Currency picker integration tested via `CurrencyPickerTests` (partial).
- **F-2.04 Add/Edit/View Expense screen** — `AddEditExpenseViewModelTests` covers all 21 acceptance scenarios in the local task ledger; sign preservation, description trimming, sub-minute date drift, isEditing gate.
- **F-2.05 Settings screen** — partial: currency-display picker, week-start cancel/confirm, iCloud row-state half. Support section (mailto / `requestReview` / privacy URL) and About section uncovered.
- **F-2.06 First-run empty state** — uncovered. No test asserts that an empty `@Query` yields the `ContentUnavailableView`.
- **F-2.07 Carry-over toggle** — covered via `AppSettingsTests` (default key) and `AddEditBudgetViewModelTests` (per-budget toggle).
- **F-3.01 Dynamic Type** — uncovered.
- **F-3.02 VoiceOver** — uncovered (composed labels for header / expense rows / `CarryOverChip`).
- **F-3.03 Internationalization of text** — partial: localized formatter coverage for currency strings; no per-locale string-catalog assertions.
- **F-3.04 Internationalization of currency** — covered by `CurrencyDisplayPreferenceTests` (4 locales) and `FormattersTests`.
- **F-3.05 Dark Mode** — uncovered.
- **F-5.01 Configurable start of week** — partial: `AppSettings` persistence covered; period math is fixed-UTC only.
- **F-6.01 Allow manually adding funds** — model layer (`isAddFunds`, `displayAmount`) covered by `ModelTests`; sign-preservation on edit covered by `AddEditExpenseViewModelTests`. Marked partial in product doc; consistent.
- **F-6.02 Expense Type** — uncovered (schema-only feature).
- **F-6.03 App Store rating prompt**, **F-7.01 / F-7.02 / F-7.03** — open features; no tests expected.

---

## Findings by area

### A. CI and tooling

- **A1. There is no CI workflow.** No `.github/workflows/` directory exists. The pre-push hook in [`lefthook.yml`](lefthook.yml) only runs `bash scripts/build.sh` (compile, no tests). Tests therefore only run when a developer types `make test` locally.
  - **Severity:** P0  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** Add `.github/workflows/ci.yml` that runs `make format` (no diff), `make lint`, `make build`, `make test` on `pull_request`. Use the same `xcodebuild -destination` strategy as `scripts/test.sh` with a pinned simulator runtime.

- **A2. Code coverage is not instrumented.** [`scripts/test.sh`](scripts/test.sh) calls `xcodebuild test` without `-enableCodeCoverage YES` and does not produce a `.xcresult` bundle. There is no per-PR coverage signal and no threshold gate.
  - **Severity:** P1  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** Add `-enableCodeCoverage YES -resultBundlePath build/Test.xcresult` to `scripts/test.sh`, then in CI run `xcrun xccov view --report --json build/Test.xcresult` and either publish the report or assert a per-target floor.

- **A3. Pre-push only builds, doesn't test.** [`lefthook.yml`](lefthook.yml) `pre-push.build` is the single gate before pushing; on a slow simulator-boot day developers may push code that breaks tests.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** Either rely on CI (recommended once A1 lands) or add a `pre-push.test` command. CI is the better split because pre-push is bypassable with `--no-verify`.

### B. Bootstrap and persistence

- **B1. `simple_recurring_budgetsApp.makeProductionModelContainer` is untested.** This is the single highest-risk file: it tries `cloudKitDatabase: .automatic`, falls back to `.none` on failure, fires four different analytics events, and `fatalError`s if the local container also fails. None of those branches are covered.
  - **Severity:** P0 (correctness for app launch)  •  **Effort:** M  •  **Horizon:** Short term
  - **Next step:** Extract `makeProductionModelContainer` (and the launch-mode switch) onto a small static type that takes an `AnalyticsClient` and a closure factory for `ModelContainer` initialization (one closure for "cloud" and one for "local"). Then write tests with closures that throw deterministically and assert the correct backing tuple and the correct sequence of events on a `SpyAnalyticsClient`.

- **B2. No SwiftData migration test harness.** [`Models/BudgetMigrationPlan.swift`](simple-recurring-budgets/Models/BudgetMigrationPlan.swift) ships with `stages: []`. There is no V0 store fixture or pattern that demonstrates round-tripping a row through a migration. When V2 lands the first migration test will be invented from scratch.
  - **Severity:** P1  •  **Effort:** M  •  **Horizon:** Long term (preventive)
  - **Next step:** Add a tiny `MigrationTestSupport` helper that writes a SchemaV1 store to a temp URL, opens it through `BudgetMigrationPlan` against a future SchemaV2 (when one exists), and asserts data shape. Until SchemaV2 exists, ship a single sanity test that opens a SchemaV1 store from a fixture URL and reads the rows back.

- **B3. Cascade delete and inverse relationship asserted only via the live SwiftData container.** `Budget.cascadeDeletesExpenses` in [`ModelTests.swift`](simple-recurring-budgetsTests/Models/ModelTests.swift) and the duplicate test in `AddEditBudgetViewModelTests` rely on `try context.save()` to flush the cascade. That is correct but doesn't surface what happens when the inverse relationship is `nil` on a partially-hydrated CloudKit record (the very case the production comment in [`Budget.swift`](simple-recurring-budgets/Models/Budget.swift) calls out).
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Long term
  - **Next step:** Add tests that build an `ExpenseItem` with `budget = nil` (orphan) and verify the partition/lifecycle paths handle it without crashing.

### C. UI tests

- **C1. UI-test target is empty.** [`simple_recurring_budgetsUITests.swift`](simple-recurring-budgetsUITests/simple_recurring_budgetsUITests.swift) has only `testExample()` (empty body) and `testLaunchPerformance()` (the Xcode template); [`simple_recurring_budgetsUITestsLaunchTests.swift`](simple-recurring-budgetsUITests/simple_recurring_budgetsUITestsLaunchTests.swift) is the launch-screen screenshot template. There is no end-to-end coverage of the headline flows that ship.
  - **Severity:** P1  •  **Effort:** L  •  **Horizon:** Short term to start (one happy-path each), long term to broaden
  - **Next step:** Stand up a minimal UI-test scaffolding that launches the app with a `-uiTesting` argument routed to `appDatabaseLaunchMode = .emptyInMemory` (already a DEBUG case in [`simple_recurring_budgetsApp.swift`](simple-recurring-budgets/App/simple_recurring_budgetsApp.swift)), plus one happy-path each for: create budget, add expense, edit expense, delete expense, change week-start (with confirmation), change currency display preference. Add an a11y identifier to every interactive element along the way.

- **C2. Empty placeholder tests still ship.** [`simple_recurring_budgetsTests.swift`](simple-recurring-budgetsTests/simple_recurring_budgetsTests.swift) `example()` is empty; [`simple_recurring_budgetsUITests.swift`](simple-recurring-budgetsUITests/simple_recurring_budgetsUITests.swift) `testExample()` is empty.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** Delete both files (or replace `simple_recurring_budgetsTests.swift` with an actual smoke test such as "the schema loads" if you want to keep a top-level entry test).

### D. View-handler tests that mirror production logic

- **D1. `BudgetsViewMoveTests` reimplements the move/sortOrder rewrite inline.** The file's header comment is candid about the trade-off; nonetheless a refactor that drops `.onMove` from the `List` would not be caught.
  - **Severity:** P1  •  **Effort:** M  •  **Horizon:** Short term
  - **Next step:** Extract the move handler into a static or instance method on a small helper (`BudgetReorderService.applyMove(rows:from:to:now:)`) that returns the mutated rows; have the view call that. Tests then exercise the helper directly (and the view's only responsibility is forwarding the indices).

- **D2. `BudgetDetailViewActionsTests` reimplements `resetBudget` / `resetCarryOver` / `deleteExpense` inline.** Same drift risk. Plus several tests use `Thread.sleep(forTimeInterval: 0.001)` to make `now` strictly after `lastModified`.
  - **Severity:** P1  •  **Effort:** M  •  **Horizon:** Short term
  - **Next step:** Pull the three actions onto a `BudgetActionsService` with explicit `now: Date` parameters. Existing tests adapt by passing `now` explicitly, removing the sleeps.

- **D3. `SettingsViewTests` reimplements the pendingWeekStart Binding logic inline.** Cancel/Confirm flow asserts variables in the test, not the View.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** Extract a `WeekStartConfirmationViewModel` (or pure helper) with `pending`, `selectNew(_:)`, `confirm()`, `cancel()`; assert against it.

- **D4. `CurrencyPickerTests.filter` mirrors `CurrencyPickerView.filteredCodes`.** Production helper is private, so the test re-implements it.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** Promote `filteredCodes(_:matching:)` to internal/static on `CurrencyPickerView` (or a sibling helper) and call it directly.

### E. Time and locale correctness

- **E1. DST and non-UTC time zones untested.** Every `Calendar` in the suite is `Calendar(identifier: .gregorian)` with `timeZone = UTC`. Production uses `Calendar.autoupdatingCurrent`, which honors the user's actual time zone. A user in `America/Los_Angeles` crossing a DST spring-forward boundary may see a "daily" period start at 23:00 the previous day or 01:00 the same day depending on direction. None of that is asserted.
  - **Severity:** P0 for users in DST regions (which is most of the user base)  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** In `PeriodCalculatorTests` add a parameterized test that runs each case with a `TimeZone(identifier: "America/Los_Angeles")` calendar across a known DST boundary (e.g., 2026-03-08, 2026-11-01). Same for `BudgetCalculatorTests.rollCarryOver` and the lifecycle service.

- **E2. Non-Gregorian calendars untested.** Hebrew, Buddhist, and Japanese calendars produce different `.month` arithmetic. While the app likely targets Gregorian only, this is worth at least one negative-case test that confirms behavior is acceptable.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Long term
  - **Next step:** Add one `PeriodCalculatorTests` case that uses `Calendar(identifier: .hebrew)` and asserts the documented behavior (or, if it's expected to fail, document that explicitly).

- **E3. Locale fallback for `OptionalDecimalParseStrategy` not asserted across decimal-comma locales.** [`Formatting/OptionalDecimalFormatStyle.swift`](simple-recurring-budgets/Formatting/OptionalDecimalFormatStyle.swift) parses with `Decimal(string:locale: .current)`; in `de_DE` "1,5" is 1.5 but in `en_US` it's invalid. No test crosses that threshold.
  - **Severity:** P1 (a French / German user typing into the Allocation field will hit this)  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** Convert `OptionalDecimalParseStrategy.parse(_:)` to take an explicit `locale: Locale` (currently hard-coded to `.current`), inject it from the format style, and add tests for `en_US` / `de_DE` / `fr_FR` round-trips.

- **E4. `DateExpenseListFormattingTests` uses `enUS` locale only.** Today / Yesterday strings are compared against lowercased English. A `de_DE` or `ja_JP` run would fail; tests just don't run that branch.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Long term
  - **Next step:** Either parameterize the relative-day tests across at least two locales, or add a separate test that just asserts the string-catalog key is resolved (independently of the formatted result).

### F. Money correctness

- **F1. No tests for very large or very small `Decimal` values.** `Decimal` has 38-digit precision; the formatters are unverified against amounts like `999_999_999_999.99` or `0.001`. While unlikely in practice, this is a 1-line addition and protects against future "what if a user enters their salary" edge cases.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Long term
  - **Next step:** Add three boundary cases to `FormattersTests`: max-supported, smallest-positive, and zero.

- **F2. Negative-currency rendering is asserted by substring only.** `negative_usd_enUS_renders_with_sign` checks `result.first == "-" || result.contains("(42")` to accept both `-$42.00` and `($42.00)` styles. That's defensible but means a cosmetic regression that swaps the two won't be caught.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Long term
  - **Next step:** Pin the expected string for the en_US locale, or make the convention explicit in a comment.

### G. Accessibility, Dynamic Type, Dark Mode

- **G1. Composed `accessibilityLabel`s are not asserted.** [`CarryOverChip.swift`](simple-recurring-budgets/Views/CarryOverChip.swift) has surplus/deficit/zero VoiceOver branches; `BudgetDetailView` advertises composed header labels (on-budget vs over-budget); expense rows advertise standard vs add-funds variants. None of these strings are tested.
  - **Severity:** P1  •  **Effort:** M  •  **Horizon:** Long term (needs a snapshot/inspect harness)
  - **Next step:** Either (a) introduce ViewInspector as a test-only dependency to assert `.accessibilityLabel` on synthesized views, or (b) extract the label-composition functions to free helpers (`carryOverAccessibilityLabel(amount:currencyCode:)`) and unit-test them.

- **G2. Dynamic Type and Dark Mode (F-3.01, F-3.05) are not exercised.** Multiple files use `@ScaledMetric`; `Color.moneyDeficit` / `moneySurplus` defer to system colors; nothing is asserted.
  - **Severity:** P2  •  **Effort:** L (best done as a screenshot-test / preview-snapshot harness)  •  **Horizon:** Long term
  - **Next step:** Adopt `swift-snapshot-testing` (or Xcode 16's preview snapshot APIs) and snapshot each top-level screen at `.large` and `.xxxLarge` Dynamic Type, light and dark.

### H. Routing and lifecycle

- **H1. `Router`, `AppRoute.budgetDetail`, all four `SheetRoute` cases are untested.** Only `AppRoute.expenseDetail` Hashable equality is asserted (in the actions-tests file).
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** Add a `RouterTests.swift` covering `path.append`, `path.removeLast`, `sheet` set/clear, `Router.path == [...]` Hashable contracts, and full Hashable parity for both enums.

- **H2. `RootView` and the sheet-routing wiring are untested.** This is the place a navigation refactor will most quietly break.
  - **Severity:** P2  •  **Effort:** M (needs UI test scaffolding from C1)  •  **Horizon:** Long term
  - **Next step:** Cover via the UI-test happy paths in C1 (every flow tap-tests at least one push and one sheet).

### I. Async / concurrency / observers

- **I1. `AppSettings` external-notification tests rely on a single `await Task.yield()`.** [`AppSettingsTests.externalNotification_*`](simple-recurring-budgetsTests/Settings/AppSettingsTests.swift) post a `didChangeExternallyNotification` and yield once before asserting. If the observer ever moves to a different scheduler, the assertion will race.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Long term
  - **Next step:** Replace with a confirmation-based wait — Swift Testing's `confirmation { confirm in … }` (or a `withCheckedContinuation` resolved inside the `applyKeys` path) — to make the test event-driven instead of yield-driven.

- **I2. `SettingsICloudNotificationTests` cannot stub `CKContainer` and tests only the `accountStatus -> rowState` half.** This is acknowledged in the file's docstring. The actual `loadICloudStatus()` and notification observer registration in `SettingsView` are uncovered.
  - **Severity:** P1  •  **Effort:** M  •  **Horizon:** Short term
  - **Next step:** Inject a `() async -> AccountStatus` closure into `SettingsView` (or a new `ICloudStatusProvider` protocol) defaulting to the live `CKContainer` call, and test the closure-driven path.

### J. Test hygiene

- **J1. `Thread.sleep(forTimeInterval: 0.001)` appears in 4–5 places.** Used to ensure `now > lastModified`. It's slow (each sleep adds ≥1 ms) and platform-flaky on a busy CI machine.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** Inject `now: Date` into the algorithm under test (D2 above) so the test can pass an explicitly-later timestamp.

- **J2. `MockKeyValueStore` lives in production target.** It is referenced from four test files via `@testable import`, but its definition sits in [`Settings/KeyValueStore.swift`](simple-recurring-budgets/Settings/KeyValueStore.swift) alongside the production `KeyValueStore` protocol. This makes it ship in the app binary (it is a `final class` not gated by `#if DEBUG`).
  - **Severity:** P1 (binary bloat + leaks a test helper into the App Store build)  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** Move `MockKeyValueStore` into the test target (e.g. `simple-recurring-budgetsTests/Helpers/MockKeyValueStore.swift`). The protocol stays in production.

- **J3. Test helpers are sprinkled per-file.** Several files re-declare a `private let cal: Calendar` and a `private func d(_:_:_:)` with the same body. Centralizing reduces drift.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Long term
  - **Next step:** Extend [`Helpers/TestModelContainer.swift`](simple-recurring-budgetsTests/Helpers/TestModelContainer.swift) (or add `Helpers/TestDates.swift`) with shared `utcGregorianCalendar()` and `utcDate(_:_:_:hour:)` helpers; replace the duplicates incrementally.

### K. Untested view assertions worth landing

- **K1. F-2.06 First-run empty state has no test.** The acceptance criterion says the empty `@Query` triggers `ContentUnavailableView` with a "Create a budget" CTA. Nothing asserts this.
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Long term
  - **Next step:** Either a UI test (preferred, see C1) or extract the `isEmpty -> view` decision into a helper that can be exercised directly.

- **K2. Period label rendering on the budget detail status header.** [`BudgetPeriod+Display.swift`](simple-recurring-budgets/Formatting/BudgetPeriod+Display.swift) `listLabel` / `inlineLabel` are not asserted at all (each case localizes a different string-catalog key).
  - **Severity:** P2  •  **Effort:** S  •  **Horizon:** Short term
  - **Next step:** Add a small `BudgetPeriodDisplayTests.swift` that asserts the four `listLabel` and four `inlineLabel` defaults and (optionally) that they are distinct strings.

---

## Recommendations — Short term (next 1–2 OpenSpec changes)

These are the actions that produce the largest visibility and drift-prevention gains for the smallest amount of effort.

1. **Add a CI workflow.** New file at `.github/workflows/ci.yml`. Runs on `pull_request`: `make format` (fail on diff), `make lint`, `make build`, `make test`. Pins a simulator runtime via `SIMULATOR_NAME`. Covers issue **A1**, indirectly covers **A3**.
2. **Enable code coverage in `scripts/test.sh`.** Add `-enableCodeCoverage YES -resultBundlePath build/Test.xcresult`. In CI, run `xcrun xccov view --report --json` and post to the PR (or fail under a soft floor like 65 %). Covers **A2**.
3. **Delete the two empty placeholder tests.** Covers **C2**.
4. **Move `MockKeyValueStore` to the test target.** Covers **J2**, removes test code from the shipped binary.
5. **Add DST and locale-comma tests.** One DST sweep in `PeriodCalculatorTests` (E1) and one comma-decimal locale test in the parser (E3). Two small, high-signal additions.
6. **Add a `RouterTests.swift` and complete `AppRoute` / `SheetRoute` Hashable / Identifiable coverage.** Covers **H1**.
7. **Wrap `simple_recurring_budgetsApp.makeProductionModelContainer` for testability.** Either inject the two `ModelContainer` factory closures or split the decision into a thin `BootstrapService` that takes `AnalyticsClient`. Add tests asserting the four event sequences (success / fallback / local success / total failure handled). Covers **B1**.
8. **Add minimal UI-test scaffolding.** Configure the app to honor a `-uiTesting` launch argument that selects `.emptyInMemory`. Add one happy-path UI test for "create a budget then add an expense". Covers the floor of **C1** and gives **H2** its scaffold.
9. **Add inline localized labels test.** A 20-line `BudgetPeriodDisplayTests.swift`. Covers **K2**.

## Recommendations — Long term

These are the structural moves that materially raise the ceiling of test value.

1. **Extract view-handler logic into a small services layer.** `BudgetReorderService`, `BudgetActionsService`, `WeekStartConfirmationViewModel`, `ICloudStatusProvider`. Each takes explicit `now: Date` / context / dependencies. Removes the inlined-algorithm anti-pattern across **D1–D4** and **I2**, and the `Thread.sleep` hack (**J1**) at the same time.
2. **Adopt a SwiftUI snapshot strategy.** `swift-snapshot-testing` or Xcode 16's preview snapshots, scoped to top-level screens at light/dark × `.large` / `.xxxLarge` Dynamic Type × LTR / RTL. Closes **G1, G2** and adds a tripwire for the F-3.01 / F-3.02 / F-3.05 acceptance criteria.
3. **Build a SwiftData migration test harness.** Add `MigrationTestSupport` that round-trips a fixture URL through `BudgetMigrationPlan`. Establish the pattern before the first real migration is written. Covers **B2**.
4. **Build out the UI-test target.** Cover the full F-2.01 → F-2.07 happy paths, edit-and-cancel flows, week-start change confirmation, and the iCloud row state under available / paused / unavailable. Two-dozen tests max, but they are the only way to assert the actual View wiring and accessibility tree as a unit. Covers **C1, H2, K1**.
5. **Centralize test helpers.** A `Helpers/TestDates.swift` and `Helpers/TestBudgets.swift` factory file. Mechanical, but makes future tests cheaper to write. Covers **J3**.
6. **Locale and calendar parameterization.** Run the date / formatter / parser tests across a parameterized matrix of `(Locale, TimeZone)` tuples — at minimum `[en_US/UTC, en_US/America/Los_Angeles, de_DE/Europe/Berlin, ja_JP/Asia/Tokyo, ar_SA/Asia/Riyadh]`. Covers **E1, E2, E4, F1, F2** in one move.
7. **Enforce a coverage floor in CI.** Once **A2** is in place and a baseline number is known, set the floor 1–2 points below current and ratchet upward. Treat each PR's coverage delta as a review signal.

---

## Appendix A — Per-file test inventory

Production file → covering test files (or "none" / "indirect").

### `App/`

- `App/AppRoute.swift` → partial (`BudgetDetailViewActionsTests` covers `.expenseDetail` Hashable only)
- `App/Router.swift` → none
- `App/SheetRoute.swift` → none
- `App/simple_recurring_budgetsApp.swift` → none

### `Domain/`

- `Domain/BudgetCalculator.swift` → `BudgetCalculatorTests.swift`
- `Domain/BudgetLifecycleService.swift` → `BudgetLifecycleServiceTests.swift`
- `Domain/BudgetPeriod.swift` → `EnumTests.swift` (`BudgetPeriodTests`)
- `Domain/PeriodCalculator.swift` → `PeriodCalculatorTests.swift`
- `Domain/ResetCadence.swift` → `EnumTests.swift` (`ResetCadenceTests`)
- `Domain/Weekday.swift` → `EnumTests.swift` (`WeekdayTests`)

### `Models/`

- `Models/Budget.swift` → `ModelTests.swift` (`BudgetModelTests`); also `AddEditBudgetViewModelTests.swift`
- `Models/BudgetMigrationPlan.swift` → indirect via `TestModelContainer.make()`; `stages` empty
- `Models/DebugData.swift` → none (DEBUG only; reasonable to skip)
- `Models/ExpenseItem.swift` → `ModelTests.swift` (`ExpenseItemModelTests`)
- `Models/ExpenseItem+Partition.swift` → `ExpenseItemPartitionTests.swift`
- `Models/SchemaV1.swift` → indirect via `TestModelContainer.make()` and `ModelContainerTests`

### `Settings/`

- `Settings/AppSettings.swift` → `AppSettingsTests.swift`
- `Settings/KeyValueStore.swift` → `AppSettingsTests.swift` (the `MockKeyValueStore` impl in this file). See finding **J2** about moving to test target.

### `Sync/`

- `Sync/SyncStatus.swift` → `SyncStatusTests.swift`; partial `SettingsViewTests.SettingsICloudNotificationTests`

### `Logging/`

- `Logging/AnalyticsClient.swift` → `AnalyticsClientTests.swift`, `SpyAnalyticsClient.swift`
- `Logging/AnalyticsEnvironment.swift` → none
- `Logging/AppLoggers.swift` → none
- `Logging/ConsoleAnalyticsClient.swift` → `AnalyticsClientTests.swift` (crash-safety suite)

### `Formatting/`

- `Formatting/BudgetPeriod+Display.swift` → none
- `Formatting/CurrencyDisplayPreference.swift` → `CurrencyDisplayPreferenceTests.swift`
- `Formatting/Formatters.swift` → `FormattersTests.swift`
- `Formatting/OptionalDecimalFormatStyle.swift` → indirect via `AddEditExpenseViewModelTests` (parse / format suite)

### `Views/`

- `Views/AddEditBudgetView.swift` → none (View itself); the embedded `AddEditBudgetViewModel.swift` → `AddEditBudgetViewModelTests.swift`
- `Views/AddEditBudgetViewModel.swift` → `AddEditBudgetViewModelTests.swift`
- `Views/AddEditExpenseView.swift` → none (View itself); the embedded `AddEditExpenseViewModel` → `AddEditExpenseViewModelTests.swift`
- `Views/BudgetDetailView.swift` → partial (`BudgetDetailViewActionsTests.swift` covers reset / delete-expense via inlined algorithms)
- `Views/BudgetDetailView+ExpenseSection.swift` → indirect via `ExpenseItemPartitionTests.swift`
- `Views/BudgetsView.swift` → partial (`BudgetsViewTests.swift` covers move via inlined algorithm)
- `Views/CarryOverChip.swift` → none (the underlying `CarryOverFormatter` is tested)
- `Views/Color+Money.swift` → none
- `Views/CurrencyPickerView.swift` → partial (`CurrencyPickerTests.swift` covers `displayName` + a mirrored filter)
- `Views/RemainingBar.swift` → none (decorative; `accessibilityHidden(true)`)
- `Views/RootView.swift` → none
- `Views/SettingsView.swift` → partial (`SettingsViewTests.swift` covers picker write path, week-start confirmation logic by mirroring, and the `accountStatus -> rowState` half of the iCloud notification chain)
- `Views/View+AppBackground.swift` → none

### `Previews/`

- `Previews/BudgetDetailFixtures.swift` → none (preview-only; reasonable to skip)
- `Previews/InMemoryModelContainer.swift` → none (preview-only; reasonable to skip)
- `Previews/PreviewContainer.swift` → none (preview-only; reasonable to skip)

---

## Appendix B — Feature ID -> covering tests

- **F-1.01 App Scaffolding** — covered by build success.
- **F-1.02 Data Architecture** — `ModelTests.ModelContainerTests`, `ModelTests.BudgetModelTests`, `ModelTests.ExpenseItemModelTests`.
- **F-2.01 Budgets screen** — partial: `BudgetsViewTests.BudgetsViewMoveTests` (drag-to-reorder algorithm). Empty-state, `@Query` rendering, toolbar wiring uncovered.
- **F-2.02 Budget screen** — partial: `BudgetDetailViewActionsTests` (reset, delete-expense), `ExpenseItemPartitionTests` (period-aware sections). Status header, lifecycle-refresh triggers, swipe-to-delete wiring, VoiceOver header labels uncovered.
- **F-2.03 Add/Edit Budget screen** — `AddEditBudgetViewModelTests` (full); `CurrencyPickerTests` (partial picker integration).
- **F-2.04 Add/Edit/View Expense Item screen** — `AddEditExpenseViewModelTests` (full).
- **F-2.05 Settings screen** — partial: `SettingsViewTests` (currency display picker, week-start confirmation logic mirrored, iCloud row-state half). Support / About sections uncovered.
- **F-2.06 First-run empty state** — none.
- **F-2.07 Carry-over toggle** — `AppSettingsTests` (default key); `AddEditBudgetViewModelTests` (per-budget toggle).
- **F-3.01 Dynamic Type** — none.
- **F-3.02 VoiceOver** — none (composed labels exist but are not asserted).
- **F-3.03 Internationalization of text** — partial via `FormattersTests`, `CurrencyDisplayPreferenceTests`; no direct string-catalog assertions.
- **F-3.04 Internationalization of currency** — `CurrencyDisplayPreferenceTests` (4 locales), `FormattersTests` (USD/EUR/JPY/SAR).
- **F-3.05 Dark Mode** — none.
- **F-5.01 Configurable start of week** — partial: `AppSettingsTests` (persistence). Period math fixed-UTC only; non-default-week-start production behavior uncovered.
- **F-6.01 Allow manually adding funds** — `ModelTests.ExpenseItemModelTests` (`isAddFunds`, `displayAmount`); `AddEditExpenseViewModelTests` (sign preservation).
- **F-6.02 Expense Type** — none (schema-only feature).
- **F-6.03 / F-7.01 / F-7.02 / F-7.03** — open features; no tests expected.
