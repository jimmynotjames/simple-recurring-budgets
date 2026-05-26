## MODIFIED Requirements

### Requirement: Form fields are Name, Allocation, Currency, Period, and Carry-Over toggle

The Add/Edit Budget screen SHALL collect the following user-editable fields, organised into cards. The number of cards depends on the selected `Period`:

- For recurring periods (`.daily`, `.weekly`, `.biweekly`, `.monthly`): four cards — Name, Allocation, Period, Carry-Over.
- For `.specificDates`: four cards — Name, Allocation, Period (with the blurb described in the "Specific Dates conditional UI" requirement immediately below the chip), Dates. The Carry-Over card SHALL be hidden.

Reset Cadence SHALL NOT appear on this screen (per `docs/main-prd.md` §6.7 PAUSED callout; Reset Cadence is permanently removed by the budget-calculations rewrite).

The fields are:

- **Name** (`String`) — bound to a single-line `TextField` in the Name card. Placeholder `"Budget"` (key `addEditBudget.field.name.placeholder`). Accessibility label `"Budget name"` (key `addEditBudget.field.name.accessibilityLabel`). In Add mode only, the field SHALL receive keyboard focus automatically when the sheet appears (via `@FocusState` + `.onAppear`); in Edit mode no automatic focus is set.
- **Allocation** (`Decimal?` in `AddEditBudgetViewModel`) — entered via a **`DecimalInputField`** — a `UITextField`-backed `UIViewRepresentable` — rather than SwiftUI's `TextField(value:format:)` (which rejects keystrokes whenever parsing throws, breaking RTL / non-Western-digit entry) or `TextField(text:)` + `.onChange` (which on iOS 17+ fails to render typed text until the field resigns first responder). The field is **seeded** from the draft `Decimal?` via `OptionalDecimalFormatStyle.editableText(_:)` at the budget currency's minor-unit precision (e.g. 0 for JPY, 2 for USD, 3 for BHD/KWD; no grouping separators), and an empty field maps to `nil` (blank default in Add mode). Each edit is parsed back to `Decimal?` via the style's **locale-aware `parseStrategy`**, which accepts whatever numbering system the locale's keyboard emits (Western, Arabic-Indic, Devanagari, …). Entry is **capped live** to the currency's minor-unit count by the field's delegate: 0-decimal currencies (JPY, KRW, …) reject the decimal separator entirely (no fractional entry), and other currencies accept at most that many fraction digits. Placeholder `"0"`. Keyboard type SHALL be `.decimalPad`. A currency symbol/code SHALL be displayed adjacent to the field in the same `HStack`, on the **locale-correct side** (leading or trailing). The decoration is derived from `settings.currencyDisplay.affixes(for: viewModel.currencyCode)`, which returns `(leading, trailing)` strings whose placement and spacing follow the same currency `FormatStyle` used by `Decimal.formatted(currencyCode:display:locale:)` — e.g. leading `"$"` for USD in en_US, trailing `" €"` for EUR in fr_FR — and mirror correctly in RTL. The decoration `Text`(s) SHALL be `accessibilityHidden`, because the field's accessibility label already announces the full formatted amount. The decoration SHALL update reactively whenever `settings.currencyDisplay` or `viewModel.currencyCode` changes. Accessibility label SHALL announce the formatted amount with the budget's currency code (key `addEditBudget.field.allocation.accessibilityLabel`). For VoiceOver, when `allocation` is `nil`, the formatted monetary argument SHALL treat the amount as `0` for the purposes of `Decimal.formatted(currencyCode:display:locale:)` only inside the localized label string; the backing draft value remains `nil`. The formatted amount SHALL be produced by the canonical `Decimal.formatted(currencyCode:display:locale:)` method with `display: settings.currencyDisplay`. The view SHALL read `AppSettings` via `@Environment(AppSettings.self)` and recompute the label whenever `settings.currencyDisplay`, `viewModel.allocation`, or `viewModel.currencyCode` changes.
- **Currency** (`String`, ISO-4217 code) — selected via a currency pill button on the Allocation card; the pill displays the current code with a `chevron.up.chevron.down` SF Symbol and opens the currency picker on activation. Accessibility label `"Currency, <code>"` (key `addEditBudget.field.currency.accessibilityLabel`); accessibility hint `"Opens currency picker"` (key `addEditBudget.field.currency.accessibilityHint`). The view SHALL capture the budget's `currencyCode` at sheet-open time into a private `initialCurrencyCode` view-state value (via `.onAppear`). When `viewModel.currencyCode` differs from `initialCurrencyCode`, the Allocation card SHALL render an inline caption beneath the amount/pill row showing the localized text `"Changing currency only updates the label. I.e. No currency conversion."` (key `addEditBudget.note.currencyLabelOnly`). The caption SHALL be styled `.font(.caption)` and `.foregroundStyle(.secondary)`, and SHALL transition in via `.opacity.combined(with: .move(edge: .top))` animated by `.easeInOut(duration: 0.2)` keyed to `viewModel.currencyCode`. When `viewModel.currencyCode` first diverges from `initialCurrencyCode`, the view SHALL post an `AccessibilityNotification.Announcement` containing the same localized text so VoiceOver users hear the disclaimer without needing to navigate to the caption.
- **Period** (`BudgetPeriod`) — selected from a chip group in the Period card. The four recurring cases (`.daily`, `.weekly`, `.biweekly`, `.monthly`) SHALL render in a 2×2 `LazyVGrid`. The `.specificDates` case SHALL render as a separate full-width chip directly below the grid (visually distinguishing the non-recurring case). The selected chip SHALL render with the accent colour fill and white foreground, with `.fontWeight(.semibold)`; unselected chips SHALL render with a low-opacity secondary background and primary foreground, with `.fontWeight(.regular)`. Each chip SHALL declare `.accessibilityAddTraits(.isSelected)` when it is the active selection. Each chip SHALL provide a per-period accessibility label (key `addEditBudget.chip.period.accessibilityLabel`, e.g. `"Daily period"`, `"Specific Dates period"`).

  In **Add mode**, every chip SHALL be a tappable `Button`; tapping a chip SHALL set `viewModel.period` to that case (animated by `.easeInOut(duration: 0.15)`). In **Edit mode**, chips SHALL be rendered as static `Text`-based labels (NOT `Button`s); tapping a chip SHALL have no effect. In Edit mode, non-selected chips SHALL render with a more subdued background (`Color.secondary.opacity(0.06)`) and a dimmed foreground (`Color.primary.opacity(0.3)`); the selected chip retains the accent fill and white foreground. In Edit mode, every chip SHALL declare an additional accessibility hint with the localized text `"Locked. Period can't be changed after creating your budget."` (key `addEditBudget.chip.period.locked.accessibilityHint`); in Add mode no such hint is applied.

  In Edit mode, the Period card SHALL render a `Label` directly below the chip grid (below the `.specificDates` chip when applicable) using `systemImage: "lock.fill"` and the localized text `"This can't be changed after creating your budget."` (key `addEditBudget.note.periodLocked`), styled `.font(.caption)` and `.foregroundStyle(.secondary)`. The caption SHALL NOT render in Add mode.
