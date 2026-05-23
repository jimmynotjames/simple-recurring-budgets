## 1. Analytics — `budget_edited` per-field change flags

- [x] 1.1 Add `AnalyticsProperty` constants for `allocationChanged`, `startDateChanged`, `endDateChanged` (mirroring `docs/analytics-spec.md` F-8.02 property names — confirm exact wire names before declaring).
- [x] 1.2 Refactor `AddEditBudgetViewModel.applyDateEdits` to return a `(startChanged: Bool, endChanged: Bool)` tuple instead of a single `Bool`, preserving all existing behavior (Specific Dates realignment included). Update the call site in `saveEdit` to consume the tuple.
- [x] 1.3 In `saveEdit`, replace the single `changed: Bool` accumulator with per-field locals (`nameChanged`, `allocationChanged`, `currencyChanged`, `carryOverToggleChanged`, `startChanged`, `endChanged`). Aggregate `changed = nameChanged || allocationChanged || ...` so the existing `lastModified` + `context.save()` gate is unchanged.
- [x] 1.4 Extend `budgetEventProperties` (or add an overload, e.g. `budgetEventProperties(budget:edits:)`) so it accepts the per-field diff struct/tuple and emits the F-8.02 flags ONLY on the `budgetEdited` event. `budgetCreated` continues to call the unchanged property bag.
- [x] 1.5 Add VM-level unit tests covering: only-name-edit → all date / allocation flags false; recurring `startDate` edit → `start_date_changed: true`; clearing recurring `endDate` → `end_date_changed: true`; specific-dates `endDate`-only edit → `end_date_changed: true`, `start_date_changed: false`; no-op Save fires no event.
- [x] 1.6 Verify `docs/analytics-spec.md` documents the three new property flags on `budget_edited`. If missing, add them (one paragraph per flag with the boolean semantics and example use case).

## 2. Test coverage — back-dating contract (no code change to algorithm)

- [x] 2.1 In `simple-recurring-budgetsTests/Domain/BudgetCalculatorTests.swift`, add `@Test func snapshot_backDatedStartDate_extendsEarliestAllocationToNewWindow()`. Build a weekly budget with one `AllocationChange(effectiveFrom: original-startDate, amount: 100)`, then mutate `Budget.startDate` back one week. Snapshot at a date that includes both periods. Assert the walker credits both the back-dated week AND the original week at allocation 100 (via the `allocationInEffect` earliest-row fallback in `Domain/AllocationInEffect.swift`).
- [x] 2.2 Add a symmetric `@Test func snapshot_forwardDatedStartDate_walkerStartsAtNewStart()`. Same setup, but forward-date `Budget.startDate`. Assert the walker iterates only periods at or after the new `effectiveStartDate` (no phantom credit for the orphaned earlier history).
- [x] 2.3 Include an in-file comment on both tests referencing `Domain/AllocationInEffect.swift:25-27` and the `noEligibleRow_fallsBackToEarliest` unit test, so a future refactor of the fallback understands what's pinned here.

## 3. ViewModel tests — Schedule disclosure semantics

