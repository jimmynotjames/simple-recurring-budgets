## Why

Specific Dates is the last `BudgetPeriod` case without UI exposure. The `rewrite-budget-calculations` change shipped the algorithm and schema support (`.specificDates` enum case, `Budget.endDate`, `BudgetCalculator.specificDatesBranch`, lifecycle guards) but intentionally deferred the user-facing surface (see archived tasks §4.9). Users currently cannot create a one-shot envelope budget (e.g., "$1,500 for the Italy trip") even though the data model and math already handle it correctly.

This change surfaces Specific Dates in the Add/Edit Budget screen, propagates the period-type carve-outs through the Budgets list, Budget detail screen, and Add/Edit Expense date bounds, and wires the latest-wins allocation-edit semantics in `BudgetLifecycleService`. Per F-2.08, the Carry-Over toggle, Carry-Over chip, Reset Carry-Over action, and Pause/Resume control are all hidden for this period type.

## What Changes

- **Add/Edit Budget screen** — Add `.specificDates` as a selectable period (rendered as a full-width chip below the recurring 2×2 grid). Show an explanatory blurb directly below the chip when selected ("Good for a trip, a birthday weekend, or any one-off spending window. When it's done, it's done. No repeating, no carry-over."). Add a "Dates" card with side-by-side start/end date pickers (sheet-presented `.graphical` `DatePicker` for reliable single-tap UX), neither pre-populated, with end constrained to `>= start`. Hide the Carry-Over card while `.specificDates` is selected. Gate Save on both dates set and `start <= end` (in addition to existing name + allocation checks).
- **`AddEditBudgetViewModel`** — Add `startDate: Date?` and `endDate: Date?` draft state. Seed from `Budget.startDate`/`Budget.endDate` in Edit mode. Extend `canSave` with the dates gate when period is `.specificDates`. Rewrite `saveNew` to use the user's chosen `startDate`/`endDate` for `.specificDates` (the current code defaults `startDate` to today and never writes `endDate`). Extend `saveEdit` to diff and write `startDate`/`endDate` when changed.
- **`BudgetLifecycleService.applyAllocationEdit`** — Replace the current `assert(period != .specificDates)` no-op with the latest-wins implementation per F-2.08: insert/replace an `AllocationChange` with `effectiveFrom = budget.startDate` so the new amount applies across the entire window.
- **Budgets list and Budget detail header** — Show the formatted date range (e.g., "May 18 – Jun 3") in place of `BudgetPeriod.listLabel` for `.specificDates` budgets via a new `Budget.periodDisplayLabel` computed property backed by `Date.IntervalFormatStyle` (already implemented during workshopping). Use `ViewThatFits` to switch the amount + period label between HStack and VStack based on available width rather than a fixed Dynamic Type threshold (already implemented during workshopping).
- **Budgets list + Budget detail — carry-over chip** — Mask the `isCarryOverEnabled` flag passed to `StatusChipRow` with `&& !isSpecificDates` so the Carry-Over chip never renders for `.specificDates` budgets, regardless of the stored `isCarryOverEnabled` value.
- **Budget detail toolbar menu** — Hide the "Reset Carry-Over…" menu item for `.specificDates` budgets (currently gated only on `budget.isCarryOverEnabled`).
- **Add/Edit Expense** — Confirm the existing `[Budget.startDate, Budget.endDate]` date-bounds logic correctly clamps the expense date picker for `.specificDates` budgets per F-2.04/F-2.08. No new requirements expected; this is a verification step.
- **Analytics** — Confirm `BudgetPeriod.analyticsValue` returns a defined non-empty string for `.specificDates` so `budgetCreated`/`budgetEdited` events carry a meaningful period value. Add if missing.
- **`DebugData` fixtures** — Add a `specificDatesDefault` budget fixture (Italy Trip, EUR 1,500, 17-day window, three expenses) used in both the Budgets list previews and a new `detailSpecificDates` fixture for `BudgetDetailView` previews (already added during workshopping).
- **Strings and translations** — Key every new user-facing string in `Localizable.xcstrings` with `comment:` and run the translation pipeline for all 38 locales.
- **Accessibility** — Add VoiceOver labels/hints for the new date controls (start/end date buttons, picker sheet). Add a `Budget.periodInlineLabel` analogue for the existing `period.inlineLabel` use in row VoiceOver labels so `.specificDates` reads as "in this window" rather than "in this specific dates period."

