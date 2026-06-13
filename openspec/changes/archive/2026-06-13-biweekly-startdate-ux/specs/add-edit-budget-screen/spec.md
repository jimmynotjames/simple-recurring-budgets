## ADDED Requirements

### Requirement: Biweekly explanatory note in the Period card

When and only when `viewModel.period == .biweekly`, the Period card SHALL render a caption directly below the chip grid (and below the `.specificDates` chip slot) with the localized text `"Repeating 14-day period. Choose your start date below to choose which day each cycle begins on."` (key `addEditBudget.note.biweekly`), styled `.font(.caption)` and `.foregroundStyle(.readableSecondary)`, transitioning in via `.opacity.combined(with: .move(edge: .top))`. The note SHALL render in **both Add and Edit modes** (it is not gated on edit state), because the start date is editable in both. The note SHALL NOT render for any other period type.

This note coexists with the Specific Dates blurb and the Edit-mode period-lock caption; they are mutually exclusive by period/mode and never render together for the same period.

#### Scenario: Biweekly note shows when Biweekly is selected in Add mode

- **WHEN** the user opens Add and selects the Biweekly period chip
- **THEN** a `.caption` note reading "Repeating 14-day period. Choose your start date below to choose which day each cycle begins on." renders below the period chip grid

#### Scenario: Biweekly note shows in Edit mode for a biweekly budget

- **WHEN** the user opens Edit for a `.biweekly` budget
- **THEN** the biweekly note renders below the (locked) period chip grid, alongside the period-lock caption

#### Scenario: Biweekly note is absent for non-biweekly periods

- **WHEN** `viewModel.period` is `.daily`, `.weekly`, `.monthly`, or `.specificDates`
- **THEN** the biweekly note (`addEditBudget.note.biweekly`) does not render

### Requirement: Save-time biweekly re-anchor confirmation

Editing a biweekly budget's `startDate` re-anchors its 14-day cycle grid and recomputes every past period (and the carry-over figure), because biweekly is the only recurring period whose grid is anchored to the budget's own `startDate`. To make that consequence explicit, when the user activates the Save toolbar button in **Edit mode** on a `.biweekly` budget AND the drafted `viewModel.startDate` (normalized via `calendar.startOfDay`) differs from the persisted `Budget.startDate`, the system SHALL present a confirmation alert before invoking `viewModel.save(...)`. The user SHALL be able to cancel (returning to the form with all draft state intact) or confirm (proceeding to the existing save path unchanged).

The gate SHALL be exposed on `AddEditBudgetViewModel` as a computed property `var isBiweeklyStartDateEdited: Bool` that returns `false` in Add mode, `false` when `period != .biweekly`, `false` when `startDate == nil`, and otherwise returns `true` iff `calendar.startOfDay(for: startDate)` differs from the bound `Budget.startDate`.

The alert's title SHALL use key `addEditBudget.biweeklyReanchor.title` (en-US source: `"Change Start Date?"`). The cancel button SHALL use key `addEditBudget.biweeklyReanchor.cancel` (en-US source: `"Cancel"`, `role: .cancel`). The confirm button SHALL use key `addEditBudget.biweeklyReanchor.confirm` (en-US source: `"Change"`) and SHALL invoke the same `viewModel.save(...)` + `dismiss()` sequence the bare Save toolbar button invokes today.

The alert's message SHALL be the localized string for key `addEditBudget.biweeklyReanchor.message` (en-US source: `"This will re-align current and future two-week cycles and recalculate past periods."`). When the same edit ALSO strands logged expenses (`viewModel.orphanedExpenseCount > 0`), the orphan sentence (`addEditBudget.orphanWarning.message`) SHALL be appended to the message, space-separated, so both consequences land in one alert and the warnings never stack.

**Save-gate precedence.** The Save toolbar action SHALL evaluate, in order: (1) if `isBiweeklyStartDateEdited` set `showBiweeklyReanchorWarning = true`; (2) else if `orphanedExpenseCount > 0` set `showOrphanWarning = true`; (3) else invoke save directly. This makes the re-anchor confirmation supersede the standalone orphan warning for biweekly start-date edits (which is why the orphan message folds into it).

The alert SHALL NOT fire in Add mode, SHALL NOT fire for non-biweekly periods, and SHALL NOT fire when the drafted start date equals the persisted value. The alert SHALL NOT alter any save side effect; the existing `viewModel.save(context:analytics:settings:router:)` + `dismiss()` SHALL fire from the confirm branch exactly as from a bare Save tap.

