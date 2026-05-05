## 1. View-model: enforce period immutability in Edit-mode save

- [x] 1.1 In `simple-recurring-budgets/Views/AddEditBudgetViewModel.swift`, remove the `period` branch from the field comparison in `saveEdit(budget:context:analytics:)` (currently lines ~187–190). After the change, the compared/written fields are `name`, `allocation`, `currencyCode`, and `isCarryOverEnabled` only.
- [x] 1.2 Add an inline `// MARK: - period is immutable post-creation (F-2.03; see openspec/changes/restrict-edit-budget-period)` style comment immediately above the `saveEdit` field-compare block explaining why `period` is intentionally absent. Keep the comment short and reference the rule + change name.
- [x] 1.3 Verify `saveNew` is unchanged: it still writes `period` from `viewModel.period` at insert. Period is written exactly once per `Budget` lifetime, at creation.

## 2. View: accessibility for the locked period chips

- [x] 2.1 In `simple-recurring-budgets/Views/AddEditBudgetView.swift`, on the Edit-mode branch of `periodChip(_:)`, add `.accessibilityHint(...)` referencing a new key `addEditBudget.chip.period.locked.accessibilityHint` with `defaultValue: "Locked. Period can't be changed after creating your budget."` and a translator comment. The hint SHALL apply to both selected and non-selected chips in Edit mode; the Add-mode branch SHALL NOT carry the hint.
- [x] 2.2 Verify the existing `.accessibilityLabel` (per-period, e.g. "Daily period") and `.accessibilityAddTraits(.isSelected)` are preserved on both Add-mode and Edit-mode branches.

## 3. View: VoiceOver announcement for the currency-change disclaimer

- [x] 3.1 In `simple-recurring-budgets/Views/AddEditBudgetView.swift`, add an `.onChange(of: viewModel.currencyCode)` modifier on the allocation card (or a parent view) that fires when `viewModel.currencyCode != initialCurrencyCode` AND `!initialCurrencyCode.isEmpty`. Inside the closure, post `AccessibilityNotification.Announcement(<localized addEditBudget.note.currencyLabelOnly>).post()`.
- [x] 3.2 Confirm the `initialCurrencyCode` capture in `.onAppear` (already on branch) is kept and works correctly when the sheet is dismissed and re-presented (re-presentation re-invokes `.onAppear`, re-seeding `initialCurrencyCode`).
- [ ] 3.3 Manually verify on a real device or VoiceOver-on-Simulator that picking a different currency produces an audible announcement of the disclaimer. *(human verification — deferred to post-build device check)*

## 4. Localization: keys + 38-locale translation pipeline

- [x] 4.1 Confirm `Localizable.xcstrings` already contains English entries for `addEditBudget.note.periodLocked` and `addEditBudget.note.currencyLabelOnly` with translator comments (added on branch). Add the new key from task 2.1 (`addEditBudget.chip.period.locked.accessibilityHint`) with a translator comment.
- [x] 4.2 Run `scripts/translate_catalog/` (extract → translate → merge → validate) to produce translations for all 38 storefront locales for the three new keys. Re-run validate until clean.
- [x] 4.3 Spot-check 3–5 representative locales (e.g., `de`, `ja`, `ar`, `pt-BR`, `zh-Hans`) for plausible translations.

## 5. Tests

- [x] 5.1 In `simple-recurring-budgetsTests/Views/AddEditBudgetViewModelTests.swift`, add `editMode_save_periodChangeIsIgnored`: seed Edit-mode VM from a `Budget(period: .weekly)`; set `vm.period = .monthly`; call `vm.save(context:)`; assert `budget.period == BudgetPeriod.weekly.rawValue` AND `budget.lastModified` equals its pre-save value.
- [x] 5.2 Add `editMode_save_periodChangeAlongsideOtherChange_writesOtherButNotPeriod`: seed Edit-mode VM from a `Budget(name: "Original", period: .daily)`; set `vm.name = "Updated"` and `vm.period = .monthly`; call `vm.save(context:)`; assert `budget.name == "Updated"`, `budget.period == BudgetPeriod.daily.rawValue`, and `budget.lastModified` was bumped exactly once.
- [x] 5.3 Verify existing tests still pass: in particular `editMode_save_singleFieldChange_updatesFieldAndLastModified` (line ~199) and `editMode_save_multiFieldChange_updatesBothFieldsAndOneLastModified` (line ~228) do not change `period` and so should remain green.

## 6. Documentation updates

- [x] 6.1 In `docs/product-features-planning.md`, under F-2.03, add an acceptance criterion: "Time Period is immutable after creation. In Edit mode the period chips are non-interactive and a `lock.fill` caption ('This can't be changed after creating your budget.') is displayed below the chip grid; the model layer also refuses to write `Budget.period` on Edit-mode Save." Update the Status line to mention this change name in the implementation list.
- [x] 6.2 In `docs/product-features-planning.md`, under F-3.04, add an acceptance criterion: "Changing a Budget's currency is a label change only — no FX conversion is performed on `Budget.allocation` or any `ExpenseItem.amount`. The Add/Edit Budget screen surfaces an inline caption when the user changes the currency from the value at sheet-open time."
- [x] 6.3 Confirm `docs/main-prd.md` and `docs/tech-design-doc.md` need no edits (no new global constraint, schema, or architectural decision). If anything during implementation reveals otherwise, surface it as a Conflict-with-docs note before completing the change.

## 7. Build/test gate (per AGENTS.md > Build and test)

- [x] 7.1 Run `make format` from the repo root.
- [x] 7.2 Run `make lint-fix`; resolve any remaining strict violations.
- [x] 7.3 Run `make build`; fix compile errors.
- [x] 7.4 Run `make test`; fix failures.

## 8. Cross-cutting concerns (docs/main-prd.md §6.8) — explicit checklist

- [x] 8.1 **Accessibility** — covered by tasks 2.1, 3.1, 3.3 (locked-chip hint, VoiceOver announcement, manual VO walkthrough). No new section headers; no destructive controls introduced; no swipe actions.
- [x] 8.2 **Localized source strings** — covered by task 4.1. All three new keys carry translator comments; no hard-coded English strings introduced.
- [x] 8.3 **Translations queue** — covered by task 4.2 (38-locale catalog run before archive).
- [x] 8.4 **Mixpanel user-action events** — N/A. The change does not introduce a new user-initiated action; it removes the ability to perform one (period editing). The existing `AnalyticsEvent.budgetEdited` event continues to fire for Edit-mode saves and its `period` property remains accurate (will always equal the original `Budget.period`).
