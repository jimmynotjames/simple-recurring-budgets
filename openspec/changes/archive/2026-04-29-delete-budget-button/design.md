## Context

`AddEditBudgetView` is the single SwiftUI sheet used for both creating and editing a `Budget` (per F-2.03 / `add-edit-budget-screen` capability). Today there is no in-app way to delete a budget — the only deletion path is the debug "Wipe All Data" action in `simple_recurring_budgetsApp`. A working draft of a Delete Budget button has already been added in this branch:

- `AddEditBudgetView` shows a destructive bordered button at the bottom of the form when `viewModel.isEditing` is `true`.
- Tapping it presents a `confirmationDialog` whose only explicit button is a destructive **Delete Budget** action; SwiftUI provides the implicit Cancel automatically.
- `AddEditBudgetViewModel.delete(context:)` deletes the editing `Budget` and saves; in Add mode it returns early.
- Four localized keys (`addEditBudget.action.delete`, `.delete.accessibilityLabel`, `addEditBudget.deleteConfirmation.title`, `addEditBudget.deleteConfirmation.confirm`) are present in `Localizable.xcstrings`.

The data layer already supports cascade deletion of expenses: `Budget`'s relationship to `ExpenseItem` is declared as `@Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)`, and `ModelTests.budget_cascadeDeletesExpenses` covers that contract. `BudgetsView` uses `@Query(sort: \Budget.sortOrder)`, so a deleted row disappears reactively without manual refresh.

What is missing today is documentation alignment (F-2.03 in `docs/product-features-planning.md` does not mention deletion, and the `add-edit-budget-screen` spec has no Delete requirements), a VoiceOver hint conveying that the button is destructive, and Swift Testing coverage for the VM's `delete(context:)` method.

## Goals / Non-Goals

**Goals:**

- Make Delete Budget a documented, first-class action in the F-2.03 acceptance criteria and in the `add-edit-budget-screen` capability spec.
- Surface the action only in Edit mode — Add mode never shows or invokes a delete path (no orphan budget exists yet).
- Use a destructive `confirmationDialog` so destruction always requires an explicit second tap; rely on SwiftUI's implicit Cancel to satisfy HIG.
- Bind into the existing SwiftData + CloudKit pipeline (`ModelContext.delete` + `ModelContext.save`), letting the existing `Budget → ExpenseItem` cascade rule clean up child expense items in a single save.
- Keep the VM testable in isolation: `delete(context:)` accepts the context at the call site, never stores it, and never touches `AppSettings`.
- Add a VoiceOver hint that announces the destructive nature of the button.

**Non-Goals:**

- A separate Budget detail screen (F-2.02 / Budget screen) and any deep-link delete entry point on it.
- Sort-order densification after deletion. Sparse `sortOrder` integers are fine for `@Query(sort: \Budget.sortOrder)` and for the existing `Budget.nextSortOrder(for:)` insert path.
- Soft delete, undo, or trash semantics. Deletion is immediate and final from the user's perspective; CloudKit history is the only recovery mechanism.
- Bulk delete (e.g., multi-select on the Budgets list). The Budgets-screen capability owns reordering, not bulk delete.
- Any change to Reset Cadences behavior (still PAUSED).
- Any change to CKRecord schema, container configuration, or settings keys.

## Decisions

### Decision 1 — Place the Delete button at the bottom of the form, not in the toolbar

**Rationale**: HIG discourages destructive actions in nav-bar toolbar items where users routinely tap to navigate. The bottom-of-form bordered red button keeps the destructive action visually distinct from the leading Cancel and trailing Save toolbar items, and matches Apple's first-party patterns (e.g., Calendar's "Delete Event" at the bottom of the edit sheet).

**Alternatives considered**:

- A trailing toolbar `trash` button: more discoverable but invites accidental taps next to Save.
- A swipe-to-delete on the Budgets list row: would split delete UX between two screens and wouldn't align with the chosen "edit-everything-on-one-sheet" pattern.

### Decision 2 — Use `confirmationDialog` (not `alert`) with implicit Cancel

**Rationale**: `confirmationDialog(_:isPresented:titleVisibility:)` with a single `role: .destructive` button automatically renders an OS-localized Cancel and emphasises the destructive choice in red. This avoids hardcoding our own Cancel string and matches HIG. The `titleVisibility: .visible` keeps the title ("Delete Budget?") on screen so the question is unambiguous.

**Alternatives considered**:

- `alert` with two buttons: works but requires our own Cancel string and a manual destructive-style handler; less idiomatic on iOS 17+.

### Decision 3 — Render the button only when `viewModel.isEditing == true`

