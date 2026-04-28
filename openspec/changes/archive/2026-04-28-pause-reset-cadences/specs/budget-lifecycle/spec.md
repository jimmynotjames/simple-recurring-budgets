## MODIFIED Requirements

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
