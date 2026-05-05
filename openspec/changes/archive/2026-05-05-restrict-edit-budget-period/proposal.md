## Why

A `Budget`'s **Time Period** (daily / weekly / biweekly / monthly) is a foundational dimension of every per-period calculation in the app — allocation, remaining, carry-over, and Budget Period boundaries all derive from it. Allowing users to mutate the period of an existing `Budget` would silently invalidate historical Budget Period totals, the carry-over running total, and the meaning of every existing `ExpenseItem` attached to that `Budget`. We are committing to the rule that **period is set at creation and immutable thereafter**.

Separately, the per-budget currency picker is intentionally a **label-only** control — the app performs no FX conversion of `Budget.allocation` or `ExpenseItem.amount` when the user changes currency. This wasn't surfaced to users, which can be confusing in Edit mode where existing amounts remain unchanged after picking a new currency.

The Add/Edit Budget UI was already updated on this branch to reflect both rules visually. This change finishes the work: defense-in-depth in the view model, accessibility, tests, doc updates, and translations.

## What Changes

- **Period immutable post-creation (defense in depth).** Drop `period` from the field comparison in `AddEditBudgetViewModel.saveEdit`; period is never written back to a `Budget` in Edit mode regardless of draft state. This formalises the UI-level lock as a model-layer invariant.
- **Period UI is read-only in Edit mode.** Period chips render as static `Text` (not buttons) with dimmed styling; selection trait preserved. A `lock.fill` caption ("This can't be changed after creating your budget.", key `addEditBudget.note.periodLocked`) appears below the chip grid.
- **Currency-change inline disclaimer in both modes.** When the draft `currencyCode` differs from the value at sheet-open time, an inline caption ("Changing currency only updates the label. I.e. No currency conversion.", key `addEditBudget.note.currencyLabelOnly`) renders below the Allocation card row.
- **Accessibility audit.**
  - Add `accessibilityHint` to the locked Edit-mode period chips conveying the lock (new key `addEditBudget.chip.period.locked.accessibilityHint`).
  - Verify the lock caption and currency-change caption read sensibly under VoiceOver; post a focused `AccessibilityNotification.Announcement` the first time the currency caption appears so VO users hear the disclaimer.
  - Spot-audit the screen against F-3.02 maintenance checklist (section labels, hints on destructive controls).
- **Translations.** Run `scripts/translate_catalog/` for the new keys across all 38 storefront locales.
- **Tests.** Cover the model-layer invariant: Edit-mode `save` must not write `period` even if the draft differs, and must not bump `lastModified` on a period-only delta.
- **Docs.** Update F-2.03 (period immutability), F-3.04 (currency is label-only, no conversion), and the `add-edit-budget-screen` spec to match.

No visual design or main-display copy changes (already finalised). No analytics events change (`budget_edited` continues to cover Edit-mode saves; `period` will simply never differ in the emitted properties).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `add-edit-budget-screen`: period chips become non-interactive in Edit mode with an explanatory lock caption; the currency pill grows an inline label-only disclaimer; Edit-mode `save` no longer writes `period`. New a11y hint key for the locked chips.

## Impact

- **Code:**
  - `simple-recurring-budgets/Views/AddEditBudgetView.swift` — already updated on branch; finalise a11y hints and the currency announcement.
  - `simple-recurring-budgets/Views/AddEditBudgetViewModel.swift` — remove the `period` branch from `saveEdit`.
- **Tests:** `simple-recurring-budgetsTests/Views/AddEditBudgetViewModelTests.swift` — new cases asserting period is not writable in Edit mode.
- **Resources:** `simple-recurring-budgets/Resources/Localizable.xcstrings` — already has two new English keys; one new a11y-hint key to add; all three need translations across 38 locales via `scripts/translate_catalog/`.
- **Docs:** `docs/product-features-planning.md` (F-2.03, F-3.04) and `openspec/specs/add-edit-budget-screen/spec.md` (delta).
- **Analytics:** No new events. `AnalyticsEvent.budgetEdited` and the `period` property continue to fire as today.
- **Schema / persistence / sync:** No changes. `Budget.period` remains a stored `String`; CloudKit schema unaffected.

## Doc alignment

- `docs/main-prd.md`: no conflicts. The period-immutability rule is an F-2.03 acceptance criterion, not a global constraint.
- `docs/product-features-planning.md`: F-2.03 currently lists "Time Period (daily, weekly, biweekly, monthly). Defaults to daily." with no immutability rule — this change adds that. F-3.04 currently does not say currency-change is label-only — this change adds that.
- `docs/tech-design-doc.md`: no conflicts. The change does not affect schema, CloudKit, MVVM ownership, or i18n/a11y/testing expectations beyond following the existing checklists.

Files this change will need to update before archive: `docs/product-features-planning.md` (F-2.03, F-3.04). No `main-prd.md` or `tech-design-doc.md` edits expected.
