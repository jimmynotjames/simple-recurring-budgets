## MODIFIED Requirements

### Requirement: Form fields are Name, Allocation, Currency, Period, and Carry-Over toggle

The Add/Edit Budget screen SHALL collect exactly five user-editable fields, organised into four cards (Name, Allocation, Period, Carry-Over) per `docs/ux-design-brief.md` and the chosen design (`MockupB_CardLayout`). Reset Cadence SHALL NOT appear on this screen while the feature is paused (per `docs/main-prd.md` §6.7 PAUSED callout).

The fields are:

- **Name** (`String`) — bound to a single-line `TextField` in the Name card. Placeholder `"Budget"` (key `addEditBudget.field.name.placeholder`). Accessibility label `"Budget name"` (key `addEditBudget.field.name.accessibilityLabel`). In Add mode only, the field SHALL receive keyboard focus automatically when the sheet appears (via `@FocusState` + `.onAppear`); in Edit mode no automatic focus is set.
- **Allocation** (`Decimal?` in `AddEditBudgetViewModel`) — bound to a `TextField` using `TextField(_:value:format:)` with a **custom `ParseableFormatStyle`** whose `FormatInput` is `Decimal?`, so an empty field maps to `nil` (blank default in Add mode) and entered text parses to a `Decimal` using the user's current `Locale`. Display formatting for non-`nil` values SHALL use `.number.precision(.fractionLength(0...2))` (same precision as before). Placeholder `"0"`. Keyboard type SHALL be `.decimalPad`. A currency prefix `Text` SHALL be displayed to the leading edge of the `TextField` in the same `HStack`; the prefix content is derived from `settings.currencyDisplay`: `.symbol` → the currency symbol from `NumberFormatter` for that ISO code, `.code` → the ISO code string, `.codeAndSymbol` → `"<CODE> <symbol>"`. The prefix SHALL update reactively whenever `settings.currencyDisplay` or `viewModel.currencyCode` changes. Accessibility label SHALL announce the formatted amount with the budget's currency code (key `addEditBudget.field.allocation.accessibilityLabel`). For VoiceOver, when `allocation` is `nil`, the formatted monetary argument SHALL treat the amount as `0` for the purposes of `Decimal.formatted(currencyCode:display:locale:)` only inside the localized label string; the backing draft value remains `nil`. The formatted amount SHALL be produced by the canonical `Decimal.formatted(currencyCode:display:locale:)` method with `display: settings.currencyDisplay`. The view SHALL read `AppSettings` via `@Environment(AppSettings.self)` and recompute the label whenever `settings.currencyDisplay`, `viewModel.allocation`, or `viewModel.currencyCode` changes.
- **Currency** (`String`, ISO-4217 code) — selected via a currency pill button on the Allocation card; the pill displays the current code with a `chevron.up.chevron.down` SF Symbol and opens the currency picker on activation. Accessibility label `"Currency, <code>"` (key `addEditBudget.field.currency.accessibilityLabel`); accessibility hint `"Opens currency picker"` (key `addEditBudget.field.currency.accessibilityHint`). The view SHALL capture the budget's `currencyCode` at sheet-open time into a private `initialCurrencyCode` view-state value (via `.onAppear`). When `viewModel.currencyCode` differs from `initialCurrencyCode`, the Allocation card SHALL render an inline caption beneath the amount/pill row showing the localized text `"Changing currency only updates the label. I.e. No currency conversion."` (key `addEditBudget.note.currencyLabelOnly`). The caption SHALL be styled `.font(.caption)` and `.foregroundStyle(.secondary)`, and SHALL transition in via `.opacity.combined(with: .move(edge: .top))` animated by `.easeInOut(duration: 0.2)` keyed to `viewModel.currencyCode`. When `viewModel.currencyCode` first diverges from `initialCurrencyCode`, the view SHALL post an `AccessibilityNotification.Announcement` containing the same localized text so VoiceOver users hear the disclaimer without needing to navigate to the caption.
- **Period** (`BudgetPeriod`) — selected via a 2×2 grid of chip buttons in the Period card, one per `BudgetPeriod` case (`.daily`, `.weekly`, `.biweekly`, `.monthly`). The selected chip SHALL render with the accent colour fill and white foreground, with `.fontWeight(.semibold)`; unselected chips SHALL render with a low-opacity secondary background and primary foreground, with `.fontWeight(.regular)`. Each chip SHALL declare `.accessibilityAddTraits(.isSelected)` when it is the active selection. Each chip SHALL provide a per-period accessibility label (key `addEditBudget.chip.period.accessibilityLabel`, e.g. `"Daily period"`).

  In **Add mode**, every chip SHALL be a tappable `Button`; tapping a chip SHALL set `viewModel.period` to that case (animated by `.easeInOut(duration: 0.15)`). In **Edit mode**, chips SHALL be rendered as static `Text`-based labels (NOT `Button`s); tapping a chip SHALL have no effect. In Edit mode, non-selected chips SHALL render with a more subdued background (`Color.secondary.opacity(0.06)`) and a dimmed foreground (`Color.primary.opacity(0.3)`); the selected chip retains the accent fill and white foreground. In Edit mode, every chip SHALL declare an additional accessibility hint with the localized text `"Locked. Period can't be changed after creating your budget."` (key `addEditBudget.chip.period.locked.accessibilityHint`); in Add mode no such hint is applied.

  In Edit mode, the Period card SHALL render a `Label` directly below the chip grid using `systemImage: "lock.fill"` and the localized text `"This can't be changed after creating your budget."` (key `addEditBudget.note.periodLocked`), styled `.font(.caption)` and `.foregroundStyle(.secondary)`. The caption SHALL NOT render in Add mode.

