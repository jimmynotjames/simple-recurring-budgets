## MODIFIED Requirements

### Requirement: Budget entity

The system SHALL define a SwiftData `@Model` class `Budget` with the following stored properties:

| Property                       | Type                       | Default                              | Notes                            |
| ------------------------------ | -------------------------- | ------------------------------------ | -------------------------------- |
| `id`                           | `UUID`                     | `UUID()`                             | Stable identity                  |
| `name`                         | `String`                   | `"Budget"`                           | Display name                     |
| `currencyCode`                 | `String`                   | Locale currency or `"USD"`           | ISO 4217 code                    |
| `period`                       | `String`                   | `BudgetPeriod.daily.rawValue`        | Stored as BudgetPeriod raw value |
| `sortOrder`                    | `Int`                      | `0`                                  | User-defined list ordering       |
| `createdAt`                    | `Date`                     | `Date()`                             | Immutable after creation         |
| `lastModified`                 | `Date`                     | `Date()`                             | Updated on every user-initiated mutation that affects math (see "Budget.lastModified write-site rule") |
| `startDate`                    | `Date?`                    | computed at save time (per-period-type rule) | Semantically always populated for a saved budget; stored as `Date?` only for CloudKit optionality. Read-path fallback: `createdAt` |
| `endDate`                      | `Date?`                    | `nil`                                | Genuinely optional for recurring; required by the Add/Edit Budget UI for `.specificDates` (per F-2.08 and the `add-edit-budget-screen` Save-validation rule) |
| `lastResetDate`                | `Date?`                    | `nil`                                | Last manual Reset Carry-Over or Reset Budget timestamp; `nil` means no manual reset has occurred. Renamed from `carryOverLastResetDate` |
| `isCarryOverEnabled`           | `Bool`                     | `true`                               | Carry-over toggle (F-2.07); ignored for `.specificDates` |
| `allocationChangesStorage`     | `[AllocationChange]?`      | `nil`                                | Stored as optional for CloudKit; use computed `allocationChanges` |
| `lifecycleEventsStorage`       | `[LifecycleEvent]?`        | `nil`                                | Stored as optional for CloudKit; use computed `lifecycleEvents` |
| `expenses`                     | `[ExpenseItem]?`           | `nil`                                | Stored as optional for CloudKit; use computed `expenseItems`     |

The following fields SHALL NOT exist on the `Budget` entity: `allocation`, `carryOverAmount`, `carryOverLastProcessedDate`, `resetCadence`. Allocation history is represented by the `AllocationChange` child entity; carry-over is computed live and never persisted; `resetCadence` is permanently removed.

All monetary values SHALL use `Decimal`, never floating-point types.

The `Budget` entity SHALL also expose non-optional computed accessors:

- `expenseItems: [ExpenseItem]` returning `expenses ?? []`
- `allocationChanges: [AllocationChange]` returning `allocationChangesStorage ?? []`
- `lifecycleEvents: [LifecycleEvent]` returning `lifecycleEventsStorage ?? []`

The `Budget` entity SHALL additionally expose two display-derived computed properties used by `BudgetsView` and `BudgetDetailView`:

- `periodDisplayLabel: String` — For recurring periods (`.daily`, `.weekly`, `.biweekly`, `.monthly`) returns `BudgetPeriod.listLabel`. For `.specificDates`, when both `startDate` and `endDate` are non-`nil`, returns the formatted date range produced by `Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)` applied to `startDate ..< endDate` (locale-aware, RTL-correct, and handles same-year vs year-crossing automatically). When either date is missing (defensive — should not happen for a saved `.specificDates` budget), falls back to `BudgetPeriod.listLabel` ("Specific Dates"). Used as the period label in list rows and screen headers.
- `periodInlineLabel: String` — For recurring periods returns `BudgetPeriod.inlineLabel` (e.g., "daily", "weekly"). For `.specificDates` returns a dedicated localized string (key `period.specificDates.inline.budgetRow` / `period.specificDates.inline.budgetDetail` as appropriate, English source: "in this window") so VoiceOver sentences read naturally for the non-recurring case. Used in the row/header VoiceOver labels.

