# Data models

SwiftData entities, enums, and related rules for budgets and expense items. Synced from change `rewrite-budget-calculations` (2026-05-15). Updated from change `specific-dates-period` (2026-05-18). Updated from change `budget-icon-emoji` (2026-05-25).

## Requirements

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

---

### Requirement: Budget icon attribute

The `Budget` entity SHALL define an optional stored property `icon: String?` (default `nil`) that holds the budget's decorative icon. By convention the value is a single emoji grapheme; the value is supplied by the icon picker (see the `budget-icon` capability) and is not otherwise validated by the model. The property SHALL be stored as `String?` for CloudKit optionality and SHALL persist and sync like other `Budget` attributes. `Budget.init` SHALL accept an `icon: String? = nil` parameter that defaults to `nil`.

This is an additive, optional attribute: it requires no migration plan (the schema is updated in place per the unreleased/greenfield convention) and existing budgets without a value SHALL read as `nil`.

#### Scenario: Default icon on Budget creation

- **WHEN** a `Budget` is initialized with no `icon` argument
- **THEN** its `icon` SHALL be `nil`

#### Scenario: Icon supplied at creation

- **WHEN** a `Budget` is initialized with `icon: "☕"`
- **THEN** its `icon` SHALL be `"☕"` and SHALL persist on save and round-trip through SwiftData

#### Scenario: Icon is optional for CloudKit

- **WHEN** the `Budget` model is described for CloudKit sync
- **THEN** `icon` SHALL be an optional field so the record type remains CloudKit-compatible

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
| `budget`       | `Budget?` | —        | Inverse of Budget.expenses (the stored optional relationship) |


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
- **THEN** the ExpenseItem SHALL appear in that Budget's `expenseItems` collection.

---

### Requirement: BudgetPeriod enum

The system SHALL define a `BudgetPeriod` enum that is `String`-backed, `Codable`, `CaseIterable`, and `Comparable` with the following cases in ascending order: `daily`, `weekly`, `biweekly`, `monthly`, `specificDates`.

The raw values SHALL be `"daily"`, `"weekly"`, `"biweekly"`, `"monthly"`, `"specificDates"`.

Ordering SHALL be implemented via a private `sortOrder` integer and a manual `static func <` so that `BudgetPeriod.daily < BudgetPeriod.weekly < BudgetPeriod.biweekly < BudgetPeriod.monthly < BudgetPeriod.specificDates`.

