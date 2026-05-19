## MODIFIED Requirements

### Requirement: Form fields are Name, Allocation, Currency, Period, and Carry-Over toggle

The Add/Edit Budget screen SHALL collect the following user-editable fields, organised into cards. The number of cards depends on the selected `Period`:

- For recurring periods (`.daily`, `.weekly`, `.biweekly`, `.monthly`): four cards — Name, Allocation, Period, Carry-Over.
- For `.specificDates`: four cards — Name, Allocation, Period (with the blurb described in the "Specific Dates conditional UI" requirement immediately below the chip), Dates. The Carry-Over card SHALL be hidden.

Reset Cadence SHALL NOT appear on this screen (per `docs/main-prd.md` §6.7 PAUSED callout; Reset Cadence is permanently removed by the budget-calculations rewrite).

The fields are:

- **Name** (`String`) — bound to a single-line `TextField` in the Name card. Placeholder `"Budget"` (key `addEditBudget.field.name.placeholder`). Accessibility label `"Budget name"` (key `addEditBudget.field.name.accessibilityLabel`). In Add mode only, the field SHALL receive keyboard focus automatically when the sheet appears (via `@FocusState` + `.onAppear`); in Edit mode no automatic focus is set.
- **Allocation** (`Decimal?` in `AddEditBudgetViewModel`) — bound to a `TextField` using `TextField(_:value:format:)` with a **custom `ParseableFormatStyle`** whose `FormatInput` is `Decimal?`, so an empty field maps to `nil` (blank default in Add mode) and entered text parses to a `Decimal` using the user's current `Locale`. Display formatting for non-`nil` values SHALL use `.number.precision(.fractionLength(0...2))` (same precision as before). Placeholder `"0"`. Keyboard type SHALL be `.decimalPad`. A currency prefix `Text` SHALL be displayed to the leading edge of the `TextField` in the same `HStack`; the prefix content is derived from `settings.currencyDisplay`: `.symbol` → the currency symbol from `NumberFormatter` for that ISO code, `.code` → the ISO code string, `.codeAndSymbol` → `"<CODE> <symbol>"`. The prefix SHALL update reactively whenever `settings.currencyDisplay` or `viewModel.currencyCode` changes. Accessibility label SHALL announce the formatted amount with the budget's currency code (key `addEditBudget.field.allocation.accessibilityLabel`). For VoiceOver, when `allocation` is `nil`, the formatted monetary argument SHALL treat the amount as `0` for the purposes of `Decimal.formatted(currencyCode:display:locale:)` only inside the localized label string; the backing draft value remains `nil`. The formatted amount SHALL be produced by the canonical `Decimal.formatted(currencyCode:display:locale:)` method with `display: settings.currencyDisplay`. The view SHALL read `AppSettings` via `@Environment(AppSettings.self)` and recompute the label whenever `settings.currencyDisplay`, `viewModel.allocation`, or `viewModel.currencyCode` changes.
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

### Requirement: Add mode seeds defaults from Budget.init and AppSettings

In Add mode, the form fields SHALL be initialised with the following defaults at sheet-open time, all of which are evaluated **once** when the `AddEditBudgetViewModel` is constructed:

- `name = ""` (empty string — the Name `TextField` displays the `"Budget"` placeholder but the draft value is blank, meaning Save is disabled until the user types a name).
- `allocation = nil` (no default amount — the Allocation field is blank until the user enters a positive value; Save remains disabled until both name is non-empty and allocation is strictly positive.)
- `currencyCode = Locale.current.currency?.identifier ?? "USD"` (matches `Budget.init`).
- `period = BudgetPeriod.daily` (matches `Budget.init` and F-2.03).
- `isCarryOverEnabled = settings.defaultCarryOverEnabled` (per F-2.07: new budgets pick up the global default at construction time).
- `startDate = nil` (no default; surfaced only when the user selects `.specificDates`, per F-2.08).
- `endDate = nil` (no default; surfaced only when the user selects `.specificDates`, per F-2.08).

The defaults SHALL NOT update reactively in response to changes in `AppSettings` after the sheet opens; the user can flip the per-budget Carry-Over toggle on the sheet if they want a value different from the global default.

#### Scenario: Add mode opens with documented defaults

- **WHEN** the sheet opens in Add mode with `settings.defaultCarryOverEnabled == true`
- **THEN** the form shows: name field empty (showing `"Budget"` placeholder), allocation field empty (draft `nil`), currency code from the user's locale (or `"USD"` if locale lookup returns `nil`), period `Daily` selected, Carry-Over toggle ON; the Dates card is hidden because period is not `.specificDates`; both `startDate` and `endDate` drafts are `nil`; Save is disabled because the name is empty and allocation is unset

