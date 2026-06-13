# Tasks — weekly-global-week-start

## 1. Core math + #247 fix (atomic with §2/§3 — the no-default param makes partial states non-compiling)

- [x] 1.1 `BudgetCalculator.snapshot` / `recurringBranch` gain `weekStart: Weekday` (no default); delete the startDate-weekday derivation (BudgetCalculator.swift:115-116); keep `biweeklyAnchor = effectiveStartDate`; update the type-level and function doc comments.
- [x] 1.2 `BudgetLifecycleService`: `result`, `applyAllocationEdit`, `pauseBudget`, `resumeBudget`, `resetBudget` gain `weekStart: Weekday` (no default; after `calendar` where present); delete the derivation in `applyAllocationEdit` (lines 141-142); thread into the internal `resetBudget` snapshot. `resetCarryOver` unchanged.
- [x] 1.3 #247: `applyAllocationEdit` recurring branch adopts the governing-row mutate rule — `key = max(currentPeriodStart, calendar.startOfDay(for: budget.effectiveStartDate))`; mutate the latest row with `effectiveFrom <= key` iff its `effectiveFrom >= currentPeriodStart`, else insert at `key`. Doc-comment the live/walker agreement rationale.
- [x] 1.4 `PeriodCalculator` doc comments: `weekStart` is now the caller's global setting (header lines 6-9 + param docs); no code change.

## 2. Production threading

- [x] 2.1 `BudgetsView` (`BudgetRowView.refreshLifecycle`): pass `weekStart: settings.weekStartDay`; add `.onChange(of: settings.weekStartDay) { refreshLifecycle() }` to the row's trigger block.
- [x] 2.2 `BudgetDetailView` + `+PauseResume`: thread `settings.weekStartDay` into `result`/`resetBudget`/`pauseBudget`/`resumeBudget` calls; add the same `.onChange` trigger.
- [x] 2.3 `AddEditBudgetViewModel.saveEdit`: use the (currently discarded) `settings` param → `applyAllocationEdit(..., weekStart: settings.weekStartDay)`; refresh the L6 ordering comment (ordering remains load-bearing for biweekly re-anchoring and the key's `effectiveStartDate` component).
- [x] 2.4 `AddEditExpenseViewModel`: both inits gain `weekStart: Weekday` (stored value, not AppSettings); thread into the 3 snapshot calls. Update `RootView` (2 construction sites) to pass `settings.weekStartDay`; update expense-form preview constructions (`weekStart: .sunday`).
- [x] 2.5 `RatingPromptCoordinator.expenseLogSignals` gains `weekStart: Weekday`; call site in `AddEditExpenseView+RatingPrompt` passes `settings.weekStartDay`.

## 3. Tests

- [x] 3.1 Mechanical plumbing: every `BudgetCalculator.snapshot` / lifecycle-service call in the test targets gains an explicit `weekStart:` chosen to preserve arithmetic — `.sunday` for Sunday-anchored/daily/biweekly/monthly/specificDates suites, `.wednesday` for the Wed-anchored weekly tests (`carryOver_weeklyMidPeriodReset`, the 3 weekly `BudgetCalculatorResetAwareSpilloverTests`), `.monday` for `BudgetCalculatorStartDateEditTests`; expense-VM test files pass the new init param. Group A suites must pass with ZERO value changes.
- [x] 3.2 Flip `BudgetCalculatorWeeklyAnchorPinTests` → `BudgetCalculatorWeeklyGlobalGridTests` (drop the Group B banner): fridayStart → periods [Apr 5–12)/[Apr 12–19), carryOver 100 then 200 (add the Apr 12 snapshot); saturdayStart → [Dec 27–Jan 3) carryOver 100, [Jan 3–10) carryOver 200; thursdayStart → carryOver −10 / remaining 100 unchanged, periodStart → Apr 12; nilStartDate → periodStart Apr 12, carryOver 100.
- [x] 3.3 Flip `BudgetLifecycleWeeklyAnchorPinTests` → fold the test into `BudgetLifecyclePeriodAlignmentTests`: edit row lands Sun Apr 12, carryOver 200.
- [x] 3.4 Flip `BudgetCalculatorWeeklyAnchorTests.snapshot_weeklyBudget_anchorsOnStartDate_notAppSettings` → `..._followsGlobalWeekStart`: period [Apr 5–12).
- [x] 3.5 Flip the #247 probe → `applyAllocationEdit_monthly_midMonthStart_mutatesStartRow_liveAndWalkerAgree`: count 1, row at Jan 15 amount 600, live 600, closed-Feb carryOver 600; delete the bug-pin warning comment.
- [x] 3.6 New tests: parameterized `weekStartSetting_controlsGrid` ((.sunday, Apr 12, 200), (.wednesday, Apr 8, 100), (.monday, Apr 13, 200)); `midGridStart_partialFirstPeriod` (carryOver 70, remaining 100, pre-start expense excluded); `applyAllocationEdit_weekly_firstPartialPeriod_mutatesStartRow_consistentReads` (count 1, live 150, closed carryOver 150); `biweekly_anchorIndependentOfWeekStartSetting` (.sunday vs .friday identical).
- [x] 3.7 Update Group A banner comments (the "survives Option 1 via parameter plumbing" promise is now fulfilled — reword to plain description).

## 4. Settings copy + translations

- [x] 4.1 `SettingsView`: `settings.weekStart.alert.message` → "Changing to %@ will immediately regroup all weekly budgets — including past weeks — onto the new week. Biweekly budgets keep their own cycle."; `settings.weekStart.accessibilityHint` → "Changing this regroups all weekly budgets, including their history". Keys unchanged.
- [x] 4.2 Run the translate-new-strings skill (autonomous) until `check_translations.py` is clean.

## 5. Docs

- [x] 5.1 `docs/product-features-planning.md`: F-5.01 scope (global weekly grid, cascade incl. history; biweekly carve-out), F-7.05 (startDate = window start + biweekly anchor only), F-2.03 weekly seeding note, Settings section line ~186.
- [x] 5.2 `docs/tech-design-doc.md` lines ~288/294 (PeriodCalculator + anchor descriptions).
- [x] 5.3 `docs/budget-calculations-rewrite-algorithm.md`: §A.4.1 step 5 weekStart rule, §A.6.2 edit-key rule (#247), walker-signature note, "Weekly, startDate == Wednesday" case-table row.
- [x] 5.4 `docs/budget-calculations-rewrite-reqs.md` decision #6: one-line "superseded by #240 (2026-06)" note.

## 6. Gate & PR

- [x] 6.1 `make format` → `make lint-fix` → `make build` → `make test` green after each commit.
- [x] 6.2 Retitle PR #248 + rewrite body (`Closes #240`, `Closes #247`; hardening commit framed as the safety net).
