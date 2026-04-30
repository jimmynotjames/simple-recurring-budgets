# Budget lifecycle

Orchestrates eager carry-over roll, scheduled reset, persistence, and display-ready remaining/period window for a `Budget`, binding `BudgetCalculator` output to SwiftData via a single entry point. Synced from change `budget-lifecycle-service` (2026-04-17).

## Requirements

### Requirement: Eager refreshAndSave entry point

> [!NOTE]
> **PAUSED (Reset Cadences) — partial.** The roll-and-remaining behavior of `refreshAndSave` is fully active. The **scheduled-reset** step (3 and 4 below) remains in code and is still tested at the unit level for correctness, but in practice it is a no-op for any `Budget` created while the Reset Cadences feature is paused (default `resetCadence = .never`). **Do not surface scheduled-reset configuration in UI, plans, or new specs while paused.**

The system SHALL provide a `BudgetLifecycleService.refreshAndSave(_:settings:context:now:calendar:)` entry point that, given a `Budget`, the app's `AppSettings`, and a `ModelContext`, executes the PRD §6.7 / tech-design §5.4 sequence in this strict order:

1. Roll carry-over across any completed periods since `Budget.carryOverLastProcessedDate`.
2. Write the resulting `carryOverAmount` and `carryOverLastProcessedDate` back onto the `Budget` when either value changed.
3. Check for a scheduled reset against `Budget.carryOverLastResetDate` and `Budget.resetCadence`. **(PAUSED at the product level — for new budgets `resetCadence` is `.never`, so this step returns no-reset.)**
4. If a reset boundary has been crossed, zero `Budget.carryOverAmount` and write the new `carryOverLastResetDate`. **(PAUSED at the product level — does not fire for new budgets.)**
5. Compute `remaining` for the current budget period.

All time-dependent inputs (`now`, `calendar`) SHALL be parameters with production defaults (`Date()`, `Calendar.autoupdatingCurrent`) so that tests can inject deterministic values.

The biweekly anchor used for period math SHALL be derived on each call as the most recent occurrence of `AppSettings.weekStartDay` at or before `Budget.createdAt` (no new persisted field).

#### Scenario: Parameters and ordering

- **WHEN** `BudgetLifecycleService.refreshAndSave` is called with a budget, app settings, a model context, a fixed `now`, and a fixed calendar
- **THEN** the service calls `BudgetCalculator.rollCarryOver` with inputs derived from the budget and settings, applies its result to the budget before invoking `BudgetCalculator.checkScheduledReset`, and computes `remaining` last

#### Scenario: Biweekly anchor derivation

- **WHEN** the budget's period is biweekly, `Budget.createdAt` is Wednesday 2026-04-01, and `AppSettings.weekStartDay` is Sunday
- **THEN** the service passes Sunday 2026-03-29 as the biweekly anchor into `BudgetCalculator` calls

#### Scenario: Default-cadence budget never schedules a reset (Reset Cadences paused)

- **WHEN** a Budget is created via `Budget.init` without an explicit `resetCadence` (so `resetCadence` persists as `"never"`) and `refreshAndSave` is called any number of times
- **THEN** `BudgetCalculator.checkScheduledReset` SHALL return a no-reset result, the service SHALL NOT zero `carryOverAmount` from a scheduled reset, and `carryOverLastResetDate` SHALL NOT advance from a scheduled reset.

### Requirement: Single write-back path from calculator results to Budget

The system SHALL be the only code path that writes `Budget.carryOverAmount`, `Budget.carryOverLastProcessedDate`, and `Budget.carryOverLastResetDate` from calculator results. ViewModels SHALL consume the returned `BudgetLifecycleResult` rather than calling `BudgetCalculator.rollCarryOver` or `BudgetCalculator.checkScheduledReset` directly for the eager access flow.

#### Scenario: Roll result persisted to Budget

- **WHEN** `BudgetCalculator.rollCarryOver` returns a new `amount` and `lastProcessedDate` that differ from the budget's current stored values
- **THEN** the service writes both values to `Budget.carryOverAmount` and `Budget.carryOverLastProcessedDate` before returning

#### Scenario: Reset result persisted to Budget

- **WHEN** `BudgetCalculator.checkScheduledReset` returns `shouldReset: true` with a `newResetDate`
- **THEN** the service sets `Budget.carryOverAmount` to 0, sets `Budget.carryOverLastResetDate` to `newResetDate`, and leaves `Budget.carryOverLastProcessedDate` as written by the roll step

### Requirement: Single save per refreshAndSave, only when state changed

The system SHALL call `ModelContext.save()` at most once per `refreshAndSave` invocation, and SHALL NOT call `save()` when no carry-over field on the budget changed. When any carry-over field changes, the system SHALL also update `Budget.lastModified` to `now` in the same save.

Errors from `save()` SHALL be handled non-throwing (logged or dropped); the in-memory `Budget` SHALL retain the correct computed values so that display is unaffected.

#### Scenario: No boundary crossed, no save

- **WHEN** `carryOverLastProcessedDate` is within the current period, no reset boundary has been crossed since `carryOverLastResetDate`, and no carry-over field would change
- **THEN** the service does not call `context.save()`, does not bump `Budget.lastModified`, and returns a result whose `carryOverAmount` equals the budget's current value

