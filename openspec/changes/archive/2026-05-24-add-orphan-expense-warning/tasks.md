## 0. Reconciliation context

The UI, layout, and text-copy work for this change already exists as unstaged modifications to `AddEditBudgetViewModel.swift`, `AddEditBudgetView.swift`, and `AddEditBudgetView+Schedule.swift`. **Existing code is the source of truth for UI structure and text copy.** Where the spec and the code diverge in those areas, update the spec to match the code (not the other way around). Spec, analytics wiring, localization, tests, and docs are the new work this change must complete.

## 1. Verify already-written code matches spec (reconcile, don't reimplement)

- [x] 1.1 Diff `AddEditBudgetViewModel.swift` against spec requirement "Orphan-expense warning on Save…": confirm `orphanedExpenseCount` shape (Edit-mode only, returns 0 in Add mode and when `startDate == nil`, otherwise `budget.expenseItems.filter { $0.date < start }.count`). No edit expected — already implemented per spec.
- [x] 1.2 Diff `AddEditBudgetView.swift` Save toolbar action + `.alert(...)` + `commitSave()` against spec: confirm gating condition, commit path, button labels (`Cancel` / `Save Changes`), and that the bare-Save path and confirm branch share `commitSave()`. No edit expected.
- [x] 1.3 Diff `AddEditBudgetView.swift` `onAppear` block against spec: confirm auto-expand fires only when `orphanedExpenseCount > 0` and runs after the existing `initialCurrencyCode` capture and name-focus seeding. No edit expected.
- [x] 1.4 Diff `AddEditBudgetView+Schedule.swift` inline warning `Text` against spec: confirm `.font(.caption)`, `.foregroundStyle(.orange)`, leading alignment, no SF Symbol icon, placement below the Clear-end-date affordance. No edit expected.
- [x] 1.5 Diff `#Preview("Edit — Orphaning start date")` against spec: confirm it loads `DebugData.weeklyDefault()` and moves `startDate` ~20 days back to orphan the day-21 and day-35 expenses. No edit expected.
- [x] 1.6 If any 1.1–1.5 check reveals a real divergence in UI structure or text copy, **update spec.md** (and proposal/design if they cascade) — do not edit the Swift code. _No divergence found in 1.1–1.5; spec stands as written._

## 2. Localization (NOT yet done in unstaged code)

Existing code uses bare `String` / `Text` literals in English. The spec mandates `String(localized:defaultValue:comment:)` for every user-visible string.

- [x] 2.1 Add the five keys to `simple-recurring-budgets/Resources/Localizable.xcstrings`:
  - `addEditBudget.orphanWarning.title` (alert title, with `\(count)` interpolation)
  - `addEditBudget.orphanWarning.message` (alert body)
  - `addEditBudget.orphanWarning.cancel` (alert cancel button)
  - `addEditBudget.orphanWarning.confirm` (alert confirm button — "Save Changes")
  - `addEditBudget.orphanWarning.inline` (inline Schedule-disclosure warning, with `\(count)` interpolation)
- [x] 2.2 Replace the hardcoded literals in `AddEditBudgetView.swift` `.alert(...)` (title, "Cancel", "Save Changes", message) with `String(localized:defaultValue:comment:)` calls bound to the keys from 2.1. Comments SHOULD note context (alert title vs body, that `\(count)` is the number of pre-`startDate` expenses).
- [x] 2.3 Replace the hardcoded inline-warning literal in `AddEditBudgetView+Schedule.swift` with `String(localized:defaultValue:comment:)` bound to `addEditBudget.orphanWarning.inline`. Comment SHOULD note that this is the quieter sibling of the Save-time alert and explain the `\(count)` interpolation.
- [x] 2.4 Run `python3 scripts/check_translations.py` to confirm the new keys are surfaced as needing translation.
- [x] 2.5 Invoke the `/translate-new-strings` skill to fan out per-locale translations across all 38 App Store storefront locales. Re-run `check_translations.py` to confirm clean.

## 3. Analytics (NOT yet done in unstaged code)

- [x] 3.1 Add `AnalyticsProperty.orphanedExpenseCount = "orphaned_expense_count"` constant.
- [x] 3.2 Modify `AddEditBudgetViewModel.saveEdit` (or whichever `Edit`-mode commit path emits `budget_edited`) so that after the write, when `budget.expenseItems.filter { $0.date < budget.startDate }.count > 0`, the resulting count is threaded into the `budget_edited` properties bag via `AnalyticsProperty.orphanedExpenseCount`. Omit the key entirely (do not emit `0`) when the count is zero. Match the threading pattern used by the existing `allocation_changed` / `start_date_changed` / `end_date_changed` flags.

## 4. Tests (NOT yet done)

- [x] 4.1 Add Swift Testing unit tests for `AddEditBudgetViewModel.orphanedExpenseCount`: (a) Add mode → 0; (b) Edit mode with no `expenseItems` → 0; (c) Edit mode with all expenses on or after `startDate` → 0 (boundary equality, `$0.date < startDate` is strict); (d) Edit mode with `N` expenses before `startDate` → `N`; (e) mutating `viewModel.startDate` recomputes the value (covered by `@Observable` semantics; assert via a sequence of reads).
- [x] 4.2 Add Swift Testing analytics test: confirmed-orphan save emits `budget_edited` with `orphaned_expense_count: N`; non-orphan save omits the key; Add-mode save emits no key. Use the existing analytics test harness.
- [x] 4.3 No UI/snapshot test for the alert or the inline warning (project convention defers UI-state verification to the new `#Preview("Edit — Orphaning start date")` plus manual confirmation under 6.2).

## 5. Docs alignment (NOT yet done)

- [x] 5.1 Update `docs/product-features-planning.md` F-2.03 Start Date / End Date sub-section: add a bullet noting the orphan-warning Save-time confirmation alert (en-US copy) and the inline Schedule-disclosure warning. Reference change ID `add-orphan-expense-warning`.
- [x] 5.2 Update `docs/analytics-spec.md` F-8.02 (`budget_edited`) to declare the new conditional property `orphaned_expense_count: Int (present iff > 0)` with a one-line description.
- [x] 5.3 Confirm `docs/main-prd.md` and `docs/tech-design-doc.md` need no updates (no schema, calculator, or global-constraint impact). Note explicitly in the PR description.

## 6. Build and manual verification (per AGENTS.md > Build and test)

- [x] 6.1 Run the four-step procedure in order: `make format` → `make lint-fix` → `make build` → `make test`. All must pass before opening the PR.
- [x] 6.2 Open `#Preview("Edit — Orphaning start date")` in Xcode and visually confirm: (a) inline orange warning text renders left-aligned with the date chips above (no icon-driven indent); (b) Save tap presents the alert with `2` in the title; (c) `Cancel` preserves draft state, sheet stays presented; (d) `Save Changes` dismisses and commits; (e) re-opening the same budget in Edit auto-expands the Schedule disclosure. _User-confirmed._
