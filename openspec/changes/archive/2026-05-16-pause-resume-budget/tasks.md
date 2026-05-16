## 1. Service layer — pause / resume write paths

- [x] 1.1 Add `BudgetLifecycleService.pauseBudget(_ budget: Budget, context: ModelContext, now: Date = Date()) -> Bool` per `specs/budget-lifecycle/spec.md` "Pause budget write-path". Implement the four eligibility rejections (Specific Dates, already paused, post-end, plus the implicit pre-start case folded into the snapshot-state check), the `[startDate, endDate]` effective-date clamp, the single `LifecycleEvent(.pause)` insert, the `Budget.lastModified = now` bump, and the single `context.save()` call.
- [x] 1.2 Add `BudgetLifecycleService.resumeBudget(_ budget: Budget, context: ModelContext, now: Date = Date()) -> Bool` per `specs/budget-lifecycle/spec.md` "Resume budget write-path". Implement the eligibility rejections (Specific Dates, already active or pre-start, post-end), the single `LifecycleEvent(.resume, effectiveDate: now)` insert, the `Budget.lastModified = now` bump, and the single `context.save()` call.
- [x] 1.3 Both methods MUST share the lifecycle-state check by calling `BudgetCalculator.snapshot(budget:expenses:now:calendar:).lifecycleState` (or the same code path used by `BudgetLifecycleService.result(for:)`) so eligibility uses the canonical algorithm, not a re-implementation.

## 2. BudgetLifecycleResult — expose lifecycle state and pausedSince

- [x] 2.1 Add `lifecycleState: BudgetLifecycleState` to `BudgetLifecycleResult`, populated from `BudgetSnapshot.lifecycleState`.
- [x] 2.2 Add `pausedSince: Date?` to `BudgetLifecycleResult`. When `lifecycleState == .paused`, compute it as the `effectiveDate` of the most recent `.pause` `LifecycleEvent` not followed by a later `.resume` (sorting events by `effectiveDate` ascending). Otherwise `nil`.
- [x] 2.3 Compute `pausedSince` inside `BudgetLifecycleService.result(for:)` — not at view sites — so the sort-and-scan logic lives in one place.
- [x] 2.4 Confirm `BudgetLifecycleResult` still satisfies `Equatable` (used by the existing idempotence scenario) and that the new fields participate in equality.

## 3. Budget detail screen — toolbar Pause/Resume item

- [x] 3.1 In `BudgetDetailView`'s toolbar overflow `Menu`, insert a state-driven Pause Budget / Resume Budget item between Edit Budget and the Divider/Reset Budget…, per `specs/budget-detail-screen/spec.md` "Toolbar overflow Menu hosts Edit Budget and Reset Budget actions" MODIFIED requirement.
- [x] 3.2 Hide the item when `BudgetPeriod(rawValue: budget.period) == .specificDates`.
- [x] 3.3 Hide the item when `lifecycle?.lifecycleState == .postEnd` (or equivalent `endDate`-passed check).
- [x] 3.4 When visible, switch label and icon by state: `.active` / `.preStart` → "Pause Budget" / `pause.circle`; `.paused` → "Resume Budget" / `play.circle`.
- [x] 3.5 Add the action handlers `pauseBudgetTapped()` and `resumeBudgetTapped()` mirroring the existing `resetCarryOver()` / `resetBudget()` pattern in `BudgetDetailView` (Logger.ui.debug → service call → analytics.track gated on the service return value → `refreshLifecycle()`).
- [x] 3.6 No confirmation dialog for either action.

## 4. Budget detail screen — primary action slot (Add Expense ↔ Resume Budget)