Both computed properties are display concerns and have no effect on persistence, sync, or algorithm behaviour.

All app code SHALL use the computed accessors. The stored optional properties exist solely for CloudKit compatibility and SHALL NOT be accessed directly outside the model definition.

`Budget.init` SHALL NOT accept `allocation`, `carryOverAmount`, `carryOverLastProcessedDate`, or `resetCadence` parameters (those fields no longer exist). Callers SHALL insert an initial `AllocationChange(effectiveFrom: startDate, amount: enteredAllocation, lastModified: now)` in the same `ModelContext.save()` as the Budget insert (see "Initial AllocationChange row on Budget creation").

#### Scenario: Creating a Budget with defaults

- **WHEN** a Budget is initialized with no arguments
- **THEN** `id` SHALL be a new UUID, `period` SHALL be `"daily"`, `startDate` SHALL be `nil` (caller is expected to populate it before save), `endDate` SHALL be `nil`, `lastResetDate` SHALL be `nil`, `isCarryOverEnabled` SHALL be `true`, `currencyCode` SHALL be the locale currency (or `"USD"` if undetermined), `createdAt` and `lastModified` SHALL be the current date, and `expenseItems`, `allocationChanges`, `lifecycleEvents` SHALL all be empty arrays

#### Scenario: Cascade delete of expenses, allocation changes, and lifecycle events

- **WHEN** a Budget is deleted from the model context
- **THEN** all associated `ExpenseItem`, `AllocationChange`, and `LifecycleEvent` records SHALL also be deleted (cascade delete on all three relationships)

#### Scenario: No allocation parameter on init

- **WHEN** code attempts to call `Budget.init(allocation: 20)` (with parameter names from the old API)
- **THEN** the call SHALL fail to compile because no `allocation` parameter exists; the new code path is to insert an `AllocationChange` row alongside the Budget

#### Scenario: periodDisplayLabel for recurring budget

- **WHEN** `Budget.periodDisplayLabel` is read on a budget with `period == .weekly`
- **THEN** the property returns the localized string for key `period.weekly` (e.g. "Weekly" in en-US), identical to `BudgetPeriod.listLabel`

#### Scenario: periodDisplayLabel for Specific Dates with both dates set

- **WHEN** `Budget.periodDisplayLabel` is read on a budget with `period == .specificDates`, `startDate == 2026-05-08`, `endDate == 2026-05-25`, and locale en-US
- **THEN** the property returns a locale-aware date-interval string (e.g. "May 8 – May 25") produced by `Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)`

#### Scenario: periodDisplayLabel for Specific Dates spanning years

- **WHEN** `Budget.periodDisplayLabel` is read on a budget with `period == .specificDates`, `startDate == 2025-12-28`, `endDate == 2026-01-05`, and locale en-US
- **THEN** the property returns a date-interval string that includes the year on at least one endpoint (e.g. "Dec 28, 2025 – Jan 5, 2026")

#### Scenario: periodDisplayLabel falls back when dates are missing

- **WHEN** `Budget.periodDisplayLabel` is read on a budget with `period == .specificDates` but `startDate == nil` (defensive — should not happen in normal flow)
- **THEN** the property falls back to `BudgetPeriod.specificDates.listLabel` (the localized "Specific Dates" string)

#### Scenario: periodInlineLabel for recurring budget

- **WHEN** `Budget.periodInlineLabel` is read on a budget with `period == .weekly`
- **THEN** the property returns `BudgetPeriod.weekly.inlineLabel` (e.g. "weekly" in en-US)

#### Scenario: periodInlineLabel for Specific Dates budget

- **WHEN** `Budget.periodInlineLabel` is read on a budget with `period == .specificDates`
- **THEN** the property returns the localized string for the dedicated specificDates inline key (English source: "in this window"); the value is suitable for use in VoiceOver sentences such as "$941.00 remaining in this window"