#### Scenario: Roll-only triggers a single save and lastModified bump

- **WHEN** the roll step changes `carryOverAmount` or `carryOverLastProcessedDate` but no reset boundary has been crossed
- **THEN** the service updates those two fields, sets `Budget.lastModified` to `now`, and calls `context.save()` exactly once

#### Scenario: Reset-only triggers a single save and lastModified bump

- **WHEN** the roll step changes nothing but a scheduled reset boundary has been crossed
- **THEN** the service sets `carryOverAmount` to 0, updates `carryOverLastResetDate`, sets `Budget.lastModified` to `now`, and calls `context.save()` exactly once

#### Scenario: Roll then reset in the same refreshAndSave persists a single coherent state

- **WHEN** a full period has completed (roll changes `carryOverAmount`) and a reset boundary has also been crossed in the same window
- **THEN** the service first applies the rolled `carryOverAmount` and `carryOverLastProcessedDate`, then zeros `carryOverAmount` and updates `carryOverLastResetDate`, then calls `context.save()` exactly once with `Budget.lastModified` set to `now`

### Requirement: `BudgetLifecycleResult` returned for display

The system SHALL return a `BudgetLifecycleResult` value with the following fields:

- `remaining: Decimal` — the current period's remaining amount computed after any roll/reset mutations.
- `carryOverAmount: Decimal` — the budget's carry-over amount after `refreshAndSave` (post-roll, post-reset). The value matches `Budget.carryOverAmount` in the same transaction.
- `periodStart: Date` — the start of the current budget period (inclusive).
- `periodEnd: Date` — the start of the next budget period (exclusive upper bound for the current period).

#### Scenario: Result reflects persisted state

- **WHEN** the service has applied a roll and a reset and saved the context
- **THEN** the returned `BudgetLifecycleResult.carryOverAmount` equals `Budget.carryOverAmount` and `BudgetLifecycleResult.remaining` equals `allocation − sum(expenses in [periodStart, periodEnd))`

#### Scenario: Remaining is independent of carry-over

- **WHEN** the budget has a non-zero carry-over amount after `refreshAndSave`
- **THEN** `BudgetLifecycleResult.remaining` is computed only from this period's allocation and expenses (per PRD §6.7); it is not offset by `carryOverAmount`

#### Scenario: Remaining may be negative

- **WHEN** the sum of this period's expenses exceeds the allocation
- **THEN** `BudgetLifecycleResult.remaining` is negative

### Requirement: Multi-period catch-up applies through the same single-save path

The system SHALL correctly handle catch-up scenarios where multiple period boundaries, or multiple reset cadence intervals, have elapsed since the last access. All accumulation SHALL occur before the single `save()`, and `carryOverLastProcessedDate` / `carryOverLastResetDate` SHALL be advanced to the latest applicable boundary at or before `now`.

#### Scenario: Multiple periods catch up in one call

- **WHEN** `carryOverLastProcessedDate` is three complete periods before `now` and no reset applies
- **THEN** the service folds in all three completed periods via `rollCarryOver`, writes the resulting `carryOverAmount` and advanced `carryOverLastProcessedDate`, and calls `context.save()` exactly once

#### Scenario: Multiple reset cadences skipped in one call

- **WHEN** `carryOverLastResetDate` is several reset cadences before `now` (e.g., a daily budget with weekly reset cadence that has not been opened for multiple weeks)
- **THEN** the service advances `carryOverLastResetDate` to the most recent applicable period boundary at or before `now` and persists a single zeroed `carryOverAmount`

### Requirement: Screen / ViewModel consumption contract

Screens (and any escalated ViewModels per `docs/tech-design-doc.md` §2.1) SHALL call `refreshAndSave` eagerly on budget access — at minimum on screen appearance and on `scenePhase == .active` — and MAY call it after mutations that could affect current-period display. Screens that have not escalated to a ViewModel invoke `refreshAndSave` directly from the view body / `.task` using `@Environment(\.modelContext)` and the injected `AppSettings`. Screens that have escalated to a ViewModel expose a method taking `(settings: AppSettings, context: ModelContext, ...)` at the call site and forward to the service.

Screens and ViewModels SHALL treat the returned `BudgetLifecycleResult` as the source of truth for current-period display values rather than recomputing them. Neither screens nor ViewModels SHALL call `BudgetCalculator.rollCarryOver` or `checkScheduledReset` directly for the eager access flow — `BudgetLifecycleService` is the single entry point for that sequence.

#### Scenario: Screen calls refreshAndSave on screen appearance

- **WHEN** a Budgets or Budget screen becomes visible
- **THEN** the screen (or its ViewModel) calls `BudgetLifecycleService.refreshAndSave` for each displayed budget and binds the returned `BudgetLifecycleResult` values to the view

#### Scenario: Screen calls refreshAndSave on scene activation

- **WHEN** the app transitions to `scenePhase == .active` while a budget is displayed
- **THEN** the screen (or its ViewModel) calls `BudgetLifecycleService.refreshAndSave` so any period or reset boundaries crossed while inactive are applied before the next frame
