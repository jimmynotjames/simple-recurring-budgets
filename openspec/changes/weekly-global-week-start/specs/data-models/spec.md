# data-models delta — weekly-global-week-start

## MODIFIED Requirements

### Requirement: Initial AllocationChange row on Budget creation

The system SHALL ensure that every user-created Budget has at least one `AllocationChange` row inserted in the same `ModelContext.save()` as the Budget itself. The row SHALL be:

- `effectiveFrom = budget.startDate` (the value computed by the Add-mode save path).
- `amount = the allocation value the user entered in the Add flow`.
- `lastModified = now`.
- `budget = the newly-created Budget`.

The `startDate` computed at Add time SHALL be derived per period type (briefing §2.4). For weekly/biweekly budgets the default aligns to the user's `AppSettings.weekStartDay` so a freshly-created budget starts at a natural grid/cycle boundary — for weekly this is a convenience default (the weekly grid itself is global per the `budget-math` capability and a mid-grid `startDate` merely clips the first period); for biweekly the saved `startDate` is the cycle anchor:

- **Daily**: `calendar.startOfDay(for: createdAt)`.
- **Weekly / biweekly**: most recent `AppSettings.weekStartDay`-aligned date at or before `calendar.startOfDay(for: createdAt)`.
- **Monthly**: start of the calendar month containing `createdAt`.
- **Specific Dates**: N/A in this change (no UI exposes this period type yet); when a future UI ships, `startDate` is user-entered.

All four computed values are start-of-day-aligned, so the initial row's `effectiveFrom` matches the storage convention used by `allocationInEffect` (algorithm doc §A.6.1) exactly.

#### Scenario: Daily budget initial allocation row

- **WHEN** the user creates a daily budget at `createdAt = 2026-04-15 14:30 UTC` with allocation 20.00
- **THEN** the Budget's `startDate` is 2026-04-15 00:00 (calendar-local) and an AllocationChange row exists with `effectiveFrom = 2026-04-15 00:00, amount = 20.00`

#### Scenario: Weekly budget default start aligns to AppSettings.weekStartDay

- **WHEN** the user creates a weekly budget on Wednesday 2026-04-15 with `AppSettings.weekStartDay = .sunday` and allocation 100.00
- **THEN** the Budget's `startDate` is Sunday 2026-04-12 and the initial AllocationChange row has `effectiveFrom = 2026-04-12 00:00, amount = 100.00`

#### Scenario: Monthly budget anchors on the calendar month

- **WHEN** the user creates a monthly budget on 2026-04-15 with allocation 500.00
- **THEN** the Budget's `startDate` is 2026-04-01 and the initial AllocationChange row has `effectiveFrom = 2026-04-01 00:00, amount = 500.00`