#### Scenario: Editing a biweekly start date presents the re-anchor alert on Save

- **WHEN** the user opens Edit for a `.biweekly` budget, changes `startDate` to a different day via the Schedule disclosure, and taps Save
- **THEN** an alert titled "Change Start Date?" is presented with message "This will re-align current and future two-week cycles and recalculate past periods." and buttons `Cancel` and `Change`; `viewModel.save(...)` has not yet been invoked

#### Scenario: Confirming the re-anchor alert commits the save

- **WHEN** the re-anchor alert is presented and the user taps `Change`
- **THEN** `viewModel.save(context:analytics:settings:router:)` fires, the sheet dismisses, and `Budget.startDate` holds the new value

#### Scenario: Cancelling the re-anchor alert preserves draft state

- **WHEN** the re-anchor alert is presented and the user taps `Cancel`
- **THEN** the alert dismisses, the sheet remains presented with the drafted `startDate` intact, no save is performed, and the persisted `Budget.startDate` is unchanged

#### Scenario: Re-anchor alert folds in the orphan sentence when expenses are stranded

- **WHEN** the user opens Edit for a `.biweekly` budget with expenses dated before the new start, moves `startDate` forward past them, and taps Save
- **THEN** a single "Change Start Date?" alert is presented whose message is the re-align sentence followed by "Those expenses still show in your list but won't be counted by this budget."; no separate orphan-warning alert is shown

#### Scenario: Re-anchor alert does not fire when the start date is unchanged

- **WHEN** the user opens Edit for a `.biweekly` budget, edits only the name, and taps Save
- **THEN** `isBiweeklyStartDateEdited == false`, no re-anchor alert is presented, and the save proceeds (subject to the orphan-warning gate, which is also inert here)

#### Scenario: Re-anchor alert is biweekly- and edit-only

- **WHEN** the budget is `.daily`, `.weekly`, `.monthly`, or `.specificDates`, OR the sheet is in Add mode
- **THEN** `isBiweeklyStartDateEdited == false` and the re-anchor alert never fires (a non-biweekly start-date change still routes to the standalone orphan warning when applicable)

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

  In **Add mode**, every chip SHALL be a tappable `Button`; tapping a chip SHALL set `viewModel.period` to that case (animated by `.easeInOut(duration: 0.15)`). In **Edit mode**, chips SHALL be rendered as static `Text`-based labels (NOT `Button`s); tapping a chip SHALL have no effect. In Edit mode, non-selected chips SHALL render with a more subdued background (`Color.secondary.opacity(0.06)`) and a dimmed foreground (`Color.primary.opacity(0.3)`); the selected chip retains the accent fill and white foreground. In Edit mode, every chip SHALL declare an additional accessibility hint with the localized text `"Locked. Period type can't be changed after creating your budget."` (key `addEditBudget.chip.period.locked.accessibilityHint`); in Add mode no such hint is applied.

  In Edit mode, the Period card SHALL render a `Label` directly below the chip grid (below the `.specificDates` chip when applicable) using `systemImage: "lock.fill"` and the localized text `"Period type can't be changed after creating your budget."` (key `addEditBudget.note.periodLocked`), styled `.font(.caption)` and `.foregroundStyle(.secondary)`. The caption SHALL NOT render in Add mode. The wording names the *period type* specifically because the start/end dates remain editable in Edit mode for every period type — only the period type is immutable post-creation.
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
- **THEN** the field renders the amount with no fraction digits, AND tapping the decimal-separator key during entry has no effect (fractional input is not possible)

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
- **THEN** VoiceOver announces the chip's per-period label followed by the localized hint sourced from `addEditBudget.chip.period.locked.accessibilityHint` ("Locked. Period type can't be changed after creating your budget.")

#### Scenario: Period card shows a lock caption in Edit mode

- **WHEN** the sheet is presented in Edit mode
- **THEN** the Period card renders a `Label` below the chip grid with `systemImage: "lock.fill"` and the localized text from `addEditBudget.note.periodLocked` ("Period type can't be changed after creating your budget.")

#### Scenario: Period card does not show a lock caption in Add mode

- **WHEN** the sheet is presented in Add mode
- **THEN** the Period card renders only the chips (and, when `.specificDates` is selected, the explanatory blurb; when `.biweekly` is selected, the biweekly note); no lock caption is rendered