**Rationale**: In Add mode there is no persisted `Budget` to delete; rendering a "Delete Budget" button there would either be a no-op (confusing) or would have to mean "Cancel" (redundant with the Cancel toolbar). Edit-mode-only is consistent with how Apple Mail's Edit Draft / Edit Reminder dialogs behave.

The VM's `delete(context:)` retains its own `guard case let .edit(budget) = mode` early return so a misuse of the API (e.g., a future caller invoking `delete` from Add mode) cannot insert garbage into the store.

### Decision 4 — Reuse the existing cascade-delete relationship on `Budget → ExpenseItem`

**Rationale**: The `@Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)` rule on `Budget` already removes child `ExpenseItem`s when the parent is deleted; this is locked in by `ModelTests.budget_cascadeDeletesExpenses`. The VM only needs to call `context.delete(budget)` and `context.save()` — no manual child traversal, no separate fetch.

CloudKit propagates the parent-record deletion through the standard private database path; SwiftData materialises the cascade as individual child deletions inside the same `ModelContext.save()` call.

### Decision 5 — Pass `ModelContext` to `delete(context:)` at the call site

**Rationale**: This matches the established VM contract documented in the existing `add-edit-budget-screen` spec ("VM exposes a save method that takes ModelContext at the call site") and `docs/tech-design-doc.md` §2.1: "Methods that need to write take `(context: ModelContext, ...)` at the call site". The VM never owns a context.

### Decision 6 — Add a VoiceOver hint to communicate destructiveness

**Rationale**: SwiftUI's `Button(role: .destructive)` is announced by VoiceOver as "Delete Budget, button" without further context. A hint such as "Permanently deletes this budget and its expenses" makes the consequence explicit before the user activates the button. No separate `accessibilityLabel` override is applied — VoiceOver synthesises the label from the button's visible text (`addEditBudget.action.delete`), keeping the key count minimal and avoiding a key-divergence risk during translation.

A new key `addEditBudget.action.delete.accessibilityHint` will be added to `Localizable.xcstrings` with the en-US default value `"Permanently deletes this budget and its expenses."` and a translator comment.

### Decision 7 — Dismiss the sheet on confirm

**Rationale**: After `viewModel.delete(context:)`, calling `dismiss()` from the destructive button's action drops the sheet. The Budgets-screen `@Query` then re-renders without the row. This keeps the flow coherent: the sheet for an entity that no longer exists should not remain on screen.

The pre-existing TODO in `AddEditBudgetViewModel` ("If we eventually create a BudgetView that navigates to this screen, that may also need to be popped off nav stack on deletion.") remains as a future-facing note. F-2.02's Budget screen does not exist yet; when it ships, the design for that screen will own its own pop-on-delete behaviour. We will not pre-build that path here.

## Risks / Trade-offs

- **[Risk]** A user accidentally taps Delete and confirms. **Mitigation**: a destructive `confirmationDialog` requires an explicit second tap; the title text "Delete Budget?" with `.visible` titleVisibility makes the question explicit; SwiftUI's implicit Cancel is the default-focused button on tvOS / Apple Watch (irrelevant here, iOS-only). No undo is offered — users must re-create the budget if they regret it. CloudKit private-database history is the last-resort recovery.
- **[Risk]** Deleting a budget while another device is editing the same record (CloudKit). **Mitigation**: SwiftData / CloudKit treats deletion as authoritative; the other device's pending mutations on the same record will resolve to "record gone" on next sync. This is the same risk as any concurrent edit and is not unique to delete.
- **[Risk]** Sparse `sortOrder` after several deletions. **Mitigation**: `@Query(sort: \Budget.sortOrder)` is order-stable across sparse integer sequences, and `Budget.nextSortOrder(for:)` returns max+1 (already covered by the budgets-screen capability). No densification is required.
- **[Risk]** Cascade delete misfires (orphaned `ExpenseItem`s). **Mitigation**: covered by `ModelTests.budget_cascadeDeletesExpenses`; this change adds an additional VM-level test that exercises the user-facing path end-to-end.
- **[Trade-off]** Edit-mode-only visibility means a brand-new (Add-mode) Budget cannot be "deleted from the form" — the user has to tap Cancel instead. This is intentional and documented (see Decision 3).

## Migration Plan

This is a UX-only addition with no schema or sync changes; no migration is required.

- All current users see the new Delete button the next time they open Edit mode after upgrading. Their existing data is untouched.
- CloudKit record types and fields are unchanged. Any existing iCloud-paired devices will not need a migration round-trip when the new build lands.

## Open Questions

- None. The implementation is already drafted and the only remaining gaps are the spec, the doc updates, the accessibility hint, and the VM test coverage — all enumerated in `tasks.md`.