The recurring period-boundary math (in the `budget-math` capability) operates on a `RecurringBudgetPeriod` wrapper that excludes `.specificDates` at compile time. `BudgetPeriod` itself retains the case so the algorithm can dispatch into its dedicated branch (per `budget-math`'s "SpecificDates snapshot branch").

`BudgetPeriod` SHALL NOT expose a `defaultResetCadence` property. The Reset Cadences feature is permanently removed.

#### Scenario: Comparable ordering

- **WHEN** two BudgetPeriod values are compared
- **THEN** `.daily < .weekly < .biweekly < .monthly < .specificDates` SHALL hold

#### Scenario: String raw values for database storage

- **WHEN** a BudgetPeriod is encoded for SwiftData storage
- **THEN** the stored value SHALL be a human-readable string (e.g. `"daily"`, `"specificDates"`)

#### Scenario: defaultResetCadence no longer exists

- **WHEN** code attempts to read `BudgetPeriod.daily.defaultResetCadence`
- **THEN** the call SHALL fail to compile because the property has been removed

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

---

### Requirement: AllocationChange entity

The system SHALL define a SwiftData `@Model` class `AllocationChange` with the following stored properties (algorithm doc §A.2.2):

| Property        | Type      | Default     | Notes                                                       |
| --------------- | --------- | ----------- | ----------------------------------------------------------- |
| `id`            | `UUID`    | `UUID()`    | Stable identity                                             |
| `effectiveFrom` | `Date`    | —           | Start of the period this allocation takes effect            |
| `amount`        | `Decimal` | —           | Allocation amount in effect from `effectiveFrom` onward     |
| `lastModified`  | `Date`    | `Date()`    | Used as tiebreaker when two rows share the same `effectiveFrom` (later wins) — needed for CloudKit cross-device convergence |
| `budget`        | `Budget?` | —           | Inverse of `Budget.allocationChangesStorage`                |

`AllocationChange` SHALL participate in `Budget`'s cascade delete (deleting a Budget deletes all its AllocationChange rows).

All monetary values SHALL use `Decimal`, never floating-point types.

#### Scenario: Creating an AllocationChange

- **WHEN** an AllocationChange is initialized with `effectiveFrom = 2026-04-01 00:00, amount = 20.00`
- **THEN** `id` SHALL be a new UUID, `lastModified` SHALL be the current date, and `budget` SHALL be set by the caller before save

#### Scenario: AllocationChange linked to a Budget

- **WHEN** an AllocationChange is created and its `budget` property is set
- **THEN** the AllocationChange SHALL appear in that Budget's `allocationChanges` collection

#### Scenario: Cascade delete from Budget

- **WHEN** a Budget with two AllocationChange rows is deleted
- **THEN** both AllocationChange rows SHALL also be deleted

---

### Requirement: LifecycleEvent entity

The system SHALL define a SwiftData `@Model` class `LifecycleEvent` with the following stored properties (algorithm doc §A.2.3):

| Property        | Type                  | Default     | Notes                                                       |
| --------------- | --------------------- | ----------- | ----------------------------------------------------------- |
| `id`            | `UUID`                | `UUID()`    | Stable identity                                             |
| `kindRawValue`  | `String`              | `"pause"`   | Stored as `LifecycleEventKind.rawValue`. The typed `kind: LifecycleEventKind` accessor reads/writes this. Storing the raw string keeps the column visible to `#Predicate<LifecycleEvent>` queries (Codable-backed enum storage is opaque to predicates). Same convention as `Budget.period`. |
| `effectiveDate` | `Date`                | —           | The instant the event takes effect                          |
| `lastModified`  | `Date`                | `Date()`    | Tiebreaker for CloudKit cross-device convergence            |
| `budget`        | `Budget?`             | —           | Inverse of `Budget.lifecycleEventsStorage`                  |

`LifecycleEvent` SHALL participate in `Budget`'s cascade delete.

#### Scenario: Creating a LifecycleEvent

- **WHEN** a LifecycleEvent is initialized with `kind = .pause, effectiveDate = 2026-04-15 10:00`
- **THEN** `id` SHALL be a new UUID, `lastModified` SHALL be the current date, and `budget` SHALL be set by the caller before save

#### Scenario: LifecycleEvent.kind round-trips through SwiftData

- **WHEN** a LifecycleEvent is saved and later fetched from a new ModelContext
- **THEN** its `kind` SHALL equal the original value (`.pause` or `.resume`); the typed accessor reads `kindRawValue` and rehydrates the enum

#### Scenario: Cascade delete from Budget

- **WHEN** a Budget with three LifecycleEvent rows is deleted
- **THEN** all three LifecycleEvent rows SHALL also be deleted

---

### Requirement: LifecycleEventKind enum

The system SHALL define a `LifecycleEventKind` enum that is `String`-backed, `Codable`, and `CaseIterable` with the following cases: `pause`, `resume`. Raw values SHALL be `"pause"`, `"resume"`.

#### Scenario: String raw values

- **WHEN** a `LifecycleEventKind` is encoded
- **THEN** the encoded value SHALL be `"pause"` or `"resume"`

---

### Requirement: Initial AllocationChange row on Budget creation

The system SHALL ensure that every user-created Budget has at least one `AllocationChange` row inserted in the same `ModelContext.save()` as the Budget itself. The row SHALL be:

- `effectiveFrom = budget.startDate` (the value computed by the Add-mode save path).
- `amount = the allocation value the user entered in the Add flow`.
- `lastModified = now`.
- `budget = the newly-created Budget`.

The `startDate` computed at Add time SHALL be derived per period type so that the user's `AppSettings.weekStartDay` preference still anchors the cycle for weekly/biweekly budgets (briefing §2.4):

- **Daily**: `calendar.startOfDay(for: createdAt)`.
- **Weekly / biweekly**: most recent `AppSettings.weekStartDay`-aligned date at or before `calendar.startOfDay(for: createdAt)`.
- **Monthly**: start of the calendar month containing `createdAt`.
- **Specific Dates**: N/A in this change (no UI exposes this period type yet); when a future UI ships, `startDate` is user-entered.

All four computed values are start-of-day-aligned, so the initial row's `effectiveFrom` matches the storage convention used by `allocationInEffect` (algorithm doc §A.6.1) exactly.

#### Scenario: Daily budget initial allocation row

- **WHEN** the user creates a daily budget at `createdAt = 2026-04-15 14:30 UTC` with allocation 20.00
- **THEN** the Budget's `startDate` is 2026-04-15 00:00 (calendar-local) and an AllocationChange row exists with `effectiveFrom = 2026-04-15 00:00, amount = 20.00`

#### Scenario: Weekly budget anchors on AppSettings.weekStartDay

- **WHEN** the user creates a weekly budget on Wednesday 2026-04-15 with `AppSettings.weekStartDay = .sunday` and allocation 100.00
- **THEN** the Budget's `startDate` is Sunday 2026-04-12 and the initial AllocationChange row has `effectiveFrom = 2026-04-12 00:00, amount = 100.00`

#### Scenario: Monthly budget anchors on the calendar month

- **WHEN** the user creates a monthly budget on 2026-04-15 with allocation 500.00
- **THEN** the Budget's `startDate` is 2026-04-01 and the initial AllocationChange row has `effectiveFrom = 2026-04-01 00:00, amount = 500.00`

---

### Requirement: Budget.lastModified write-site rule

The system SHALL bump `Budget.lastModified = now` in the same `ModelContext.save()` as every user-initiated write that affects budget math. Specifically:

- Every `ExpenseItem` add, edit, or delete SHALL set the owning `Budget.lastModified = now` before save. (Edit was previously unhandled when refresh triggers relied on `expenseItems.count`; this rule closes that gap.)
- Every `AllocationChange` insert or mutation SHALL bump the owning `Budget.lastModified = now` (handled inside `BudgetLifecycleService.applyAllocationEdit`).
- `BudgetLifecycleService.resetCarryOver(...)` and `BudgetLifecycleService.resetBudget(...)` SHALL bump `Budget.lastModified = now`.
- Future write sites (pause, resume, start/end date edits) SHALL follow the same rule.

This provides a single reliable refresh signal that every chip-observing view can observe via `.onChange(of: budget.lastModified)`.

#### Scenario: Expense Add bumps lastModified

- **WHEN** a new ExpenseItem is inserted and `context.save()` is called
- **THEN** the owning `Budget.lastModified` equals `now` at the moment of save

#### Scenario: Expense Edit bumps lastModified

- **WHEN** an existing ExpenseItem's `amount` is changed and `context.save()` is called
- **THEN** the owning `Budget.lastModified` equals `now` at the moment of save (this case was previously unhandled by the count-based refresh trigger)

#### Scenario: Expense Delete bumps lastModified

- **WHEN** an ExpenseItem is deleted and `context.save()` is called
- **THEN** the owning `Budget.lastModified` equals `now` at the moment of save
