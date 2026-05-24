## Context

The Add/Edit Budget sheet (`AddEditBudgetView` + `AddEditBudgetViewModel`) lets the user edit `Budget.startDate` on a recurring budget without any cross-check against `Budget.expenseItems`. `BudgetCalculator.snapshot` (recurring branch) and `walkCarryOver` both filter expenses by `max(effectiveStartDate, lastResetDate ?? .distantPast)`, so any expense dated before a newly-moved-forward `startDate` becomes a list-only row that does not influence remaining or carry-over. `AddEditExpenseView` already enforces the inverse direction — its `dateRange` lower bound is `budget.effectiveStartDate`, so an expense cannot be created with a pre-start date in the first place. The asymmetry is the bug class: the only path into the orphaning state is via the *budget* edit screen.

Existing UI patterns in the same screen establish the precedent for save-time confirmation alerts (Delete Budget at `AddEditBudgetView.swift:108-153`) and for inline `.caption` captions inside the Schedule disclosure (the existing `addEditBudget.schedule.summary.*` strings).

The cross-cutting concerns from `docs/main-prd.md §6.8` apply: this is a UI-touching change, so accessibility, localized source strings, translations queue, and Mixpanel analytics need to be addressed.

## Goals / Non-Goals

**Goals:**

- Surface the orphan-expense state at two points in the flow: (1) inline as soon as the orphaning condition is met during draft editing, and (2) as a blocking confirmation at the Save commit moment.
- Keep the orphan check Edit-mode only — Add mode has no existing expenses, so the count is always zero.
- Preserve the existing calculator semantics. Orphaned expenses continue to be excluded from carry-over and remaining; the change is a UI affordance, not a math change.
- Preserve the existing single-call `viewModel.save(...)` path. The new alert wraps the call site; it does not introduce a second save path.
- Cover the new behavior in the `add-edit-budget-screen` spec so it survives doc regeneration and codifies the count + copy expectations.

**Non-Goals:**