- [x] 4.1 In `BudgetDetailView`'s primary action section, make the button content state-driven from `lifecycle?.lifecycleState` per `specs/budget-detail-screen/spec.md` "Primary action section presents a full-width Add Expense button" MODIFIED requirement.
- [x] 4.2 In `.active` / `.preStart` / `.postEnd` states, keep the existing Add Expense behavior unchanged.
- [x] 4.3 In `.paused` state, render the button as "Resume Budget" (key `budgetDetail.action.resume`, icon `play.circle`). Activation invokes the same `resumeBudgetTapped()` handler used by the toolbar menu item.
- [x] 4.4 Below the button in the same section, when `.paused`, render the localized caption `budgetDetail.action.resume.caption.format` (en-US "Paused since %@. Resume to log expenses.") in `.caption`/`.secondary` styling, using `lifecycle?.pausedSince` formatted via `Date.formatted(date: .abbreviated, time: .omitted)`. Render no caption in any other state.
- [x] 4.5 Add VoiceOver label and hint keys for the Resume Budget button: `budgetDetail.action.resume.accessibilityLabel`, `budgetDetail.action.resume.accessibilityHint`.

## 5. Budget detail screen — paused header presentation

- [x] 5.1 In `BudgetDetailView`'s status header, when `lifecycle?.lifecycleState == .paused`, override the large remaining amount's foreground to `.secondary` per `specs/budget-detail-screen/spec.md` "Status header renders paused presentation when lifecycle state is paused" ADDED requirement.
- [x] 5.2 Render a `.caption`/`.secondary` line below the period label with the localized caption `chip.paused.caption.format` (en-US "Paused since %@") using `lifecycle?.pausedSince`.
- [x] 5.3 When `Budget.isCarryOverEnabled == true` and `lifecycle?.lifecycleState == .paused`, override the `CarryOverChip`'s value foreground to `.secondary` while keeping its background tint unchanged (consistent with the chip remaining identifiable as a carry-over chip).
- [x] 5.4 Add a paused-state composed VoiceOver label key `budgetDetail.header.accessibilityLabel.paused` and switch the header's `.accessibilityLabel` to that key when paused.
- [x] 5.5 Confirm the chip's value stays live across backdated edits to prior active periods (this is automatic — the value comes from `BudgetLifecycleResult.carryOverAmount`, which the existing `.task(id:)` / `onChange(of: expenseItems.count)` triggers already refresh; no new refresh trigger is needed).

## 6. Budgets screen — paused row presentation

- [x] 6.1 In `BudgetRowView`, when the row's `lifecycle?.lifecycleState == .paused`, override the `remaining` label foreground to `.secondary` per `specs/budgets-screen/spec.md` "Row renders paused presentation when budget lifecycle state is paused" ADDED requirement.
- [x] 6.2 Override the `RemainingBar` foreground to `.secondary` when paused.
- [x] 6.3 When `Budget.isCarryOverEnabled == true` and `lifecycle?.lifecycleState == .paused`, override the row's `CarryOverChip` value foreground to `.secondary` while keeping its background tint unchanged.
- [x] 6.4 Render a `.caption`/`.secondary` line below the row's primary content with the localized caption `chip.paused.caption.format` using `lifecycle?.pausedSince` formatted via `Date.formatted(date: .abbreviated, time: .omitted)`.
- [x] 6.5 Add a paused-state composed VoiceOver label key `budget.row.accessibilityLabel.paused` and switch the row's `.accessibilityLabel` to that key when paused.
- [x] 6.6 Verify drill-in, per-row Add Expense (`plus.circle.fill`), swipe, and reorder affordances are unaffected on paused rows.

## 7. Add/Edit Expense screen — date-bounds for paused budgets