#### Scenario: Currency-change inline caption appears when draft currency diverges from initial

- **WHEN** the sheet is presented in either Add or Edit mode, the user opens the currency picker, and selects a code different from the budget's currency at sheet-open time
- **THEN** an inline caption with the localized text from `addEditBudget.note.currencyLabelOnly` ("Changing currency only updates the label. I.e. No currency conversion.") SHALL render below the amount/pill row in the Allocation card

#### Scenario: Currency-change inline caption hides when draft returns to initial

- **WHEN** the user has changed the currency away from the initial value, then opens the picker again and re-selects the original currency
- **THEN** the inline currency-change caption SHALL no longer render

#### Scenario: Currency-change disclaimer is announced to VoiceOver on first divergence

- **WHEN** in either mode the user changes the currency away from the value at sheet-open time for the first time during this presentation of the sheet
- **THEN** the system SHALL post an `AccessibilityNotification.Announcement` carrying the localized `addEditBudget.note.currencyLabelOnly` text so VoiceOver users hear the disclaimer

### Requirement: Orphan-expense warning on Save when startDate moves past existing expenses

When the user activates the Save toolbar button in Edit mode on a recurring-period budget AND the drafted `viewModel.startDate` (normalized via `calendar.startOfDay`) is **after** the `date` of at least one item in `Budget.expenseItems`, the system SHALL present a confirmation alert before invoking `viewModel.save(...)`. The user SHALL be able to either cancel (returning to the form with all draft state intact) or confirm (proceeding to the existing save path unchanged).

The alert's title SHALL be the localized string for key `addEditBudget.orphanWarning.title` (en-US source: `"Start date is after \(count) logged expenses"`, where `count` is the number of items in `Budget.expenseItems` whose `date` is before the drafted `startDate`). The alert's message SHALL be the localized string for key `addEditBudget.orphanWarning.message` (en-US source: `"Those expenses still show in your list but won't be counted by this budget."`). The cancel button SHALL use key `addEditBudget.orphanWarning.cancel` (en-US source: `"Cancel"`, `role: .cancel`). The confirm button SHALL use key `addEditBudget.orphanWarning.confirm` (en-US source: `"Save Changes"`) and SHALL invoke the same `viewModel.save(...)` + `dismiss()` sequence the bare Save toolbar button invokes today.

The count SHALL be exposed on `AddEditBudgetViewModel` as a computed property `var orphanedExpenseCount: Int` that returns `0` in Add mode (no bound budget) and when `startDate == nil`, and otherwise returns `budget.expenseItems.count(where: { $0.date < startDate })` (equivalent to `filter { ... }.count`; the predicate is the contract).

**Save-gate precedence.** The view SHALL gate the Save toolbar button's action in this order: (1) if `viewModel.isBiweeklyStartDateEdited` it SHALL present the biweekly re-anchor confirmation (`showBiweeklyReanchorWarning = true`) — that alert subsumes this orphan message when `orphanedExpenseCount > 0` (see "Save-time biweekly re-anchor confirmation"); (2) else if `orphanedExpenseCount > 0` it SHALL set `@State var showOrphanWarning = true`; (3) else it SHALL invoke save directly. Consequently the standalone orphan alert described here fires for non-biweekly periods (and for `.specificDates`); for biweekly Edit-mode start-date changes the re-anchor confirmation is the surface, with the orphan sentence folded in.

The alert SHALL NOT replace or duplicate any existing save-side-effect behavior — the existing `viewModel.save(context:analytics:settings:router:)` method, its persistence logic, and the `dismiss()` call SHALL fire from the confirm branch exactly as they fire today from a bare Save tap.

The alert SHALL NOT fire in Add mode (where `orphanedExpenseCount` is always `0`).

The standalone alert SHALL fire across every period type except biweekly Edit-mode start-date changes — including `.specificDates` — wherever an Edit-mode `startDate` change orphans at least one existing expense and the biweekly re-anchor gate does not take precedence. (The inline Schedule-disclosure warning is recurring-only, because Specific Dates uses the Dates card rather than the Schedule disclosure; the Save-time alert is the cross-period surface.)

#### Scenario: Save with no orphaned expenses commits immediately

- **WHEN** the user opens Edit for a `.weekly` budget, edits the name only, and taps Save
- **THEN** `viewModel.orphanedExpenseCount == 0`, no alert is presented, `viewModel.save(...)` fires, and the sheet dismisses — identical to today's behavior