- **Carry-Over** (`Bool`) — a `Toggle` in the Carry-Over card titled `"Carry-Over"` (key `addEditBudget.section.carryOver`). The toggle SHALL be tinted with the accent colour. A short caption (key `addEditBudget.note.carryOver`) SHALL render below the toggle in both on and off states (per `docs/main-prd.md` §6.7: the underlying carry-over figure is maintained internally even when display is off, so the caption remains accurate either way). The Carry-Over card SHALL NOT render when `viewModel.period == .specificDates` (see F-2.08 and the "Specific Dates conditional UI" requirement).
- **Start Date** (`Date?` in `AddEditBudgetViewModel`) and **End Date** (`Date?`) — bound to the two `DateColumn` buttons in the Dates card; surfaced only when `viewModel.period == .specificDates` (see the "Specific Dates conditional UI" requirement for full details).

#### Scenario: All cards render for a recurring period

- **WHEN** the sheet is visible in either Add or Edit mode and `viewModel.period` is one of `.daily`, `.weekly`, `.biweekly`, `.monthly`
- **THEN** the screen displays four cards in this order: Name, Allocation, Period, Carry-Over; the Allocation card contains both the amount field and the currency pill; the Period card contains the 2×2 chip grid and the `.specificDates` chip below; the Carry-Over card contains the toggle and the caption

