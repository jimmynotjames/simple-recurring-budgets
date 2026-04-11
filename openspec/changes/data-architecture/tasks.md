## 1. Enums

- [x] 1.1 Create `BudgetPeriod.swift` with `String`-backed, `Codable`, `CaseIterable`, `Comparable` enum (cases: `daily`, `weekly`, `biweekly`, `monthly`) and manual `sortOrder`-based `<` operator.
- [x] 1.2 Create `ResetCadence.swift` with `String`-backed, `Codable`, `CaseIterable` enum (cases: `weekly`, `biweekly`, `monthly`, `quarterly`, `never`) and `isBroaderThan(_:BudgetPeriod) -> Bool` method.
- [x] 1.3 Add computed property `BudgetPeriod.defaultResetCadence` returning `ResetCadence` with explicit mapping (daily→weekly, weekly→monthly, biweekly→quarterly, monthly→quarterly).
- [x] 1.4 Add `validResetCadences(for:)` function returning `ResetCadence` cases where `isBroaderThan` returns `true` for the given period.

## 2. SwiftData Models

- [x] 2.1 Create `Budget.swift` with `@Model` class containing all stored properties (id, name, allocation, currencyCode, period, sortOrder, createdAt, lastModified, carryOverAmount, carryOverLastProcessedDate, carryOverLastResetDate, resetCadence, isCarryOverEnabled) with code-level defaults per spec.
- [x] 2.2 Add `expenses` relationship on Budget (one-to-many, `@Relationship(.cascade)` delete rule, inverse: `\ExpenseItem.budget`).
- [x] 2.3 Create `ExpenseItem.swift` with `@Model` class containing all stored properties (id, amount (signed Decimal), name, date, createdAt, lastModified, expenseType) and computed properties (`isAddFunds`, `displayAmount`) with code-level defaults per spec.
- [x] 2.4 Add `budget` inverse relationship on ExpenseItem (`Budget?`).

## 3. Schema Versioning

- [x] 3.1 Create `SchemaV1.swift` defining `SchemaV1` conforming to `VersionedSchema` with `versionIdentifier = Schema.Version(1, 0, 0)` and `models = [Budget.self, ExpenseItem.self]`.
- [x] 3.2 Create `BudgetMigrationPlan.swift` conforming to `SchemaMigrationPlan` with `schemas = [SchemaV1.self]` and empty `stages` array.

## 4. App Configuration

- [x] 4.1 Update `simple_recurring_budgetsApp.swift`: replace `Item.self` schema with `Budget.self` and `ExpenseItem.self`, set `ModelConfiguration` to use `cloudKitDatabase: .automatic`, wire `BudgetMigrationPlan`.
- [x] 4.2 Update `ContentView.swift` to remove all `Item` references (temporary placeholder view is fine — screens are a separate change).

## 5. Cleanup

- [x] 5.1 Delete `Item.swift`.
- [x] 5.2 Remove any remaining `Item` references from test files (`simple_recurring_budgetsTests.swift`, UI test files).

## 6. Tests

- [x] 6.1 Add unit tests for `BudgetPeriod` ordering (`daily < weekly < biweekly < monthly`), raw value encoding, `defaultResetCadence` mapping; `ResetCadence` raw values, `isBroaderThan` logic, and `validResetCadences(for:)` including `.quarterly` and `.never` cases.
- [x] 6.2 Add SwiftData tests using in-memory `ModelContainer`: Budget creation with defaults (including `isCarryOverEnabled == true`), ExpenseItem creation with defaults, signed amount semantics (positive = expense, negative = add funds, computed `isAddFunds`/`displayAmount`), Budget–ExpenseItem relationship, cascade delete.
- [x] 6.3 Add test verifying `ModelContainer` can be created with `isStoredInMemoryOnly: true` and both model types.