#### Scenario: Save with orphaned expenses presents the alert

- **WHEN** the user opens Edit for a `.weekly` budget that has expenses dated `Apr 15` and `Apr 8`, moves `startDate` to `Apr 20` via the Schedule disclosure, and taps Save
- **THEN** an alert is presented with title `"Start date is after 2 logged expenses"` and message `"Those expenses still show in your list but won't be counted by this budget."`, with buttons `Cancel` and `Save Changes`; `viewModel.save(...)` has **not** yet been invoked

#### Scenario: Confirming the alert commits the save

- **WHEN** the alert is presented and the user taps `Save Changes`
- **THEN** `viewModel.save(context:analytics:settings:router:)` fires, the sheet dismisses, the orphaned expenses remain in `budget.expenseItems` unchanged, and `Budget.startDate` is the new value

#### Scenario: Cancelling the alert returns to the form with draft preserved

- **WHEN** the alert is presented and the user taps `Cancel`
- **THEN** the alert dismisses, the sheet remains presented, all draft state (including the moved `startDate`) is preserved, no save is performed, and `Budget.startDate` in storage is unchanged

#### Scenario: Add mode never presents the orphan warning

- **WHEN** the user opens Add, picks a `startDate` in the past, and taps Save
- **THEN** no orphan-warning alert is presented (a new budget has no `expenseItems`); the save proceeds directly

#### Scenario: Specific Dates budgets also present the orphan warning on Save

- **WHEN** the user opens Edit for a `.specificDates` budget that has expenses dated before the drafted `startDate`, and taps Save
- **THEN** the orphan-warning alert is presented with the count of pre-`startDate` expenses, identical to the recurring-budget flow. (The inline Schedule-disclosure warning does not appear because Specific Dates uses the Dates card, not the Schedule disclosure — see the modified Schedule disclosure requirement below.)

#### Scenario: Biweekly start-date edits route to the re-anchor confirmation instead

- **WHEN** the user opens Edit for a `.biweekly` budget, moves `startDate` forward past existing expenses, and taps Save
- **THEN** the standalone orphan alert is NOT shown; instead the "Change Start Date?" re-anchor alert is presented with the orphan sentence appended to its message (per "Save-time biweekly re-anchor confirmation")

#### Scenario: orphanedExpenseCount is zero when startDate equals the earliest expense date

- **WHEN** the drafted `startDate` is exactly equal to the `date` of the earliest expense (boundary equality, not strictly after)
- **THEN** `orphanedExpenseCount == 0` and no alert is presented (the filter is `$0.date < startDate`, half-open at the start)

### Requirement: Schedule disclosure card for recurring period types

When and only when `viewModel.period` is one of `.daily`, `.weekly`, `.biweekly`, `.monthly` (i.e. NOT `.specificDates`), the Add/Edit Budget screen SHALL render a `Schedule` card in the slot directly below the Period card and above the Carry-Over card. The card SHALL surface the budget's `startDate` and optional `endDate` via a collapsed-by-default disclosure.

The card SHALL be implemented in `simple-recurring-budgets/Views/AddEditBudgetView+Schedule.swift` as an extension on `AddEditBudgetView`, accessed by the main view's body composition (`if isSpecificDates { datesCard } else { scheduleCard; carryOverCard }`). The collapsed/expanded state SHALL be held in `AddEditBudgetView.isScheduleExpanded` (`@State var isScheduleExpanded: Bool = false`, cross-file-extension access).

**Collapsed-disclosure summary row.** The collapsed state SHALL render a single subdued summary line followed by a trailing `chevron.down` (SF Symbol, `.font(.caption)`, `.foregroundStyle(.secondary)`). The chevron SHALL rotate 180 degrees on expansion via `.rotationEffect(.degrees(isScheduleExpanded ? 180 : 0))`, animated with `.easeInOut(duration: 0.2)` keyed to `isScheduleExpanded`. The whole row SHALL be a single tap target (a `Button` with `.buttonStyle(.plain)` and `.contentShape(Rectangle())`).

The summary SHALL be built from two fragments concatenated with `" · "`:

