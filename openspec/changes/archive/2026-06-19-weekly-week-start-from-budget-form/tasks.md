## 1. UI & copy — already committed on this branch (do NOT change without checking with Jimmy)

- [x] 1.1 Weekly note + "Change start of week" link in the Period card (`AddEditBudgetView.swift`)
- [x] 1.2 `WeekStartPickerScreen.swift`: weekday list, app-wide scope banner, reused `WeekStartConfirmation` + `settings.weekStart.alert.*`, `setting_changed` analytics
- [x] 1.3 `AddEditBudgetViewModel.realignWeeklyStartDate(to:)` + `.onChange(of: settings.weekStartDay)` wiring in the form
- [x] 1.4 Preview "Add — Weekly (note + link)" added adjacent to the biweekly variant
- [x] 1.5 Treat layout and en source copy as frozen; if any spec/test work seems to require a copy or layout change, stop and confirm with Jimmy first (no copy/layout changes made)

## 2. Accessibility (PRD §6.8.1)

- [x] 2.1 Weekday rows: expose the localized weekday name as the VoiceOver label and convey selected state via `.isSelected` trait on the current week-start row
- [x] 2.2 Scope banner: `exclamationmark.triangle.fill` symbol is `.accessibilityHidden(true)`; only the banner text is announced
- [x] 2.3 Weekly note link: accessibility hint added ("Opens the app-wide start-of-week setting") + stable identifier
- [x] 2.4 `.xxxLarge` Dynamic Type preview added for `WeekStartPickerScreen`; banner symbol scales with its text (matched font + first-baseline alignment), rows/note use semantic styles and wrap (live device check delegated per the localization+VoiceOver audit)

## 3. Localization / translations (PRD §6.8.3)

- [x] 3.1 Registered five new keys via `add_keys.py` (build's Xcode extraction not used on CLI): `addEditBudget.note.weekly`, `addEditBudget.note.weekly.changeLink`, `addEditBudget.note.weekly.changeLink.accessibilityHint`, `weekStartPicker.navTitle`, `weekStartPicker.scopeNote`
- [x] 3.2 Ran the `translate-new-strings` pipeline (49 locales); `check_translations.py` reports all 263 strings fully translated, `check_source_strings.py` clean
- [x] 3.3 `validate.py --subset` confirmed `%@` preserved in every locale (caught + fixed one mr false-positive that had added a stray `%@` to the no-specifier changeLink key)

## 4. Analytics (PRD §6.8.4)

- [x] 4.1 Confirmed: `WeekStartPickerScreen` confirm path fires `setting_changed` with `setting_name = "week_start_day"` and `old_value`/`new_value` from `Weekday.analyticsValue`; reuses the existing event, no new event introduced

## 5. UI-test screen objects (PRD §6.8.5)

- [x] 5.1 Added `WeekStartScreen` screen object (weekday rows by identifier, scope banner, cascade confirm/cancel alert, `selectAndConfirm`)
- [x] 5.2 Updated `AddBudgetScreen` with `weeklyNote`, `changeStartOfWeekLink`, and `tapChangeStartOfWeek()`
- [x] 5.3 Added `testWeeklyPeriodNoteOpensStartOfWeekPicker` journey: select Weekly → note appears → tap link → Start of Week screen (banner + rows) → Back → note persists (locale-independent; does not mutate the global setting — confirm gating is unit-tested)
- [x] 5.4 UI suite passed via `make test` (runs the UI tests too); `testWeeklyPeriodNoteOpensStartOfWeekPicker` passed first try, no journey regressions (two unrelated expense journeys flaked once and recovered on retry)

## 6. Automated unit tests

- [x] 6.1 `realignWeeklyStartDate_addWeekly_reanchorsToNewWeekStart`
- [x] 6.2 `realignWeeklyStartDate_inEditMode_isNoOp`
- [x] 6.3 `realignWeeklyStartDate_nonWeeklyPeriod_isNoOp`
- [x] 6.4 No selection/confirmation logic is unique to `WeekStartPickerScreen` — it reuses `WeekStartConfirmation` (already unit-tested); no additional coverage required

## 7. Docs alignment

- [x] 7.1 Updated `docs/product-features-planning.md` F-5.01: Status + new "Entry points" acceptance bullet documenting the second (in-form) entry point, reaffirming global scope
- [x] 7.2 Updated F-2.03 Weekly/biweekly pre-population bullet to note the Add-mode weekly `startDate` re-anchor on a mid-create week-start change
- [x] 7.3 No change needed: `docs/tech-design-doc.md` §2.1 lists illustrative View/ViewModel examples (it omits peer simple screens like `SettingsView`), not an exhaustive screen inventory

## 8. Gate, validate, and finalize

- [x] 8.1 Four-step gate green: `make format` → `make lint-fix` → `make build` → `make test` (** TEST SUCCEEDED **)
- [x] 8.2 `openspec validate weekly-week-start-from-budget-form` passes
- [x] 8.3 Gap-fill committed separately from the finalized UI commit (`504931f`). `/opsx:verify` + archive are the remaining user-driven steps.
