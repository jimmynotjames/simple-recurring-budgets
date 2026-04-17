## 1. Result Type

- [x] 1.1 Create `Domain/BudgetLifecycleService.swift` and add a `BudgetLifecycleResult` struct with `remaining: Decimal`, `carryOverAmount: Decimal`, `periodStart: Date`, `periodEnd: Date`.

## 2. Service — Implementation

- [x] 2.1 Add a caseless `enum BudgetLifecycleService` in the same file with a single entry point: `@discardableResult static func refreshAndSave(_ budget: Budget, settings: AppSettings, context: ModelContext, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> BudgetLifecycleResult`.
- [x] 2.2 Compute the biweekly anchor inline from `budget.createdAt` + `settings.weekStartDay` (most recent `weekStartDay` at or before `createdAt`); factor into a private helper if it aids readability.
- [x] 2.3 Parse `budget.period` and `budget.resetCadence` from their stored raw-string values to `BudgetPeriod` / `ResetCadence` (guard and early-return with a computed-only `BudgetLifecycleResult` if either cannot be parsed — unexpected, should not happen).
- [x] 2.4 Call `BudgetCalculator.rollCarryOver(...)` with `currentAmount: budget.carryOverAmount`, `allocation: budget.allocation`, `expenses: budget.expenseItems`, `lastProcessedDate: budget.carryOverLastProcessedDate`, `now`, parsed period, `settings.weekStartDay`, the biweekly anchor, and `calendar`.
- [x] 2.5 When the roll result's `amount` or `lastProcessedDate` differs from the budget's stored values, assign them to `budget.carryOverAmount` and `budget.carryOverLastProcessedDate` and set a `didChange` flag.
- [x] 2.6 Call `BudgetCalculator.checkScheduledReset(...)` with `lastResetDate: budget.carryOverLastResetDate`, parsed `resetCadence`, `now`, parsed period, `settings.weekStartDay`, the biweekly anchor, and `calendar`.
- [x] 2.7 When the reset result's `shouldReset` is true and `newResetDate` is non-nil, set `budget.carryOverAmount = 0`, `budget.carryOverLastResetDate = newResetDate`, and set `didChange`.
- [x] 2.8 If `didChange`, set `budget.lastModified = now` and call `try? context.save()` exactly once (use `try?` to swallow errors; add a debug log if the project has a standard logger).
- [x] 2.9 Compute `periodStart` / `periodEnd` via `PeriodCalculator` using the parsed period, `settings.weekStartDay`, the biweekly anchor, and `calendar`.
- [x] 2.10 Compute `remaining` via `BudgetCalculator.remaining(allocation: budget.allocation, expenses: budget.expenseItems, periodStart: periodStart, periodEnd: periodEnd)`.
- [x] 2.11 Return a `BudgetLifecycleResult` populated with the post-`refreshAndSave` `budget.carryOverAmount`, `remaining`, `periodStart`, and `periodEnd`.

## 3. Tests — Setup

- [x] 3.1 Create `simple-recurring-budgetsTests/Domain/BudgetLifecycleServiceTests.swift` using Swift Testing.
- [x] 3.2 Reuse the existing in-memory `ModelContainer` helper in `simple-recurring-budgetsTests/Helpers/` for `Budget` + `ExpenseItem` setup.
- [x] 3.3 Use a fixed UTC `Calendar` and a fixed `now` across tests for determinism.

## 4. Tests — No-op path

- [x] 4.1 Test that when `carryOverLastProcessedDate` is within the current period and no reset boundary has elapsed, `refreshAndSave` does not mutate any `carryOver*` field and does not bump `lastModified`.
- [x] 4.2 Test that the returned `BudgetLifecycleResult.remaining` equals `allocation − sum(expenses in current period)` and `BudgetLifecycleResult.carryOverAmount` equals the budget's existing `carryOverAmount`.

## 5. Tests — Roll-only path

- [x] 5.1 Daily budget: set `carryOverLastProcessedDate` to the start of yesterday; add yesterday's expenses that do not equal allocation; assert that `budget.carryOverAmount` and `budget.carryOverLastProcessedDate` are updated and `lastModified` is set to `now`.
- [x] 5.2 Weekly budget: set `carryOverLastProcessedDate` to the start of last week; add expenses spanning last week only; assert the rolled amount and advanced processed date match `BudgetCalculator.rollCarryOver` output.
- [x] 5.3 Multi-period catch-up: set `carryOverLastProcessedDate` three daily periods before `now`; provide distinct per-day expense totals; assert the accumulated `carryOverAmount` and that `carryOverLastProcessedDate` advances to the latest completed boundary in a single `save`.

## 6. Tests — Reset-only path

- [x] 6.1 Daily budget with weekly reset cadence: set `carryOverLastResetDate` to last week's start-of-week day; set `carryOverLastProcessedDate` to `now` (so no roll); assert `carryOverAmount` is zeroed and `carryOverLastResetDate` advances to the expected boundary.
- [x] 6.2 `never` cadence: assert `refreshAndSave` never changes `carryOverAmount` or `carryOverLastResetDate` regardless of elapsed time, and does not save.
- [x] 6.3 Long gap (multiple reset cadences skipped): set `carryOverLastResetDate` several cadences before `now`; assert `carryOverLastResetDate` advances to the most recent applicable boundary at or before `now`.

## 7. Tests — Roll-then-reset ordering

- [x] 7.1 Construct a scenario where both the roll step changes values and a scheduled reset fires in the same invocation; assert the roll is applied before the reset by inspecting the final `carryOverAmount` (0 after reset) and `carryOverLastProcessedDate` (advanced) and `carryOverLastResetDate` (advanced to the reset boundary).
- [x] 7.2 Assert that `context.save()` is called exactly once for this case (e.g., by asserting a single `lastModified == now` value with no intermediate value observed — acceptable proxy when direct save-count observation is not easy).

## 8. Tests — Save and lastModified semantics

- [x] 8.1 Assert that when no field changes, `budget.lastModified` is unchanged after `refreshAndSave`.
- [x] 8.2 Assert that when at least one field changes, `budget.lastModified == now` after `refreshAndSave`.
- [x] 8.3 Assert that `BudgetLifecycleResult.remaining` is computed independently of `carryOverAmount` (high carry-over does not reduce `remaining`).

## 9. Tests — Biweekly anchor

- [x] 9.1 Construct a budget with `createdAt` mid-week and assert the service derives the biweekly anchor as the most recent `AppSettings.weekStartDay` at or before `createdAt`, matching the `budget-math` spec's biweekly anchor scenario.

## 10. Documentation

- [x] 10.1 Update `docs/tech-design-doc.md` §5.4 to name `BudgetLifecycleService` as the sole orchestrator of the eager roll → persist → reset → persist → compute-remaining sequence, and clarify that ViewModels call the service rather than `BudgetCalculator` directly for that flow.
- [x] 10.2 Confirm no changes are needed in `docs/main-prd.md` (PRD §6.7 is already aligned) and `docs/product-features-planning.md` (no new F-x.xx introduced); confirmed: neither file requires updates for this change.
