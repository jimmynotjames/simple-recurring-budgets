# week-start-picker-screen Specification

## Purpose
TBD - created by archiving change weekly-week-start-from-budget-form. Update Purpose after archive.
## Requirements
### Requirement: Focused, pushable Start of Week screen

The system SHALL provide `WeekStartPickerScreen`, a focused screen for viewing and changing the global week-start day (`AppSettings.weekStartDay`, capability `app-settings`) from inside a navigation stack without leaving the host flow. The screen SHALL be hostable via `NavigationLink` push (e.g. from the Add/Edit Budget form's own `NavigationStack`) so any in-progress host state remains alive underneath and the user returns to it on Back.

The screen SHALL render its content in a `List`, apply the app's global background via `.appBackground()`, and use an inline navigation title from key `weekStartPicker.navTitle` (en source: "Start of Week"). The screen SHALL access `AppSettings` via `@Environment(AppSettings.self)` and SHALL NOT instantiate its own instance.

#### Scenario: Pushed within the host navigation stack

- **WHEN** `WeekStartPickerScreen` is pushed via `NavigationLink` from a host screen that owns a `NavigationStack`
- **THEN** the host screen's state remains intact underneath, and tapping Back returns the user to it

#### Scenario: Screen composition

- **WHEN** `WeekStartPickerScreen` appears
- **THEN** it renders a `List` containing the scope banner and the weekday selection rows, with an inline title resolved from `weekStartPicker.navTitle`

---

### Requirement: Weekday rows with current-selection indicator

The screen SHALL list all seven `Weekday` cases in `Weekday.allCases` order (Sunday through Saturday), labeling each with the locale-aware standalone weekday name from `Calendar.current.standaloneWeekdaySymbols` (`weekday.rawValue - 1`). The row whose `Weekday` equals the current `AppSettings.weekStartDay` SHALL show a trailing checkmark; all other rows SHALL not. Each row SHALL be an actionable control (button) that initiates selection of that weekday.

#### Scenario: All seven weekdays listed in order

- **WHEN** the screen renders
- **THEN** it shows seven rows, one per `Weekday`, in Sunday-through-Saturday order, each labeled with the locale-aware standalone weekday name

#### Scenario: Current day shows the checkmark

- **WHEN** `AppSettings.weekStartDay` is `.monday`
- **THEN** the Monday row shows a checkmark and no other row does

---

### Requirement: App-wide scope banner

The screen SHALL display, above the weekday list, a scope banner consisting of an `exclamationmark.triangle.fill` SF Symbol tinted with `Color.accentColor` (overriding the symbol's default multicolor rendering) and the localized text from key `weekStartPicker.scopeNote` (en source: "App-wide setting. Changes here will update all weekly budgets."). The banner communicates that the setting is global, not scoped to the budget the user navigated from. The symbol SHALL match the banner text font so it baseline-aligns with the first line and scales with Dynamic Type.

#### Scenario: Banner renders above the list with an accent-tinted icon

- **WHEN** the screen renders
- **THEN** the scope banner appears above the weekday rows with the `exclamationmark.triangle.fill` symbol drawn in the app accent color (not orange)

#### Scenario: Banner states app-wide scope

- **WHEN** the banner is read
- **THEN** its text resolves from `weekStartPicker.scopeNote` and states that the change updates all weekly budgets

---

### Requirement: Selecting a weekday is gated by the cascade-warning confirmation

Selecting a weekday SHALL reuse the shared `WeekStartConfirmation` state machine and the shared `settings.weekStart.alert.*` strings (capability `settings-screen`). Selecting a weekday different from the current `AppSettings.weekStartDay` SHALL NOT write the value directly; it SHALL hold the candidate in transient view state and present a confirmation alert (title `settings.weekStart.alert.title`, confirm `settings.weekStart.alert.confirm`, cancel `settings.weekStart.alert.cancel`, message `settings.weekStart.alert.message` interpolating the candidate weekday name and warning that the change re-aligns existing weekly budgets and recalculates past weeks). Selecting the already-current weekday SHALL be a no-op (no alert, no write). Cancelling, or dismissing the alert by any other means, SHALL discard the candidate with no write.

#### Scenario: Selecting a different weekday presents the confirmation

- **WHEN** the current week-start is Sunday and the user taps the Monday row
- **THEN** the system holds Monday as a pending candidate and presents the cascade-warning confirmation alert; `AppSettings.weekStartDay` is not yet changed

#### Scenario: Selecting the current weekday is a no-op

- **WHEN** the current week-start is Sunday and the user taps the Sunday row
- **THEN** no alert is presented and no write occurs

#### Scenario: Cancelling discards the candidate

- **WHEN** the confirmation alert is presented and the user taps Cancel (or dismisses it)
- **THEN** `AppSettings.weekStartDay` is unchanged and the checkmark remains on the original weekday

---

### Requirement: Confirming writes the global setting and fires analytics

Activating the alert's confirm ("Change") button SHALL set `AppSettings.weekStartDay` to the pending candidate (persisted and synced per the `app-settings` capability) and SHALL fire the existing `setting_changed` analytics event with `setting_name = "week_start_day"`, `new_value` = the chosen `Weekday.analyticsValue`, and `old_value` = the prior `Weekday.analyticsValue`. The screen SHALL NOT introduce a new analytics event for this flow.

#### Scenario: Confirm writes weekStartDay and fires setting_changed

- **WHEN** the user confirms a change from Sunday to Monday
- **THEN** `AppSettings.weekStartDay` becomes `.monday`, and one `setting_changed` event fires with `setting_name = "week_start_day"`, `new_value` for Monday, and `old_value` for Sunday

#### Scenario: Confirm updates the selection indicator

- **WHEN** the user confirms a change to Monday
- **THEN** the Monday row shows the checkmark and the previously-selected row no longer does

---

### Requirement: Accessibility for the Start of Week screen

Every weekday row SHALL expose its localized weekday name to VoiceOver and convey its selected state (the current week-start row reads as selected). The scope-banner symbol SHALL be `.accessibilityHidden(true)` so only the banner text is announced. The screen SHALL remain usable at `.xxxLarge` Dynamic Type (the banner symbol scales with its text and the rows wrap rather than clip).

#### Scenario: Selected row conveys selected state

- **WHEN** VoiceOver focuses the current week-start row
- **THEN** it announces the weekday name and that the row is selected

#### Scenario: Banner icon is decorative

- **WHEN** VoiceOver traverses the scope banner
- **THEN** the `exclamationmark.triangle.fill` symbol is skipped and only the banner text is announced

---

### Requirement: Start of Week screen strings are registered in Localizable.xcstrings

The new user-visible keys `weekStartPicker.navTitle` and `weekStartPicker.scopeNote` SHALL be registered in `Localizable.xcstrings` with translator-friendly comments, and SHALL be translated to all 49 storefront locales via the `translate-new-strings` pipeline. The screen SHALL reuse the existing `settings.weekStart.alert.*` keys rather than introducing duplicates.

#### Scenario: New keys present with comments

- **WHEN** the catalog is inspected
- **THEN** `weekStartPicker.navTitle` and `weekStartPicker.scopeNote` exist, each with a comment, and no duplicate of the `settings.weekStart.alert.*` keys is introduced

#### Scenario: No hard-coded English literals

- **WHEN** `WeekStartPickerScreen` is inspected
- **THEN** every visible label resolves through `String(localized:)` / `Text(...)`, with no hard-coded English literal

