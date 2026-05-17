## Why

When a user confirms Reset Budget on a paused budget, they are left in an unusable limbo: all expenses wiped and carry-over zeroed, but the budget still paused and unable to accept new expenses. The intent of "start fresh" implies an active, ready-to-use budget, and requiring a separate Resume tap to complete that intent is unnecessary friction.

## What Changes

- The Reset Budget confirmation dialog body copy is updated to inform the user that a paused budget will also be resumed.
- The accessibility hint on the Reset Budget menu item is updated to match.
- `BudgetLifecycleService.resetBudget(...)` is extended so that, before its single `context.save()`, it checks the current lifecycle state and — if the budget is paused — inserts a `LifecycleEvent(kind: .resume, effectiveDate: now)` into the same context. The view layer is unchanged.
- The `arrow.counterclockwise` system image replaces `trash` for the Reset Budget menu item (already applied in code; spec updated to match).
- The existing `budget-detail-screen` Reset Budget requirement is corrected for pre-existing drift: the operational steps now reference `Budget.lastResetDate` (the actual stored field) instead of `Budget.carryOverAmount = 0` and `Budget.carryOverLastResetDate` (fields that were removed by the budget-calculations rewrite and are no longer present on the model).

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `budget-detail-screen`: Reset Budget write-path behavior changes — auto-resumes a paused budget; dialog body copy updated; system image updated from `trash` to `arrow.counterclockwise`.

## Impact

- `BudgetLifecycleService.resetBudget(...)` — gains an internal paused-state check that inserts a `.resume` `LifecycleEvent` before the single `context.save()`. No public API change.
- `BudgetDetailView` — no code change; continues to call `BudgetLifecycleService.resetBudget(...)` exactly as it does today.
- `budget-detail-screen` spec — Reset Budget requirement reworded around the service-delegation pattern, operational steps corrected to match the current `Budget` model fields, dialog body copy updated, scenario set extended to cover paused and active branches.
- `docs/product-features-planning.md` F-2.02 and `docs/main-prd.md` §6.7 + glossary entry for "Reset Budget" — short addition noting that a paused budget is also resumed.
- String Catalog (`Localizable.xcstrings`) — `budgetDetail.resetBudget.dialog.message` and `budgetDetail.menu.resetBudget.accessibilityHint` values updated (en-US and translations queue).
- No data-model, CloudKit schema, or analytics-event changes required; the existing `budget_reset` Mixpanel event already fires after the full write path completes. The auto-resume is deliberately not surfaced as a separate `budget_resumed` event because it is system-initiated, not a user-initiated resume action.