- **Start fragment** — `"Starts {formatted}"` when `viewModel.startDate` is non-`nil` (key `addEditBudget.schedule.summary.start.set`, where `{formatted}` is `viewModel.startDate!.formatted(date: .abbreviated, time: .omitted)`); otherwise `"Starts today"` (key `addEditBudget.schedule.summary.start.today`).
- **End fragment** — `"Ends {formatted}"` when `viewModel.endDate` is non-`nil` (key `addEditBudget.schedule.summary.end.set`); otherwise `"No end date"` (key `addEditBudget.schedule.summary.end.none`).

**Expanded state.** When `isScheduleExpanded == true`, two `DateColumn` chips SHALL render side-by-side inside an `HStack(alignment: .top, spacing: 12)` directly below the disclosure row, separated by 12 pt of vertical padding. The `DateColumn` struct (defined in `AddEditBudgetView+SpecificDates.swift`) SHALL be reused as-is. The start-date chip SHALL bind to `$viewModel.startDate` with `minDate: nil` and placeholder key `addEditBudget.field.date.start.recurring.placeholder` (en-US source: "Today"). The end-date chip SHALL bind to `$viewModel.endDate` with `minDate: viewModel.startDate` and placeholder key `addEditBudget.field.date.end.recurring.placeholder` (en-US source: "No end date").

**Clear-end-date affordance.** When `viewModel.endDate != nil`, a small "Clear end date" button (key `addEditBudget.schedule.action.clearEndDate`, en-US source: "Clear end date") SHALL render below the chip row, right-aligned (`.frame(maxWidth: .infinity, alignment: .trailing)`), styled `.font(.caption).foregroundStyle(.secondary)`. Tapping it SHALL set `viewModel.endDate = nil`. The button SHALL NOT render for `.specificDates` budgets (which use a different card).

**Inline orphan warning.** When `viewModel.orphanedExpenseCount > 0`, a single localized `Text` view SHALL render inside the expanded content (below the Clear-end-date affordance when present), `.frame(maxWidth: .infinity, alignment: .leading)`, styled `.font(.caption).foregroundStyle(.orange)`. The text SHALL use key `addEditBudget.orphanWarning.inline` (en-US source: `"Start date is after \(count) logged expenses. Those expenses still show in your list but won't be counted by this budget."`, where `count` is `viewModel.orphanedExpenseCount`). The warning SHALL NOT render when `orphanedExpenseCount == 0`. The warning SHALL NOT include a leading SF Symbol icon (the orange color carries the warning signal; an icon would indent wrapped text and misalign with the left edge of the date chips above).

**Auto-expand on appear.** The main view's `onAppear` SHALL set `isScheduleExpanded = true` when, at the moment the sheet appears, EITHER `viewModel.orphanedExpenseCount > 0` OR `viewModel.period == .biweekly`. The orphan condition ensures a user re-opening Edit on an already-orphaning budget sees the inline warning without an extra tap; the biweekly condition surfaces the start date because it is the cycle anchor. When neither condition holds, the auto-expand SHALL NOT fire (the collapsed default is preserved for the common case). It SHALL fire after the existing `onAppear` side effects (`initialCurrencyCode` capture, name-field focus seeding).

**Auto-expand on biweekly selection.** In Add mode, when the user taps the `.biweekly` period chip, the chip-tap handler SHALL set `isScheduleExpanded = true` within the same `withAnimation` that updates `viewModel.period`, so the start date is immediately visible. This is auto-expand only: selecting a different period afterward SHALL NOT auto-collapse the disclosure (the user retains manual control once expanded).

**Animation.** Expanded content SHALL appear with `.transition(.opacity.combined(with: .move(edge: .top)))` animated by `.easeInOut(duration: 0.2)` keyed to `isScheduleExpanded`.

**Accessibility.** The disclosure row SHALL declare an `accessibilityLabel` (key `addEditBudget.schedule.disclosure.accessibilityLabel.format`, en-US source: "Schedule. {summary}", where `{summary}` is the resolved summary text) and an `accessibilityHint` (key `addEditBudget.schedule.disclosure.accessibilityHint`, en-US source: "Tap to show or hide the start date and end date controls."). The expanded `DateColumn` chips inherit their existing accessibility wiring from the shared `DateColumn` struct. The inline orphan warning SHALL be a plain `Text` and inherit default VoiceOver behavior.

**Specific Dates fallback.** This requirement applies only to recurring period types. For `.specificDates` the existing always-visible `Dates` card (see "Specific Dates conditional UI") continues to govern. The inline orphan warning SHALL NOT render for `.specificDates` (the Schedule card is not rendered for that period type at all).

