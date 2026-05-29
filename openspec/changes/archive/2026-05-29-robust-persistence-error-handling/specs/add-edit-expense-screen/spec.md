## MODIFIED Requirements

### Requirement: VM exposes save and delete methods that take ModelContext at the call site

The `AddEditExpenseViewModel` SHALL expose a `save` method and a `delete` method that take `ModelContext` at the call site and surface a persistence-save failure to the caller (e.g. marked `throws`). Each method SHALL route its `context.save()` through the shared persistence-save helper rather than `try? context.save()`. The view SHALL read `@Environment(\.modelContext)`, invoke `save`/`delete` from inside `body`, and dismiss the sheet **only** when the call returns without error; on a thrown persistence error the view SHALL present the standard save-error alert and SHALL NOT dismiss (see the `persistence-error-handling` capability). The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The save and delete bodies SHALL NOT consult `AppSettings`. The VM SHALL NOT have any stored property of type `ModelContext` and SHALL NOT have any stored property of type `AppSettings`.

#### Scenario: Save reports failure to the caller

- **WHEN** `AddEditExpenseViewModel.save` is inspected
- **THEN** it takes `ModelContext` at the call site, does not take `AppSettings`, surfaces persistence-save failure to its caller (e.g. is marked `throws`), and routes its save through the shared persistence-save helper

#### Scenario: Delete reports failure to the caller

- **WHEN** `AddEditExpenseViewModel.delete` is inspected
- **THEN** it takes `ModelContext` at the call site, does not take `AppSettings`, surfaces persistence-save failure to its caller (e.g. is marked `throws`), and routes its save through the shared persistence-save helper

#### Scenario: VM does not own ModelContext or AppSettings

- **WHEN** `AddEditExpenseViewModel` is inspected
- **THEN** it has no stored property of type `ModelContext`, no stored property of type `AppSettings`, and no `init` taking either type

#### Scenario: View dismisses only on a successful save or delete

- **WHEN** the user activates Save or Delete and the method returns without error
- **THEN** the sheet dismisses; **AND WHEN** the method throws a persistence error, the sheet stays open and the save-error alert is shown

### Requirement: Save in Add mode inserts a new ExpenseItem attached to the in-flight Budget

When the user activates Save in Add mode, the system SHALL:

0. **Guard:** If validation would disable Save (`!canSave`), the implementation SHALL return without inserting an `ExpenseItem` (defence in depth if save is invoked without a valid draft).
1. Compute `trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)`. If `trimmedName.isEmpty == true`, the persisted name SHALL be `nil`; otherwise the persisted name SHALL be the trimmed value.
2. Compute `signedAmount = isAddFunds ? -amount! : amount!`. The unwrap is safe because `canSave` guarantees `amount != nil && amount > 0`.
3. Construct an `ExpenseItem(amount: signedAmount, name: trimmedName, date: date)`. The resulting `ExpenseItem.isAddFunds` SHALL equal the viewmodel's `isAddFunds`.
4. Set `expense.budget = budget` (the in-flight `Budget` from the VM's `Mode.add` associated value), establishing the parent relationship before insert.
5. Call `context.insert(expense)`.
6. Persist via the shared persistence-save helper (operation `expense_create`), which throws on failure; the method propagates that error to the caller instead of swallowing it with `try?`.
7. On success, the view dismisses the sheet. On a thrown persistence error, the view presents the save-error alert and does not dismiss; the inserted-but-unsaved `ExpenseItem` remains in the context so Retry re-attempts the same save.

The new expense SHALL appear in the budget's expense list immediately due to SwiftData's reactivity once the save succeeds. CloudKit sync SHALL propagate the new row through the existing pipeline; no schema or container changes are introduced.

The `AnalyticsProperty.isAddFunds` property on the `expense_logged` event SHALL reflect the just-inserted `ExpenseItem.isAddFunds` (which equals the viewmodel's `isAddFunds` at Save time). The `expense_logged` event SHALL fire only on a successful save; on a thrown persistence error it SHALL NOT fire.

#### Scenario: Add Save inserts a positive-amount expense when Add Funds is off

- **WHEN** the user activates Save in Add mode with `amount = 5.00`, `name = "Coffee"`, `date = 2026-04-29 10:00`, `isAddFunds = false`, against an in-memory `ModelContainer` containing the in-flight `Budget`, and the save succeeds
- **THEN** the store contains exactly one new `ExpenseItem` with `amount == 5.00` (positive), `name == "Coffee"`, `date == 2026-04-29 10:00`, `budget` referencing the in-flight `Budget`, and `isAddFunds == false`

#### Scenario: Add Save inserts a negative-amount expense when Add Funds is on

- **WHEN** the user activates Save in Add mode with `amount = 25.00`, `name = "Add funds"`, `date = 2026-04-29 10:00`, `isAddFunds = true`, and the save succeeds
- **THEN** the inserted `ExpenseItem.amount == -25.00` (sign flipped), `isAddFunds == true`, `name == "Add funds"`

#### Scenario: Add Save trims description whitespace

- **WHEN** the user activates Save in Add mode with `name = "  Coffee  "` and the save succeeds
- **THEN** the inserted `ExpenseItem.name` is `"Coffee"` (whitespace trimmed)

#### Scenario: Add Save persists nil description for whitespace-only input

- **WHEN** the user activates Save in Add mode with `name = "   "` (whitespace only) or `name = ""` and the save succeeds
- **THEN** the inserted `ExpenseItem.name` is `nil`

#### Scenario: Add Save guards against !canSave

- **WHEN** save is invoked while `canSave == false`
- **THEN** no `ExpenseItem` is inserted and no save is attempted

#### Scenario: Add Save emits expense_logged with correct isAddFunds

- **WHEN** the user activates Save in Add mode with `isAddFunds = true`, `amount = 25.00`, and the save succeeds
- **THEN** the `expense_logged` analytics event is fired with `AnalyticsProperty.isAddFunds: true`

- **WHEN** the user activates Save in Add mode with `isAddFunds = false`, `amount = 5.00`, and the save succeeds
- **THEN** the `expense_logged` analytics event is fired with `AnalyticsProperty.isAddFunds: false`

#### Scenario: Failed Add-mode save keeps the sheet open and does not fire expense_logged

- **WHEN** the user activates Save in Add mode and the persistence-save helper throws
- **THEN** the sheet remains open with the drafted values intact, the save-error alert is presented, and the `expense_logged` event is not fired

### Requirement: Save in Edit mode mutates only changed fields and bumps lastModified once

When the user activates Save in Edit/View mode, the system SHALL compare each editable field on the existing `ExpenseItem` to its corresponding draft value. For each field whose stored value differs from the draft value, the system SHALL write the draft value back to the `ExpenseItem`. The system SHALL set `ExpenseItem.lastModified = Date()` exactly once if at least one field changed. If no field changed, the system SHALL NOT mutate `lastModified` and SHALL NOT attempt a save. After mutating any field, the system SHALL persist via the shared persistence-save helper (operation `expense_edit`), which throws on failure. The view SHALL dismiss the sheet only when the save returns without error; on a thrown persistence error it SHALL present the save-error alert and SHALL NOT dismiss, leaving the mutated-but-unsaved `ExpenseItem` so a Retry re-attempts the same save.

The fields compared are:

- **Amount**: compared as `expense.displayAmount != newAmount` (where `newAmount` is the unwrapped draft `amount`).
- **Description**: compared as `expense.name != trimmedName`.
- **Date**: compared via `Calendar.current.isDate(expense.date, equalTo: date, toGranularity: .minute)`. Sub-minute differences SHALL NOT count as a change.

The system SHALL NOT touch any other persisted field of `ExpenseItem` (notably `expenseType`, `createdAt`, `id`, the `budget` relationship). The `expense_edited` event SHALL fire only on a successful save; on a thrown persistence error it SHALL NOT fire.

#### Scenario: No-op Save does not bump lastModified

- **WHEN** the user opens the sheet for an existing `ExpenseItem`, makes no changes, and taps Save
- **THEN** the `ExpenseItem.lastModified` is unchanged and no save is invoked

#### Scenario: Single-field change updates lastModified once

- **WHEN** the user changes only the description on an existing `ExpenseItem` and taps Save and the save succeeds
- **THEN** the `ExpenseItem.name` is updated, `lastModified` is set to a `Date()` greater than its prior value, and no other persisted field is mutated

#### Scenario: Multi-field change is batched into a single save

- **WHEN** the user changes both the description and the amount on an existing `ExpenseItem` and taps Save and the save succeeds
- **THEN** both fields are written, `lastModified` is set to a single `Date()` value, and the save helper is called exactly once for the whole edit

#### Scenario: Sub-minute date change is treated as no-op

- **WHEN** the user opens the sheet, the picker emits a sub-minute drift on the Date, and the user taps Save without any other change
- **THEN** the `ExpenseItem.lastModified` is unchanged and no save is invoked

#### Scenario: Failed Edit-mode save keeps the sheet open

- **WHEN** the user changes a field, taps Save, and the persistence-save helper throws
- **THEN** the sheet remains open with the edits intact, the save-error alert is presented, and `expense_edited` is not fired

### Requirement: Delete in Edit mode removes the row; Delete in Add mode is a no-op

The `AddEditExpenseViewModel` delete method SHALL behave as follows:

- In **Edit/View mode**, the method SHALL invoke `context.delete(expense)` for the editing `ExpenseItem` and SHALL persist via the shared persistence-save helper (operation `expense_delete`) once. The method SHALL surface a persistence-save failure to its caller rather than swallowing it with `try?`.
- In **Add mode**, the method SHALL be a no-op: it SHALL NOT call `context.delete`, SHALL NOT save, and SHALL NOT mutate any state.

The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The VM SHALL NOT consult `AppSettings` from delete. `ExpenseItem` has no child relationships, so no cascade is needed. The view SHALL dismiss only on a successful delete; on failure it SHALL present the save-error alert and SHALL NOT dismiss.

#### Scenario: Delete in Edit mode removes the expense and saves once

- **WHEN** a test constructs an `AddEditExpenseViewModel` in Edit mode for an existing `ExpenseItem` and invokes the delete method against an in-memory `ModelContext`, and the save succeeds
- **THEN** the `ExpenseItem` is removed from the store, the save helper is invoked exactly once, and the in-memory `ModelContext` no longer returns the expense from a `FetchDescriptor<ExpenseItem>` query

#### Scenario: Delete is a no-op in Add mode

- **WHEN** a test constructs an `AddEditExpenseViewModel` in Add mode and invokes the delete method against an in-memory `ModelContext` containing zero or more pre-existing `ExpenseItem` rows
- **THEN** the in-memory store contents are unchanged: no `ExpenseItem` is inserted, deleted, or mutated, and no save is invoked as a result of the call

#### Scenario: Failed Edit-mode delete keeps the sheet open

- **WHEN** the user confirms Delete Expense and the persistence-save helper throws
- **THEN** the sheet remains open and the save-error alert is presented
