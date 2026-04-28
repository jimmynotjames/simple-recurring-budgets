## MODIFIED Requirements

### Requirement: Budget entity

> [!NOTE]
> **PAUSED — Reset Cadences feature is not in scope.** The `resetCadence` column remains on the `Budget` entity for schema/CloudKit stability and for the (currently unused) scheduled-reset code path. **Do not surface Reset Cadence in any UI, plan, or new spec while this pause is in effect.** New rows persist `"never"` regardless of period.

The system SHALL define a SwiftData `@Model` class `Budget` with the following stored properties:


| Property                     | Type            | Default                        | Notes                            |
| ---------------------------- | --------------- | ------------------------------ | -------------------------------- |
| `id`                         | `UUID`          | `UUID()`                       | Stable identity                  |
| `name`                       | `String`        | `"Budget"`                     | Display name                     |
| `allocation`                 | `Decimal`       | `10`                           | Per-period spending allowance    |
| `currencyCode`               | `String`        | Locale currency or `"USD"`     | ISO 4217 code                    |
| `period`                     | `String`        | `BudgetPeriod.daily.rawValue`  | Stored as BudgetPeriod raw value |
| `sortOrder`                  | `Int`           | `0`                            | User-defined list ordering       |
| `createdAt`                  | `Date`          | `Date()`                       | Immutable after creation         |
| `lastModified`               | `Date`          | `Date()`                       | Updated on user-facing mutation  |
| `carryOverAmount`            | `Decimal`       | `0`                            | Cumulative signed carryover      |
| `carryOverLastProcessedDate` | `Date`          | `Date()`                       | End of last rolled period        |
| `carryOverLastResetDate`     | `Date`          | `Date()`                       | Last manual/scheduled reset      |
| `resetCadence`               | `String`        | `ResetCadence.never.rawValue`  | **PAUSED.** Stored as ResetCadence raw value; persisted default is now `"never"` while the feature is paused |
| `isCarryOverEnabled`         | `Bool`          | `true`                         | Carry-over toggle (F-2.07)       |
| `expenses`                   | `[ExpenseItem]?` | `[]`                          | Stored as optional for CloudKit; use computed `expenseItems` in app code |


All monetary values SHALL use `Decimal`, never floating-point types.

The `Budget` entity SHALL also expose a non-optional computed property `expenseItems: [ExpenseItem]` that returns `expenses ?? []`. All app code SHALL use `expenseItems`; the stored `expenses` property exists solely for CloudKit compatibility and SHALL NOT be accessed directly outside of the model definition.

While Reset Cadences are paused, `Budget.init` SHALL persist `ResetCadence.never.rawValue` whenever the caller does not pass an explicit `resetCadence`. The `BudgetPeriod.defaultResetCadence` mapping SHALL NOT be consumed by `Budget.init` while paused; it remains available on the type for future use.

#### Scenario: Creating a Budget with defaults

- **WHEN** a Budget is initialized with no arguments
- **THEN** `id` SHALL be a new UUID, `allocation` SHALL be `10`, `period` SHALL be `"daily"`, `resetCadence` SHALL be `"never"` (Reset Cadences paused), `carryOverAmount` SHALL be `0`, `isCarryOverEnabled` SHALL be `true`, `currencyCode` SHALL be the locale currency (or `"USD"` if undetermined), `createdAt` and `lastModified` SHALL be the current date, and `expenseItems` SHALL be empty.

#### Scenario: Creating a Budget with custom values

- **WHEN** a Budget is initialized with explicit `name`, `allocation`, `currencyCode`, `period`, and `resetCadence`
- **THEN** the provided values SHALL be stored and all other properties SHALL use their defaults. (The explicit `resetCadence` parameter is honored even while the feature is paused, so existing tests and `DebugData` continue to compile and run.)

#### Scenario: Creating a Budget without an explicit reset cadence — feature paused

- **WHEN** a Budget is initialized with any `period` but without an explicit `resetCadence`
- **THEN** the persisted `resetCadence` SHALL be `"never"` regardless of the period.

#### Scenario: Cascade delete of expenses

- **WHEN** a Budget is deleted from the model context
- **THEN** all associated ExpenseItem records SHALL also be deleted.

---

### Requirement: Default reset cadence mapping

> [!NOTE]
> **PAUSED — Reset Cadences feature is not in scope.** The mapping below is retained as design knowledge so that un-pausing is a small, mechanical revert. **It SHALL NOT be consumed by `Budget.init` while paused** (see "Budget entity"). **Do not surface this mapping in UI, planning, or Figma work.** New tests/specs MUST NOT depend on `Budget.init` producing one of these defaults.

The system SHALL provide a computed property `BudgetPeriod.defaultResetCadence` that returns a `ResetCadence` using the following explicit mapping:


| Budget Period | Default Reset Cadence |
| ------------- | --------------------- |
| `.daily`      | `.weekly`             |
| `.weekly`     | `.monthly`            |
| `.biweekly`   | `.quarterly`          |
| `.monthly`    | `.quarterly`          |


This mapping SHALL NOT be derived algorithmically from enum ordering.

#### Scenario: Default for daily

- **WHEN** `BudgetPeriod.daily.defaultResetCadence` is read
- **THEN** the result SHALL be `.weekly`. (PAUSED — not consumed by `Budget.init`.)

#### Scenario: Default for weekly

- **WHEN** `BudgetPeriod.weekly.defaultResetCadence` is read
- **THEN** the result SHALL be `.monthly`. (PAUSED — not consumed by `Budget.init`.)

#### Scenario: Default for biweekly

- **WHEN** `BudgetPeriod.biweekly.defaultResetCadence` is read
- **THEN** the result SHALL be `.quarterly`. (PAUSED — not consumed by `Budget.init`.)

#### Scenario: Default for monthly

- **WHEN** `BudgetPeriod.monthly.defaultResetCadence` is read
- **THEN** the result SHALL be `.quarterly`. (PAUSED — not consumed by `Budget.init`.)
