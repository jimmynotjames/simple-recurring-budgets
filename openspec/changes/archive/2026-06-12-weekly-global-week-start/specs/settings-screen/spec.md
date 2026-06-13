# settings-screen delta — weekly-global-week-start

## MODIFIED Requirements

### Requirement: Calendar section — week-start picker with confirmation

The Settings screen SHALL include a "Calendar" section that contains a menu-style `Picker` bound (with confirmation gating) to `AppSettings.weekStartDay`. The picker SHALL list every `Weekday` case (Sunday through Saturday) using locale-aware standalone weekday names from `Calendar.current.standaloneWeekdaySymbols`.

Selecting a different value from the current `AppSettings.weekStartDay` SHALL NOT directly write the value. Instead the system SHALL hold the candidate value in a transient view-local state and present a confirmation alert (localized title, body, and buttons). The alert's body SHALL include the newly-selected weekday name as an interpolated argument.

The alert body and the picker's accessibility hint SHALL accurately reflect the cascade scope per the `budget-math` capability: the change **also affects existing weekly budgets and recalculates their past weeks** onto the new grid. The copy SHALL NOT claim any effect on biweekly budgets (whose 14-day cycle stays anchored to their own start date); it need not mention biweekly explicitly.

The system SHALL commit the candidate value to `AppSettings.weekStartDay` only when the user activates the alert's "Change" (confirmation) button. Activating the alert's "Cancel" (cancel-role) button SHALL discard the candidate value with no write. Dismissing the alert by any other means SHALL also discard the candidate value.

Persistence and sync of `AppSettings.weekStartDay` are governed by the `app-settings` capability and by F-5.01.

#### Scenario: Picking the same value as currently set

- **WHEN** the picker reports a selection equal to the current `AppSettings.weekStartDay`
- **THEN** the system SHALL NOT present the confirmation alert and SHALL NOT write to `AppSettings`.

#### Scenario: Confirming a new week-start

- **WHEN** the user picks a different weekday and taps the "Change" alert button
- **THEN** the system SHALL set `AppSettings.weekStartDay` to the picked value (which persists per the `app-settings` capability) and SHALL clear the candidate state.

#### Scenario: Cancelling a new week-start

- **WHEN** the user picks a different weekday and taps the "Cancel" alert button (or dismisses the alert without confirming)
- **THEN** the system SHALL discard the candidate value, leave `AppSettings.weekStartDay` unchanged, and the picker SHALL display the original (unchanged) weekday on next render.

#### Scenario: Alert copy states the weekly-only cascade

- **WHEN** the confirmation alert is presented for a candidate weekday
- **THEN** the body communicates that all weekly budgets re-align immediately (including their history) and does not claim any effect on biweekly budgets
