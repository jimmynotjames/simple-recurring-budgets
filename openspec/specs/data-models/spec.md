# Data models

SwiftData entities, enums, and related rules for budgets and expense items. Synced from change `data-architecture` (2026-04-11).

## Requirements

### Requirement: Budget entity

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
| `resetCadence`               | `String`        | `ResetCadence.weekly.rawValue` | Stored as ResetCadence raw value |
| `isCarryOverEnabled`         | `Bool`          | `true`                         | Carry-over toggle (F-2.07)       |
| `expenses`                   | `[ExpenseItem]` | `[]`                           | One-to-many, cascade delete      |


All monetary values SHALL use `Decimal`, never floating-point types.

#### Scenario: Creating a Budget with defaults

- **WHEN** a Budget is initialized with no arguments
- **THEN** `id` SHALL be a new UUID, `allocation` SHALL be `10`, `period` SHALL be `"daily"`, `resetCadence` SHALL be `"weekly"`, `carryOverAmount` SHALL be `0`, `isCarryOverEnabled` SHALL be `true`, `currencyCode` SHALL be the locale currency (or `"USD"` if undetermined), `createdAt` and `lastModified` SHALL be the current date, and `expenses` SHALL be empty.

#### Scenario: Creating a Budget with custom values

- **WHEN** a Budget is initialized with explicit `name`, `allocation`, `currencyCode`, `period`, and `resetCadence`
- **THEN** the provided values SHALL be stored and all other properties SHALL use their defaults.

#### Scenario: Cascade delete of expenses

- **WHEN** a Budget is deleted from the model context
- **THEN** all associated ExpenseItem records SHALL also be deleted.

---

### Requirement: ExpenseItem entity

The system SHALL define a SwiftData `@Model` class `ExpenseItem` with the following stored properties:


| Property       | Type      | Default  | Notes                                                     |
| -------------- | --------- | -------- | --------------------------------------------------------- |
| `id`           | `UUID`    | `UUID()` | Stable identity                                           |
| `amount`       | `Decimal` | `0`      | Signed: positive = expense, negative = add funds (F-6.01) |
| `name`         | `String?` | `nil`    | Optional description                                      |
| `date`         | `Date`    | `Date()` | When the expense occurred                                 |
| `createdAt`    | `Date`    | `Date()` | Immutable after creation                                  |
| `lastModified` | `Date`    | `Date()` | Updated on user-facing mutation                           |
| `expenseType`  | `String?` | `nil`    | e.g. "Cash", "Credit Card" (F-6.02)                       |
| `budget`       | `Budget?` | —        | Inverse of Budget.expenses                                |


All monetary values SHALL use `Decimal`, never floating-point types.

#### Scenario: Creating an ExpenseItem with defaults

- **WHEN** an ExpenseItem is initialized with only an `amount`
- **THEN** `id` SHALL be a new UUID, `date` SHALL be the current date, `createdAt` and `lastModified` SHALL be the current date, and `name`, `expenseType` SHALL be `nil`.

#### Scenario: Signed amount for adding funds

- **WHEN** an ExpenseItem is created with a negative `amount`
- **THEN** it SHALL represent an "add funds" transaction; computed property `isAddFunds` SHALL return `true` and `displayAmount` SHALL return the absolute value.

#### Scenario: Signed amount for expense

- **WHEN** an ExpenseItem is created with a positive `amount`
- **THEN** it SHALL represent a normal expense; computed property `isAddFunds` SHALL return `false` and `displayAmount` SHALL return the amount as-is.

#### Scenario: Computed helpers on ExpenseItem

- **WHEN** `isAddFunds` and `displayAmount` are accessed on an ExpenseItem
- **THEN** they SHALL be computed (not stored) properties derived from the sign of `amount`.

#### Scenario: ExpenseItem linked to a Budget

- **WHEN** an ExpenseItem is created and its `budget` property is set to an existing Budget
- **THEN** the ExpenseItem SHALL appear in that Budget's `expenses` array.

---

### Requirement: BudgetPeriod enum

