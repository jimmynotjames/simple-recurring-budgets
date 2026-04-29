## Why

Users have no in-app way to delete a `Budget` once it has been created. Reordering and editing exist, but the only path to remove a budget today is to wipe local data via the debug menu, which is not user-facing. A working draft of a Delete Budget button has been added to `AddEditBudgetView` in Edit mode (with a destructive confirmation dialog and a `ViewModel.delete(context:)` entry point), but it is undocumented: the F-2.03 acceptance criteria do not mention deletion, the `add-edit-budget-screen` capability spec has no Delete requirements, and there are no tests for the delete path. This change documents the addition, closes the small gaps to make the feature ship-ready, and aligns the docs with the implemented behavior.

## What Changes

- **add-edit-budget-screen capability** (modified):
  - Add requirements for a Delete Budget action that is **visible only in Edit mode**, rendered as a destructive bordered button beneath the four cards.
  - Add requirements for a confirmation dialog that gates destruction and uses SwiftUI's standard implicit Cancel.
  - Add requirements for the new VM entry point `func delete(context: ModelContext)` that removes the editing `Budget` and saves; in Add mode it is a no-op.
  - Add requirements that on confirm-delete the sheet dismisses, the row disappears reactively from the Budgets list, and the cascade-delete relationship on `Budget → ExpenseItem` removes the budget's expenses.
  - Extend the existing localization requirement to cover the new keys (`addEditBudget.action.delete`, `addEditBudget.action.delete.accessibilityLabel`, `addEditBudget.deleteConfirmation.title`, `addEditBudget.deleteConfirmation.confirm`) and add a VoiceOver hint key for the Delete button (gap to close).
- **Implementation gaps to close**:
  - Add an `.accessibilityHint` to the Delete button explaining the destructive nature (key `addEditBudget.action.delete.accessibilityHint`).
  - Add Swift Testing coverage for `AddEditBudgetViewModel.delete(context:)`: deletes the editing `Budget`, is a no-op in Add mode, and (via the existing `Budget → ExpenseItem` cascade rule) removes the budget's expense items in the same `ModelContext.save()`.
  - Resolve / re-classify the in-code TODO about popping a future `BudgetView` off the navigation stack on deletion: leave the comment but make explicit in the spec that the only known caller today is the modal Add/Edit Budget sheet, so SwiftUI's `dismiss()` is sufficient. A future `BudgetView` deep-link-to-edit path is out of scope here and tracked under F-2.02.
- **Documentation updates**:
  - `docs/product-features-planning.md` — add a Delete Budget acceptance criterion to **F-2.03** (Add/Edit Budget screen) and a brief note that delete is exposed only in Edit mode.
  - `docs/tech-design-doc.md` — short note in §5 / data model that the user-facing delete entry point lives on the Add/Edit Budget sheet (Edit mode) and relies on the existing cascade rule to remove expenses; no schema or sync change.
  - `docs/main-prd.md` — no glossary or §6.7 changes needed (carry-over math is per-budget; deletion does not affect other budgets' carry-over).

This change does **not** introduce any new schema, CloudKit, or settings surface area, and does not affect Reset Cadences (still PAUSED).

## Capabilities

### New Capabilities

_None._ All behavior fits inside the existing Add/Edit Budget sheet capability.

### Modified Capabilities

- `add-edit-budget-screen`: adds Delete Budget UI (Edit-mode-only button + confirmation dialog), a new `delete(context:)` VM method, and the corresponding localized strings.

## Impact

- **Affected code**:
  - `simple-recurring-budgets/Views/AddEditBudgetView.swift` — already contains the Delete button, dialog, and bindings; this change adds an `.accessibilityHint` and the registered hint string.
  - `simple-recurring-budgets/Views/AddEditBudgetViewModel.swift` — already exposes `delete(context:)`; this change does not modify the implementation.
  - `simple-recurring-budgets/Resources/Localizable.xcstrings` — already contains the four delete keys; this change adds one accessibility hint key.
  - `simple-recurring-budgetsTests/...` — adds a new test file (or extends an existing VM test) covering the `delete(context:)` paths.
- **Affected docs**: `docs/product-features-planning.md` (F-2.03), `docs/tech-design-doc.md` (§5 data-model note).
- **Affected specs**: `openspec/specs/add-edit-budget-screen/spec.md` via delta `openspec/changes/delete-budget-button/specs/add-edit-budget-screen/spec.md`.
- **Sync / persistence**: deletion uses the existing SwiftData + CloudKit pipeline; the `@Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)` rule on `Budget` already cascades to expense items (covered by `ModelTests.budget_cascadeDeletesExpenses`). No CKRecord schema change.
- **Reactivity**: `BudgetsView`'s existing `@Query(sort: \Budget.sortOrder)` removes the deleted row without manual refresh.
- **Sort order**: deletion leaves a sparse `sortOrder` sequence by design. The existing `Budget.nextSortOrder(for:)` insert path is unaffected (it picks max+1), and `@Query` sorts ascending regardless of gaps. Densifying after delete is **not** in scope.

## Doc alignment

Read against the three source-of-truth docs before drafting:

- `docs/main-prd.md` — §6.7 (Carry-Over) and §7 (Glossary) do not constrain budget deletion. No conflict.
- `docs/product-features-planning.md` — F-2.03 lists fields and entry points for Add/Edit Budget but does not currently mention deletion. **Conflict (omission)**: this change adds a Delete Budget acceptance criterion to F-2.03 (resolution: update the doc as part of this change's tasks).
- `docs/tech-design-doc.md` — §5 documents the `Budget → ExpenseItem` cascade-delete relationship. **Aligned**; this change adds a sentence pointing at the user-facing entry point on the Add/Edit Budget sheet so the doc reflects how the cascade is actually triggered from UI.

Docs that will be updated by this change: `docs/product-features-planning.md`, `docs/tech-design-doc.md`. `docs/main-prd.md` will not be updated.
