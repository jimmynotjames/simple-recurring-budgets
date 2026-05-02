## 1. Pre-flight

- [x] 1.1 Re-skim [`docs/main-prd.md`](../../../docs/main-prd.md) §6.3, [`docs/product-features-planning.md`](../../../docs/product-features-planning.md) F-8.01, [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §7, and [`docs/analytics-spec.md`](../../../docs/analytics-spec.md) §17 to confirm no doc has shifted since the proposal was written.
- [x] 1.2 Confirm `simple-recurring-budgets/Logging/AppLoggers.swift` still defines exactly `Logger.bootstrap`, `Logger.cloudKit`, `Logger.ui` keyed off the bundle subsystem; no rename needed.
- [x] 1.3 Confirm the four existing `Logger.cloudKit` call sites in `simple_recurring_budgetsApp.makeProductionModelContainer` are unchanged (`backed`, `localFallback`, `localSuccess`, `failed`).

## 2. Bootstrap launch-mode log site

- [x] 2.1 In `simple-recurring-budgets/App/simple_recurring_budgetsApp.swift`, add a single `Logger.bootstrap.info` call from `init()` after `makeModelContainer()` returns, recording the resolved `appDatabaseLaunchMode` (Release: always `.normal`; DEBUG: the active dev-override case). Use a stable message prefix (`"bootstrap.launchMode: <case>"`) and `privacy: .public` for the interpolated case name.
- [x] 2.2 Verify the line emits exactly once per launch by reading the unified log via Console.app filtered on subsystem + `category:bootstrap` during a manual smoke pass.

## 3. CloudKit account-status transition log site

- [x] 3.1 In `simple-recurring-budgets/Views/SettingsView.swift`, modify `loadICloudStatus()` so that after `syncStatus.accountStatus` is updated, a `Logger.cloudKit.notice` is emitted only when the new value differs from the previous value. Interpolate both the old and new `AccountStatus` case names at `privacy: .public`. Use a stable message prefix (`"cloudkit.account.transition: <old> → <new>"`).
- [x] 3.2 Confirm no log line is emitted when `loadICloudStatus()` re-resolves to the same value.
- [x] 3.3 Confirm both code paths into `loadICloudStatus()` (initial `.task` load and the `observeAccountChanges()` notification group) flow through the same transition guard so duplication is impossible.

## 4. UI destructive-action log sites

- [x] 4.1 In `simple-recurring-budgets/Views/BudgetDetailView.swift`, add `Logger.ui.debug` inside `resetBudget()` recording `budget.persistentModelID` at `privacy: .private` and the static action name `"resetBudget"` at `privacy: .public`.
- [x] 4.2 In the same file, add `Logger.ui.debug` inside `resetCarryOver()` with the same shape and action name `"resetCarryOver"`.
- [x] 4.3 In `simple-recurring-budgets/Views/AddEditBudgetViewModel.swift`, add `Logger.ui.debug` inside `delete(context:)` recording `budget.persistentModelID` at `privacy: .private` and action name `"deleteBudget"` at `privacy: .public`.
- [x] 4.4 In `simple-recurring-budgets/Views/BudgetDetailView+ExpenseSection.swift`, add `Logger.ui.debug` inside `deleteExpense(_:)` recording `expense.persistentModelID` at `privacy: .private` and action name `"deleteExpense"` at `privacy: .public`. Do NOT add a separate log line at the swipe-action or rotor-action call sites — both paths already funnel through `deleteExpense(_:)`.
- [x] 4.5 Confirm no other view, viewmodel, or service emits a `Logger.ui` line in this change. Phase 1 is destructive-only.

## 5. Privacy-argument audit

- [x] 5.1 Grep the codebase for `Logger\.` interpolations and confirm every interpolated value (`\(...)`) carries an explicit `privacy:` argument. Static literals without interpolation are exempt. Fix any drift discovered.

## 6. Tests

- [x] 6.1 Create `simple-recurring-budgetsTests/Logging/AppLoggersTests.swift` with a Swift Testing suite asserting that `Logger.bootstrap`, `Logger.cloudKit`, and `Logger.ui` exist and that `AppLoggers.swift` defines exactly those three constants. Test the `subsystem` and `category` strings indirectly (e.g., by referencing the constants and asserting they are non-equal `Logger` values; `os.Logger` does not expose its `subsystem`/`category` for direct read-back, so this is a structural existence test).
- [x] 6.2 Create `simple-recurring-budgetsTests/Logging/AnalyticsClientLoggerBoundaryTests.swift` asserting that no method on `AnalyticsClient` (or its concrete implementations `ConsoleAnalyticsClient`, `SpyAnalyticsClient`, and `MixpanelAnalyticsClient` if present) takes an `os.Logger`, `OSLogEntry`, `OSLogEntryLog`, or `OSLogMessage` parameter. Implementation: verify by exercising the existing protocol surface (`track`, `identify`, `reset`) and asserting a hand-curated allow-list of method signatures matches the actual surface; failing gracefully if a new method is added without updating this test.
- [x] 6.3 Run `make format && make lint-fix && make build && make test` per [`AGENTS.md` > Build and test](../../../AGENTS.md). All four steps MUST pass.

## 7. Doc updates

- [x] 7.1 Update [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §7: confirm the three categories (`bootstrap`, `cloudkit`, `ui`) match `AppLoggers.swift` end-to-end; add a one-line cross-reference to [`docs/analytics-spec.md`](../../../docs/analytics-spec.md) §17 for the boundary contract; bump the revision history table at the bottom.
- [x] 7.2 Update [`docs/product-features-planning.md`](../../../docs/product-features-planning.md) F-8.01: flip `**Status:**` from "Partially implemented" to "**Implemented.** Implemented by change `oslog-diagnostic-logging`." Bump the version + date in the file header. Leave Acceptance Criteria, Edge Cases / Notes, and Dependencies untouched.
- [x] 7.3 Update [`docs/analytics-spec.md`](../../../docs/analytics-spec.md): in §19 mark the "F-8.01 ships" row as done (e.g., add a checkmark or strike through, matching whatever convention this doc adopts; if no convention exists yet, add a short "(done by `oslog-diagnostic-logging`)" suffix). Bump the revision history.
- [x] 7.4 Confirm no other `docs/*.md` file needs an update: `main-prd.md` is unchanged; `ux-design-brief.md` is unchanged; `product-features-planning.md` only changes F-8.01 status.

## 8. Verify and archive readiness

- [x] 8.1 Run `openspec verify --change oslog-diagnostic-logging` (or the equivalent skill) to confirm specs, design, tasks, and proposal are consistent.
- [x] 8.2 Confirm via manual review that every Acceptance Criterion in F-8.01 has a corresponding requirement in `specs/diagnostic-logging/spec.md` and at least one task in §§2–4 of this file.
- [x] 8.3 Mark all tasks above complete and proceed to OpenSpec archive. The archive step should not need additional doc-drift work because §7 was completed in this change.