The system SHALL define a `BudgetPeriod` enum that is `String`-backed, `Codable`, `CaseIterable`, and `Comparable` with the following cases in ascending order: `daily`, `weekly`, `biweekly`, `monthly`.

The raw values SHALL be `"daily"`, `"weekly"`, `"biweekly"`, `"monthly"`.

Ordering SHALL be implemented via a private `sortOrder` integer and a manual `static func <` so that `BudgetPeriod.daily < BudgetPeriod.weekly < BudgetPeriod.biweekly < BudgetPeriod.monthly`.

#### Scenario: Comparable ordering

- **WHEN** two BudgetPeriod values are compared
- **THEN** `.daily < .weekly < .biweekly < .monthly` SHALL hold.

#### Scenario: String raw values for database storage

- **WHEN** a BudgetPeriod is encoded for SwiftData storage
- **THEN** the stored value SHALL be a human-readable string (e.g. `"daily"`, not an integer).

---

### Requirement: ResetCadence enum

The system SHALL define a `ResetCadence` enum that is `String`-backed, `Codable`, and `CaseIterable` with the following cases: `weekly`, `biweekly`, `monthly`, `quarterly`, `never`.

The raw values SHALL be `"weekly"`, `"biweekly"`, `"monthly"`, `"quarterly"`, `"never"`.

`ResetCadence` SHALL NOT conform to `Comparable`. Cross-type comparison SHALL be provided via an `isBroaderThan(_:BudgetPeriod) -> Bool` method, where:

- `.never` returns `true` for any budget period (always valid).
- `.quarterly` returns `true` for any budget period (always broader).
- `.monthly` returns `true` when the budget period is less than `.monthly`.
- `.biweekly` returns `true` when the budget period is less than `.biweekly`.
- `.weekly` returns `true` when the budget period is less than `.weekly`.

#### Scenario: String raw values for database storage

- **WHEN** a ResetCadence is encoded for SwiftData storage
- **THEN** the stored value SHALL be a human-readable string (e.g. `"quarterly"`, not an integer).

#### Scenario: isBroaderThan for .never

- **WHEN** `ResetCadence.never.isBroaderThan(.daily)` is evaluated
- **THEN** the result SHALL be `true`.

#### Scenario: isBroaderThan for .quarterly vs .monthly period

- **WHEN** `ResetCadence.quarterly.isBroaderThan(.monthly)` is evaluated
- **THEN** the result SHALL be `true`.

#### Scenario: isBroaderThan for .weekly vs .weekly period

- **WHEN** `ResetCadence.weekly.isBroaderThan(.weekly)` is evaluated
- **THEN** the result SHALL be `false` (not strictly broader).

---

### Requirement: Valid reset cadence computation

The system SHALL provide a function that, given a `BudgetPeriod`, returns the list of valid `ResetCadence` options. Valid options are all `ResetCadence` cases where `isBroaderThan` returns `true` for the given budget period.

#### Scenario: Valid options for daily budget

- **WHEN** the budget period is `.daily`
- **THEN** valid reset cadences SHALL be `[.weekly, .biweekly, .monthly, .quarterly, .never]`.

#### Scenario: Valid options for weekly budget

- **WHEN** the budget period is `.weekly`
- **THEN** valid reset cadences SHALL be `[.biweekly, .monthly, .quarterly, .never]`.

#### Scenario: Valid options for biweekly budget

- **WHEN** the budget period is `.biweekly`
- **THEN** valid reset cadences SHALL be `[.monthly, .quarterly, .never]`.

#### Scenario: Valid options for monthly budget

- **WHEN** the budget period is `.monthly`
- **THEN** valid reset cadences SHALL be `[.quarterly, .never]`.

---

### Requirement: Default reset cadence mapping

The system SHALL provide a computed property `BudgetPeriod.defaultResetCadence` that returns a `ResetCadence` using the following explicit mapping:


| Budget Period | Default Reset Cadence |
| ------------- | --------------------- |
| `.daily`      | `.weekly`             |
| `.weekly`     | `.monthly`            |
| `.biweekly`   | `.quarterly`          |
| `.monthly`    | `.quarterly`          |


This mapping SHALL NOT be derived algorithmically from enum ordering.