#### Scenario: Add mode picks up the AppSettings carry-over default at construction

- **WHEN** the sheet is constructed while `settings.defaultCarryOverEnabled == false`
- **THEN** the Carry-Over toggle initial value is `false`

#### Scenario: Selecting Specific Dates does not pre-populate the dates

- **WHEN** the sheet is in Add mode and the user taps the `.specificDates` period chip
- **THEN** the Dates card appears, the Carry-Over card disappears, both `startDate` and `endDate` remain `nil`, and the Save button stays disabled until the user picks both dates

### Requirement: Edit mode seeds form fields from the existing Budget

In Edit mode, every editable form field SHALL be seeded from the corresponding field of the `Budget` passed to the sheet, evaluated **once** at sheet-open time:

- `name` from `Budget.name`.
- `allocation` from `Budget.allocation` (`Decimal` on the model, represented in the VM as `Decimal?` that is non-`nil` immediately after Edit-mode init).
- `currencyCode` from `Budget.currencyCode`.
- `period` from `BudgetPeriod(rawValue: Budget.period) ?? .daily` (defensive decoding for forward-compat with unknown raw values).
- `isCarryOverEnabled` from `Budget.isCarryOverEnabled`.
- `startDate` from `Budget.startDate` (always populated for `.specificDates` budgets; defensive `nil` for recurring budgets where the field is irrelevant on this screen).
- `endDate` from `Budget.endDate` (always populated for `.specificDates` budgets; `nil` for recurring budgets that have no end date).

The view SHALL hold a reference to the passed-in `Budget` so that Save in Edit mode can mutate the same instance. Cancel SHALL NOT mutate the `Budget`.

#### Scenario: Edit mode pre-fills from a recurring budget

- **WHEN** the sheet is presented for an existing `Budget` named "Coffee" with allocation `7`, currency `"USD"`, period `.weekly`, and carry-over enabled
- **THEN** the form shows: name `"Coffee"`, allocation `7`, currency `USD`, the Weekly chip selected, Carry-Over toggle ON

#### Scenario: Edit mode pre-fills from a Specific Dates budget

- **WHEN** the sheet is presented for an existing `Budget` named "Italy Trip" with allocation `1500`, currency `"EUR"`, period `.specificDates`, `startDate = 2026-05-08`, `endDate = 2026-05-25`
- **THEN** the form shows: name `"Italy Trip"`, allocation `1500`, currency `EUR`, the Specific Dates chip selected, the Dates card visible with the two date columns displaying "May 8, 2026" and "May 25, 2026", and the Carry-Over card hidden

#### Scenario: Edit mode tolerates unknown stored period raw values

- **WHEN** the sheet is presented for a `Budget` whose stored `period` raw value does not match any `BudgetPeriod` case (e.g., a value introduced by a future schema)
- **THEN** the form falls back to selecting `Daily` rather than crashing

### Requirement: Save is enabled only when validation passes

The Save toolbar button SHALL be enabled if and only if **all** of the following are true:

- The trimmed name is non-empty: `name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false`.
- Allocation is present and strictly positive: `(allocation ?? 0) > 0` (equivalently: `allocation` is non-`nil` and `> 0`; empty or unset allocation in Add mode is `nil` and fails validation).
- When `period == .specificDates`: both `startDate` and `endDate` are non-`nil` AND `startDate <= endDate`. For all other periods this clause is vacuously true.

When any condition fails, the Save button SHALL be disabled. Disabled state SHALL use the system disabled appearance; no inline error text is displayed.

#### Scenario: Empty name disables Save

- **WHEN** the user clears the Name field, leaving only whitespace or an empty string
- **THEN** the Save button is disabled

#### Scenario: Unset allocation disables Save

- **WHEN** the user has entered a non-empty name but has not entered an allocation (draft `allocation == nil`), or has cleared the Allocation field back to empty
- **THEN** the Save button is disabled

#### Scenario: Zero allocation disables Save

- **WHEN** the user sets the allocation to `0`
- **THEN** the Save button is disabled, even if the name is non-empty

#### Scenario: Positive allocation and non-empty name enable Save for recurring periods

- **WHEN** `period` is one of `.daily`, `.weekly`, `.biweekly`, `.monthly` AND the trimmed name is non-empty AND `allocation != nil` AND the allocation is `> 0`
- **THEN** the Save button is enabled

#### Scenario: Specific Dates without both dates disables Save

- **WHEN** `period == .specificDates` AND the trimmed name is non-empty AND allocation is `> 0` AND either `startDate` or `endDate` is `nil`
- **THEN** the Save button is disabled

