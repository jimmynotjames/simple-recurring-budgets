## ADDED Requirements

### Requirement: Weekly explanatory note and Change-start-of-week link in the Period card

When and only when `viewModel.period == .weekly`, the Period card SHALL render, directly below the chip grid (and below the `.specificDates` chip slot), a two-part block:

1. A caption (key `addEditBudget.note.weekly`, en source: `"All weekly budgets start on %@."` where `%@` is the localized standalone name of `AppSettings.weekStartDay`), styled `.font(.caption)` and `.foregroundStyle(.readableSecondary)`. The weekday name SHALL be read live from `AppSettings.weekStartDay` so the caption updates immediately when the setting changes.
2. A quiet link beneath the caption (key `addEditBudget.note.weekly.changeLink`, en source: `"Change start of week"`), rendered as a `NavigationLink` tinted with `Color.accentColor`, that pushes `WeekStartPickerScreen` (capability `week-start-picker-screen`) onto the form's own `NavigationStack`. Pushing it SHALL preserve the in-progress budget draft.

The block SHALL transition in via `.opacity.combined(with: .move(edge: .top))`. It SHALL render in **both Add and Edit modes** (the week-start is relevant in both) and SHALL NOT render for any other period type. It coexists with the Edit-mode period-lock caption.

#### Scenario: Weekly note and link show when Weekly is selected in Add mode

- **WHEN** the user opens Add and selects the Weekly period chip
- **THEN** a `.caption` note reading "All weekly budgets start on `<current week-start day>`." renders below the period chip grid, with a "Change start of week" link beneath it

#### Scenario: Weekly note shows in Edit mode for a weekly budget

- **WHEN** the user opens Edit for a `.weekly` budget
- **THEN** the weekly note and link render below the (locked) period chip grid, alongside the period-lock caption

#### Scenario: Weekly note is absent for non-weekly periods

- **WHEN** `viewModel.period` is `.daily`, `.biweekly`, `.monthly`, or `.specificDates`
- **THEN** the weekly note (`addEditBudget.note.weekly`) and its link do not render

#### Scenario: Tapping the link pushes the Start of Week screen and preserves the draft

- **WHEN** the user taps "Change start of week"
- **THEN** `WeekStartPickerScreen` is pushed onto the form's `NavigationStack`, the in-progress draft remains intact underneath, and tapping Back returns to the form

#### Scenario: Note reflects the current week-start day live

- **WHEN** the displayed week-start day changes (e.g. confirmed on the pushed `WeekStartPickerScreen`) and the user returns to the form
- **THEN** the weekly note re-reads `AppSettings.weekStartDay` and shows the new weekday name

---

### Requirement: Weekly draft start-date re-anchors when the global week-start changes

`AddEditBudgetViewModel` SHALL expose `func realignWeeklyStartDate(to weekStart: Weekday)` that, in **Add mode only** and only when `period == .weekly`, sets `startDate` to the most-recent-past occurrence of `weekStart` at or before `startOfDay(Date())` — the same alignment `onPeriodChange()` applies when Weekly is first selected. It SHALL be a no-op in Edit mode (an existing budget's `startDate` is user data that must not be silently moved) and a no-op for any non-weekly period.

The Add/Edit Budget screen SHALL invoke `realignWeeklyStartDate(to:)` via `.onChange(of: AppSettings.weekStartDay)`, so that changing the week-start from the pushed `WeekStartPickerScreen` re-aligns the in-progress weekly draft to the new grid.

#### Scenario: Add-mode weekly draft re-anchors on a week-start change

- **WHEN** an Add-mode draft has `period == .weekly` and `AppSettings.weekStartDay` changes from Sunday to Monday
- **THEN** `realignWeeklyStartDate(to: .monday)` sets `startDate` to the most-recent-past Monday at or before today

#### Scenario: Edit mode does not re-anchor

- **WHEN** the VM is in Edit mode for a `.weekly` budget and `realignWeeklyStartDate(to:)` is invoked
- **THEN** `startDate` is unchanged

#### Scenario: Non-weekly period does not re-anchor

- **WHEN** an Add-mode draft has `period == .daily` (or `.biweekly`, `.monthly`, `.specificDates`) and `realignWeeklyStartDate(to:)` is invoked
- **THEN** `startDate` is unchanged

#### Scenario: The form wires the re-anchor to the setting

- **WHEN** the Add/Edit Budget screen is inspected
- **THEN** it observes `AppSettings.weekStartDay` via `.onChange` and calls `viewModel.realignWeeklyStartDate(to:)` with the new value