- **Carry-Over** (`Bool`) — a `Toggle` in the Carry-Over card titled `"Carry-Over"` (key `addEditBudget.section.carryOver`). The toggle SHALL be tinted with the accent colour. A short caption (key `addEditBudget.note.carryOver`) SHALL render below the toggle in both on and off states (per `docs/main-prd.md` §6.7: the underlying carry-over figure is maintained internally even when display is off, so the caption remains accurate either way).

#### Scenario: All five fields render in their cards

- **WHEN** the sheet is visible in either Add or Edit mode
- **THEN** the screen displays four cards in this order: Name, Allocation, Period, Carry-Over; the Allocation card contains both the amount field and the currency pill; the Period card contains the 2×2 chip grid; the Carry-Over card contains the toggle and the caption

#### Scenario: Reset Cadence is not surfaced

- **WHEN** the sheet is visible in either Add or Edit mode
- **THEN** there is no UI that lets the user view, select, or change a Reset Cadence; the Carry-Over card contains only the toggle and caption (Reset Cadence is paused per `docs/main-prd.md` §6.7)

#### Scenario: Name field auto-focuses in Add mode

- **WHEN** the sheet opens in Add mode
- **THEN** the Name `TextField` receives keyboard focus immediately (the software keyboard appears), so the user can start typing a name without tapping the field first

#### Scenario: Name field does not auto-focus in Edit mode

- **WHEN** the sheet opens in Edit mode for an existing `Budget`
- **THEN** no field receives automatic focus; the user must tap to edit

#### Scenario: Allocation card shows currency prefix matching AppSettings.currencyDisplay

- **WHEN** `settings.currencyDisplay == .symbol` and the budget's currency is `"USD"`
- **THEN** the Allocation card displays `"$"` as a leading prefix text before the numeric field

- **WHEN** `settings.currencyDisplay == .code` and the budget's currency is `"USD"`
- **THEN** the Allocation card displays `"USD"` as a leading prefix text

- **WHEN** `settings.currencyDisplay == .codeAndSymbol` and the budget's currency is `"USD"`
- **THEN** the Allocation card displays `"USD $"` as a leading prefix text

#### Scenario: Currency prefix updates live when settings change

- **WHEN** the user changes `AppSettings.currencyDisplay` while the sheet is open
- **THEN** the prefix text in the Allocation card updates immediately to reflect the new preference without dismissing or reloading the sheet

#### Scenario: Allocation field parses optional Decimal with locale-aware parsing

- **WHEN** the user clears the Allocation `TextField` or leaves it empty in Add mode
- **THEN** the draft value is `nil` (blank), not `0`

- **WHEN** the user enters a number in the Allocation `TextField`
- **THEN** the parse strategy reads the text using `Decimal(string:locale:)` with `.current`, so locale-appropriate decimal separators apply; successful parse yields `Decimal`; the underlying VM state remains `Decimal?` (entered value or `nil` when empty)

#### Scenario: Allocation accessibility label respects AppSettings.currencyDisplay

- **WHEN** the user changes `AppSettings.currencyDisplay` (e.g. from `.symbol` to `.code`) while the Add/Edit Budget sheet is open
- **THEN** the Allocation field's VoiceOver label SHALL re-render so its formatted-amount component reflects the new preference (e.g. `"USD 25.00"` for `.code` instead of `"$25.00"` for `.symbol` when the budget's `currencyCode` is `"USD"`); the announcement SHALL be produced by `Decimal.formatted(currencyCode: viewModel.currencyCode, display: settings.currencyDisplay)` and not by any other formatter

#### Scenario: Period chip selection is exclusive and announced to VoiceOver

- **WHEN** the user taps a period chip in Add mode
- **THEN** that period becomes the selected one; the previously-selected chip drops its `isSelected` accessibility trait; the new chip gains the `isSelected` trait; only one chip carries the trait at any time

#### Scenario: Period chips are non-interactive in Edit mode

- **WHEN** the sheet is presented in Edit mode and the user taps any period chip (selected or not)
- **THEN** `viewModel.period` does NOT change, no visual feedback is shown, and no underlying `Budget` mutation occurs; the previously-selected chip retains the `isSelected` accessibility trait and no other chip gains it

#### Scenario: Locked period chips carry a VoiceOver hint

- **WHEN** the sheet is presented in Edit mode and VoiceOver focus moves to any period chip
- **THEN** VoiceOver announces the chip's per-period label followed by the localized hint sourced from `addEditBudget.chip.period.locked.accessibilityHint` ("Locked. Period can't be changed after creating your budget.")

