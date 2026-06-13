## 1. Preconditions (already shipped — verify, do NOT modify)

- [x] 1.1 Confirm the shipped UI/copy is present and unchanged: biweekly note (`addEditBudget.note.biweekly`), Schedule auto-expand on biweekly (`AddEditBudgetView.onAppear` + biweekly chip-tap), `isBiweeklyStartDateEdited` + re-anchor alert in `AddEditBudgetView.swift`/`AddEditBudgetViewModel.swift`, and the reworded period-lock strings. These are the spec's source of truth; tasks below test them, they do not re-implement them.
- [x] 1.2 Confirm translations are already merged and `python3 scripts/check_translations.py` exits 0 (no translation run needed unless a later task adds a user-facing string).

## 2. ViewModel unit tests

- [x] 2.1 In `simple-recurring-budgetsTests/Views/BudgetForm/AddEditBudgetViewModelScheduleTests.swift`, add `isBiweeklyStartDateEdited` coverage: returns `true` only for Edit mode + `.biweekly` + drafted `startDate` (normalized) differing from the persisted `Budget.startDate`.
- [x] 2.2 Add the false cases for `isBiweeklyStartDateEdited`: Add mode; `.daily`/`.weekly`/`.monthly`/`.specificDates`; biweekly with an unchanged start date; biweekly where the draft differs only by intra-day time but normalizes to the same day (must be `false`).
- [x] 2.3 Add a combined-inputs test asserting the Save-gate drivers compute correctly together for a biweekly Edit that moves the start past existing expenses: `isBiweeklyStartDateEdited == true` AND `orphanedExpenseCount > 0` (the gate inputs that make the alert fold in the orphan sentence).

## 3. Period-math regression tests

- [x] 3.1 In `simple-recurring-budgetsTests/Domain/PeriodCalculatorTests.swift`, add a regression test that changing a biweekly budget's anchor re-anchors its period boundaries: the same reference date yields a period start shifted by the same delta as the anchor (e.g. anchor +3 days → period start +3 days). Confirms editing the start date re-slices periods exactly as the re-anchor confirmation warns.
- [x] 3.2 Add the inverse invariant: weekly/daily/monthly period starts are unaffected by an anchor-day change — guards the "biweekly is the only anchored period" invariant the spec relies on.

## 4. UI test screen object + journey (PRD §6.8.5)

- [x] 4.1 Extend `simple-recurring-budgetsUITests/AddBudgetScreen.swift` with element queries for: the biweekly note, the start-date chip (expanded-disclosure proxy), the re-anchor alert, and a `selectPeriod(_:)` helper.
- [x] 4.2 In `simple-recurring-budgetsUITests/UserJourneyTests.swift`, add a journey: open Add → tap Biweekly → assert the note is visible AND the Schedule disclosure is expanded (start-date chip hittable).
- [x] 4.3 Re-anchor alert journey — **resolved as a manual carve-out** (user decision): triggering the alert requires driving a graphical `DatePicker`, which this repo exercises manually (`testAddBudgetSpecificDatesPeriod`). The gate (`isBiweeklyStartDateEdited`) is fully unit-tested and the gate→alert binding is trivial SwiftUI; a documented carve-out comment + manual steps live in `UserJourneyTests.swift`, and `AddBudgetScreen.reanchorAlert` is provided for the manual pass / future automation.
- [x] 4.4 Add an assertion that the Edit-mode period-lock caption reads the reworded "Period type can't be changed after creating your budget." text — guards the copy fix against regression.
- [x] 4.5 Ran the new journeys (`testBiweeklyPeriodShowsNoteAndExpandsSchedule`, `testEditBudgetPeriodLockCaptionNamesPeriodType`) plus the full `make test-ui` suite — all green, no stale queries.

## 5. Docs alignment

- [x] 5.1 In `docs/product-features-planning.md` F-2.03, correct the quoted period-lock caption copy → "Period type can't be changed after creating your budget." (and note it names the period type because dates remain editable).
- [x] 5.2 In `docs/product-features-planning.md` F-2.03, add acceptance criteria for the biweekly note, Schedule auto-expand, and the Save-time re-anchor confirmation (with orphan-sentence folding); cross-reference F-7.05.
- [x] 5.3 Confirm no other docs drift: `docs/tech-design-doc.md` and `docs/main-prd.md` §6.8 need no change (verified — no edit required).

## 6. Verify & close

- [x] 6.1 Four-step gate green: `make format` / `make lint-fix` / `make build` clean; `make test-unit` = 738 tests pass; `make test-ui` full suite passed.
- [x] 6.2 `python3 scripts/check_translations.py` and `python3 scripts/check_source_strings.py` both green (258 strings fully translated; 99 files clean).
- [x] 6.3 `openspec validate biweekly-startdate-ux` passes. **Archive deferred** to post-merge (the change rides PR #251); run `/opsx:archive` after merge to sync the delta into the main `add-edit-budget-screen` spec.