#### Scenario: All cards render for Specific Dates

- **WHEN** the sheet is visible in either Add or Edit mode and `viewModel.period == .specificDates`
- **THEN** the screen displays four cards in this order: Name, Allocation, Period (with the explanatory blurb directly below the `.specificDates` chip), Dates (with two `DateColumn` buttons side-by-side); the Carry-Over card SHALL NOT render

#### Scenario: Reset Cadence is not surfaced

- **WHEN** the sheet is visible in either Add or Edit mode
- **THEN** there is no UI that lets the user view, select, or change a Reset Cadence

#### Scenario: Name field auto-focuses in Add mode

- **WHEN** the sheet opens in Add mode
- **THEN** the Name `TextField` receives keyboard focus immediately (the software keyboard appears), so the user can start typing a name without tapping the field first

#### Scenario: Name field does not auto-focus in Edit mode

- **WHEN** the sheet opens in Edit mode for an existing `Budget`
- **THEN** no field receives automatic focus; the user must tap to edit

#### Scenario: Allocation card shows currency decoration on the locale-correct side

- **WHEN** `settings.currencyDisplay == .symbol`, the budget's currency is `"USD"`, and the locale is `en_US`
- **THEN** the Allocation card displays `"$"` as a **leading** decoration before the numeric field, and no trailing decoration

- **WHEN** `settings.currencyDisplay == .symbol`, the budget's currency is `"EUR"`, and the locale is `fr_FR`
- **THEN** the Allocation card displays the `"€"` symbol as a **trailing** decoration after the numeric field, and no leading decoration (mirroring how `Decimal.formatted(currencyCode:display:locale:)` renders the amount)

- **WHEN** `settings.currencyDisplay == .code` and the budget's currency is `"USD"`
- **THEN** the Allocation card displays `"USD"` as a leading decoration

- **WHEN** `settings.currencyDisplay == .codeAndSymbol` and the budget's currency is `"USD"`
- **THEN** the Allocation card displays `"USD $"` as a leading decoration

#### Scenario: Currency decoration updates live when settings change

- **WHEN** the user changes `AppSettings.currencyDisplay` while the sheet is open
- **THEN** the decoration around the Allocation field updates immediately to reflect the new preference without dismissing or reloading the sheet

#### Scenario: Allocation fraction precision follows the budget currency

- **WHEN** the budget's currency is a 3-decimal currency (e.g. `"BHD"`) and an existing allocation of `1.234` is shown
- **THEN** the field displays all three fraction digits (`1.234`), not a value truncated to two places

- **WHEN** the budget's currency is a 0-decimal currency (e.g. `"JPY"`)
- **THEN** the field renders the amount with no fraction digits

#### Scenario: Allocation field parses optional Decimal with locale-aware parsing

- **WHEN** the user clears the Allocation `TextField` or leaves it empty in Add mode
- **THEN** the draft value is `nil` (blank), not `0`

- **WHEN** the user enters a number in the Allocation `TextField`
- **THEN** the parse strategy reads the text using a locale-aware `Decimal.FormatStyle`, so locale-appropriate decimal/grouping separators apply; successful parse yields `Decimal`; the underlying VM state remains `Decimal?` (entered value or `nil` when empty)