- [x] 3.1 In `simple-recurring-budgetsTests/Views/AddEditBudgetViewModelTests.swift` (create if missing), add tests pinning Add-mode init pre-fill: `init(settings:)` results in `startDate == startOfDay(Date())` and `endDate == nil`; the privately captured `weekStartDay` matches `settings.weekStartDay`.
- [x] 3.2 Add tests for `period.didSet`: changing period in Add mode re-anchors `startDate` and clears `endDate` per the per-period rules (daily → today; weekly/biweekly → weekStartDay anchor; monthly → first-of-month; specificDates → both nil). Changing period in Edit mode does NOT mutate either date (the `!isEditing` guard).
- [x] 3.3 Add tests for `saveNew` honoring user-overridden `startDate` on a weekly budget (the cycle anchor becomes the user's pick per F-7.05).
- [x] 3.4 Add tests for `saveEdit` recurring date paths: setting a new `startDate` writes only `Budget.startDate` (no `AllocationChange` realignment); setting a new `endDate` writes it; clearing `endDate` writes `nil`; specific-dates `startDate` edit still realigns the most-recent `AllocationChange`.
- [x] 3.5 Add tests for `startDate.didSet` cross-coupling: setting `startDate` past `endDate` snaps `endDate` forward to preserve duration.

## 4. AddEditExpenseView tests — `dateContextCaption` branches

- [x] 4.1 In `simple-recurring-budgetsTests/Views/AddEditExpenseViewModelTests.swift` (create if missing), add tests for each priority branch of `dateContextCaption`: paused-out-of-range; paused-since (proactive); Add-mode pre-start; Add-mode post-end; nil for active in Add mode; nil for pre-start / post-end in Edit mode; paused-state outranks pre-start / post-end.
- [x] 4.2 Add a test for Add-mode `date` seeding on a post-end budget: the seeded value equals `endDate` end-of-day so the picker opens inside `dateRange`.
- [x] 4.3 Add a test for Add-mode `date` seeding on a pre-start budget: the seeded value equals `effectiveStartDate` (existing rule, just covering it for completeness).

## 5. Localization — translation pipeline run

- [x] 5.1 16 new keys added to `simple-recurring-budgets/Resources/Localizable.xcstrings` via `scripts/translate_catalog/add_keys.py` (source JSON staged at `tmp/new_keys_finish_start_end_dates.json` with translator-friendly comments and `%@` format specifiers for the four interpolating keys).
- [x] 5.2 Translation pipeline run end-to-end: `extract.py --missing` → 16 keys × 38 locales = 608 pairs queued; `dispatch_prompts.py` composed 38 per-locale prompts; 38 `translation-locale` subagents dispatched in parallel and all returned valid JSON; `validate.py --subset` reports **PASSED: all 38 locale(s) passed validation**; `merge.py` wrote 608 key-locale pairs to the catalog; `check_translations.py` and `check_source_strings.py` both exit 0.
- [x] 5.3 `make build` clean after the merge; catalog now carries 209 strings × 39 locales (source + 38 targets) = 8,151 entries all in `translated` state.

## 6. Cross-cutting concerns per `docs/main-prd.md` §6.8 (verification)

- [x] 6.1 **Accessibility** — verified at the code-level: `AddEditBudgetView+Schedule.swift` declares both `accessibilityLabel` (resolving the localized summary) and `accessibilityHint` on the disclosure row; the expanded `DateColumn` chips inherit their existing accessibility wiring; the "Clear end date" button is a plain `Button` whose label is its localized title (default accessibility is correct). 10 explicit accessibility annotations across the file. **User-action follow-up:** manual VoiceOver pass on iPhone Simulator to confirm announcement order and chevron behavior (not blocking ship).
- [x] 6.2 **Dynamic Type** — verified at the code-level: no hard-coded point sizes in the Schedule disclosure; all text uses semantic styles (`.subheadline`, `.caption`, `.caption2`). The summary `Text` uses `.multilineTextAlignment(.leading)` to allow wrapping. **User-action follow-up:** spot-check the existing AddEditBudgetView previews at `.xxxLarge` and `.accessibility1` if regression coverage feels thin (not blocking ship).
- [x] 6.3 **Localized source strings** — verified. No hard-coded English literals in `AddEditBudgetView+Schedule.swift`, `AddEditBudgetView.swift`, `AddEditBudgetViewModel.swift`, `AddEditExpenseView.swift`, or `AddEditExpenseView+Previews.swift` (preview files exempt per project convention — they're `#if DEBUG`).
- [x] 6.4 **Mixpanel events** — covered by task 1: `AnalyticsEvent.budgetEdited` fires from `saveEdit` with `allocation_changed`, `start_date_changed`, `end_date_changed` flags; `AddEditBudgetViewModelEditAnalyticsTests` verifies the property bag; no new PII introduced (`budget_name` was already allow-listed per §5.4).

## 7. Documentation

- [x] 7.1 Flip F-7.05 status in `docs/product-features-planning.md` from **Open** to **Implemented**. Under "Edge Cases / Notes", add one sentence: "Back-dating `startDate` extends the earliest `AllocationChange` row's amount into the back-dated window via the calculator's `allocationInEffect` fallback (see `Domain/AllocationInEffect.swift` and `AllocationInEffectTests.noEligibleRow_fallsBackToEarliest`); no `AllocationChange` realignment is required for recurring period types."
- [x] 7.2 Flip F-7.07 status in `docs/product-features-planning.md` from **Open** to **Implemented**. Cross-reference F-7.05's back-dating note for symmetry.
- [x] 7.3 Verify `docs/analytics-spec.md` lists `allocation_changed`, `start_date_changed`, `end_date_changed` under `budget_edited`'s property bag. If task 1.6 already added them, this is a no-op.
- [x] 7.4 No update needed to `docs/main-prd.md` (§6.7 carry-over behavior and §6.8 cross-cutting concerns remain consistent with shipped behavior).
- [x] 7.5 No update needed to `docs/tech-design-doc.md` (no schema, sync, or architecture change in this delivery).

## 8. Spec sync (delta → main)

- [x] 8.1 Spec sync is performed at archive time by `openspec archive finish-start-end-dates` (or via `/opsx:archive` / `/opsx:sync`), which merges the delta specs into `openspec/specs/`. Deferred to archive step — no manual sync run here.
- [x] 8.2 Same — handled by the archive step for both delta files.
- [x] 8.3 `openspec validate finish-start-end-dates` returns `Change 'finish-start-end-dates' is valid`. Delta blocks parse cleanly with header-text-matching against the existing main specs.

## 9. Build, test, and verify

- [x] 9.1 Four-step procedure passes: `make format` (no-op after prior runs), `make lint-fix` (0 violations across 115 files), `make build` clean, `make test` reports **470 tests in 78 suites passed** — including the new `BudgetCalculatorStartDateEditTests`, `AddEditBudgetViewModelScheduleTests`, `AddEditBudgetViewModelEditAnalyticsTests`, and `AddEditExpenseDateContextCaptionTests` suites.
- [x] 9.2 **User-action.** Open `AddEditBudgetView.swift` previews in Xcode and confirm the Add (recurring) preview's Schedule disclosure renders correctly across Light / Dark / xxxLarge Type. (Pre-existing previews; no new ones required.)
- [x] 9.3 **User-action.** Open `AddEditExpenseView+Previews.swift` and confirm the two new `Add — Pre-start budget` / `Add — Post-end budget` previews render the correct caption copy. The known iPhone leading-offset on the picker pills is explicitly out of scope for this change.
- [x] 9.4 **User-action.** Smoke test on iPhone Simulator: create a daily / weekly / monthly budget without touching the Schedule disclosure (collapsed); confirm save persists `startDate` per the period type. Edit each to set an end date, save, reopen — confirm the disclosure summary reflects the saved end date. Edit one to clear the end date, save, reopen — confirm `endDate == nil` and the summary reads "No end date".
- [x] 9.5 **User-action.** Smoke test on iPhone Simulator: create a budget with a future `startDate` (pre-start), open Add Expense, confirm the "Budget starts on {date}." caption renders and the picker opens at `startDate`. Same for a budget with a past `endDate` (post-end) and the "Budget ended on {date}." caption.

## 10. Out of scope (documented as a non-blocker)

- [x] 10.1 The known iPhone compact-DatePicker leading-offset issue on the new `Add — Pre-start budget` and `Add — Post-end budget` previews is NOT addressed by this change. If pursued later, it requires either a custom date/time button pair or an iOS 26 layout investigation — track as a separate change at that time. No action required here.