- [x] 7.1 In `AddEditExpenseView` (or its view model), compute the bounding `ClosedRange<Date>` for the When `DatePicker` based on the bound budget's `LifecycleEvent` history. Reuse the existing `LifecycleClassification` helper rather than writing a new traversal. Range is `[firstActivePeriodStart, lastActivePeriodEnd]` per `specs/add-edit-expense-screen/spec.md` "Date picker bounds restrict the When field to the budget's active periods when paused" ADDED requirement.
- [x] 7.2 Apply the bounding range to the `DatePicker`'s `in:` parameter only when `lifecycle?.lifecycleState == .paused`. For active / pre-start / post-end budgets, the existing F-2.04 date-bounds rule applies unchanged.
- [x] 7.3 Implement Save-time validation against the **full** active-period union (not the bounding range): if the picked date sits inside a paused gap or outside `[startDate, endDate]`, disable Save and show the inline caption `addEditExpense.date.outOfRange.caption` directly below the When card.
- [x] 7.4 In Edit mode, allow the picker to load with an out-of-range existing `expense.date`; gate Save on the same validation; clear the caption as soon as the user picks a date inside an active interval.
- [x] 7.5 Add the new localized string `addEditExpense.date.outOfRange.caption` (en-US "Pick a date within an active period of this budget.") with a translator-friendly `comment:`.

## 8. Analytics — budget_paused / budget_resumed events

- [x] 8.1 Add `AnalyticsEvent.budgetPaused = "budget_paused"` and `AnalyticsEvent.budgetResumed = "budget_resumed"` constants in `simple-recurring-budgets/Logging/AnalyticsClient.swift`.
- [x] 8.2 Wire the event firing into the `pauseBudgetTapped()` / `resumeBudgetTapped()` handlers from §3.5, gated on the service method's `Bool` return (only fire on `true`). Properties: `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount` (matching the existing `budget_reset` / `carry_over_reset` property shape).
- [x] 8.3 Add the corresponding `Logger.ui.debug("ui.action: pauseBudget budget=… ", privacy: .private)` and `…resumeBudget…` lines next to the service call, with the same sibling-pattern boundary comment used by the existing `resetCarryOver` and `resetBudget` code paths.

## 9. Localization

- [x] 9.1 Add the new localized strings to `Localizable.xcstrings` (English source) with translator-friendly `comment:` values:
  - `budgetDetail.menu.pauseBudget` ("Pause Budget")
  - `budgetDetail.menu.resumeBudget` ("Resume Budget")
  - `budgetDetail.action.resume` ("Resume Budget")
  - `budgetDetail.action.resume.caption.format` ("Paused since %@. Resume to log expenses.")
  - `budgetDetail.action.resume.accessibilityLabel` (e.g. "Resume budget %@")
  - `budgetDetail.action.resume.accessibilityHint` (e.g. "Tap to resume this budget so you can log expenses again.")
  - `budgetDetail.header.accessibilityLabel.paused` (paused composed header label format)
  - `chip.paused.caption.format` ("Paused since %@") — shared by Budget detail header, Budgets list row, and any other chip surface
  - `budget.row.accessibilityLabel.paused` (paused composed row label format)
  - `addEditExpense.date.outOfRange.caption` ("Pick a date within an active period of this budget.")
- [x] 9.2 Run `scripts/translate_catalog/` (extract → translate → merge → validate) to produce translations for all 38 storefront locales per F-3.03. Commit the updated catalog.
- [x] 9.3 Pseudo-loc smoke check per `docs/audits/localization+voiceover-audit-2026-04-30.md` Appendix B for the new strings (focus on the paused caption length and the When-out-of-range caption).

## 10. Tests — service layer

- [x] 10.1 Add Swift Testing tests for `BudgetLifecycleService.pauseBudget(...)` covering: active → returns `true` and inserts one `LifecycleEvent`; clamp at `startDate` when `now < startDate`; rejected for `.specificDates`; rejected when already paused; rejected past `endDate`; `Budget.lastModified` bumped on success; `context.save()` called exactly once on success.
- [x] 10.2 Add Swift Testing tests for `BudgetLifecycleService.resumeBudget(...)` covering: paused → returns `true` and inserts one `LifecycleEvent`; rejected for `.specificDates`; rejected when already active or pre-start; rejected past `endDate`; `Budget.lastModified` bumped on success; `context.save()` called exactly once on success.
- [x] 10.3 Add a `BudgetLifecycleService.result(for:)` test that verifies `pausedSince` returns the most recent unbalanced `.pause` event's `effectiveDate`, and `nil` when the latest event is a `.resume` (or when no events exist).
- [x] 10.4 Confirm existing `LifecycleClassification` and `CarryOverWalker` tests still pass — no algorithm changes were made in this change.