## Capabilities

### New Capabilities

None. All requirements modify existing specs.

### Modified Capabilities

- `add-edit-budget-screen`: Add `.specificDates` to the period chip set, add the Dates card (start/end date pickers + sheet-presented `.graphical` DatePicker), hide the Carry-Over card while `.specificDates` is selected, gate Save on dates. Update VM requirements to include `startDate`/`endDate` draft state and the new `saveNew`/`saveEdit` write paths.
- `budgets-screen`: Use `Budget.periodDisplayLabel` for the period label, hide the Carry-Over chip for `.specificDates` budgets, switch the amount + period label layout to `ViewThatFits`.
- `budget-detail-screen`: Use `Budget.periodDisplayLabel` in the header, hide the Carry-Over chip and the "Reset Carry-Over…" menu item for `.specificDates` budgets, switch the header amount + period label layout to `ViewThatFits`.
- `add-edit-expense-screen`: Confirm/strengthen the existing `[Budget.startDate, Budget.endDate]` date-bounds rule so it explicitly covers `.specificDates` budgets, where both fields are guaranteed to be present.
- `budget-lifecycle`: Implement `applyAllocationEdit` for `.specificDates` (latest-wins whole-window overwrite) per F-2.08.
- `data-models`: Add `Budget.periodDisplayLabel` and `Budget.periodInlineLabel` computed properties (display-derived; no schema change).

## Impact

- **New file:** `simple-recurring-budgets/Models/Budget+Display.swift` (already added).
- **Updated files:** `AddEditBudgetView.swift`, `AddEditBudgetView+SpecificDates.swift`, `AddEditBudgetViewModel.swift`, `BudgetsView.swift`, `BudgetDetailView.swift`, `BudgetLifecycleService.swift`, possibly `AddEditExpenseView.swift`, `Analytics+DomainExtensions.swift`, `DebugData.swift`, `BudgetDetailFixtures.swift`, `Localizable.xcstrings`.
- **No schema migration** — `Budget.endDate` already exists in the SwiftData model from the algorithm rewrite. CloudKit-synced records with both fields set behave correctly through the algorithm seam.
- **No new dependencies.**
- **Cross-cutting concerns** (docs/main-prd.md §6.8): accessibility (new date controls), localized source strings (new copy), translations queue (run pipeline for all 38 locales), Mixpanel analytics (verify `.specificDates` analyticsValue). All four addressed in tasks.

## Doc alignment

- `docs/product-features-planning.md` F-2.08, F-2.03, F-7.07, F-2.07 already document the behaviour this change implements. After implementation, flip the **Status** line on F-2.08 from "Open" to "Implemented" and update F-2.03's "Outstanding items" note that listed Specific Dates as deferred.
- `docs/main-prd.md` and `docs/tech-design-doc.md` need no changes — no new architecture or global constraints introduced.

## Workshop status

Substantial workshopping has already happened on this branch. Already implemented (and verified via build + lint + previews) but **not yet wired through the ViewModel or persisted on save**:
- `.specificDates` chip + explanatory blurb in `AddEditBudgetView`.
- "Dates" card with side-by-side `DateColumn` views, sheet-presented `.graphical` DatePicker.
- View-local `@State var startDate/endDate` and view-local `canSave` workaround (in `AddEditBudgetView+SpecificDates.swift`).
- `Budget.periodDisplayLabel` (`Budget+Display.swift`).
- `BudgetsView` and `BudgetDetailView` swapped to `periodDisplayLabel` and `ViewThatFits` for the amount + period layout.
- `DebugData.specificDatesDefault` and `DebugData.detailSpecificDates` fixtures + corresponding previews.

The tasks artifact captures the remaining work (VM wiring, carry-over chip masking, allocation-edit semantics, expense-date-bounds verification, analytics check, strings + translations, accessibility, doc updates) and explicitly marks the workshop items above as done.
