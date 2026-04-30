## Context

`BudgetDetailView` currently uses `allowsFullSwipe: false` on the trailing swipe action for expense rows, and the swipe button sets `expenseToDelete` + `showDeleteConfirm = true` to trigger a `.confirmationDialog`. The dialog requires the user to tap a second time to confirm deletion.

Swipe-to-delete in a UIKit/SwiftUI `List` is a well-established iOS affordance. The system-standard full-swipe gesture (trailing edge) is sufficient destructive intent signal on its own — the animation and red background provide clear affordance. The confirmation dialog adds a tap and a modal that interrupts the flow without meaningful safety value for low-stakes data like an individual expense entry.

## Goals / Non-Goals

**Goals:**
- Enable `allowsFullSwipe: true` so a full trailing swipe immediately deletes an expense row.
- Remove the confirmation dialog and all associated state (`expenseToDelete`, `showDeleteConfirm`, `.confirmationDialog`).
- Remove the four dialog-only localization keys from `Localizable.xcstrings`.
- Keep the explicit swipe button (partial swipe still shows the red "Delete" button and tapping it deletes directly).
- Update tests to reflect that the dialog flow no longer exists.

**Non-Goals:**
- Undo/undo-snackbar support (not in scope for this change).
- Changing the delete behavior in `AddEditExpenseView` (that screen retains its own confirmation dialog).
- Any data-model, navigation, or CloudKit changes.

## Decisions

### Direct call to `deleteExpense(_:)` from swipe action
**Decision:** The swipe button action calls `deleteExpense(expense)` directly.  
**Rationale:** The two state variables (`expenseToDelete`, `showDeleteConfirm`) existed solely to bridge the swipe action to the dialog. Removing the dialog eliminates the need for this indirection. The `deleteExpense` function is already defined in `BudgetDetailView+ExpenseSection.swift` and handles `context.delete`, `context.save`, and `refreshLifecycle()`.  
**Alternative considered:** Keep the state vars and just change `showDeleteConfirm = true` to call `deleteExpense`. Rejected — the state vars would become dead code and should be cleaned up.

### `allowsFullSwipe: true`
**Decision:** Set `allowsFullSwipe: true` on the trailing swipe action.  
**Rationale:** Without a confirmation step, full-swipe is now safe to enable. This matches the iOS standard list delete gesture (used by Mail, Reminders, etc.) and is what most users expect.  
**Alternative considered:** Leave `allowsFullSwipe: false` to require the button tap. Rejected — the confirmation dialog was the primary reason for preventing full swipe. Now that it's gone, blocking full swipe would be inconsistent with platform norms.

### Localization cleanup
**Decision:** Remove the four `budgetDetail.deleteExpense.dialog.*` keys from `Localizable.xcstrings`.  
**Rationale:** These strings are only referenced by the `.confirmationDialog` being removed. Leaving them would create dead entries that mislead future translators.

### Tests
**Decision:** Remove or rewrite tests that specifically verify the confirmation dialog trigger path. Keep `DeleteExpenseAlgorithmTests` unchanged — those test the underlying `context.delete` + save algorithm, which is unchanged.  
**Rationale:** The dialog trigger was a UI-interaction concern, not a data-integrity concern. The algorithm tests already cover the core correctness guarantee.

## Risks / Trade-offs

- **Accidental deletion with no undo** — Without the confirmation dialog or an undo mechanism, a user who full-swipes accidentally has no recovery path (other than re-adding the expense). The risk is acceptable: expenses are individually small, the full-swipe gesture requires deliberate intent, the action is localized to a single row, and the existing "Delete" button tap (partial swipe) provides a clear visual warning before action. An undo mechanism is a separate, larger feature.
- **VoiceOver / a11y** — VoiceOver users trigger swipe actions via the accessibility rotor, which always shows the action label ("Delete"). The behavior change is transparent to them; the action label is unchanged and still requires an intentional activation.
