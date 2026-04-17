## Why

The pure `BudgetCalculator` (`Domain/BudgetCalculator.swift`) deliberately has no SwiftData dependency: it returns `CarryOverRollResult` and `ResetCheckResult` values but never mutates a `Budget`. Per tech-design §5.4, every Budgets/Budget screen ViewModel must perform the exact same ordered sequence on access — roll carry-over, persist, check scheduled reset, persist, then compute remaining for display. Duplicating that orchestration across ViewModels risks subtle drift (wrong ordering, missing `lastModified` bumps, forgetting to stamp `carryOverLastProcessedDate`) and makes the §6.7 contract hard to test end-to-end. We need one place that knows how to turn the pure-math results into persisted state.

## What Changes

- **New `BudgetLifecycleService`** in `Domain/` (stateless `enum` namespace, matching the existing calculator pattern) — takes a `Budget`, `AppSettings`, `ModelContext`, `now`, and `Calendar`, and runs the §5.4 sequence in order:
  1. Derive inputs from the budget (`period`, `resetCadence`, `expenseItems`, `carryOver*` fields, biweekly anchor).
  2. Call `BudgetCalculator.rollCarryOver(...)`; write `carryOverAmount` and `carryOverLastProcessedDate` back onto the `Budget` when either changed.
  3. Call `BudgetCalculator.checkScheduledReset(...)`; when `shouldReset` is true, zero `carryOverAmount` and write the new `carryOverLastResetDate`.
  4. Bump `Budget.lastModified` only when any of the above fields actually changed, and save the `ModelContext` once (a single save per `refreshAndSave`, not per step).
  5. Compute `remaining` for the current period and return a `BudgetLifecycleResult` with `remaining: Decimal`, `carryOverAmount: Decimal`, `periodStart: Date`, and `periodEnd: Date` — the exact values a VM needs for display.
- **New result type** — `BudgetLifecycleResult` in the same file, exposing the current-period window alongside the freshly persisted numbers so callers don't re-derive them.
- **ViewModel contract** — Budgets/Budget VMs call `BudgetLifecycleService.refreshAndSave` once eagerly on budget access (and optionally on `scenePhase == .active`). No VM reaches directly into `BudgetCalculator` for the roll/reset orchestration anymore; they consume the lifecycle result.
- **No schema changes** — reads and writes the existing `carryOverAmount`, `carryOverLastProcessedDate`, `carryOverLastResetDate`, and `lastModified` fields on `Budget`. Uses `AppSettings.weekStartDay` as the week-start input.

## Capabilities

### New Capabilities

- `budget-lifecycle`: Orchestrates the roll → persist → reset → persist → compute-remaining sequence on a `Budget` using pure `BudgetCalculator` outputs. Owns the single write-back path from calculator results to SwiftData, including `lastModified` bumping and `ModelContext` saves.

### Modified Capabilities

_(none — `budget-math` remains pure; this change only adds a new orchestration layer on top of it.)_

## Impact

- **New files in `Domain/`**: `BudgetLifecycleService.swift` (service + `BudgetLifecycleResult` struct).
- **New test file**: `simple-recurring-budgetsTests/Domain/BudgetLifecycleServiceTests.swift` — uses the existing in-memory `ModelContainer` helper to assert persisted fields after each branch (no roll, roll only, reset only, roll-then-reset, multi-period catch-up).
- **No changes to `Budget`, `ExpenseItem`, or the SwiftData schema.**
- **No changes to `BudgetCalculator` or `PeriodCalculator`** — they remain pure; the service consumes their existing APIs.
- **ViewModels (future screen changes for F-2.01 / F-2.02)** will depend on this service instead of calling `BudgetCalculator` directly for the roll+reset sequence. Those screens are not part of this change.
- **Doc update needed**: `docs/tech-design-doc.md` — extend §5.4 to reference the lifecycle service as the sole writer of carry-over fields, and describe the ViewModel consumption contract.

## Doc alignment

- **Aligned** with `docs/main-prd.md` §6.7 — implements the "roll at period boundary, then scheduled reset aligned to period boundaries, both per-budget" contract without introducing new display rules.
- **Aligned** with `docs/tech-design-doc.md` §3.2 (Over/Under bookkeeping: eager roll + scheduled reset on access) and §5.4 (`rollCarryOver` then `checkScheduledReset` eagerly on budget access, then `remaining` for display).
- **Aligned** with `docs/tech-design-doc.md` §5.3 — keeps all math pure in `BudgetCalculator`; this service is the narrow, testable seam that binds results to SwiftData.
- **Doc update after implementation**: `docs/tech-design-doc.md` §5.4 — add the lifecycle service as the single orchestrator of the eager sequence; note that ViewModels do not call `rollCarryOver` / `checkScheduledReset` directly.
