## 0. Workshop work already shipped (no action — for context only)

The following items were completed during workshopping on this branch and pass `make build` / `make lint-fix`. They do **not** need to be re-done; they are listed here so reviewers can verify them in the diff.

- [x] 0.1 `.specificDates` chip rendered as a full-width chip below the recurring 2×2 grid in `AddEditBudgetView.periodCard`.
- [x] 0.2 Explanatory blurb (inline literal) rendered below the `.specificDates` chip when selected.
- [x] 0.3 "Dates" card with side-by-side `DateColumn` views (inline literals) rendered when `period == .specificDates`; Carry-Over card hidden in that case.
- [x] 0.4 `DateColumn` struct opens a `.graphical` `DatePicker` in a sheet with Cancel / Done toolbar items and `.presentationDetents([.medium, .large])`.
- [x] 0.5 View-local `@State var startDate: Date?` / `endDate: Date?` workaround in `AddEditBudgetView`; view-local `isSpecificDates` / `datesValid` / `canSave` in `AddEditBudgetView+SpecificDates.swift` extension.
- [x] 0.6 `Budget+Display.swift` adds `periodDisplayLabel` using `Date.IntervalFormatStyle`.
- [x] 0.7 `BudgetsView` and `BudgetDetailView.headerRow` swapped from `period.listLabel` to `budget.periodDisplayLabel`.
- [x] 0.8 Both views swapped from fixed `amountLayout` to `ViewThatFits(in: .horizontal)` over HStack/VStack with appropriate `.lineLimit(1)` on the HStack branch.
- [x] 0.9 `DebugData.specificDatesDefault` fixture (Italy Trip, EUR 1,500, 17-day window) inserted as the 3rd row of `BudgetsView` previews.
- [x] 0.10 `DebugData.detailSpecificDates` fixture and two preview variants ("Specific Dates · Light", "Specific Dates · Dark") added to `BudgetDetailView`.

## 1. ViewModel — startDate / endDate draft state

- [x] 1.1 In `AddEditBudgetViewModel`, declare `var startDate: Date?` and `var endDate: Date?` as `@Observable`-tracked properties. Default both to `nil`.
- [x] 1.2 In `init(settings:)` (Add mode), leave both `nil` (no pre-population per F-2.08).
- [x] 1.3 In `init(editing: Budget)` (Edit mode), seed `startDate = budget.startDate` and `endDate = budget.endDate`.
- [x] 1.4 Extend `canSave` per design decision #2: gate on `name`, `allocation`, AND (when `period == .specificDates`) both dates non-`nil` with `start <= end`.
- [x] 1.5 In `AddEditBudgetView.swift`, remove the view-local `@State var startDate: Date?` and `endDate: Date?`.
- [x] 1.6 In `AddEditBudgetView+SpecificDates.swift`, remove the view-local `isSpecificDates`, `datesValid`, and `canSave` computed properties.
- [x] 1.7 In `AddEditBudgetView.swift`, replace the references to the deleted view-local `canSave` with `viewModel.canSave`. Remove the explicit `.tint(.accentColor)` workaround on the Save button if it was added solely for the workshop (keep it if it's still aesthetically preferred — per the user's earlier decision).
- [x] 1.8 Rewire the `DateColumn` view's `date` binding from `$startDate` (view) to `$viewModel.startDate` / `$viewModel.endDate`.
- [x] 1.9 Update `AddEditBudgetView+SpecificDates.swift` so the `datesCard` body uses `viewModel.period`-driven derivation instead of the view-local `isSpecificDates`. Move `isSpecificDates` to a private computed on the main view that reads `viewModel.period`.

## 2. ViewModel — save paths

- [x] 2.1 In `AddEditBudgetViewModel.saveNew`, rewrite the `.specificDates` branch per design decision #3: use `calendar.startOfDay(for: startDate!)` for `budget.startDate` and set `budget.endDate = calendar.startOfDay(for: endDate!)`. Keep the existing initial `AllocationChange` insertion (its `effectiveFrom` is `budget.startDate`).
- [x] 2.2 Verify the `saveNew` recurring branches (`.daily`, `.weekly`/`.biweekly`, `.monthly`) are unchanged.
- [x] 2.3 In `AddEditBudgetViewModel.saveEdit`, extend the field-diff to compare `startDate` and `endDate` for `.specificDates` budgets per design decision #4. Normalise drafts with `calendar.startOfDay(for:)` before comparison.
- [x] 2.4 In `saveEdit` for `.specificDates`: when `startDate` changes, also update the most-recent `AllocationChange.effectiveFrom` (by `(effectiveFrom, lastModified)`) to the new start in the same write. Bump `lastModified` on the change row as well.
- [x] 2.5 Confirm `saveEdit` still ignores `period` divergence (immutable post-creation per existing spec).

