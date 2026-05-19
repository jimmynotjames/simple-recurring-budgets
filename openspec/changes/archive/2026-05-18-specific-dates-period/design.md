## Context

The `rewrite-budget-calculations` change (archived 2026-05-15) shipped the algorithm, schema, and lifecycle guards for `.specificDates` but explicitly deferred the user-facing surface — see archived tasks §4.9 and design.md notes on the "future UI work" that would ship `.specificDates` in the period chip group. The current state on this branch (`u/jimmyho/workshopping-specific-dates-period`) reflects substantial UI workshopping: the chip is wired, the Dates card renders, a sheet-based `.graphical` `DatePicker` works on single tap, and `Budget.periodDisplayLabel` plus `ViewThatFits` layouts have been added to both the Budgets list and Budget detail header.

What's NOT yet in place: the draft `startDate`/`endDate` live on the **view** as `@State` (workshop hack), not on `AddEditBudgetViewModel`. `saveNew` ignores user-chosen dates for `.specificDates` and defaults `startDate` to today; `saveEdit` never writes dates. `BudgetLifecycleService.applyAllocationEdit` has an `assert(period != .specificDates)` that no-ops. The Carry-Over chip on `BudgetsView` and `BudgetDetailView` will still render for `.specificDates` budgets if `isCarryOverEnabled` happens to be true. The "Reset Carry-Over…" menu item on `BudgetDetailView` is similarly ungated.

The algorithm and pause/resume guards in `BudgetLifecycleService` (`canPause`, `canResume`, `resetCarryOver`, the `specificDatesBranch` in `BudgetCalculator`) are already correct from the rewrite and do not need changes.

## Goals / Non-Goals

**Goals:**

- Make Specific Dates a fully shippable, end-to-end feature: a user can pick `.specificDates` on Add Budget, set start and end dates, save, see the budget in the list with a date-range label, edit it, log expenses against it constrained to the window, and have Mixpanel events fire correctly.
- Preserve all decisions already made during workshopping (UI layout, date formatting, copy, blurb wording). Specifically: the full-width chip below the 2×2 grid; "Good for a trip, a birthday weekend..." blurb under the chip; "Dates" card with side-by-side `DateColumn` buttons opening a `.graphical` `DatePicker` sheet; `periodDisplayLabel` using `Date.IntervalFormatStyle`; `ViewThatFits` for amount + period label.
- Enforce F-2.08 carve-outs in every surface: Carry-Over toggle, Carry-Over chip (both screens), Reset Carry-Over action, and Pause/Resume action are all hidden for `.specificDates` budgets.
- Implement latest-wins allocation edits for `.specificDates` per F-2.08.

**Non-Goals:**

- No changes to the SwiftData schema. `Budget.endDate: Date?` already exists from the algorithm rewrite.
- No changes to the algorithm. `BudgetCalculator.specificDatesBranch` is already correct.
- No changes to `BudgetPeriod` enum, its display labels, or sort order.
- No range-style date picker UI (single-calendar booking-site pattern). The two-field side-by-side approach is the iOS-native pattern; a range picker would be a separate change.
- No changes to F-2.03's editable Start Date / End Date behaviour for **recurring** budget types — that's a separate, larger scope (see F-7.07).
- No new dependencies.

## Decisions

### 1. Draft state lives on the ViewModel, not the view

**Decision.** Move `@State var startDate: Date?` / `@State var endDate: Date?` from `AddEditBudgetView` into `AddEditBudgetViewModel` as draft properties. `Date?` because the spec (F-2.08) explicitly requires no pre-population in Add mode and the Save button must remain disabled until both are set.

**Why.** Same pattern as `name`, `allocation`, `currencyCode`, `period`, and `isCarryOverEnabled` — all draft state for the form lives on the `@Observable @MainActor` VM per `docs/tech-design-doc.md` §2.1 ("Methods that need to write take `(context: ModelContext, ...)` at the call site"). The current view-local state is an acknowledged workshop hack and the existing spec for the screen explicitly says the VM owns draft state (`@Observable AddEditBudgetViewModel owned by the view as @State`).

