## Why

Tapping **Pause Budget** within the period the user is currently in produces no visible UI change until the next period boundary — because pause classification today is period-granular for both the carry-over math and the UI presentation. A user who creates a daily budget and immediately taps Pause sees nothing: no paused chip, no Resume CTA, and the date picker still defaults to today. This is a system-correctness optimization (no proration) leaking into user-visible behavior, and it consistently reads as "did that work?" — failing the basic mental model that **pause means paused now**.

This change splits the two clocks: UI presentation becomes **moment-granular** (paused immediately on tap), while carry-over math stays **period-granular** (the pause-action period's allocation and existing expenses continue to roll into carry-over normally, with no proration).

## What Changes

- **`BudgetSnapshot.lifecycleState` becomes moment-granular for `.paused`.** When a `.pause` `LifecycleEvent` exists with `effectiveDate ≤ now` and no later `.resume` event before `now`, the snapshot returns `lifecycleState = .paused` regardless of where `now` falls inside the pause-action period. `.preStart` and `.postEnd` semantics are unchanged.
- **Carry-over math is unchanged.** `LifecycleClassification.isActive(period:lifecycleEvents:)` continues to operate at period granularity: the pause-action period remains active for accrual, contributing `allocation - in-period-expenses` to carry-over at period close.
- **`BudgetSnapshot.remaining` is unchanged.** During the pause-action period, `remaining = allocation - in-period-expenses` (the live "what would roll forward" value). Periods strictly after the pause-action period continue to report `remaining = 0` per the existing rule.
- **Add Expense sheet gets a proactive paused note.** While the bound budget's `lifecycleState == .paused`, an always-on `.caption`/`.secondary` line renders below the When card with new key `addEditExpense.paused.caption.format` (en-US: *"Paused since %@. You can still add expenses dated before then."*). It persists for the sheet's lifetime — not gated on date selection.
- **Existing date-picker out-of-range caption is unchanged.** Key `addEditExpense.date.outOfRange.caption` (en-US: *"Pick a date within an active period of this budget."*) still fires when the picked date lands in a multi-cycle paused gap. The two captions occupy the same slot; violation replaces the proactive note when triggered.
- **Detail-screen resume caption tweaked.** Key `budgetDetail.action.resume.caption.format` updates from *"Paused since %@. Resume to log expenses."* to *"Paused since %@. Resume to log new expenses."* — quietly truthful about backdated entries via the list `+` button remaining available.
- **Allocation edits during the pause-action period defer to resume.** F-2.03's existing rule ("Allocation edits made while a budget is paused take effect at the resume point") now applies from the pause moment forward, consistent with the new moment-granular `.paused` semantics.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `budget-math`: `BudgetSnapshot.lifecycleState` semantics change — `.paused` becomes moment-granular; period-granular `isActive(...)` for math is preserved as-is. Spec needs to call out the **two-clock model** explicitly so future readers understand the asymmetry.
- `budget-lifecycle`: `BudgetLifecycleResult.lifecycleState` flips immediately on pause-tap (it surfaces the new snapshot semantics). The existing "Pause and resume produce period-granular semantics via the existing algorithm" requirement is refined to "period-granular for math, moment-granular for UI state."
- `add-edit-expense-screen`: new always-on paused note required; date-picker upper bound clarified to be the `.pause` event's `effectiveDate` (preserves the same-period-before-pause-moment affordance the user explicitly wants).
- `budget-detail-screen`: caption copy under the Resume button updates to *"Paused since %@. Resume to log new expenses."*.

## Impact

**Code**
- `simple-recurring-budgets/Domain/BudgetCalculator.swift` — introduce a moment-granular UI classification used only for `lifecycleState`; preserve the period-granular `isActive(...)` for the math branches (`remaining` zeroing, walker accrual).
- `simple-recurring-budgets/Domain/LifecycleClassification.swift` — unchanged (math classifier). A new sibling helper for the moment-granular UI check lives alongside it (or as a private function in `BudgetCalculator`).
- `simple-recurring-budgets/Views/AddEditExpenseView.swift` — wire the new always-on paused caption below the When card; the existing out-of-range caption remains in the same slot for the violation state.
- `simple-recurring-budgets/Views/BudgetDetailView.swift` — caption copy update only.
- `simple-recurring-budgets/Resources/Localizable.xcstrings` — add `addEditExpense.paused.caption.format`; update value for `budgetDetail.action.resume.caption.format` and queue retranslation across all storefront locales.

**Tests**
- `simple-recurring-budgetsTests` — update snapshot tests that asserted `lifecycleState == .active` during the pause-action period (now `.paused`); add tests verifying the math branches (`remaining`, walker carry-over) are unchanged for the pause-action period; cover edge cases for `pause-before-startDate` (pre-start presentation still wins until `startDate`), and `pause + resume same period` (UI flips paused → active; math net-zero).
- `AddEditExpenseDateBoundsTests` — extend with assertions for the new always-on caption being present at sheet-open time and persisting; existing out-of-range caption assertions stay.

**Docs**
- `docs/product-features-planning.md` — F-7.06: refine the "Semantics" bullet to spell out the two-clock model (UI moment-granular, math period-granular) and explicitly call out the same-period-before-pause-moment affordance for backdated entries. F-2.03: clarify that "while paused" begins at the pause moment.
- `docs/tech-design-doc.md` — note the split classification inside `BudgetCalculator.snapshot`.
- `docs/main-prd.md` — no global-constraint changes.

**No data-model or schema changes.** No new SwiftData fields, no migrations, no CloudKit shape changes. Existing `LifecycleEvent` rows remain the source of truth; only their interpretation at the snapshot layer changes.

**Doc alignment.** Reviewed `docs/main-prd.md`, `docs/product-features-planning.md` (F-7.06, F-2.03, F-2.04), and `docs/tech-design-doc.md`. F-7.06 currently states "Pause and Resume operate at period granularity: the within-period timing of the action does not affect the math" — this remains true for math, but the UI half of that statement needs to be replaced with the moment-granular rule. The change updates the doc as part of tasks; no conflict with `main-prd.md`.