#### Scenario: Allocation field accepts non-Western numerals

- **WHEN** the locale's `.decimalPad` emits non-Western digits (e.g. Arabic-Indic `٠١٢٣…` in `ar_EG`/`ar_SA`, Extended Arabic-Indic in `fa_IR`, or Devanagari in `ne_NP`) and the user taps digits into the Allocation field
- **THEN** the digits SHALL be accepted and parsed to the corresponding `Decimal` (the field SHALL NOT reject the keystrokes), because parsing routes through the locale-aware `Decimal.FormatStyle` rather than `Decimal(string:locale:)`

#### Scenario: Allocation accessibility label respects AppSettings.currencyDisplay

- **WHEN** the user changes `AppSettings.currencyDisplay` (e.g. from `.symbol` to `.code`) while the Add/Edit Budget sheet is open
- **THEN** the Allocation field's VoiceOver label SHALL re-render so its formatted-amount component reflects the new preference (e.g. `"USD 25.00"` for `.code` instead of `"$25.00"` for `.symbol` when the budget's `currencyCode` is `"USD"`); the announcement SHALL be produced by `Decimal.formatted(currencyCode: viewModel.currencyCode, display: settings.currencyDisplay)` and not by any other formatter

#### Scenario: Period chip selection is exclusive and announced to VoiceOver

- **WHEN** the user taps a period chip in Add mode (any of the recurring four or `.specificDates`)
- **THEN** that period becomes the selected one; the previously-selected chip drops its `isSelected` accessibility trait; the new chip gains the `isSelected` trait; only one chip carries the trait at any time

#### Scenario: Period chips are non-interactive in Edit mode

- **WHEN** the sheet is presented in Edit mode and the user taps any period chip (selected or not)
- **THEN** `viewModel.period` does NOT change, no visual feedback is shown, and no underlying `Budget` mutation occurs; the previously-selected chip retains the `isSelected` accessibility trait and no other chip gains it

#### Scenario: Locked period chips carry a VoiceOver hint

- **WHEN** the sheet is presented in Edit mode and VoiceOver focus moves to any period chip
- **THEN** VoiceOver announces the chip's per-period label followed by the localized hint sourced from `addEditBudget.chip.period.locked.accessibilityHint` ("Locked. Period can't be changed after creating your budget.")

#### Scenario: Period card shows a lock caption in Edit mode

- **WHEN** the sheet is presented in Edit mode
- **THEN** the Period card renders a `Label` below the chip grid with `systemImage: "lock.fill"` and the localized text from `addEditBudget.note.periodLocked` ("This can't be changed after creating your budget.")

#### Scenario: Period card does not show a lock caption in Add mode

- **WHEN** the sheet is presented in Add mode
- **THEN** the Period card renders only the chips (and, when `.specificDates` is selected, the explanatory blurb); no lock caption is rendered

#### Scenario: Currency-change inline caption appears when draft currency diverges from initial

- **WHEN** the sheet is presented in either Add or Edit mode, the user opens the currency picker, and selects a code different from the budget's currency at sheet-open time
- **THEN** an inline caption with the localized text from `addEditBudget.note.currencyLabelOnly` ("Changing currency only updates the label. I.e. No currency conversion.") SHALL render below the amount/pill row in the Allocation card

#### Scenario: Currency-change inline caption hides when draft returns to initial

- **WHEN** the user has changed the currency away from the initial value, then opens the picker again and re-selects the original currency
- **THEN** the inline currency-change caption SHALL no longer render

#### Scenario: Currency-change disclaimer is announced to VoiceOver on first divergence

- **WHEN** in either mode the user changes the currency away from the value at sheet-open time for the first time during this presentation of the sheet
- **THEN** the system SHALL post an `AccessibilityNotification.Announcement` carrying the localized `addEditBudget.note.currencyLabelOnly` text so VoiceOver users hear the disclaimer
