## 1. Code: change `Budget.init` default and add PAUSED annotations

- [x] 1.1 In `simple-recurring-budgets/Models/Budget.swift`, change the `Budget.init` body so `self.resetCadence = (resetCadence ?? .never).rawValue` (do **not** call `period.defaultResetCadence`). Update the doc comment on `resetCadence` and on the initializer to lead with `// PAUSED (Reset Cadences):` explaining the pause and stating that callers must not consume `BudgetPeriod.defaultResetCadence` for the initializer default while paused.
- [x] 1.2 In `simple-recurring-budgets/Domain/ResetCadence.swift`, add a leading file/type doc comment that begins `// PAUSED (Reset Cadences):` and explains: feature is paused, no UI surfaces it today, do not introduce new UI/specs that surface it, type and methods are retained for the (currently unused) scheduled-reset path and for the future un-pause.
- [x] 1.3 In `simple-recurring-budgets/Domain/BudgetPeriod.swift`, prepend `// PAUSED (Reset Cadences):` to the doc comment on `defaultResetCadence`, stating: this mapping is retained as design knowledge but is **not** consumed by `Budget.init` while paused; do not introduce new callers.
- [x] 1.4 In `simple-recurring-budgets/Domain/BudgetCalculator.swift`, prepend `// PAUSED (Reset Cadences):` to the doc comment on `checkScheduledReset(...)`, stating: behavior remains correct and unit-tested, but in practice all new Budgets persist `.never`, so this returns a no-reset result; do not surface scheduling configuration in UI/specs while paused.
- [x] 1.5 In `simple-recurring-budgets/Domain/BudgetLifecycleService.swift`, prepend `// PAUSED (Reset Cadences):` to the doc comment on the function/section that calls `checkScheduledReset`, repeating the "no UI/specs while paused" guidance.

## 2. Tests: align with new default and lock the pause

- [x] 2.1 In `simple-recurring-budgetsTests/Models/ModelTests.swift`, update `budget_defaultResetCadence_followsPeriod` (or replace it) so that, for each `BudgetPeriod` case, a `Budget` initialized without an explicit `resetCadence` ends up with `resetCadence == ResetCadence.never.rawValue`. Rename the test to something like `budget_defaultResetCadence_isNeverWhilePaused` and add a comment marker `// PAUSED (Reset Cadences)`.
- [x] 2.2 Update the "Creating a Budget with defaults" assertion (around `#expect(budget.resetCadence == ResetCadence.weekly.rawValue)`) to expect `ResetCadence.never.rawValue`.
- [x] 2.3 Confirm `simple-recurring-budgetsTests/Domain/EnumTests.swift` `defaultResetCadence_*` tests are unchanged (they still assert the type-level mapping). Add a comment block at the top of that section noting `// PAUSED (Reset Cadences) — type-level mapping retained; not consumed by Budget.init while paused.`
- [x] 2.4 Confirm `BudgetCalculatorTests` and `BudgetLifecycleServiceTests` continue to pass without behavioral edits — they exercise the type/engine, not the `Budget.init` default.

## 3. Docs annotations (PAUSED callouts; preserve content)

- [x] 3.1 `docs/main-prd.md` §6.7: insert a `> [!NOTE] **PAUSED — Reset Cadences feature is not in scope.**` callout immediately above the **Scheduled** bullet. Body of the callout: "Scheduled carry-over resets are paused. Manual reset remains supported. Existing prose retained for future reference; **do not surface Reset Cadence in UI, plans, or new specs while this pause is in effect.**" Leave the existing prose intact.
- [x] 3.2 `docs/main-prd.md` §6.7 "Monthly Budgets" sub-bullet: append a brief `_PAUSED — see callout above._` italic note.
- [x] 3.3 `docs/main-prd.md` glossary entries for "Carry-over Amount" and "Reset cadence": append a one-line `_PAUSED — feature not in scope; retained for design reference._`
- [x] 3.4 `docs/product-features-planning.md`: above the "Carry-over reset cadence" bullet (around line 88) and the monthly-default sub-bullet (around line 89), insert the same `> [!NOTE] **PAUSED — Reset Cadences feature is not in scope.**` callout. Add: "Acceptance criteria for current work MUST NOT depend on Reset Cadence UI; treat any default as `.never`."
- [x] 3.5 `docs/ux-design-brief.md`: in the line listing Add/Edit Budget fields ("…allocation, period, carry-over toggle, reset cadence."), strike through "reset cadence" with markdown (`~~reset cadence~~`) and append a callout: `> [!NOTE] **PAUSED — Reset Cadences feature is not in scope.** Do not include a Reset Cadence control in the Add/Edit Budget sheet (or any UI) while paused.`
- [x] 3.6 `docs/tech-design-doc.md`: add the `> [!NOTE] **PAUSED — Reset Cadences feature is not in scope.**` callout above the validation example sentence ("…cross-field validation such as Budget Period → Reset Cadence rules…"), the "more than one model property" example sentence, the data-model paragraph that mentions `ResetCadence`, and the "Scheduled reset" bullet. Each callout body should clarify that the type and engine are retained for future use; UI/specs MUST NOT surface scheduling configuration while paused.

## 4. Verify

- [x] 4.1 `rg 'PAUSED \(Reset Cadences\)'` lists hits in `ResetCadence.swift`, `BudgetPeriod.swift`, `Budget.swift`, `BudgetCalculator.swift`, `BudgetLifecycleService.swift`, and at least one test file.
- [x] 4.2 `rg 'PAUSED — Reset Cadences feature is not in scope\.'` lists hits in all four `docs/*.md` files and in both delta spec files (`openspec/changes/pause-reset-cadences/specs/data-models/spec.md`, `.../budget-lifecycle/spec.md`).
- [x] 4.3 Run `make test` (or `bash scripts/test.sh`) and confirm green on the canonical iPhone simulator.
- [x] 4.4 Run `openspec validate pause-reset-cadences` (or `openspec status --change pause-reset-cadences`) and confirm artifacts are complete and apply-ready.
