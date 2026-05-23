## Why

F-6.01 ("Allow manually adding funds") has been partially implemented for some time — the data model is signed (`ExpenseItem.amount` allows negatives, with `isAddFunds` / `displayAmount` derived), the Budget detail row already tints add-funds entries green and announces them distinctly via VoiceOver, and the analytics surface already carries an `isAddFunds` property on `expense_logged` / `expense_edited` / `expense_deleted`. What's missing is the user-facing way to **create** an add-funds entry in the first place: today, the Add Expense sheet unconditionally writes a positive amount. This change closes that gap so users can record reimbursements, refunds, cash gifts, or other inflows directly into a budget without back-channel workarounds.

## What Changes

- Add an "Add funds" Toggle card at the end of the Add/Edit Expense form (after the When card, before Delete in Edit mode), with a `.tint(.accentColor)` switch and an explanatory caption: *"Adds to your remaining balance instead of subtracting."*
- When the toggle is flipped on, the navigation title swaps from "Add Expense" → "Add Funds" (Add mode) and "Expense" → "Add Funds" (Edit mode — the same string in both modes, breaking the Expense/Add Expense symmetry because "Funds" alone reads awkwardly); the amount-field text and currency prefix tint to `Color.moneySurplus`; and — only if the Description field is empty/whitespace — the field is seeded with the localized default "Add funds". The seed is one-way: toggling back off does not clear it.
- Wire the Add-mode `save()` path to apply the sign on the inserted `ExpenseItem.amount` per the toggle (currently writes amount as-is regardless of sign intent).
- Wire `init(editing:)` in `AddEditExpenseViewModel` to seed `isAddFunds` from the bound `ExpenseItem.isAddFunds` so tap-to-edit on an existing add-funds row opens the sheet in the correct state (toggle on, amount tinted, title says "Funds").
- Allow flipping the toggle in Edit mode: the existing Edit-mode `save()` already preserves the sign, but `expense.amount = expense.isAddFunds ? -newAmount : newAmount` reads the **persisted** `isAddFunds`, not the draft. Update it to read the viewmodel's current `isAddFunds`, so a user who flips the toggle during edit gets a corresponding sign flip on Save.
- Rename the unnamed-row placeholder `budgetDetail.expenseRow.unnamed` from "Untitled expense" to "Untitled" so it reads naturally for both expense and add-funds rows.
- Update F-2.04 in `docs/product-features-planning.md` to remove the line stating "Add mode unconditionally inserts a non-negative amount" (and the parenthetical pointer to "F-6.01's future change"); F-6.01 itself moves from "Partially implemented" to "Implemented" with concrete ACs filled in.

Out of scope (intentionally deferred): new analytics events (the existing `isAddFunds` property is sufficient); changes to the Budgets-list per-row "Add Expense" button label or any second entry point — the toggle remains the single discrete affordance.

## Capabilities

### New Capabilities

(none — this change extends and finishes existing capabilities)

### Modified Capabilities

- `add-edit-expense-screen`: add the Add Funds toggle + caption card, the sign-on-save behavior in Add mode, the Edit-mode init seeding from `expense.isAddFunds`, the navigation-title flip, the amount tinting rule, and the description default-seed behavior. Amend the existing "non-negative amount in Add mode" requirement (and matching scenarios) to reflect the new toggle-driven sign.
- `budget-detail-screen`: rename the unnamed-row placeholder from "Untitled expense" to "Untitled" so the same key reads naturally for both transaction types (key `budgetDetail.expenseRow.unnamed` stays; only the localized value and comment change).

## Impact

- Code: `simple-recurring-budgets/Views/AddEditExpenseView.swift` (mockup UI already in place from prior session; remaining wiring is the Add-mode sign and the Edit-mode sign-flip read); `simple-recurring-budgets/Views/BudgetDetailView+ExpenseSection.swift` (already updated for the "Untitled" copy change); `simple-recurring-budgets/Previews/BudgetDetailFixtures.swift` (already interleaves add-funds entries into three preview fixtures).
- Tests: `simple-recurring-budgets-Tests/AddEditExpenseViewModelTests.swift` — new tests for Add-mode sign on save, Edit-mode init seeding, Edit-mode sign flip via toggle, description default seed (only when empty, one-way), and that toggling the picker does not affect a non-empty description.
- Data model: no schema changes. `ExpenseItem.amount` already supports negative values; `isAddFunds` and `displayAmount` already derived. No migration required.
- Analytics: no new events or properties. Existing `expense_logged` / `expense_edited` / `expense_deleted` events already carry `isAddFunds`. Verify the Add-mode write produces the correct value through the existing call site.
- Localization (cross-cutting per main-prd.md §6.8): new keys `addEditExpense.addFunds.toggle.label`, `addEditExpense.addFunds.toggle.caption`, `addEditExpense.field.name.addFundsDefault`, `addEditExpense.title.add.addFunds`, `addEditExpense.title.existing.addFunds`, `addEditExpense.field.amount.accessibilityLabel.addFunds`; modified value for existing key `budgetDetail.expenseRow.unnamed`. All require translations for all 38 storefront locales via `scripts/translate_catalog/`.
- Accessibility (cross-cutting): the Toggle reads via SwiftUI's default `Toggle` VoiceOver semantics; the amount field's accessibility label is conditional ("Funds amount" vs "Expense amount"); the navigation-title flip is announced naturally by VoiceOver on focus.
- Documentation: update `docs/product-features-planning.md` (F-6.01 → Implemented with ACs; F-2.04 amendment removing the "non-negative" line). No `docs/tech-design-doc.md` or `docs/main-prd.md` updates required (no architecture, schema, or global-constraint changes).

## Doc alignment

- `docs/main-prd.md` — no conflict.
- `docs/product-features-planning.md` — F-6.01 currently lists empty Acceptance Criteria and "Partially implemented" status; this change fills both. F-2.04 currently says Add mode unconditionally inserts a non-negative amount — this change retires that line. Both updates are part of the tasks list, not deferred.
- `docs/tech-design-doc.md` — no conflict.
