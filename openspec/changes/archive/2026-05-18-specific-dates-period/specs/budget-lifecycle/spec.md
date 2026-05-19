## MODIFIED Requirements

### Requirement: Allocation edit write-path

The system SHALL provide `BudgetLifecycleService.applyAllocationEdit(_ budget: Budget, newAmount: Decimal, context: ModelContext, now: Date, calendar: Calendar)` for view sites that change a budget's allocation in Edit mode. The method SHALL implement the algorithm doc §A.6.2 insert-or-mutate convention with a period-type carve-out for `.specificDates`:

**For recurring periods (`.daily`, `.weekly`, `.biweekly`, `.monthly`):**

1. Compute `currentPeriodStart` for the budget using its `RecurringBudgetPeriod`.
2. If an `AllocationChange` row already exists with `effectiveFrom == currentPeriodStart`, update its `amount` to `newAmount` and bump its `lastModified = now`.
3. Otherwise, insert a new `AllocationChange(effectiveFrom: currentPeriodStart, amount: newAmount, lastModified: now)` linked to the budget.
4. Bump `Budget.lastModified = now`.
5. Call `context.save()` exactly once.

The method SHALL NOT mutate any other `AllocationChange` row for recurring periods. Prior periods continue to consult their historical allocations via `allocationInEffect` (forward-only semantics per F-2.03).

**For `.specificDates` (latest-wins whole-window overwrite, per F-2.08):**

1. Locate the most-recent `AllocationChange` for the budget by `(effectiveFrom, lastModified)`. For a `.specificDates` budget this is always the initial row inserted at budget creation (with `effectiveFrom == Budget.startDate`).
2. If that row's `amount != newAmount`, write `amount = newAmount` and `lastModified = now`. If the amount is unchanged, no row mutation occurs and the method SHALL be a no-op.
3. SHALL NOT insert a new `AllocationChange` row — `.specificDates` has only one period (the entire window) and there is no audit-trail requirement (the prior figure is not retrievable per F-2.08).
4. When a write occurred, bump `Budget.lastModified = now` and call `context.save()` exactly once. When the amount was unchanged, do not bump `lastModified` or save.

This `.specificDates` branch is the documented exception to the forward-only allocation-edit rule that applies to recurring periods.

#### Scenario: First allocation edit in the current period inserts a new row (recurring)

- **WHEN** the budget has a single `AllocationChange(effectiveFrom: startDate, amount: 20.00)` and the user changes allocation to 25.00 mid-period for a `.daily` budget
- **THEN** a new `AllocationChange(effectiveFrom: currentPeriodStart, amount: 25.00, lastModified: now)` is inserted, `Budget.lastModified = now`, and `context.save()` is called once

#### Scenario: Repeated edits in the same period mutate the existing row (recurring)

- **WHEN** an `AllocationChange` already exists with `effectiveFrom == currentPeriodStart` and the user changes the allocation again for a `.daily` budget
- **THEN** the existing row's `amount` is overwritten with the new value, its `lastModified` is bumped, no new row is inserted, `Budget.lastModified = now`, and `context.save()` is called once

#### Scenario: Prior periods are unaffected (recurring)

- **WHEN** the user changes the allocation in the current period of a recurring budget
- **THEN** no `AllocationChange` row whose `effectiveFrom < currentPeriodStart` is mutated, and the walker continues to use the historical amounts for those periods

#### Scenario: Specific Dates allocation edit overwrites the single row

- **WHEN** the budget is `.specificDates` with `startDate = 2026-05-08`, `endDate = 2026-05-25`, a single `AllocationChange(effectiveFrom: 2026-05-08, amount: 1500.00, lastModified: 2026-05-07)`, and the user changes allocation to 1800.00 mid-window at `now = 2026-05-15`
- **THEN** the existing row's `amount` is overwritten to 1800.00, `lastModified` is bumped to `now`, no new `AllocationChange` row is inserted, `Budget.lastModified = now`, and `context.save()` is called once

#### Scenario: Specific Dates no-op edit does not write

- **WHEN** the budget is `.specificDates` with a single `AllocationChange(amount: 1500.00)` and the user "edits" the allocation to the same value 1500.00
- **THEN** no `AllocationChange` row is mutated, `Budget.lastModified` is NOT bumped, and `context.save()` is NOT called

#### Scenario: Specific Dates edit does not preserve audit history

- **WHEN** the user edits a `.specificDates` budget's allocation from 1500.00 to 1800.00 and later to 2000.00
- **THEN** the store contains exactly one `AllocationChange` row whose `amount` is 2000.00; the prior figures (1500.00, 1800.00) are not retrievable (per F-2.08, latest-wins is the documented exception to the recurring forward-only rule)
