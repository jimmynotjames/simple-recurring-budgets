## Why

`Reset Carry-over…` and `Reset Budget…` set `Budget.lastResetDate`, which gates only the carry-over **walker** (completed prior periods). The **current-period spillover** component (`currentPeriodSpillover`, algorithm doc §A.5.6) ignores `lastResetDate` entirely, so two reset bugs ship today:

- **Issue #242** — a current-period deficit keeps spilling into carry-over after a Reset Carry-over. The lingering value is transient (the walker forgives pre-reset expenses when the period closes), but the live chip contradicts what close-time math will produce.
- **Issue #241** — on an ended (`.postEnd`) budget the spillover folds the *entire* final-period remaining into carry-over, and the final period never closes — so after a reset the stale value persists **forever**. After Reset Budget it shows the full final-period allocation instead of 0.

The reset-vs-spillover interaction was never specified in the algorithm doc or the `budget-math` spec; this change specifies and implements it.

## What Changes

- `currentPeriodSpillover`'s input becomes reset-aware in `BudgetCalculator.recurringBranch`:
  - The spillover's expense sum excludes expenses dated before `lastResetDate` (lower bound `max(effectivePeriodStart, lastResetDate)`), mirroring the walker's existing "full allocation, no proration" convention for the period containing a reset. The live spillover thus exactly previews the walker's contribution when that period closes. Carry-over reads 0 immediately after a mid-period reset even with a current-period deficit.
  - When `lastResetDate >= effectiveEndExclusive` (reset performed after the budget ended), spillover is 0 — post-end resets zero carry-over permanently.
- `remaining` (the current-period envelope) is **unchanged** — it still reflects all current-period expenses per the documented post-reset rebound (§A.6.4).
- The pure `currentPeriodSpillover` function itself is unchanged; only the `remaining`-equivalent input computed for it in `recurringBranch` changes.
- Algorithm doc §A.5.6 / §A.6.4 / §A.6.5 (docs/budget-calculations-rewrite-algorithm.md) gain the reset-interaction rule.
- No data model, UI, analytics, or localization changes. Pure math + tests.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `budget-math`: The "Asymmetric live coupling for the current period" requirement gains the reset-aware input rule — spillover is computed from post-reset expenses only, and collapses to 0 when the reset occurred after the budget's end. Walker and `remaining` requirements are unchanged.

## Impact

- `simple-recurring-budgets/Domain/BudgetCalculator.swift` — `recurringBranch` computes a reset-aware spillover input.
- `simple-recurring-budgetsTests/Domain/BudgetCalculatorTests.swift` (and/or a focused new test file) — scenarios for mid-period reset with deficit (#242), post-end Reset Carry-over and Reset Budget (#241), and reset-then-spend-again overflow.
- `docs/budget-calculations-rewrite-algorithm.md` — §A.5.6 spillover rule + reset sections updated to specify the interaction.
- `openspec/specs/budget-math/spec.md` — via delta spec in this change.
- Closes GitHub issues #241 and #242. (Issue #240 was analyzed alongside and explicitly deferred — different feature area.)

## Doc alignment

- `docs/budget-calculations-rewrite-algorithm.md` §A.5.6/§A.6.4/§A.6.5: updated by this change (task).
- `docs/main-prd.md`, `docs/product-features-planning.md`, `docs/tech-design-doc.md`: no conflicts — none of them specify the reset-vs-spillover interaction; F-5.01/F-2.03 (week-start) deliberately untouched.