#### Scenario: Default for daily

- **WHEN** a new Budget is created with period `.daily`
- **THEN** the default reset cadence SHALL be `.weekly`.

#### Scenario: Default for weekly

- **WHEN** a new Budget is created with period `.weekly`
- **THEN** the default reset cadence SHALL be `.monthly`.

#### Scenario: Default for biweekly

- **WHEN** a new Budget is created with period `.biweekly`
- **THEN** the default reset cadence SHALL be `.quarterly`.

#### Scenario: Default for monthly

- **WHEN** a new Budget is created with period `.monthly`
- **THEN** the default reset cadence SHALL be `.quarterly`.

---

### Requirement: Budget sortOrder assignment

When a new Budget is created, its `sortOrder` SHALL be assigned the value `max(sortOrder of all existing budgets) + 1`. If no budgets exist, `sortOrder` SHALL be `0`.

#### Scenario: First budget created

- **WHEN** a Budget is created and no other Budgets exist in the store
- **THEN** its `sortOrder` SHALL be `0`.

#### Scenario: Additional budget created

- **WHEN** a Budget is created and existing Budgets have `sortOrder` values `[0, 1, 2]`
- **THEN** the new Budget's `sortOrder` SHALL be `3`.

---

### Requirement: Period-boundary-aligned resets

Scheduled carry-over resets SHALL fire at the first period boundary after the cadence interval has elapsed since the last reset date. Resets SHALL NOT occur mid-period. The cadence interval defines a minimum elapsed time; the actual reset may slip by up to one period length beyond the cadence interval.

#### Scenario: Monthly reset on a biweekly budget

- **WHEN** a biweekly budget has a monthly reset cadence, last reset was Jan 6, and biweekly period boundaries fall on Jan 19, Feb 2, Feb 16
- **THEN** the reset SHALL occur at the Feb 16 boundary (the first period boundary after Jan 6 + 1 month = Feb 6), not on Feb 1 or Feb 2.

#### Scenario: Quarterly reset on a biweekly budget

- **WHEN** a biweekly budget has a quarterly reset cadence, last reset was Jan 6, and biweekly period boundaries fall every 14 days
- **THEN** the reset SHALL occur at the first period boundary on or after Apr 6 (Jan 6 + 3 months).

#### Scenario: Weekly reset on a daily budget

- **WHEN** a daily budget has a weekly reset cadence, last reset was Mon Jan 6
- **THEN** the reset SHALL occur at the Jan 13 day boundary (exactly 7 days, always aligns).

---

### Requirement: Carry-over toggle on Budget

Each Budget SHALL have an `isCarryOverEnabled` property (`Bool`, default `true`) that controls whether carry-over is active for that budget. When `false`, carry-over SHALL NOT be computed or displayed for that budget. The default value for new budgets SHALL be sourced from `AppSettings.defaultCarryOverEnabled` at creation time; callers that create a `Budget` SHALL pass the current value explicitly. The `Budget.init` parameter `isCarryOverEnabled` SHALL default to `true` as a safe fallback when `AppSettings` is not available (e.g., in tests or previews).

#### Scenario: New budget inherits global default (enabled)

- **WHEN** a Budget is created and `AppSettings.defaultCarryOverEnabled` is `true`
- **THEN** the Budget's `isCarryOverEnabled` SHALL be `true`.

#### Scenario: New budget inherits global default (disabled)

- **WHEN** a Budget is created and `AppSettings.defaultCarryOverEnabled` is `false`
- **THEN** the caller SHALL pass `isCarryOverEnabled: false` to `Budget.init`, and the Budget's `isCarryOverEnabled` SHALL be `false`.

#### Scenario: Carry-over disabled on existing budget

- **WHEN** a Budget's `isCarryOverEnabled` is set to `false`
- **THEN** the carry-over amount SHALL NOT be computed or displayed for that budget.

#### Scenario: Budget.init does not depend on AppSettings directly

- **WHEN** `Budget.init` is called in a test without an `AppSettings` instance
- **THEN** `isCarryOverEnabled` SHALL default to `true` (the init parameter default), and no runtime error SHALL occur.
