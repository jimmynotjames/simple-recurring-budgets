## 1. Service Write-Path Update

- [x] 1.1 In `simple-recurring-budgets/Domain/BudgetLifecycleService.swift`, extend `static func resetBudget(_:context:now:)`: after the existing expense-delete loop and the `lastResetDate` / `lastModified` assignments — but **before** the `try? context.save()` — compute the current snapshot via `BudgetCalculator.snapshot(budget:expenses:now:calendar:)` and, if `snapshot.lifecycleState == .paused`, insert `LifecycleEvent(budget: budget, kind: .resume, effectiveDate: now)` into the same `context`
- [x] 1.2 Verify the method still calls `context.save()` exactly once after all mutations (including the optional resume-event insertion); no second save path
- [x] 1.3 Do NOT change the method's signature or default-argument values; do NOT call `BudgetLifecycleService.resumeBudget(...)` from within `resetBudget(...)` (it saves internally and would break atomicity)
- [x] 1.4 No changes to `BudgetDetailView.resetBudget()`; verify the view continues to delegate to the service unchanged

## 2. Localization (cross-cutting per AGENTS.md and main-prd.md §6.8)

- [x] 2.1 In `simple-recurring-budgets/Resources/Localizable.xcstrings`, update the en-US value for `budgetDetail.resetBudget.dialog.message` to: "All expenses will be permanently deleted, carry-over will reset to zero, and if paused, the budget will resume."
- [x] 2.2 In the same file, update the en-US value for `budgetDetail.menu.resetBudget.accessibilityHint` to: "Permanently deletes every expense for this budget, resets carry-over to zero, and resumes the budget if it is paused."
- [x] 2.3 Mark both updated strings as needing re-translation in the String Catalog (status: New / Stale) so the translations queue picks them up

## 3. Tests

- [x] 3.1 In `simple-recurring-budgetsTests/Domain/BudgetLifecycleServiceTests.swift`, add a test: calling `resetBudget` on a non-paused budget with one or more expenses deletes every expense, sets `lastResetDate == now`, sets `lastModified == now`, inserts **no** `LifecycleEvent`, and produces a single saved state (verifiable by post-save fetch)
- [x] 3.2 In the same file, add a test: calling `resetBudget` on a paused budget (seeded with at least one `.pause` `LifecycleEvent` such that the snapshot reports `.paused`) deletes every expense, sets `lastResetDate == now` and `lastModified == now`, inserts exactly one new `LifecycleEvent` with `kind == .resume` and `effectiveDate == now`, and a subsequent `BudgetLifecycleService.result(for:)` call returns `lifecycleState == .active`
- [x] 3.3 In the same file, add a test confirming `resetBudget` on a non-paused budget does NOT insert a resume event even when historical pause/resume events already exist on the budget (i.e., the branch only triggers on current `.paused` state). Also tightens the previous `resetBudget_preservesLifecycleEvents` test (which had been written with an unbalanced `.pause` setup that would now trigger the auto-resume branch).
- [~] 3.4 Optional UI-layer regression test (if `BudgetDetailViewActionsTests.swift` covers reset today): confirm dismissing the dialog still leaves the budget untouched after the wording change — **skipped**. Dialog dismissal is SwiftUI behavior with no unit-test surface in this file; existing service-level tests cover the no-mutation path. The wording change is sourced entirely from `Localizable.xcstrings` via the existing localized `Text(...)` binding, so there is no logic change to assert.

## 4. Build Verification

- [x] 4.1 Run `make format && make lint-fix && make build && make test` per AGENTS.md; confirm all four steps pass

## 5. Doc Updates

- [x] 5.1 In `docs/product-features-planning.md` F-2.02, extend the Reset Budget bullet (currently noting "Available while paused.") to also note that a paused budget is automatically resumed as part of the same atomic operation
- [x] 5.2 In `docs/main-prd.md` §6.7, update the "Reset Budget" row of the action table to mention auto-resume (e.g., append: "If the budget is paused, also inserts a `.resume` `LifecycleEvent` so the post-reset state is active.")
- [x] 5.3 In `docs/main-prd.md` glossary entry for "Reset Budget", append a sentence noting the auto-resume behavior
