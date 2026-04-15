## Why

The carry-over logic in PRD §6.7 is the most complex business logic in the app: period boundary detection, multi-period catch-up rolls, scheduled resets aligned to period boundaries, and "remaining for current period" — all needed by both F-2.01 (Budgets screen) and F-2.02 (Budget screen). The tech design doc §5.3 mandates this logic live in "pure, testable services with no SwiftData/UI dependencies." Without a shared calculator layer, this math will be duplicated across ViewModels and become hard to test correctly.

## What Changes

- **New `PeriodCalculator` struct** — Pure date math: given a date, `BudgetPeriod`, `Weekday` (week start), and `Calendar`, compute the current period's start/end and enumerate all period boundaries between two dates. Biweekly periods are anchored to the most recent week-start day at or before the budget's creation date (derived from existing fields; no new stored data).
- **New `BudgetCalculator` struct** — Financial math built on `PeriodCalculator`: compute "remaining for current Budget Period" (allocation minus this-period expenses only, per §6.7), roll carry-over across one or more completed periods, and detect scheduled reset boundaries.
- **New result types** — `CarryOverResult` (new amount + last-processed date) and `ResetCheckResult` (should reset + new reset date) so callers get all the data they need to write back to the model.
- **Comprehensive unit tests** — Cover daily/weekly/biweekly/monthly periods, multi-period catch-up, reset cadence boundaries, edge cases (no expenses, over-spending, negative carry-over, week-start variations).

## Capabilities

### New Capabilities

- `budget-math`: Period boundary detection, remaining-for-current-period calculation, carry-over roll (including multi-period catch-up), and scheduled carry-over reset detection — all as pure functions with no SwiftData or UI dependencies.

### Modified Capabilities

_(none)_

## Impact

- **New files in `Domain/`** (or `Services/`): `PeriodCalculator.swift`, `BudgetCalculator.swift`, result types.
- **New test files**: `PeriodCalculatorTests.swift`, `BudgetCalculatorTests.swift` — no `ModelContainer` needed; all inputs are plain values and dates.
- **No changes to existing models**, UI, or persistence. The `Budget` and `ExpenseItem` `@Model` classes remain untouched; ViewModels will call through to the calculator when screens are built later.
- **Doc update needed**: `docs/tech-design-doc.md` should be updated to document the new service layer (where it lives, its public API contract, and how ViewModels will consume it).

## Doc alignment

- **Aligned** with `docs/main-prd.md` §6.7 — all carry-over rules (period boundary roll, scheduled reset, manual reset, display as separate number from remaining) are implemented by this service.
- **Aligned** with `docs/tech-design-doc.md` §5.3 — "Business logic (budget math, Over/Under rolls, date boundaries) lives in pure, testable services with no SwiftData/UI dependencies."
- **Aligned** with `docs/tech-design-doc.md` §3.2 — Over/Under bookkeeping (eager roll on app launch/budget access, scheduled reset, manual reset).
- **Doc update after implementation**: `docs/tech-design-doc.md` — add a section documenting the `PeriodCalculator` / `BudgetCalculator` service layer, its public API, and the biweekly anchor convention.