#### Scenario: Specific Dates with start after end disables Save

- **WHEN** `period == .specificDates` AND both dates are set AND `startDate > endDate`
- **THEN** the Save button is disabled

#### Scenario: Specific Dates with valid date range enables Save

- **WHEN** `period == .specificDates` AND the trimmed name is non-empty AND allocation is `> 0` AND both dates are set AND `startDate <= endDate`
- **THEN** the Save button is enabled

### Requirement: Save in Add mode inserts a new Budget with the next sortOrder

When the user activates Save in Add mode, the system SHALL:

0. **Guard:** If validation would disable Save (`!canSave`), the implementation SHALL return without inserting a `Budget` (defence in depth if `save(context:)` is invoked without a valid draft).
1. Build a `Budget` using `Budget.init` with the drafted `name` (post-trim, but the model stores the user's value as entered; trimming is for validation only), the drafted `currencyCode`, the drafted `period`, and the drafted `isCarryOverEnabled`.
2. Compute and set `budget.startDate` per the period type:
   - **Daily:** `calendar.startOfDay(for: now)`.
   - **Weekly / Biweekly:** the most-recent `AppSettings.weekStartDay`-aligned date at or before `startOfDay(for: now)`.
   - **Monthly:** `calendar.startOfDay` of the first day of the calendar month containing `now`.
   - **Specific Dates:** `calendar.startOfDay(for: viewModel.startDate!)` (non-nil by `canSave`).
3. For `.specificDates`, also set `budget.endDate = calendar.startOfDay(for: viewModel.endDate!)`. For all other periods `endDate` SHALL remain `nil`.
4. Set `budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0` BEFORE inserting, so the fetch does not include the new instance.
5. Call `context.insert(budget)`.
6. Insert one initial `AllocationChange(effectiveFrom: budget.startDate!, amount: drafted allocation)` attached to the same budget.
7. Call `try? context.save()`.
8. Dismiss the sheet.

The new budget SHALL appear in the Budgets screen list immediately due to the existing `@Query(sort: \Budget.sortOrder)` reactivity. CloudKit sync SHALL propagate the new row through the existing pipeline; no new container or schema changes are introduced.

#### Scenario: First budget gets sortOrder 0

- **WHEN** the store is empty and the user creates a `Budget` via Save
- **THEN** the inserted `Budget` has `sortOrder == 0`

#### Scenario: Subsequent budget gets next sortOrder

- **WHEN** the store contains budgets with `sortOrder` values up to `N`, and the user creates a `Budget` via Save
- **THEN** the inserted `Budget` has `sortOrder == N + 1`

#### Scenario: Save inserts exactly one budget

- **WHEN** the user activates Save in Add mode
- **THEN** the store contains exactly one new `Budget` whose fields match the drafted values

#### Scenario: Specific Dates Save writes both startDate and endDate

- **WHEN** the user creates a `.specificDates` budget with `startDate = 2026-05-08`, `endDate = 2026-05-25`, allocation `1500`
- **THEN** the inserted `Budget` has `startDate == startOfDay(2026-05-08)`, `endDate == startOfDay(2026-05-25)`, and one `AllocationChange(effectiveFrom: startDate, amount: 1500)`

#### Scenario: Recurring Save leaves endDate nil

- **WHEN** the user creates a `.daily`, `.weekly`, `.biweekly`, or `.monthly` budget
- **THEN** the inserted `Budget.endDate` is `nil`

### Requirement: Save in Edit mode mutates only changed fields and bumps lastModified once

When the user activates Save in Edit mode, the system SHALL compare each editable field on the existing `Budget` to its corresponding draft value. For each field whose stored value differs from the draft value, the system SHALL write the draft value back to the `Budget`. The system SHALL set `Budget.lastModified = Date()` exactly once if at least one field changed. If no field changed, the system SHALL NOT mutate `Budget.lastModified` and SHALL NOT call `context.save()`. After mutating any field, the system SHALL call `try? context.save()` and dismiss the sheet.

The fields compared are: `name`, `allocation`, `currencyCode`, `isCarryOverEnabled`, and — when `Budget.period == .specificDates` — `startDate` and `endDate`. `period` SHALL NOT be compared and SHALL NOT be written in Edit mode regardless of the draft value: a `Budget`'s Time Period is fixed at creation per F-2.03 and is enforced both by the UI (chips are non-interactive in Edit mode) and by the model layer (this requirement). For `allocation`, the implementation SHALL update the `Budget` only when the draft `allocation` is non-`nil` and differs from `Budget.allocation` (a `nil` draft cannot accompany a successful Save while Save remains gated on `canSave`). For `startDate` and `endDate` on `.specificDates` budgets: the implementation SHALL normalise the draft with `calendar.startOfDay(for:)` before comparison, and when `startDate` changes the implementation SHALL also update `effectiveFrom` on the budget's most-recent `AllocationChange` to the new `startDate` (latest-wins semantics, see F-2.08). The system SHALL NOT touch any other persisted field of `Budget` (notably `sortOrder`, `createdAt`, `period`, `lastResetDate`).

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
- **THEN** `Budget.isCarryOverEnabled` is set to `false`, but no other carry-over-related state on the `Budget` is mutated by this screen — those values continue to be maintained by `BudgetLifecycleService` per `docs/main-prd.md` §6.7

#### Scenario: Period draft divergence is ignored on Edit-mode Save

- **WHEN** the view model's `period` differs from the existing `Budget.period` at the time Save is activated in Edit mode (e.g. via a programmatic mutation of `viewModel.period`; the production UI cannot produce this state)
- **THEN** `Budget.period` SHALL NOT be written, `Budget.lastModified` SHALL NOT be bumped on account of the period divergence alone, and no `context.save()` write SHALL occur unless some other field also changed

#### Scenario: Period divergence alongside another field change writes the other field but not period

- **WHEN** the view model's `name` differs from `Budget.name` AND `viewModel.period` differs from `Budget.period` at the time Save is activated in Edit mode
- **THEN** `Budget.name` SHALL be written to the new value, `Budget.period` SHALL remain unchanged, `Budget.lastModified` SHALL be bumped exactly once, and `context.save()` SHALL be called exactly once

#### Scenario: Specific Dates Edit changes endDate only

- **WHEN** the user opens Edit for a `.specificDates` budget and changes only `endDate` from `2026-05-25` to `2026-05-30`, then taps Save
- **THEN** `Budget.endDate` is updated to `startOfDay(2026-05-30)`, `Budget.lastModified` is bumped once, no `AllocationChange` row is mutated, and no other `Budget` fields are written

#### Scenario: Specific Dates Edit changes startDate

- **WHEN** the user opens Edit for a `.specificDates` budget with start `2026-05-08` and the most-recent `AllocationChange.effectiveFrom == 2026-05-08`, changes start to `2026-05-09`, and taps Save
- **THEN** `Budget.startDate` is updated to `startOfDay(2026-05-09)` AND the most-recent `AllocationChange.effectiveFrom` is updated to the same value, `Budget.lastModified` is bumped once, and `context.save()` is called exactly once

## ADDED Requirements

### Requirement: Specific Dates conditional UI — blurb, Dates card, Carry-Over hidden

When and only when `viewModel.period == .specificDates`, the Add/Edit Budget screen SHALL render the following Specific Dates-specific UI elements:

- **Explanatory blurb** — directly below the `.specificDates` chip inside the Period card, a `Text` view SHALL render the localized string keyed `addEditBudget.note.specificDates` (English source: "Good for a trip, a birthday weekend, or any one-off spending window. When it's done, it's done. No repeating, no carry-over.") styled `.font(.caption)` and `.foregroundStyle(.secondary)`, transitioned in via `.opacity.combined(with: .move(edge: .top))` animated by `.easeInOut(duration: 0.2)` keyed to `isSpecificDates`. The blurb SHALL NOT render for any other period type.

- **Dates card** — a `GroupBox`-backed card titled `"Dates"` (key `addEditBudget.section.dates`) SHALL render in the same slot the Carry-Over card occupies for recurring periods (i.e., directly below the Period card). The card SHALL contain a single `HStack` with two `DateColumn` buttons side-by-side: one for `startDate` (placeholder key `addEditBudget.field.date.start.placeholder`, English source: "Choose start date") and one for `endDate` (placeholder key `addEditBudget.field.date.end.placeholder`, English source: "Choose end date"). Each column SHALL fill its half of the row with `.frame(maxWidth: .infinity, alignment: .leading)`.

- **Carry-Over card hidden** — the Carry-Over card SHALL NOT render. The underlying `viewModel.isCarryOverEnabled` value is unaffected.

`DateColumn` behaviour:

- When the bound `Date?` is `nil`, the button SHALL render as a full-width rounded-rect chip matching the unselected period chip style: `RoundedRectangle(cornerRadius: 8, style: .continuous)` filled with `Color.secondary.opacity(0.1)`, `.font(.subheadline)`, `.foregroundStyle(Color.primary)`, vertical padding 10, full-width `.frame(maxWidth: .infinity)`. The button label SHALL be the placeholder text.

- When the bound `Date?` is non-`nil`, the button SHALL render the date using `Date.formatted(date: .abbreviated, time: .omitted)` (locale-aware, e.g. "May 18, 2026" in en-US), keeping the same chip styling.

- Tapping the button SHALL present a `.sheet` containing a `.graphical` `DatePicker` for the bound date, bounded to `(minDate ?? .distantPast) ... Date.distantFuture`. For the End Date column, `minDate` SHALL be the current `startDate` so the user cannot pick an end date before the start. The sheet SHALL have a cancellation toolbar item labelled `"Cancel"` (key `addEditBudget.dates.picker.cancel`) and a confirmation toolbar item labelled `"Done"` (key `addEditBudget.dates.picker.done`) with `.fontWeight(.semibold)`. Cancel dismisses without writing; Done assigns the picked date to the binding and dismisses. The sheet SHALL use `.presentationDetents([.medium, .large])`.

- VoiceOver: the empty-state chip SHALL declare an `accessibilityLabel` from the placeholder text and an `accessibilityHint` (keys `addEditBudget.field.date.start.accessibilityHint` and `.end.accessibilityHint`, English source: "Opens a calendar to pick the start/end date"). The set-state chip SHALL declare an `accessibilityLabel` that combines the field label and the formatted date (e.g. "Start date, May 18, 2026").

#### Scenario: Blurb appears below the Specific Dates chip

- **WHEN** the user selects the Specific Dates chip
- **THEN** the explanatory blurb (key `addEditBudget.note.specificDates`) renders directly below the chip inside the Period card, with caption styling and an opacity+move transition

#### Scenario: Dates card replaces the Carry-Over slot for Specific Dates

- **WHEN** `viewModel.period == .specificDates`
- **THEN** the Dates card renders in the same vertical slot the Carry-Over card occupies for recurring periods, and the Carry-Over card does NOT render

#### Scenario: Date column placeholder reads as a chip

- **WHEN** the Dates card is visible and `startDate == nil`
- **THEN** the start date column renders as a full-width rounded-rect chip with the localized placeholder "Choose start date" centred, styled identically to an unselected period chip

#### Scenario: Tapping a date column opens the graphical picker sheet

- **WHEN** the user taps the start date column
- **THEN** a sheet presents with `presentationDetents` of `.medium` and `.large`, containing a graphical `DatePicker` bounded by `.distantPast ... .distantFuture`, plus Cancel and Done toolbar items

#### Scenario: Done writes the picked date and dismisses

- **WHEN** the user picks a date in the sheet and taps Done
- **THEN** the bound `Date?` is updated to the picked date, the sheet dismisses, and the chip re-renders with the formatted date

#### Scenario: Cancel discards the picked date

- **WHEN** the user changes the picker selection and taps Cancel
- **THEN** the bound `Date?` is unchanged and the sheet dismisses

#### Scenario: End date picker is bounded by start date

- **WHEN** `startDate` is set and the user taps the end date column
- **THEN** the picker's lower bound is the current `startDate`, preventing selection of an earlier date

#### Scenario: Set-state chip shows the locale-formatted date

- **WHEN** `startDate` is set to `2026-05-18` and the user's locale is en-US
- **THEN** the start date column renders "May 18, 2026" as the chip label

### Requirement: ViewModel holds startDate and endDate draft state

The `AddEditBudgetViewModel` SHALL declare `startDate: Date?` and `endDate: Date?` as draft properties owned by the VM (not the view). Both SHALL default to `nil` in Add mode. In Edit mode, both SHALL be seeded from `Budget.startDate` and `Budget.endDate` respectively (see the "Edit mode seeds form fields from the existing Budget" requirement). The view SHALL bind the two `DateColumn` buttons to `$viewModel.startDate` and `$viewModel.endDate`.

#### Scenario: VM declares date drafts

- **WHEN** `AddEditBudgetViewModel` is inspected
- **THEN** it declares stored properties `var startDate: Date?` and `var endDate: Date?` and these are observable

#### Scenario: Add mode dates are nil at construction

- **WHEN** `AddEditBudgetViewModel(settings:)` is invoked
- **THEN** the constructed VM has `startDate == nil` and `endDate == nil`

#### Scenario: Edit mode dates are seeded from the budget

- **WHEN** `AddEditBudgetViewModel(editing: budget)` is invoked for a `.specificDates` budget with `budget.startDate == 2026-05-08` and `budget.endDate == 2026-05-25`
- **THEN** the constructed VM has `startDate == 2026-05-08` and `endDate == 2026-05-25`
