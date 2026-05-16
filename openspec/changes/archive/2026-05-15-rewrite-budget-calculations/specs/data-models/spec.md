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
| `endDate`                      | `Date?`                    | `nil`                                | Genuinely optional for recurring; required by future UI for `.specificDates` |
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

## REMOVED Requirements

### Requirement: ResetCadence enum

**Reason**: The Reset Cadences feature is permanently removed (briefing §5.4). The enum, the `Budget.resetCadence` stored property, and every reference to "PAUSED — Reset Cadences" are deleted in the same change.

**Migration**: No replacement. Manual Reset Carry-Over remains as the only carry-over reset affordance and is invoked via `BudgetLifecycleService.resetCarryOver(_:context:now:)` (see `budget-lifecycle` capability).

### Requirement: Valid reset cadence computation

**Reason**: Depends on the removed `ResetCadence` enum.

**Migration**: No replacement.

### Requirement: Default reset cadence mapping

**Reason**: Depends on the removed `ResetCadence` enum.

**Migration**: No replacement. `BudgetPeriod.defaultResetCadence` is deleted; the `Budget.resetCadence` init parameter no longer exists.

### Requirement: Period-boundary-aligned resets

**Reason**: Scheduled resets are removed entirely (Reset Cadences deletion). Manual Reset Carry-Over and Reset Budget are user-initiated at arbitrary instants — they SHALL NOT be aligned to period boundaries; the walker honors whatever `lastResetDate` was written (see `budget-math` capability).

**Migration**: No replacement.

## ADDED Requirements

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

### Requirement: LifecycleEvent entity

The system SHALL define a SwiftData `@Model` class `LifecycleEvent` with the following stored properties (algorithm doc §A.2.3):

| Property        | Type                  | Default     | Notes                                                       |
| --------------- | --------------------- | ----------- | ----------------------------------------------------------- |
| `id`            | `UUID`                | `UUID()`    | Stable identity                                             |
| `kind`          | `LifecycleEventKind`  | —           | One of `.pause`, `.resume`. Stored directly as the enum; SwiftData serializes `String, Codable` enums automatically |
| `effectiveDate` | `Date`                | —           | The instant the event takes effect                          |
| `lastModified`  | `Date`                | `Date()`    | Tiebreaker for CloudKit cross-device convergence            |
| `budget`        | `Budget?`             | —           | Inverse of `Budget.lifecycleEventsStorage`                  |

`LifecycleEvent` SHALL participate in `Budget`'s cascade delete.

#### Scenario: Creating a LifecycleEvent

- **WHEN** a LifecycleEvent is initialized with `kind = .pause, effectiveDate = 2026-04-15 10:00`
- **THEN** `id` SHALL be a new UUID, `lastModified` SHALL be the current date, and `budget` SHALL be set by the caller before save

#### Scenario: LifecycleEvent.kind round-trips through SwiftData

- **WHEN** a LifecycleEvent is saved and later fetched from a new ModelContext
- **THEN** its `kind` SHALL equal the original value (`.pause` or `.resume`) without any manual encoding/decoding code

#### Scenario: Cascade delete from Budget

- **WHEN** a Budget with three LifecycleEvent rows is deleted
- **THEN** all three LifecycleEvent rows SHALL also be deleted

### Requirement: LifecycleEventKind enum

The system SHALL define a `LifecycleEventKind` enum that is `String`-backed, `Codable`, and `CaseIterable` with the following cases: `pause`, `resume`. Raw values SHALL be `"pause"`, `"resume"`.

#### Scenario: String raw values

- **WHEN** a `LifecycleEventKind` is encoded
- **THEN** the encoded value SHALL be `"pause"` or `"resume"`

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

## Doc alignment

`docs/tech-design-doc.md` §3 (data model) describes the previous `Budget` shape and the PAUSED Reset Cadences references. This delta defines the new shape; the tasks artifact updates the doc accordingly. No conflicts.