## 11. Tests — UI / view-level

- [x] 11.1 Add a unit test (or ViewModel test, if `BudgetDetailViewModel` is escalated) that confirms the toolbar Menu omits the Pause/Resume item for `.specificDates` budgets and budgets past `endDate`, and shows the correct state-driven label / icon for `.active` and `.paused`.
- [x] 11.2 Add a ViewModel test (or AddEditExpenseViewModel test) covering the Save-time date-bounds validation: a date inside a paused gap blocks Save; picking a date inside an active interval clears the block.
- [x] 11.3 Add a SwiftUI preview matrix entry (or update the existing six-state matrix from `budget-detail-screen/spec.md` "Six SwiftUI previews exercise the visual matrix in DEBUG builds") for the `.paused` lifecycle state so the paused header + primary slot + caption are exercised in DEBUG builds.

## 12. Doc updates

- [x] 12.1 Flip `docs/product-features-planning.md` F-7.06 status from "Open" to "Implemented" with a "Implemented by change `pause-resume-budget`" note. Remove the "Mark Implemented when the rewrite ships" line.
- [x] 12.2 Append `budget_paused` and `budget_resumed` event rows to `docs/analytics-spec.md` (event taxonomy section). Document the property list (`period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount`) and reference F-7.06 + F-8.02.
- [x] 12.3 Add `pauseBudget(...)` and `resumeBudget(...)` rows to `docs/tech-design-doc.md` §4.5 (service surface table) if such a table exists; otherwise add a brief paragraph in the relevant subsection.
- [x] 12.4 Verify `docs/main-prd.md` §6.7 still reads correctly with pause/resume as a refresh trigger; no edits expected.
- [x] 12.5 If `docs/ux-design-brief.md` tracks the paused chip presentation in a copy-table or design-notes section, update it; otherwise no change needed.

## 13. Cross-cutting concerns checklist (`docs/main-prd.md` §6.8)

- [x] 13.1 **Accessibility:** every new control (toolbar item, prominent Resume button, paused chip caption, out-of-range caption) carries a localized `.accessibilityLabel` (and hint where it adds value). Destructive trait NOT applied (pause/resume is reversible).
- [x] 13.2 **Localized source strings:** every new user-visible string is keyed in the catalog with a translator-friendly `comment:` — no English literals remain in `BudgetDetailView`, `BudgetRowView`, or `AddEditExpenseView` from this change.
- [x] 13.3 **Translations queue:** `scripts/translate_catalog/` has been run and all 38 storefront locales have translations for the new keys (per §9.2).
- [x] 13.4 **Mixpanel:** `budget_paused` and `budget_resumed` events fire from the action sites with the property shape defined in §8.2 and `docs/analytics-spec.md`.

## 14. Build / verify

- [x] 14.1 Run the four-step `AGENTS.md > Build and test` procedure: `make format` → `make lint-fix` → `make build` → `make test`. All four must pass before considering the change apply-complete.
- [x] 14.2 Manual UI smoke on a real device (or Simulator at minimum): Pause from toolbar → header greyed, primary button swaps to Resume, caption shows; Resume from primary button → header re-tints, button swaps back to Add Expense, analytics events fire. Pause → backdate an expense to a prior active period → chip value updates while paused. Open Add Expense on a paused budget → picker constrained as specified; pick a date inside a paused gap → Save blocked with caption.
- [x] 14.3 Verify Specific Dates budgets (once F-2.08 ships, in a separate change) do not show the Pause/Resume toolbar item. Until F-2.08 ships, this is a code-path check rather than a UI check.
- [x] 14.4 Cross-check final implementation against `docs/budget-calculations-rewrite-reqs.md` §5.5 and §6.7 cases 1–16. Each algorithmic case should be exercised by the existing rewrite tests (no new algorithm code) or by the new service / UI tests in this change.