**Alternative considered.** Keep dates on the view and pass into VM at save time via parameters. Rejected — diverges from the existing pattern, doesn't survive an `onChange` re-init of the VM (e.g., sheet re-presentation), and complicates the `canSave` computed property.

### 2. `canSave` extends with a dates gate keyed off `period`

**Decision.** Replace the current `canSave` (which checks only name + allocation) with:

```swift
var canSave: Bool {
  let nameOK = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  let allocOK = (allocation ?? 0) > 0
  let datesOK: Bool
  if period == .specificDates {
    guard let s = startDate, let e = endDate else { return false }
    datesOK = s <= e
  } else {
    datesOK = true
  }
  return nameOK && allocOK && datesOK
}
```

**Why.** Per F-2.08, both `startDate` and `endDate` are required and `start <= end` is implicit (a zero- or negative-length window is meaningless). For recurring budgets, dates are not user-visible in this change (scope is `.specificDates` only) so `datesOK` short-circuits to `true`.

### 3. `saveNew` uses the user-chosen dates for `.specificDates`

**Decision.** In `AddEditBudgetViewModel.saveNew`, replace the existing `.specificDates` branch (which sets `startDate = calendar.startOfDay(for: now)` and never writes `endDate`) with:

```swift
case .specificDates:
  guard let s = startDate, let e = endDate else { return }  // canSave already gated this
  startDate = calendar.startOfDay(for: s)
  // endDate written separately below
```

After the existing `Budget(...)` construction, set `budget.endDate = calendar.startOfDay(for: e)`. Keep the existing `AllocationChange(effectiveFrom: startDate, amount: allocation)` insertion — the algorithm's `specificDatesBranch` uses the most-recent `AllocationChange` for the entire window so this seeds it correctly.

**Why.** Honours the user's chosen window. `startOfDay` normalisation matches the convention used for `.daily`/`.weekly`/etc. and avoids time-zone surprises if a user picks a date with an embedded time component (sheet pickers default to current time).

**Trade-off.** End-of-day vs start-of-day for `endDate`: the spec (F-2.04) says expenses dated within `[startDate, endDate]` are valid. Using `startOfDay(for: endDate)` means an expense dated on the end date at 6 PM is technically after `endDate`. The cleaner interpretation is to store `endDate` as the *day* the window ends, and let the algorithm + date-bounds logic treat it inclusively. The existing `BudgetCalculator.specificDatesBranch` uses `<=` for the end comparison (per the algorithm doc), so day-aligned `endDate` is consistent. If a snapshot test reveals a boundary bug, the fix is in this branch.

### 4. `saveEdit` diffs and writes `startDate`/`endDate`

**Decision.** Extend the Edit-mode field-diff in `AddEditBudgetViewModel.saveEdit` to compare and write `budget.startDate` and `budget.endDate` for `.specificDates` budgets only:

```swift
if period == .specificDates {
  if let s = startDate, budget.startDate != calendar.startOfDay(for: s) {
    budget.startDate = calendar.startOfDay(for: s)
    changed = true
  }
  if let e = endDate, budget.endDate != calendar.startOfDay(for: e) {
    budget.endDate = calendar.startOfDay(for: e)
    changed = true
  }
}
```

**Why.** F-2.03 says Start Date and End Date are editable in both Add and Edit modes. Per F-2.08, period itself is immutable post-creation, so this only runs when the budget already is `.specificDates`. For recurring period types (out of scope this change), the existing `saveEdit` path is unchanged.

**Open detail.** Editing `startDate` on an existing budget shifts the anchor of the only `AllocationChange` row. The current saveEdit code calls `BudgetLifecycleService.applyAllocationEdit` only when **allocation** changes, not when start date changes. For `.specificDates` the single allocation row's `effectiveFrom` should also follow the new `startDate`. Decision: update the most-recent `AllocationChange.effectiveFrom = newStartDate` in saveEdit for `.specificDates`, in the same `context.save()`. Simpler than adding a new lifecycle-service method for a one-line model write.

