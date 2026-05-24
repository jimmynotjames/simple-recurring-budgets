## Why

Editing a recurring budget's `startDate` forward past existing expenses silently orphans those expenses: they remain in the budget detail's expense list but are excluded from both `remaining` (current-period filter clamps to `effectiveStartDate`) and `carry-over` (walker's `walkWindowStart = max(effectiveStartDate, lastResetDate ?? .distantPast)`). The user has no signal that the totals on the Budgets list and Budget Detail screens will diverge from the visible expense rows. Validation of the use case showed the divergence is reachable today (`AddEditExpenseView` blocks pre-start expense dates, but `AddEditBudgetView` has no symmetric check before letting the user move `startDate` forward).

## What Changes

- Add a Save-time confirmation alert on the Add/Edit Budget sheet (Edit mode, recurring period types) when the drafted `startDate` is after one or more existing `Budget.expenseItems.date`. Title: `Start date is after N logged expenses`. Body: `Those expenses still show in your list but won't be counted by this budget.` Buttons: `Cancel` / `Save Changes`.
- Add a quieter inline warning (orange `.caption` `Text`, no icon) inside the expanded Schedule disclosure that surfaces the same count + message as soon as the orphaning condition is met during draft editing.
- Auto-expand the Schedule disclosure on `onAppear` when the bound budget already has orphaned expenses, so a user re-opening Edit Budget sees the inline warning without an extra tap.
- No change to `BudgetCalculator`, `CarryOverWalker`, or any data model — orphaned expenses continue to be excluded from carry-over and remaining as today. This change is purely a UI/UX surfacing affordance.
- Out of scope: blocking the save outright; offering to delete the orphaned expenses; symmetric warning for `endDate` moves earlier (a known parallel gap, deferred).

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `add-edit-budget-screen`: adds a new save-flow requirement (orphan-warning confirmation alert before commit), a new inline warning element inside the Schedule disclosure, and a Schedule auto-expand-on-orphan behavior in `onAppear`.

## Impact

- **Code:** `simple-recurring-budgets/Views/AddEditBudgetViewModel.swift` (new `orphanedExpenseCount` computed property, Edit-mode only); `simple-recurring-budgets/Views/AddEditBudgetView.swift` (Save button gating, `.alert(...)`, `onAppear` auto-expand, new `#Preview("Edit — Orphaning start date")`); `simple-recurring-budgets/Views/AddEditBudgetView+Schedule.swift` (inline warning `Text` inside `scheduleExpandedContent`).
- **APIs / data model:** none.
- **Calculator / persistence:** none.
- **Cross-cutting (§6.8):** accessibility (alert + inline warning need standard accessibility treatment), localized source strings (new strings need `String(localized:)` and translations-queue updates), Mixpanel analytics (the existing `budget_edited` event grows a new `orphanedExpenseCount` property when non-zero, so confirmed-orphan saves are measurable; the Cancel branch records no event since the budget was not saved).
- **Docs alignment:** F-2.03 (`docs/product-features-planning.md`) should pick up a sub-bullet under the recurring Start Date / End Date fields documenting the orphan-warning confirmation. No conflicts with `docs/main-prd.md` or `docs/tech-design-doc.md`. F-2.04 already documents the symmetric expense-side guard (`Budget.effectiveStartDate` as the `dateRange` lower bound on `AddEditExpenseView`); the budget-side guard described here is the missing half.
