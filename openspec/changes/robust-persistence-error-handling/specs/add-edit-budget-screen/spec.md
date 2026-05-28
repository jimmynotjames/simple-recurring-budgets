## MODIFIED Requirements

### Requirement: VM exposes a save method that takes ModelContext at the call site

The `AddEditBudgetViewModel` SHALL expose a `save` method that takes `ModelContext` at the call site and performs the Add or Edit branch documented below. The method SHALL surface a persistence-save failure to its caller — it SHALL be marked `throws` (or otherwise report failure), routing its `context.save()` through the shared persistence-save helper rather than `try? context.save()`. The view SHALL read `@Environment(\.modelContext)`, invoke the save method from inside `body`, and dismiss the sheet **only** when the call returns without error; on a thrown persistence error the view SHALL present the standard save-error alert and SHALL NOT dismiss (see the `persistence-error-handling` capability). The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The save body SHALL NOT consult `AppSettings` — `AppSettings` is read only at construction time via `init(settings:)` to seed the Add-mode Carry-Over default.

#### Scenario: Save reports failure to the caller

- **WHEN** the `AddEditBudgetViewModel` save method is inspected
- **THEN** it surfaces a persistence-save failure to its caller (e.g. it is marked `throws`) and routes its save through the shared persistence-save helper, not `try? context.save()`

#### Scenario: View dismisses only on a successful save

- **WHEN** the user activates Save and the save method returns without error
- **THEN** the sheet dismisses; **AND WHEN** the save method throws a persistence error, the sheet stays open and the save-error alert is shown

### Requirement: Save in Add mode inserts a new Budget with the next sortOrder

When the user activates Save in Add mode, the system SHALL:

0. **Guard:** If validation would disable Save (`!canSave`), the implementation SHALL return without inserting a `Budget` (defence in depth if the save method is invoked without a valid draft).
1. Build a `Budget` using `Budget.init` with the drafted `name` (post-trim, but the model stores the user's value as entered; trimming is for validation only), the drafted `currencyCode`, the drafted `period`, and the drafted `isCarryOverEnabled`.
2. Set `budget.startDate = calendar.startOfDay(for: viewModel.startDate!)`. The drafted `startDate` is non-`nil` by canSave (specific dates) or by the Add-mode pre-fill + `period.didSet` re-anchoring rule (recurring). For weekly / biweekly the drafted value may be the AppSettings-derived anchor (default) or a user-overridden date — both paths are stored as the budget's `startDate`, which becomes the per-budget cycle anchor per F-7.05.
3. Set `budget.endDate = viewModel.endDate.map { calendar.startOfDay(for: $0) }`. For `.specificDates`, `endDate` is non-`nil` by `canSave`. For recurring period types it is optional — `nil` is the common case for "no terminal date."
4. For `.specificDates` only, force-clamp `isCarryOverEnabled = false` before insert (the toggle is hidden on the Add/Edit sheet for this period type; without the clamp, a pre-toggle session default of `true` would persist a stale value that pollutes analytics cohorts that read `Budget.isCarryOverEnabled` directly).
5. Set `budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0` BEFORE inserting, so the fetch does not include the new instance.
6. Call `context.insert(budget)`.
7. Insert one initial `AllocationChange(effectiveFrom: budget.startDate!, amount: drafted allocation, lastModified: Date())` attached to the same budget.
8. Persist via the shared persistence-save helper (operation `budget_create`), which throws on failure; the method propagates that error to the caller instead of swallowing it with `try?`.
9. On success, the view dismisses the sheet. On a thrown persistence error, the view presents the save-error alert and does not dismiss; the just-inserted (but unsaved) `Budget` remains in the context so a Retry re-attempts the same save.

The new budget SHALL appear in the Budgets screen list immediately due to the existing `@Query(sort: \Budget.sortOrder)` reactivity once the save succeeds. CloudKit sync SHALL propagate the new row through the existing pipeline; no new container or schema changes are introduced.

#### Scenario: First budget gets sortOrder 0

- **WHEN** the store is empty and the user creates a `Budget` via Save
- **THEN** the inserted `Budget` has `sortOrder == 0`

#### Scenario: Subsequent budget gets next sortOrder

- **WHEN** the store contains budgets with `sortOrder` values up to `N`, and the user creates a `Budget` via Save
- **THEN** the inserted `Budget` has `sortOrder == N + 1`

#### Scenario: Save inserts exactly one budget

- **WHEN** the user activates Save in Add mode and the save succeeds
- **THEN** the store contains exactly one new `Budget` whose fields match the drafted values

#### Scenario: Failed Add-mode save keeps the sheet open

- **WHEN** the user activates Save in Add mode and the persistence-save helper throws
- **THEN** the sheet remains open with the drafted values intact and the save-error alert is presented

#### Scenario: Recurring Save uses pre-filled startDate

- **WHEN** the user creates a `.daily` budget without touching the Schedule disclosure
- **THEN** the inserted `Budget.startDate` equals `calendar.startOfDay(for: Date())` (the Add-mode pre-fill) AND the initial `AllocationChange.effectiveFrom` equals the same value AND `Budget.endDate` is `nil`

#### Scenario: Recurring Save honors a user-overridden startDate

- **WHEN** the user creates a `.weekly` budget, expands the Schedule disclosure, picks a Thursday three weeks ago via the start-date chip, and taps Save
- **THEN** the inserted `Budget.startDate` equals the picked Thursday at `startOfDay`, AND the initial `AllocationChange.effectiveFrom` equals the same value — the cycle anchor becomes Thursday per F-7.05 (`weekStart = budget.startDate.weekday`)

#### Scenario: Recurring Save persists an optional endDate

- **WHEN** the user creates a `.monthly` budget and picks an end date six months in the future via the Schedule disclosure
- **THEN** the inserted `Budget.endDate` equals the picked date at `startOfDay`

#### Scenario: Specific Dates Save writes both startDate and endDate

- **WHEN** the user creates a `.specificDates` budget with `startDate = 2026-05-08`, `endDate = 2026-05-25`, allocation `1500`
- **THEN** the inserted `Budget` has `startDate == startOfDay(2026-05-08)`, `endDate == startOfDay(2026-05-25)`, and one `AllocationChange(effectiveFrom: startDate, amount: 1500)`

#### Scenario: Recurring Save leaves endDate nil by default

- **WHEN** the user creates a `.daily`, `.weekly`, `.biweekly`, or `.monthly` budget without setting an end date in the Schedule disclosure
- **THEN** the inserted `Budget.endDate` is `nil`

### Requirement: Save in Edit mode mutates only changed fields and bumps lastModified once

When the user activates Save in Edit mode, the system SHALL compare each editable field on the existing `Budget` to its corresponding draft value. For each field whose stored value differs from the draft value, the system SHALL write the draft value back to the `Budget`. The system SHALL set `Budget.lastModified = Date()` exactly once if at least one field changed. If no field changed, the system SHALL NOT mutate `Budget.lastModified` and SHALL NOT attempt a save. After mutating any field, the system SHALL persist via the shared persistence-save helper (operation `budget_edit`), which throws on failure. The view SHALL dismiss the sheet only when the save returns without error; on a thrown persistence error it SHALL present the save-error alert and SHALL NOT dismiss, leaving the mutated-but-unsaved `Budget` so a Retry re-attempts the same save.

#### Scenario: No-change Edit save does not persist or dismiss-as-saved

- **WHEN** the user activates Save in Edit mode without changing any field
- **THEN** no save is attempted and `Budget.lastModified` is not mutated

#### Scenario: Failed Edit-mode save keeps the sheet open

- **WHEN** the user changes a field, activates Save, and the persistence-save helper throws
- **THEN** the sheet remains open with the edits intact and the save-error alert is presented

### Requirement: ViewModel exposes a delete method that takes ModelContext at the call site

The `AddEditBudgetViewModel` SHALL expose a `delete` method taking `ModelContext` at the call site with the following contract:

- In **Edit mode**, the method SHALL invoke `context.delete(budget)` for the editing `Budget` and SHALL persist via the shared persistence-save helper (operation `budget_delete`) once. The method SHALL surface a persistence-save failure to its caller (e.g. by being marked `throws`) rather than swallowing it with `try?`.
- In **Add mode**, the method SHALL be a no-op: it SHALL NOT call `context.delete`, SHALL NOT save, and SHALL NOT mutate any state.

The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The VM SHALL NOT consult `AppSettings` from the delete method. The method SHALL rely on the existing `Budget → ExpenseItem` cascade-delete relationship (`@Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)`) to remove the budget's `ExpenseItem` rows. The VM SHALL NOT manually fetch or delete child `ExpenseItem` instances. The view SHALL dismiss only on a successful delete; on failure it SHALL present the save-error alert and SHALL NOT dismiss.

#### Scenario: Delete in Edit mode removes the budget and saves once

- **WHEN** a test constructs an `AddEditBudgetViewModel` in Edit mode for an existing `Budget` and invokes the delete method against an in-memory `ModelContext`
- **THEN** the `Budget` is removed from the store, the save helper is invoked exactly once, and the in-memory `ModelContext` no longer returns the budget from a `FetchDescriptor<Budget>` query

#### Scenario: Delete is a no-op in Add mode

- **WHEN** a test constructs an `AddEditBudgetViewModel` in Add mode (`init(settings:)`) and invokes the delete method against an in-memory `ModelContext` that contains zero or more pre-existing `Budget` rows
- **THEN** the in-memory store contents are unchanged: no `Budget` is inserted, deleted, or mutated, and no save is invoked as a result of the call

#### Scenario: Delete cascades to ExpenseItem rows in a single save

- **WHEN** a test constructs an `AddEditBudgetViewModel` in Edit mode for a `Budget` that owns one or more `ExpenseItem` rows, and invokes the delete method against an in-memory `ModelContext`
- **THEN** after the call returns, neither the `Budget` nor any of its `ExpenseItem` rows can be fetched from the store; the cascade SHALL be performed by the SwiftData relationship's `deleteRule: .cascade`, not by any manual VM-side traversal

#### Scenario: Failed delete keeps the sheet open

- **WHEN** the user confirms Delete Budget in Edit mode and the persistence-save helper throws
- **THEN** the sheet remains open and the save-error alert is presented