## 3. Domain — BudgetLifecycleService.applyAllocationEdit

- [x] 3.1 In `BudgetLifecycleService.applyAllocationEdit`, remove the `assert(periodRaw != .specificDates, ...)` no-op guard.
- [x] 3.2 Add the `.specificDates` branch per design decision #5: find the most-recent `AllocationChange` by `(effectiveFrom, lastModified)`. If `amount != newAmount`, write the new amount and bump `lastModified`. Otherwise no-op (no `save`, no `lastModified` bump).
- [x] 3.3 When writing, bump `Budget.lastModified = now` and call `context.save()` exactly once.

## 4. BudgetsView and BudgetDetailView — carry-over chip masking

- [x] 4.1 In `BudgetsView.BudgetRowView`, derive `isSpecificDates` locally (it isn't currently defined there). Pass `isCarryOverEnabled: budget.isCarryOverEnabled && !isSpecificDates` to `StatusChipRow`.
- [x] 4.2 In `BudgetDetailView.headerRow`, change the `StatusChipRow` call to pass `isCarryOverEnabled: budget.isCarryOverEnabled && !isSpecificDates`.

## 5. BudgetDetailView — Reset Carry-Over menu item

- [x] 5.1 In the toolbar `Menu`, change `if budget.isCarryOverEnabled {` to `if budget.isCarryOverEnabled && !isSpecificDates {` so the "Reset Carry-Over…" item is hidden for `.specificDates` budgets per F-2.08.
- [x] 5.2 Confirm the existing `showPauseResumeItem` (which already uses `!isSpecificDates`) and `BudgetLifecycleService.resetCarryOver` assertion remain unchanged.

## 6. Add/Edit Expense — date bounds verification

- [x] 6.1 Open `AddEditExpenseView.swift` and confirm the existing `[Budget.startDate, Budget.endDate]` clamping rule (referenced in `openspec/specs/add-edit-expense-screen/spec.md` around the "Date picker bounds" requirement) correctly constrains the date picker for `.specificDates` budgets. Both fields are guaranteed populated for a saved `.specificDates` budget.
- [x] 6.2 Add or extend a Swift Testing test in `AddEditExpenseViewModelTests` covering: a `.specificDates` budget with `startDate = 2026-05-08`, `endDate = 2026-05-25`. Verify the picker's `in:` range is `[startDate, endDate]`, that an expense dated `2026-05-08` is admitted, an expense dated `2026-05-25` is admitted, and an expense dated `2026-05-26` is rejected.
- [x] 6.3 If the existing rule does NOT cover `.specificDates` correctly, scope the smallest fix into this change rather than punting — and add a delta to `add-edit-expense-screen/spec.md` describing the change.

## 7. Analytics — BudgetPeriod.analyticsValue

- [x] 7.1 Read `simple-recurring-budgets/Logging/Analytics+DomainExtensions.swift` and confirm `BudgetPeriod.analyticsValue` defines a stable non-empty string for `.specificDates` (suggest `"specific_dates"` to match the snake-case convention of existing values).
- [x] 7.2 If missing, add the case. No new analytics event types are required by this change — the existing `budgetCreated`/`budgetEdited` events carry the period property and that's the surface this affects.
- [ ] 7.3 Verify with a unit test: create a `.specificDates` budget via the VM and assert the `budget_created` event property `period == "specific_dates"`.

## 8. Strings — Localizable.xcstrings

Replace every inline literal introduced during workshopping with a localized key. Run the catalog rebuild as part of `make build`.

- [x] 8.1 Key `addEditBudget.section.dates` — section header for the Dates card. English source: "Dates". Comment: "Section header for the start/end dates card on the Add/Edit Budget sheet when Specific Dates is selected."
- [x] 8.2 Key `addEditBudget.note.specificDates` — explanatory blurb below the Specific Dates chip. English source (decided during workshopping): "Good for a trip, a birthday weekend, or any one-off spending window. When it's done, it's done. No repeating, no carry-over." Comment: "Caption shown below the Specific Dates period chip explaining that this budget type is non-recurring with no carry-over."
- [x] 8.3 Key `addEditBudget.field.date.start.placeholder` — placeholder on the empty start-date chip. English source: "Choose start date".
- [x] 8.4 Key `addEditBudget.field.date.end.placeholder` — placeholder on the empty end-date chip. English source: "Choose end date".
- [x] 8.5 Key `addEditBudget.dates.picker.cancel` — Cancel button in the date picker sheet. English source: "Cancel". (Could be reused from `addEditBudget.action.cancel` if review prefers; document the decision in the catalog comment.)
- [x] 8.6 Key `addEditBudget.dates.picker.done` — Done button in the date picker sheet. English source: "Done".
- [x] 8.7 Keys `addEditBudget.field.date.start.accessibilityHint` / `addEditBudget.field.date.end.accessibilityHint` — VoiceOver hints for the date chips. English source: "Opens a calendar to pick the start date." / "Opens a calendar to pick the end date."
- [x] 8.8 Key `addEditBudget.chip.period.accessibilityLabel` — confirm the existing key still produces "Specific Dates period" via the `\(p.listLabel) period` interpolation when `p == .specificDates`. No change expected; just verification.
- [x] 8.9 Key `period.specificDates.inline.budgetRow` — inline period descriptor used in the Budgets list row VoiceOver label. English source: "in this window".
- [x] 8.10 Key `period.specificDates.inline.budgetDetail` — inline period descriptor used in the Budget detail header VoiceOver label. English source: "in this window". (Could share the same key as 8.9 if review prefers; current spec specifies separate keys to allow per-surface tuning.)
- [x] 8.11 Replace every inline `Text("...")` / `Button("...")` literal in `AddEditBudgetView.swift`, `AddEditBudgetView+SpecificDates.swift`, and `Budget+Display.swift` (where relevant) with `String(localized: ..., defaultValue: ..., comment: ...)`.
- [x] 8.12 Remove the `WORKSHOP — ...` comment headers on `AddEditBudgetView+SpecificDates.swift` and `Budget+Display.swift` once the strings are localized and the VM is wired through (i.e., when items 1–8.11 are complete).

## 9. Translations pipeline

- [x] 9.1 Run `python3 scripts/check_source_strings.py` to verify no bare English literals remain in the touched files. Address any flagged keys.
- [x] 9.2 Use the `translate-new-strings` skill (or run `scripts/translate_catalog/extract.py → dispatch_prompts.py → merge.py → validate.py` manually) to translate the new keys across all 38 storefront locales.
- [x] 9.3 Run `python3 scripts/check_translations.py` and confirm all locales are current (no missing or stale translations for the new keys).
- [ ] 9.4 Spot-check at least one locale (e.g., Japanese or Arabic) in a Preview to verify the `Date.IntervalFormatStyle` output and the period-inline strings render correctly under the locale, including RTL layout for Arabic.

## 10. Accessibility

- [x] 10.1 Wire `.accessibilityLabel` and `.accessibilityHint` on the empty-state `DateColumn` buttons using the keys from §8.3, §8.4, §8.7.
- [x] 10.2 Wire `.accessibilityLabel` on the set-state `DateColumn` to read "Start date, May 8, 2026" (or locale equivalent) — composed from the field name and the formatted date.
- [x] 10.3 Add `Budget.periodInlineLabel` computed property per design decision #10. Implementation parallels `periodDisplayLabel` but returns the inline-tone string for VoiceOver sentences.
- [x] 10.4 In `BudgetsView`'s row accessibility label and `BudgetDetailView`'s header accessibility label, swap any direct `period.inlineLabel` reference to `budget.periodInlineLabel` so `.specificDates` reads as "in this window".
- [ ] 10.5 Test VoiceOver on the simulator: focus the Italy Trip row in the Budgets list and confirm it announces "Italy Trip, €941.00 remaining in this window" (or the localized equivalent). Focus the Budget detail header for the same budget and confirm it announces "€941.00 remaining in this window".
- [ ] 10.6 Confirm Dynamic Type still works correctly at `.xxxLarge` and higher accessibility sizes; the `ViewThatFits` switch already shipped in workshopping handles this, but verify with a Preview at `.accessibility5`.

## 11. Tests

- [x] 11.1 Add `AddEditBudgetViewModelTests` cases:
  - Add mode: constructor leaves `startDate == nil`, `endDate == nil`.
  - Setting `period = .specificDates` does not pre-populate dates.
  - `canSave` returns `false` for `.specificDates` when either date is `nil`.
  - `canSave` returns `false` for `.specificDates` when `start > end`.
  - `canSave` returns `true` for `.specificDates` when all preconditions met.
  - `saveNew` for `.specificDates` writes `budget.startDate` and `budget.endDate` (start-of-day normalised) and inserts one `AllocationChange(effectiveFrom: startDate)`.
  - `saveEdit` for `.specificDates`: editing `endDate` updates `Budget.endDate` and bumps `lastModified`; no `AllocationChange` mutation.
  - `saveEdit` for `.specificDates`: editing `startDate` updates `Budget.startDate` AND `AllocationChange.effectiveFrom`.
- [x] 11.2 Add `BudgetLifecycleServiceTests` cases for `applyAllocationEdit` on `.specificDates`:
  - Edit to a new amount: existing `AllocationChange.amount` is updated, no new row inserted, `lastModified` bumped, `save` called once.
  - No-op edit (same amount): no mutation, no `save`, no `lastModified` bump.
- [x] 11.3 Add a `BudgetCalculatorTests` regression covering: a `.specificDates` budget whose user edits start date later in the window; the snapshot continues to compute `remaining` correctly using the new `startDate` and `AllocationChange.effectiveFrom`.
- [ ] 11.4 Add a `BudgetDetailViewActionsTests` (or equivalent) case asserting that "Reset Carry-Over…" is omitted from the toolbar Menu for a `.specificDates` budget, regardless of `isCarryOverEnabled`.
- [x] 11.5 Add a `Budget+Display` test asserting `periodDisplayLabel` returns the expected formatted interval string for same-year and year-crossing date ranges, and falls back to `BudgetPeriod.listLabel` when dates are `nil`.
- [x] 11.6 Run the full four-step procedure: `make format && make lint-fix && make build && make test`. Capture logs to `tmp/*.log` (project-local, not `/tmp`).

## 12. Mixpanel verification

- [ ] 12.1 Manually verify in the simulator (with a real Mixpanel token configured) that creating a `.specificDates` budget fires `budget_created` with `period == "specific_dates"`, `currency_code == "EUR"` (or whatever was selected), and the other expected properties. Verify in the Mixpanel debug console or live view.
- [ ] 12.2 Edit the allocation on a `.specificDates` budget and verify `budget_edited` fires with the new properties. No new event types or properties are introduced by this change.

## 13. Documentation updates

- [x] 13.1 In `docs/product-features-planning.md`, change F-2.08's **Status** from "Open. Scoped to be delivered by the budget-calculations rewrite..." to "Implemented (by change `specific-dates-period`)." Add a brief revision-history entry.
- [x] 13.2 In `docs/product-features-planning.md` F-2.03, remove the "Outstanding items" note that listed Specific Dates as deferred. Replace with a single sentence confirming the Specific Dates period and the Dates card ship in this change.
- [x] 13.3 No changes required to `docs/main-prd.md` or `docs/tech-design-doc.md` (no global constraints, schema, or architecture changes).

## 14. Workshop cleanup

- [x] 14.1 Once items 1–13 are complete, confirm the `AddEditBudgetView+SpecificDates.swift` extension file is reduced to just the `DateColumn` struct (or remove the file entirely and move `DateColumn` into `AddEditBudgetView.swift`, depending on how the file feels at the end). Update the file header comment to remove the WORKSHOP language.
- [x] 14.2 Remove the `WORKSHOP — ...` comment in `Budget+Display.swift` (the file becomes production code at that point).
- [x] 14.3 Confirm no stray inline literals or workshop-only artifacts remain by re-running `python3 scripts/check_source_strings.py` and reviewing the diff.

## 15. Verification before archive

- [x] 15.1 Re-run `make format && make lint-fix && make build && make test` (project-local log paths). All green.
- [ ] 15.2 Manually exercise the feature in the simulator: create, edit, log an expense to, and reset (Reset Budget) a `.specificDates` budget. Confirm the Carry-Over and Pause/Resume controls are absent throughout. Confirm the Budgets list shows the date-range label and the Budget detail header shows the same.
- [ ] 15.3 Spot-check VoiceOver on the Budgets list row and the Budget detail header for a `.specificDates` budget.
- [ ] 15.4 Spot-check Arabic (RTL) or Japanese locale Preview for layout correctness.
- [ ] 15.5 Run `openspec verify-change specific-dates-period` (or equivalent) to confirm specs / implementation alignment before archive.