- Blocking the save outright when orphans exist. The user has a legitimate reason to want it (e.g., consolidating a new budget period after a months-long break); a soft warning is the right call.
- Offering "delete the N orphaned expenses" as an action in the alert. That destroys data and conflates two operations.
- A symmetric guard for `endDate` moving earlier past existing expenses. This is a known parallel gap, deferred to its own change so this one stays small.
- Filtering orphaned expenses *out* of the expense list on the Budget Detail screen, or visually marking them as "not counted." Both were considered during workshopping and intentionally rejected — the user explicitly wanted them to remain visible to reduce data-loss anxiety.
- Customizing the alert presentation for Specific Dates (`F-2.08`). The Save-time alert applies uniformly across every period type: the orphan condition (`expenseItems.date < startDate`) is well-defined regardless of recurrence, the user-facing consequence is the same (the orphaned expense stays in the list but doesn't affect `remaining`), and a separate copy for one period type would be churn. The *inline* warning is recurring-only by structural necessity — Specific Dates uses the always-visible Dates card rather than the Schedule disclosure that hosts the inline `Text`.

## Decisions

### Decision 1: Save-time alert + inline warning, not picker clamping

**Choice:** Show a `.alert(...)` at the Save tap when `orphanedExpenseCount > 0`, plus a quieter inline `Text` warning inside the expanded Schedule disclosure for the duration of the draft.

**Alternatives considered:**

- **Clamp the start-date picker's upper bound** to `min(expenseItems.date)` so the inverted state can't be picked. Rejected: silently restricts a legitimate user action (the user may genuinely want the new window), and provides no in-place explanation of *why* the picker is constrained.
- **Inline warning only, no alert.** Rejected: the user can dismiss the disclosure and forget; the Save tap is the irreversible moment and deserves an explicit confirm.
- **Alert only, no inline warning.** Rejected: the alert appears only after the user has committed mentally to saving; surfacing the consequence during editing lets them adjust earlier.

**Rationale:** Two surfaces, two moments — the inline warning is a continuous draft-state signal, the alert is a one-shot commit-time confirmation. Matches the project's existing two-tier safety pattern (inline `dateContextCaption` on `AddEditExpenseView` + `.alert` on Delete Budget).

### Decision 2: Auto-expand Schedule disclosure when orphans exist on appear

**Choice:** In `onAppear`, if `viewModel.orphanedExpenseCount > 0`, set `isScheduleExpanded = true`.

**Alternatives considered:**

- **Leave the disclosure in its default collapsed state.** Rejected: a user re-opening Edit Budget on a budget that was already saved in an orphaning state would see no signal until they expand the Schedule themselves.
- **Auto-expand always in Edit mode.** Rejected: defeats the purpose of the collapsed-by-default design (most users never need to look at the Schedule), and the existing default reflects a deliberate calm-form choice.

**Rationale:** Auto-expanding *only* when the warning has something to say preserves the calm default while ensuring the signal is unmissable in the (uncommon) state where it matters.

### Decision 3: `orphanedExpenseCount` lives on the viewModel, not as a free function

**Choice:** Add `var orphanedExpenseCount: Int` as an `@Observable` computed property on `AddEditBudgetViewModel`. It reads `budget.expenseItems` (Edit mode only; returns 0 in Add mode and when `startDate == nil`).

**Alternatives considered:**

- **Free function in a `BudgetEditValidation` namespace.** Rejected: the count is a property of the draft state, and putting it on the viewModel lets SwiftUI's `@Observable` machinery recompute it automatically when `startDate` changes during the draft.
- **Materialize as `@State` in the view and recompute manually on date change.** Rejected: duplicates state and re-introduces the synchronization bug class the `@Observable` model is designed to avoid.

**Rationale:** Same shape as `canSave` (an existing computed property on the viewModel). Consistent.

### Decision 4: No analytics event for the alert; one new property on `budget_edited`

**Choice:** When the user confirms the alert and the save commits, the existing `budget_edited` Mixpanel event grows a new `orphanedExpenseCount` property (Int, omitted when zero). No event fires for "alert shown" or "alert cancelled" — cancelled saves emit nothing today, and we keep that.

**Alternatives considered:**

- **`budget_orphan_warning_shown` and `budget_orphan_warning_cancelled` events.** Rejected: noise; the only product question is "how often do users save through the warning?", which `budget_edited.orphanedExpenseCount > 0` answers.
- **No analytics at all.** Rejected: we want to monitor the prevalence to decide whether to invest in the deferred end-date counterpart or list-side marking.

**Rationale:** Cheapest measurement that answers the relevant question, and matches the existing `budget_edited` property-bag pattern.

### Decision 5: Defer the `endDate`-earlier counterpart

**Choice:** Ship only the `startDate`-forward case in this change. Note the parallel `endDate`-earlier case in the proposal and in the spec scenarios as out-of-scope.

**Alternatives considered:**

- **Bundle both directions.** Rejected: doubles the surface area, doubles the alert/inline-warning copy, and the `endDate` direction has its own design nuances (e.g., the existing `endDate.didSet` snap behavior on the viewModel) that warrant their own design pass.

**Rationale:** Smaller landing area, faster feedback on the chosen UI pattern.

## Risks / Trade-offs

- **[Risk] Alert fatigue if a power user routinely edits start dates on budgets with many expenses.** → Mitigation: the inline warning gives the user the same information ahead of Save, so they can predict the alert; the alert appears at most once per Save attempt; cancel returns the user to the form with no state lost.
- **[Risk] The auto-expand on `onAppear` can feel surprising — the user opens Edit and a section is open they didn't expand.** → Mitigation: the section in question is the one containing the warning the auto-expand is surfacing; this is the intended affordance, not a regression.
- **[Risk] `budget.expenseItems` is unsorted; counting filter passes through every item.** → Mitigation: the lists are tiny in practice (well under 1000 for any realistic budget); the cost is bounded and runs only when SwiftUI recomputes the view (triggered by `startDate` changes during draft). No prefiltering or caching needed.
- **[Trade-off] Confirmed-orphan saves are observable in analytics, but cancelled-orphan saves are not.** Acceptable: the metric we care about is "users who proceeded anyway," and the cancelled case is functionally a no-op on persistence.
- **[Trade-off] `.specificDates` gets the alert but not the inline warning.** Acceptable: the alert is the irreversible commit-time signal and applies uniformly; the inline warning lives inside the Schedule disclosure which doesn't exist for Specific Dates. A Specific Dates user therefore sees the consequence only at Save time — the same as today's pre-change behavior, just now surfaced instead of silent.

## Doc alignment

- `docs/product-features-planning.md` F-2.03 should gain a sub-bullet under the Start Date description noting the orphan-warning confirmation on save and the inline warning under the Schedule disclosure. To be folded in by the implementation tasks.
- `docs/main-prd.md` — no change. The orphan-warning is a UI affordance, not a constraint or glossary change.
- `docs/tech-design-doc.md` — no change. No schema, no calculator, no sync impact.
- F-2.04 already documents the symmetric expense-side guard. No edit needed there.

No conflicts with the three docs.