### 5. `BudgetLifecycleService.applyAllocationEdit` for `.specificDates` — latest-wins

**Decision.** Replace the current `assert(period != .specificDates)` no-op with a latest-wins implementation: find the most-recent `AllocationChange` (max by `(effectiveFrom, lastModified)`), and if its `amount` differs from the new amount, write `amount = newAmount` and bump `lastModified = now`. Do NOT insert a new row.

**Why.** F-2.08: "Mid-window allocation edits use **latest-wins** (the new value applies to the entire window; the prior figure is not retrievable)." Mutating the existing row rather than inserting a new one keeps the model clean (one period, one allocation row) and matches the algorithm's read which uses the most-recent row's amount across the whole window.

**Alternative considered.** Insert a new row with `effectiveFrom = budget.startDate` to preserve audit trail. Rejected — F-2.08 explicitly says the prior figure is not retrievable, and the algorithm's max-by-`(effectiveFrom, lastModified)` rule would just ignore the older row anyway. Audit trail for `.specificDates` is not a spec requirement.

### 6. Carry-Over chip masking

**Decision.** In `BudgetsView.BudgetRowView` and `BudgetDetailView.headerRow`, change the `isCarryOverEnabled:` argument passed to `StatusChipRow` from `budget.isCarryOverEnabled` to `budget.isCarryOverEnabled && !isSpecificDates`. Both views already have `isSpecificDates` computed locally (BudgetDetailView) or can derive it cheaply (BudgetsView).

**Why.** Per F-2.08, the Carry-Over chip is hidden for `.specificDates` regardless of the stored `isCarryOverEnabled` value. This is the simplest, lowest-touch fix and keeps `StatusChipRow` agnostic of period type.

**Alternative considered.** Move the period awareness into `StatusChipRow` by passing the budget directly. Rejected — `StatusChipRow` is a generic display component; mixing period-type logic in would couple it to a single budget type's rules.

### 7. Reset Carry-Over menu item gated on `!isSpecificDates`

**Decision.** In `BudgetDetailView`'s toolbar Menu, change the `if budget.isCarryOverEnabled` gate around the "Reset Carry-Over…" button to `if budget.isCarryOverEnabled && !isSpecificDates`.

**Why.** Per F-2.08, this action is hidden for `.specificDates`. The algorithm already ignores `lastResetDate` for that period type, and `BudgetLifecycleService.resetCarryOver` asserts `!= .specificDates`, so this is just closing the UI affordance.

### 8. Add/Edit Expense date bounds — verification only

**Decision.** Audit `AddEditExpenseView.swift` and `add-edit-expense-screen` spec to confirm the existing `[Budget.startDate, Budget.endDate]` date-bounds rule (referenced at spec.md:510–515) correctly clamps the date picker for `.specificDates` budgets. No new requirement is expected; this is verification work.

**Why.** F-2.04 already says the date picker is constrained to `[Budget.startDate, Budget.endDate]` when those fields are set. For `.specificDates` both are always set (canSave enforces it). If the existing rule handles this correctly — which the spec quotation suggests it does — no code change is needed. If not, scope a small fix into this change.

### 9. Analytics — `BudgetPeriod.analyticsValue` audit

**Decision.** Read `Analytics+DomainExtensions.swift` and confirm `BudgetPeriod.analyticsValue` returns a non-empty stable string for `.specificDates` (e.g., `"specific_dates"`). Add the case if missing.

**Why.** `budgetCreated` and `budgetEdited` events include the `period` property. A missing case would either crash (if exhaustive switch) or produce a blank value (if defaulted). Trivial fix; just needs verification.

### 10. Accessibility for new date controls

**Decision.** Wire VoiceOver labels and hints on the new `DateColumn` buttons and the picker sheet. Add a `Budget.periodInlineLabel` computed property analogous to `BudgetPeriod.inlineLabel` so the existing row-VoiceOver-label format strings (`"\(remaining)... remaining this \(period.inlineLabel) period"`) read sensibly for `.specificDates` (e.g., "remaining in this window" rather than "remaining this specific dates period").

