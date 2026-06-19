## Why

When a user picks the Weekly period on the Add/Edit Budget screen, nothing tells them which day their weeks start on, and the only place to change it (`AppSettings.weekStartDay`, F-5.01) is buried in the Settings screen — far from where the budget is being created. This change surfaces the week-start at the point of relevance and lets the user change it without leaving the budget form, while keeping the setting honestly app-wide.

The UI and text copy were workshopped and are already committed on this branch (finalized — not to be re-litigated here). This proposal fills the remaining gaps: the cross-cutting concerns (translations, accessibility, UI-test screen objects), automated tests, and spec/doc updates.

## What Changes

- **Weekly disclosure note** on the Add/Edit Budget screen: when Weekly is selected, a caption under the period grid reads "All weekly budgets start on `<day>`." (live from `AppSettings.weekStartDay`), with a quiet "Change start of week" link beneath it. Shown in both Add and Edit modes.
- **New focused Start of Week screen** (`WeekStartPickerScreen`): a pushable list of the seven weekdays with the current one checked, an app-wide-scope banner ("App-wide setting. Changes here will update all weekly budgets."), and the same cascade-warning confirmation the Settings picker uses before committing. Writes the global `AppSettings.weekStartDay` and fires the existing `setting_changed` (`week_start_day`) analytics event.
- **In-flow navigation**: the link pushes `WeekStartPickerScreen` onto the budget form's own `NavigationStack`, preserving the in-progress draft; tapping Back returns the user to the form with the new week-start reflected.
- **Start-date re-anchor**: when the global week-start changes, the Add-mode weekly draft's `startDate` re-anchors to the most-recent-past occurrence of the new week-start day (no-op in Edit mode and for non-weekly periods).
- **Settings screen unchanged**: its existing Calendar / Week-Starts-On picker stays as-is (the two surfaces are intentionally distinct).
- **Gap-fill (the point of this proposal)**: translate the new source strings to all 49 locales; add VoiceOver labels/traits to the new screen and the note link; add a `WeekStartPickerScreen` UI-test screen object and update `AddBudgetScreen`; add unit coverage for the re-anchor behavior.

No new analytics event is introduced (the picker reuses `setting_changed`). No data-model or budget-math requirement changes — the weekly grid already follows `AppSettings.weekStartDay` at math-time (F-5.01).

## Capabilities

### New Capabilities
- `week-start-picker-screen`: a focused, pushable screen for viewing and changing the global week-start day from inside a navigation stack (e.g. the budget form), with an app-wide-scope banner, the shared week-start confirmation, and `setting_changed` analytics — without leaving the host flow.

### Modified Capabilities
- `add-edit-budget-screen`: adds the Weekly disclosure note + "Change start of week" link that pushes `WeekStartPickerScreen`, and the re-anchor of the Add-mode weekly draft `startDate` when `AppSettings.weekStartDay` changes.

## Impact

- **Code (already committed on this branch — finalized UI/copy):** `simple-recurring-budgets/Views/BudgetForm/AddEditBudgetView.swift`, `AddEditBudgetView+Previews.swift`, `AddEditBudgetViewModel.swift` (`realignWeeklyStartDate(to:)`), and new `simple-recurring-budgets/Views/Settings/WeekStartPickerScreen.swift`.
- **Strings:** four new `Localizable.xcstrings` keys — `addEditBudget.note.weekly`, `addEditBudget.note.weekly.changeLink`, `weekStartPicker.navTitle`, `weekStartPicker.scopeNote` — plus reuse of the existing `settings.weekStart.alert.*` keys. Catalog currently clean (keys not yet extracted); the translate pipeline will own extract→translate→merge→validate.
- **Tests:** new unit coverage for `realignWeeklyStartDate(to:)`; new `WeekStartPickerScreen` UI-test screen object + `AddBudgetScreen` updates for the note/link (no XCUITest journey is required to add, but the screen objects must not go stale per PRD §6.8.5).
- **Analytics:** reuses `setting_changed` / `week_start_day` (product-analytics unchanged).
- **Accessibility:** new screen rows, scope banner, and the form's note link need labels/traits/hints.

## Doc alignment

Skimmed `docs/main-prd.md`, `docs/product-features-planning.md`, `docs/tech-design-doc.md`. No conflicts.

- **F-5.01 (Configurable start of week)** currently describes a single entry point (the Settings picker). It should be updated to note the **second entry point** — the Add/Edit Budget weekly disclosure note + "Change start of week" link pushing a focused picker — while reaffirming the setting remains global. Update as a task before archive.
- **F-2.03 (Per-budget Start Date)** should gain a note that the Add-mode weekly draft `startDate` re-anchors when the global week-start changes mid-create (consistent with its existing pre-population rule). Update as a task before archive.
- Cross-cutting concerns (PRD §6.8) apply: translations, accessibility, and UI-test screen objects are explicit tasks in this change.
