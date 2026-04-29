## ADDED Requirements

### Requirement: Delete Budget button is rendered only in Edit mode

The Add/Edit Budget screen SHALL render a destructive **Delete Budget** button beneath the four cards (Name, Allocation, Period, Carry-Over) when, and only when, the screen is in Edit mode (`viewModel.isEditing == true`). In Add mode the button SHALL NOT be rendered or rendered hidden — there must be no Delete affordance for a draft `Budget` that has not yet been inserted.

The button SHALL be rendered with `.buttonStyle(.bordered)`, tinted red (`.tint(.red)` / destructive role), with its label expanded across the available width via `.frame(maxWidth: .infinity)` to match a full-width destructive footer pattern. The label text SHALL come from the localized key `addEditBudget.action.delete` with English source value `"Delete Budget"`.

The button SHALL declare a VoiceOver hint sourced from `addEditBudget.action.delete.accessibilityHint` (English source `"Permanently deletes this budget and its expenses."`) so assistive-tech users learn the consequence of activation before tapping. No explicit `accessibilityLabel` override is needed; VoiceOver synthesises the label from the button's visible text (`addEditBudget.action.delete`).

#### Scenario: Add mode does not show the Delete button

- **WHEN** the sheet is presented in Add mode (`viewModel.isEditing == false`)
- **THEN** there is no Delete Budget button anywhere on the screen, in the toolbar, or beneath the cards

#### Scenario: Edit mode shows the Delete button below the cards

- **WHEN** the sheet is presented in Edit mode for some `Budget`
- **THEN** a destructive bordered button labeled `"Delete Budget"` (key `addEditBudget.action.delete`) is rendered beneath the four cards, full-width, with `.tint(.red)` and `role: .destructive`

#### Scenario: VoiceOver announces destructive hint

- **WHEN** VoiceOver focuses the Delete Budget button in Edit mode
- **THEN** it announces the hint from `addEditBudget.action.delete.accessibilityHint` in addition to its destructive button trait; the label is synthesised from the button's visible text and no separate `accessibilityLabel` override is applied

### Requirement: Delete Budget action requires a destructive confirmation dialog

Activating the Delete Budget button SHALL present a `confirmationDialog` with `titleVisibility: .visible`. The dialog SHALL expose exactly one explicit button: a destructive confirm button. SwiftUI's implicit Cancel button SHALL provide the cancel path; the implementation SHALL NOT add a redundant cancel button. No other dialog buttons SHALL be added.

- The dialog title SHALL come from `addEditBudget.deleteConfirmation.title` (English source `"Delete Budget?"`).
- The dialog message body SHALL come from `addEditBudget.deleteConfirmation.message` (English source `"This action cannot be undone."`) and SHALL be rendered as a `Text` view in the `message:` trailing closure of `confirmationDialog(_:isPresented:titleVisibility:actions:message:)`.
- The destructive confirm button label SHALL come from `addEditBudget.deleteConfirmation.confirm` (English source `"Delete Budget"`) with `role: .destructive`.

The dialog SHALL be presented from the `AddEditBudgetView` (sheet root) so it is anchored to the form, and SHALL be driven by a private `@State` flag on the view that the Delete button toggles to `true`.

#### Scenario: Tapping Delete opens the confirmation dialog without deleting

- **WHEN** the user taps the Delete Budget button in Edit mode
- **THEN** a confirmation dialog appears with the title from `addEditBudget.deleteConfirmation.title`, the message body from `addEditBudget.deleteConfirmation.message`, a destructive confirm button from `addEditBudget.deleteConfirmation.confirm`, and SwiftUI's implicit Cancel; no `Budget` has been deleted yet and the sheet remains on screen

#### Scenario: Cancelling the dialog leaves the budget intact

- **WHEN** the user opens the confirmation dialog and dismisses it via SwiftUI's implicit Cancel (e.g., taps Cancel or taps outside the dialog where the platform allows)
- **THEN** the editing `Budget` is not deleted, no `ModelContext.save()` is invoked as a result of the dialog interaction, and the sheet remains in Edit mode with all in-flight draft state intact

#### Scenario: Confirming the dialog deletes the budget and dismisses the sheet