**Why.** The cross-cutting concern (docs/main-prd.md §6.8) requires accessibility for every UI-touching change. The new date pickers don't have any a11y wiring yet from workshopping; this closes that gap.

### 11. Strings + translations

**Decision.** Replace every inline `Text("...")` and `Button("...")` introduced during workshopping with `String(localized: "key", defaultValue: "English", comment: "translator context")` per the project's keying conventions. New keys: `addEditBudget.section.dates`, `addEditBudget.note.specificDates`, `addEditBudget.field.date.start.placeholder`, `addEditBudget.field.date.end.placeholder`, `addEditBudget.dates.picker.cancel`, `addEditBudget.dates.picker.done`, plus the inline `period.specificDates.inline.budgetRow` and `period.specificDates.inline.budgetDetail` analogues for `periodInlineLabel`. Run the full translation pipeline (`extract → dispatch → merge → validate`) plus `check_source_strings.py` and `check_translations.py`.

**Why.** Cross-cutting concern. Workshop strings are explicitly not localized; this is the gate before ship.

## Risks / Trade-offs

- **Risk: A `.specificDates` budget that pre-dates this UI change exists in CloudKit with `isCarryOverEnabled = true`.** → Mitigation: the chip-masking decision (#6) makes the chip hidden regardless of the stored value. The toggle is already hidden in the Add/Edit Budget UI when `.specificDates` is selected, so the value cannot be set via the production UI; the only path is a direct CloudKit write or a future bug. The algorithm already ignores `isCarryOverEnabled` for `.specificDates` per the rewrite.
- **Risk: `startOfDay` normalisation on `endDate` causes off-by-one bugs at the `[startDate, endDate]` window boundary.** → Mitigation: the existing algorithm and date-bounds logic use `<=` end comparisons. Verify with at least one snapshot test that an expense dated on the end day is admitted. If a bug surfaces, the fix lives in `BudgetCalculator.specificDatesBranch` or `AddEditExpenseView`'s clamping logic — not this change's scope.
- **Risk: Editing `startDate` on an existing `.specificDates` budget creates a divergence between `Budget.startDate` and the lone `AllocationChange.effectiveFrom`.** → Mitigation: the saveEdit decision (#4) explicitly updates the most-recent `AllocationChange.effectiveFrom` in the same write. A snapshot test covering "edit start date" verifies the algorithm reads the new value.
- **Trade-off: Latest-wins allocation edits lose audit history for `.specificDates`.** → Accepted per F-2.08. Recurring budgets retain forward-only insert semantics; this is the documented exception.
- **Trade-off: The view-local `isSpecificDates`/`datesValid`/`canSave` workaround in `AddEditBudgetView+SpecificDates.swift` extension goes away once items 1–4 land.** → Accepted. Cleanup happens in the same change so we don't ship dead code.

## Migration Plan

None required. Greenfield app, no production users. No schema migration (`Budget.endDate` already exists). After this change ships, the F-2.08 status flips from "Open" to "Implemented" in `docs/product-features-planning.md`.

## Open Questions

- **Does the existing Add/Edit Expense `[Budget.startDate, Budget.endDate]` clamping already cover `.specificDates`?** Answered during apply (see decision #8). If yes, no expense-screen code changes. If no, scope a small fix into this change rather than punting.
- **Does `BudgetPeriod.analyticsValue` already define `.specificDates`?** Same — answered during apply (see decision #9). One-line fix if missing.

## Doc alignment

- `docs/product-features-planning.md`: flip F-2.08 status from "Open" to "Implemented (by `specific-dates-period`)" after archive. F-2.03's Outstanding-items note that mentions Specific Dates as deferred can be removed.
- `docs/main-prd.md` / `docs/tech-design-doc.md`: no changes — no global constraints or architecture changes.