#### Scenario: Period card shows a lock caption in Edit mode

- **WHEN** the sheet is presented in Edit mode
- **THEN** the Period card renders a `Label` below the 2×2 chip grid with `systemImage: "lock.fill"` and the localized text from `addEditBudget.note.periodLocked` ("This can't be changed after creating your budget.")

#### Scenario: Period card does not show a lock caption in Add mode

- **WHEN** the sheet is presented in Add mode
- **THEN** the Period card renders only the 2×2 chip grid; no lock caption is rendered

#### Scenario: Currency-change inline caption appears when draft currency diverges from initial

- **WHEN** the sheet is presented in either Add or Edit mode, the user opens the currency picker, and selects a code different from the budget's currency at sheet-open time
- **THEN** an inline caption with the localized text from `addEditBudget.note.currencyLabelOnly` ("Changing currency only updates the label. I.e. No currency conversion.") SHALL render below the amount/pill row in the Allocation card

#### Scenario: Currency-change inline caption hides when draft returns to initial

- **WHEN** the user has changed the currency away from the initial value, then opens the picker again and re-selects the original currency
- **THEN** the inline currency-change caption SHALL no longer render

#### Scenario: Currency-change disclaimer is announced to VoiceOver on first divergence

- **WHEN** in either mode the user changes the currency away from the value at sheet-open time for the first time during this presentation of the sheet
- **THEN** the system SHALL post an `AccessibilityNotification.Announcement` carrying the localized `addEditBudget.note.currencyLabelOnly` text so VoiceOver users hear the disclaimer

### Requirement: Save in Edit mode mutates only changed fields and bumps lastModified once

When the user activates Save in Edit mode, the system SHALL compare each editable field on the existing `Budget` to its corresponding draft value. For each field whose stored value differs from the draft value, the system SHALL write the draft value back to the `Budget`. The system SHALL set `Budget.lastModified = Date()` exactly once if at least one field changed. If no field changed, the system SHALL NOT mutate `Budget.lastModified` and SHALL NOT call `context.save()`. After mutating any field, the system SHALL call `try? context.save()` and dismiss the sheet.

The fields compared are: `name`, `allocation`, `currencyCode`, and `isCarryOverEnabled`. `period` SHALL NOT be compared and SHALL NOT be written in Edit mode regardless of the draft value: a `Budget`'s Time Period is fixed at creation per F-2.03 and is enforced both by the UI (chips are non-interactive in Edit mode) and by the model layer (this requirement). For `allocation`, the implementation SHALL update the `Budget` only when the draft `allocation` is non-`nil` and differs from `Budget.allocation` (a `nil` draft cannot accompany a successful Save while Save remains gated on `canSave`). The system SHALL NOT touch any other persisted field of `Budget` (notably `carryOverAmount`, `carryOverLastProcessedDate`, `carryOverLastResetDate`, `resetCadence`, `sortOrder`, `createdAt`, `period`).

#### Scenario: No-op Save does not bump lastModified

- **WHEN** the user opens the sheet for an existing `Budget`, makes no changes, and taps Save
- **THEN** the `Budget`'s `lastModified` is unchanged from before the sheet was opened, and no `context.save()` write occurs as a result of this Save

#### Scenario: Single-field change updates lastModified once

- **WHEN** the user changes only the name on an existing `Budget` and taps Save
- **THEN** the `Budget`'s `name` is updated, `lastModified` is set to a `Date()` greater than its prior value, and no other persisted field of the `Budget` is mutated

#### Scenario: Multi-field change is batched into a single context.save()

- **WHEN** the user changes both the name and the allocation on an existing `Budget` and taps Save
- **THEN** both fields are written, `lastModified` is set to a single `Date()` value, and `context.save()` is called exactly once for the whole edit

#### Scenario: Carry-over toggle off does not zero the persisted carry-over amount

- **WHEN** the user flips `isCarryOverEnabled` from `true` to `false` and taps Save
- **THEN** `Budget.isCarryOverEnabled` is set to `false`, but `Budget.carryOverAmount` (and `carryOverLastProcessedDate`, `carryOverLastResetDate`) are NOT mutated by this screen — those values continue to be maintained by `BudgetLifecycleService` per `docs/main-prd.md` §6.7

#### Scenario: Period draft divergence is ignored on Edit-mode Save

- **WHEN** the view model's `period` differs from the existing `Budget.period` at the time Save is activated in Edit mode (e.g. via a programmatic mutation of `viewModel.period`; the production UI cannot produce this state)
- **THEN** `Budget.period` SHALL NOT be written, `Budget.lastModified` SHALL NOT be bumped on account of the period divergence alone, and no `context.save()` write SHALL occur unless some other field also changed

#### Scenario: Period divergence alongside another field change writes the other field but not period

- **WHEN** the view model's `name` differs from `Budget.name` AND `viewModel.period` differs from `Budget.period` at the time Save is activated in Edit mode
- **THEN** `Budget.name` SHALL be written to the new value, `Budget.period` SHALL remain unchanged, `Budget.lastModified` SHALL be bumped exactly once, and `context.save()` SHALL be called exactly once
