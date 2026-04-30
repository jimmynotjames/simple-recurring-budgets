## Context

`AddEditExpenseView` serves two entry points:

1. **Add mode** — presented as a sheet (`SheetRoute.addExpense(Budget)`). No record exists yet; Cancel discards the draft entirely; Save inserts a new `ExpenseItem`.
2. **Edit mode** — pushed onto the `NavigationStack` (`AppRoute.expenseDetail(ExpenseItem)`). A record already exists; Save mutates it; the back chevron dismisses without saving.

In Edit mode, the leading Cancel button calls `dismiss()`, which on a pushed view pops it from the stack — identical to the system back chevron. The button is therefore redundant and contrary to iOS convention for pushed edit screens (Calendar, Contacts, etc.), which rely on the back button as the discard path and keep only an explicit commit action (Save/Done) in the trailing position.

## Goals / Non-Goals

**Goals:**
- Hide the Cancel `ToolbarItem` when `viewModel.isEditing == true`.
- Retain Cancel unconditionally in Add mode.
- Retain Save unconditionally in both modes.
- Update the `add-edit-expense-screen` spec to reflect the new toolbar contract.

**Non-Goals:**
- Auto-saving on back navigation (not in scope; Save remains the only write path).
- Any change to Save behavior, enablement, or VoiceOver labels.
- Any change to the Delete Expense button.
- Any change to Add mode presentation or behavior.
- Accessibility label changes (Cancel is simply absent; no replacement needed).

## Decisions

### Gate Cancel on `!viewModel.isEditing`

`viewModel.isEditing` is already the canonical mode discriminator used for the Delete button and the auto-focus behavior. Using the same property keeps the condition consistent and requires no new state.

```swift
// Before
ToolbarItem(placement: .cancellationAction) {
    Button("Cancel") { dismiss() }
}

// After
if !viewModel.isEditing {
    ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
    }
}
```

**Alternative considered — `@Environment(\.isPresented)`**: SwiftUI does not expose a reliable "is this view pushed vs. presented" environment value in the current SDK. Using `isEditing` is simpler and semantically correct: Add mode is always a sheet, Edit mode is always pushed; the mode and the presentation style are 1:1.

**Alternative considered — pass `isPushed: Bool` to the view**: Adds an extra init parameter and couples the view to its presentation context. Not needed since `isEditing` already captures the distinction.

### No spec change to `addEditExpense.action.cancel` string key

The string key and its catalog entry remain. The Cancel string is still used in Add mode. Removing it from the catalog would be premature (it might be needed for future flows). The key is simply not rendered in Edit mode.

## Risks / Trade-offs

**[VoiceOver — no Cancel announcement in Edit mode]** VoiceOver users navigating the Edit mode toolbar will only encounter the Save button. They navigate back via the system back button, which VoiceOver announces as "Back, button". This is standard iOS behavior and is not a regression. → No mitigation needed.

**[Add mode sheet behavior unchanged]** The sheet's `.cancellationAction` placement is provided by a `NavigationStack` wrapper in `RootView`. Removing Cancel in Edit mode does not affect the sheet path. Verified: the gate `!viewModel.isEditing` is `true` in Add mode, so the Cancel button renders as before. → No risk.