- **WHEN** the user taps the destructive confirm button in the dialog
- **THEN** `viewModel.delete(context:)` is invoked with the view's `@Environment(\.modelContext)`, and the sheet is dismissed via `dismiss()` after the VM call returns

### Requirement: ViewModel exposes a delete method that takes ModelContext at the call site

The `AddEditBudgetViewModel` SHALL expose `func delete(context: ModelContext)` with the following contract:

- In **Edit mode**, the method SHALL invoke `context.delete(budget)` for the editing `Budget` and SHALL invoke `try? context.save()` once.
- In **Add mode**, the method SHALL be a no-op: it SHALL NOT call `context.delete`, SHALL NOT call `context.save`, and SHALL NOT mutate any state.

The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The VM SHALL NOT consult `AppSettings` from `delete(...)` — `AppSettings` is read only at construction time via `init(settings:)` for Add-mode seeding, consistent with the existing save contract on the same VM.

The method SHALL rely on the existing `Budget → ExpenseItem` cascade-delete relationship (`@Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)`) to remove the budget's `ExpenseItem` rows. The VM SHALL NOT manually fetch or delete child `ExpenseItem` instances.

#### Scenario: Delete in Edit mode removes the budget and saves once

- **WHEN** a test constructs an `AddEditBudgetViewModel` in Edit mode for an existing `Budget` and invokes `delete(context:)` against an in-memory `ModelContext`
- **THEN** the `Budget` is removed from the store, `context.save()` is invoked exactly once, and the in-memory `ModelContext` no longer returns the budget from a `FetchDescriptor<Budget>` query

#### Scenario: Delete is a no-op in Add mode

- **WHEN** a test constructs an `AddEditBudgetViewModel` in Add mode (`init(settings:)`) and invokes `delete(context:)` against an in-memory `ModelContext` that contains zero or more pre-existing `Budget` rows
- **THEN** the in-memory store contents are unchanged: no `Budget` is inserted, deleted, or mutated, and `context.save()` is not invoked as a result of the call

#### Scenario: Delete cascades to ExpenseItem rows in a single save

- **WHEN** a test constructs an `AddEditBudgetViewModel` in Edit mode for a `Budget` that owns one or more `ExpenseItem` rows, and invokes `delete(context:)` against an in-memory `ModelContext`
- **THEN** after the call returns, neither the `Budget` nor any of its `ExpenseItem` rows can be fetched from the store; the cascade SHALL be performed by the SwiftData relationship's `deleteRule: .cascade`, not by any manual VM-side traversal

### Requirement: Delete Budget localization keys in Localizable.xcstrings

`Localizable.xcstrings` SHALL contain entries for every user-visible string introduced by the Delete Budget feature, each with a non-empty translator `comment`:

- `addEditBudget.action.delete` — Delete Budget button label (also serves as the VoiceOver label via synthesis).
- `addEditBudget.action.delete.accessibilityHint` — VoiceOver hint announcing the destructive consequence.
- `addEditBudget.deleteConfirmation.title` — Confirmation dialog title.
- `addEditBudget.deleteConfirmation.message` — Confirmation dialog message body ("This action cannot be undone.").
- `addEditBudget.deleteConfirmation.confirm` — Destructive confirm button label inside the dialog.

Each key SHALL use the screen-namespaced `addEditBudget.*` prefix already defined for the Add/Edit Budget sheet.

#### Scenario: Catalog contains all Delete Budget localization keys with translator comments

- **WHEN** the app is built
- **THEN** `simple-recurring-budgets/Resources/Localizable.xcstrings` contains entries for `addEditBudget.action.delete`, `addEditBudget.action.delete.accessibilityHint`, `addEditBudget.deleteConfirmation.title`, `addEditBudget.deleteConfirmation.message`, and `addEditBudget.deleteConfirmation.confirm`, and every entry has a non-empty `comment`

#### Scenario: Delete keys reuse the addEditBudget namespace

- **WHEN** an inspector reads the keys introduced by the Delete Budget feature
- **THEN** every key starts with `addEditBudget.`; no key is hoisted into a generic top-level namespace, and no other namespace is reused for delete-related copy