#### Scenario: Recurring Add opens with Schedule collapsed

- **WHEN** the user opens Add for a default-period (`.daily`) budget
- **THEN** the Schedule card renders directly below the Period card, the disclosure row reads "Starts {today, abbreviated} · No end date" (the start fragment uses the set form because `startDate` is pre-filled per the "Add mode seeds defaults" requirement), the trailing chevron points down, the chip area is not rendered, and (because Add mode has no `expenseItems` and the period is not biweekly) the auto-expand behavior does not fire

#### Scenario: Selecting Biweekly in Add mode auto-expands the Schedule

- **WHEN** the user opens Add and taps the Biweekly period chip
- **THEN** the Schedule disclosure expands (start/end `DateColumn` chips visible) without an extra tap, and switching to another period afterward leaves it expanded

#### Scenario: Editing a biweekly budget opens the Schedule expanded

- **WHEN** the user opens Edit for a `.biweekly` budget
- **THEN** on `onAppear` the Schedule disclosure is rendered already expanded so the start date (cycle anchor) is visible, regardless of orphan state

#### Scenario: Tapping the disclosure row expands the chip area

- **WHEN** the user taps the Schedule disclosure row in its collapsed state
- **THEN** the chevron rotates 180 degrees, two `DateColumn` chips appear side-by-side with the start-date chip on the leading edge bound to `$viewModel.startDate` and the end-date chip on the trailing edge bound to `$viewModel.endDate` (`minDate: viewModel.startDate`), animated by `.easeInOut(duration: 0.2)` with an opacity-plus-top-move transition

#### Scenario: Clear end date button appears only when endDate is set

- **WHEN** the user expands the Schedule disclosure and `viewModel.endDate == nil`
- **THEN** no "Clear end date" button is rendered

- **WHEN** the user sets an end date via the end-date chip
- **THEN** the "Clear end date" button appears below the chip row, right-aligned, styled `.font(.caption).foregroundStyle(.secondary)`

- **WHEN** the user taps "Clear end date"
- **THEN** `viewModel.endDate` becomes `nil`, the button disappears, and the disclosure summary's end fragment reverts to "No end date"

#### Scenario: Schedule card hidden for Specific Dates

- **WHEN** the user selects the `.specificDates` chip
- **THEN** the Schedule card is not rendered; the always-visible `Dates` card (per the "Specific Dates conditional UI" requirement) renders instead

#### Scenario: Disclosure summary uses 'Starts today' fragment when startDate is nil

- **WHEN** `viewModel.startDate == nil` (a transient state — `onPeriodChange` for `.specificDates` clears it; recurring periods always have a pre-filled `startDate`)
- **THEN** the disclosure summary reads "Starts today · {end fragment}" using `addEditBudget.schedule.summary.start.today`

#### Scenario: Moving startDate past existing expenses shows the inline orphan warning

- **WHEN** the user opens Edit for a `.weekly` budget that has 3 expenses dated within the last 14 days, expands the Schedule disclosure, and moves `startDate` forward past 2 of those expenses
- **THEN** an orange `.caption` `Text` reading `"Start date is after 2 logged expenses. Those expenses still show in your list but won't be counted by this budget."` renders below the Clear-end-date affordance area, left-aligned to the leading edge of the expanded content

#### Scenario: Inline orphan warning hides when startDate is moved back

- **WHEN** the inline orphan warning is showing for a drafted `startDate` and the user moves `startDate` back to a date at or before every expense
- **THEN** `viewModel.orphanedExpenseCount` becomes `0` and the inline warning disappears (no other UI shifts; the Save button does not gate to the alert)

#### Scenario: Re-opening Edit on an already-orphaning budget auto-expands Schedule

- **WHEN** the user opens Edit for a budget whose persisted `Budget.startDate` is after the `date` of at least one item in `Budget.expenseItems` (i.e. a confirmed-orphan save happened in a prior session)
- **THEN** on `onAppear` the Schedule disclosure is rendered already expanded with the inline orphan warning visible, **without** the user tapping the disclosure row

#### Scenario: Re-opening Edit on a non-orphaning, non-biweekly budget preserves the collapsed default

- **WHEN** the user opens Edit for a non-biweekly budget whose persisted `Budget.startDate` is at or before every `expenseItems.date` (or there are no expenses)
- **THEN** on `onAppear` the Schedule disclosure is rendered collapsed (the default behavior); the auto-expand does not fire
