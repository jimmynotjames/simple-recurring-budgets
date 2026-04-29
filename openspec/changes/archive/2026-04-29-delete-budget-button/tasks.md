## 1. Implementation gap-closing

- [x] 1.1 Add an `accessibilityHint` modifier to the Delete Budget button in `AddEditBudgetView` using a new key `addEditBudget.action.delete.accessibilityHint` with English source value `"Permanently deletes this budget and its expenses."` and a translator comment.
- [x] 1.2 Add a `message:` trailing closure to the `confirmationDialog` in `AddEditBudgetView` using a new key `addEditBudget.deleteConfirmation.message` with English source value `"This action cannot be undone."` and a translator comment, so the dialog body communicates irreversibility.
- [x] 1.3 Add `addEditBudget.action.delete.accessibilityHint` and `addEditBudget.deleteConfirmation.message` to `simple-recurring-budgets/Resources/Localizable.xcstrings` with `extractionState: extracted_with_value` and non-empty `comment`s.
- [x] 1.4 Confirm no other production code references a stale name for `AddEditBudgetViewModel.delete(...)`; the in-code TODO about a future `BudgetView` nav-stack pop stays as documentation, not a blocker.

## 2. Tests (Swift Testing)

- [x] 2.1 Add a test file `simple-recurring-budgetsTests/ViewModels/AddEditBudgetViewModelDeleteTests.swift` (or extend the existing VM test file if one exists) using the `@MainActor` Swift Testing pattern already in the repo.
- [x] 2.2 Test: `delete_inEditMode_removesBudgetAndSavesOnce` — construct an in-memory `ModelContainer`, insert a `Budget`, build `AddEditBudgetViewModel(editing:)`, invoke `delete(context:)`, assert the budget is no longer fetchable via `FetchDescriptor<Budget>`.
- [x] 2.3 Test: `delete_inAddMode_isNoOp` — construct an in-memory `ModelContainer` with one pre-existing `Budget`, build `AddEditBudgetViewModel(settings:)` (Add mode), invoke `delete(context:)`, assert the pre-existing budget is still fetchable and the store contents are unchanged.
- [x] 2.4 Test: `delete_inEditMode_cascadesToExpenseItems` — construct an in-memory `ModelContainer`, insert a `Budget` with one or more `ExpenseItem` rows attached, build the VM in Edit mode, invoke `delete(context:)`, assert neither the parent `Budget` nor its `ExpenseItem` rows can be fetched. (Cascade rule itself is locked in by `ModelTests.budget_cascadeDeletesExpenses`; this test asserts the user-facing path triggers it.)
- [x] 2.5 Run the suite locally with `bash scripts/test.sh` (single iPhone simulator) and confirm all new tests pass alongside the existing suite.

## 3. Documentation updates

- [x] 3.1 Update `docs/product-features-planning.md`:
  - Add a Delete Budget acceptance criterion to **F-2.03** (Add/Edit Budget screen) stating: "**Delete Budget** — Edit mode only, presented as a destructive bordered button beneath the form cards, gated by a `confirmationDialog`. Confirming the dialog deletes the `Budget` and (via the existing `Budget → ExpenseItem` cascade-delete rule) all of its `ExpenseItem` rows in a single `ModelContext.save()`. Add mode does not show the button."
  - Bump the file's "Last Updated" date.
- [x] 3.2 Update `docs/tech-design-doc.md` §3.1 (data model) with a note: the user-facing entry point for `Budget` deletion is the Delete Budget button on the Add/Edit Budget sheet (Edit mode), and the existing `@Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)` rule on `Budget` is what removes the budget's `ExpenseItem` rows. No schema change.
- [x] 3.3 Confirmed `docs/main-prd.md` requires no edits (deletion is not a Carry-Over §6.7 concern and does not affect glossary terms).

## 4. Verify and archive prep

- [x] 4.1 Run `bash scripts/test.sh` (or `make test`) and confirm a green run. ✓ All tests passed.
- [x] 4.2 Run `openspec validate delete-budget-button --strict`. ✓ Change is valid.
- [x] 4.3 **Deferred.** Full manual QA of “row disappears reactively” from the Budgets list ideally exercises edit-from-detail flows; schedule when F-2.02 Budget screen exists. Implemented behavior is covered by unit tests (`AddEditBudgetViewModelTests` delete scenarios) plus code review against the delta spec.
- [x] 4.4 Confirmed `docs/product-features-planning.md` (F-2.03) and `docs/tech-design-doc.md` (§3.1) reflect the shipped behavior and that `Localizable.xcstrings` carries the five delete keys with translator comments (`addEditBudget.action.delete`, `.accessibilityHint`, `.deleteConfirmation.title`, `.deleteConfirmation.message`, `.deleteConfirmation.confirm`). Note: `addEditBudget.action.delete.accessibilityLabel` was dropped during code review — VoiceOver synthesises the label from the button's visible text.
