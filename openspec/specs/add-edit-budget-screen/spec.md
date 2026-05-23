# add-edit-budget-screen Specification

## Purpose

SwiftUI sheet used for both creating a new `Budget` and editing an existing one. Provides a card-based form (Name, Allocation/Currency, Period, Carry-Over / Dates depending on period) backed by `AddEditBudgetViewModel`, wired into the centralised `Router.sheet` mechanism. Satisfies F-2.03, F-2.08, and the currency-picker path of F-3.04. Updated from change `specific-dates-period` (2026-05-18).
## Requirements
### Requirement: Add/Edit Budget screen is a single sheet for both create and edit modes

The system SHALL present a single SwiftUI sheet, `AddEditBudgetView`, used for both creating a new `Budget` and editing an existing `Budget`. The sheet SHALL be presented from the existing `Router.sheet` mechanism via two existing `SheetRoute` cases:

- `SheetRoute.addBudget` — Add mode.
- `SheetRoute.editBudget(Budget)` — Edit mode.

No new `SheetRoute` cases SHALL be introduced.

The sheet's navigation title SHALL read the localized string `"New Budget"` (key `addEditBudget.title.add`) in Add mode and `"Edit Budget"` (key `addEditBudget.title.edit`) in Edit mode. The title SHALL be displayed inline (`.navigationBarTitleDisplayMode(.inline)`).

The sheet SHALL expose two toolbar items: a leading `Cancel` button (key `addEditBudget.action.cancel`) that dismisses without persisting any changes, and a trailing `Save` button (key `addEditBudget.action.save`) whose enablement follows the form-validation rules below.

#### Scenario: Add mode is presented via SheetRoute.addBudget

- **WHEN** a caller sets `Router.sheet = .addBudget`
- **THEN** `RootView` SHALL present `AddEditBudgetView` configured for Add mode

#### Scenario: Edit mode is presented via SheetRoute.editBudget

- **WHEN** a caller sets `Router.sheet = .editBudget(budget)` for some `Budget`
- **THEN** `RootView` SHALL present `AddEditBudgetView` configured for Edit mode, seeded from that `Budget`

#### Scenario: Sheet exposes Cancel and Save toolbar items

- **WHEN** the sheet is visible
- **THEN** the navigation bar SHALL show a leading Cancel button and a trailing Save button (localized via `addEditBudget.action.cancel` and `addEditBudget.action.save`); no other toolbar items SHALL be present on this sheet

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
- `startDate = Calendar.autoupdatingCurrent.startOfDay(for: Date())` (the per-period default for the initial `.daily` period; see also the `period.didSet` re-anchoring rule under "ViewModel holds startDate and endDate draft state"). The Schedule disclosure's collapsed summary thus reads "Starts {today} · No end date" from sheet-open without any user interaction.
- `endDate = nil` (no default; optional for recurring period types and surfaced via the Schedule disclosure's chip area when expanded).
- `weekStartDay = settings.weekStartDay` is captured privately at construction time (used by `onPeriodChange` to re-anchor `startDate` when the user toggles to `.weekly` or `.biweekly`; not user-visible).

The defaults SHALL NOT update reactively in response to changes in `AppSettings` after the sheet opens; the user can flip the per-budget Carry-Over toggle on the sheet if they want a value different from the global default. The captured `weekStartDay` likewise SHALL NOT track later changes to `AppSettings.weekStartDay`.

#### Scenario: Add mode opens with documented defaults

- **WHEN** the sheet opens in Add mode with `settings.defaultCarryOverEnabled == true`
- **THEN** the form shows: name field empty (showing `"Budget"` placeholder), allocation field empty (draft `nil`), currency code from the user's locale (or `"USD"` if locale lookup returns `nil`), period `Daily` selected, Carry-Over toggle ON, the Schedule card visible with the disclosure collapsed, `viewModel.startDate == startOfDay(Date())`, `viewModel.endDate == nil`, Save is disabled because the name is empty and allocation is unset

#### Scenario: Add mode picks up the AppSettings carry-over default at construction

- **WHEN** the sheet is constructed while `settings.defaultCarryOverEnabled == false`
- **THEN** the Carry-Over toggle initial value is `false`

#### Scenario: Selecting a non-default recurring period re-anchors startDate

- **WHEN** the sheet is in Add mode and the user taps the `.weekly` period chip
- **THEN** `viewModel.startDate` is reset to the most-recent `settings.weekStartDay`-aligned date at or before `startOfDay(Date())`, `viewModel.endDate` is `nil`, the Schedule disclosure summary updates to reflect the new start, and the Carry-Over card remains visible

#### Scenario: Selecting Specific Dates clears the pre-populated dates

- **WHEN** the sheet is in Add mode and the user taps the `.specificDates` period chip
- **THEN** the `Dates` card replaces the Schedule + Carry-Over slot, both `startDate` and `endDate` are set to `nil`, and the Save button stays disabled until the user picks both dates (per F-2.08 / the "Specific Dates conditional UI" requirement)

### Requirement: Edit mode seeds form fields from the existing Budget

In Edit mode, every editable form field SHALL be seeded from the corresponding field of the `Budget` passed to the sheet, evaluated **once** at sheet-open time:

- `name` from `Budget.name`.
- `allocation` from `Budget.currentAllocation` (`Decimal` on the model, represented in the VM as `Decimal?` that is non-`nil` immediately after Edit-mode init).
- `currencyCode` from `Budget.currencyCode`.
- `period` from `BudgetPeriod(rawValue: Budget.period) ?? .daily` (defensive decoding for forward-compat with unknown raw values).
- `isCarryOverEnabled` from `Budget.isCarryOverEnabled`.
- `startDate` from `Budget.startDate` (populated for any period type that has a stored value).
- `endDate` from `Budget.endDate` (populated when the budget has an end date — required for `.specificDates`, optional for recurring period types).

In Edit mode, the captured `weekStartDay` value is a defensive default (e.g. `.sunday`) and is NEVER read, because `period.didSet` short-circuits via the `!isEditing` guard so `onPeriodChange` does not fire.

The view SHALL hold a reference to the passed-in `Budget` so that Save in Edit mode can mutate the same instance. Cancel SHALL NOT mutate the `Budget`.

#### Scenario: Edit mode pre-fills from a recurring budget

- **WHEN** the sheet is presented for an existing `Budget` named "Coffee" with allocation `7`, currency `"USD"`, period `.weekly`, carry-over enabled, `startDate == 2026-04-13`, `endDate == nil`
- **THEN** the form shows: name `"Coffee"`, allocation `7`, currency `USD`, the Weekly chip selected and locked, Carry-Over toggle ON, the Schedule card visible with the disclosure collapsed, the summary reading "Starts Apr 13, 2026 · No end date"

#### Scenario: Edit mode pre-fills from a recurring budget with endDate set

- **WHEN** the sheet is presented for an existing `Budget` with period `.monthly`, `startDate == 2026-01-01`, `endDate == 2026-12-31`
- **THEN** the Schedule disclosure summary reads "Starts Jan 1, 2026 · Ends Dec 31, 2026"; expanding the disclosure shows two `DateColumn` chips with both dates set and a "Clear end date" button visible

#### Scenario: Edit mode pre-fills from a Specific Dates budget

- **WHEN** the sheet is presented for an existing `Budget` named "Italy Trip" with allocation `1500`, currency `"EUR"`, period `.specificDates`, `startDate = 2026-05-08`, `endDate = 2026-05-25`
- **THEN** the form shows: name `"Italy Trip"`, allocation `1500`, currency `EUR`, the Specific Dates chip selected and locked, the `Dates` card visible with the two date columns displaying "May 8, 2026" and "May 25, 2026", and the Carry-Over and Schedule cards both hidden

#### Scenario: Edit mode tolerates unknown stored period raw values

- **WHEN** the sheet is presented for a `Budget` whose stored `period` raw value does not match any `BudgetPeriod` case (e.g., a value introduced by a future schema)
- **THEN** the form falls back to selecting `Daily` rather than crashing

### Requirement: Save is enabled only when validation passes

Save SHALL be enabled only when ALL of the following hold:

- The trimmed name (`name.trimmingCharacters(in: .whitespacesAndNewlines)`) is non-empty.
- `allocation` is non-`nil` and strictly positive (`(allocation ?? 0) > 0`).
- When `period == .specificDates`: both `startDate` and `endDate` are non-`nil` AND `startDate <= endDate`. For all other periods this clause is vacuously true.

For recurring period types, `startDate` is pre-filled at Add-mode init and re-anchored on `period.didSet`, so it is always non-`nil` at the time the user could tap Save — the validation clause specific to `.specificDates` is the only date-related gate.

#### Scenario: Save is disabled when name is empty

- **WHEN** name is empty and allocation is `25`
- **THEN** Save is disabled

#### Scenario: Save is disabled when allocation is zero

- **WHEN** name is non-empty and allocation is `0`
- **THEN** Save is disabled

#### Scenario: Save is disabled when allocation is nil

- **WHEN** name is non-empty and the user has not typed anything in the Allocation field (draft `nil`)
- **THEN** Save is disabled

#### Scenario: Specific Dates Save is disabled when only one date is set

- **WHEN** `period == .specificDates` AND the trimmed name is non-empty AND allocation is `> 0` AND either `startDate` or `endDate` is `nil`
- **THEN** Save is disabled

#### Scenario: Specific Dates Save is disabled when start exceeds end

- **WHEN** `period == .specificDates` AND both dates are set AND `startDate > endDate`
- **THEN** Save is disabled

#### Scenario: Specific Dates Save is enabled when both dates are set and well-ordered

- **WHEN** `period == .specificDates` AND the trimmed name is non-empty AND allocation is `> 0` AND both dates are set AND `startDate <= endDate`
- **THEN** Save is enabled

#### Scenario: Recurring Save does not require an end date

- **WHEN** `period == .daily` (or any recurring period) AND the trimmed name is non-empty AND allocation is `> 0` AND `startDate` is set (always true for recurring per init) AND `endDate == nil`
- **THEN** Save is enabled

### Requirement: VM exposes a save method that takes ModelContext at the call site

The `AddEditBudgetViewModel` SHALL expose `func save(context: ModelContext)` that performs the Add or Edit branch documented below. The view SHALL read `@Environment(\.modelContext)` and invoke `viewModel.save(context: context)` from inside `body`, then call `dismiss()`. The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The save body SHALL NOT consult `AppSettings` — `AppSettings` is read only at construction time via `init(settings:)` to seed the Add-mode Carry-Over default (per `docs/tech-design-doc.md` §2.1: "Methods that need to write take `(context: ModelContext, ...)` at the call site (and `AppSettings` similarly when relevant)" — for the save body, `AppSettings` is not relevant).

#### Scenario: Save method signature does not include AppSettings

- **WHEN** the `AddEditBudgetViewModel.save(...)` method is inspected
- **THEN** its signature SHALL be `func save(context: ModelContext)`; `AppSettings` SHALL NOT be a parameter of `save`

### Requirement: Save in Add mode inserts a new Budget with the next sortOrder

When the user activates Save in Add mode, the system SHALL:

0. **Guard:** If validation would disable Save (`!canSave`), the implementation SHALL return without inserting a `Budget` (defence in depth if `save(context:)` is invoked without a valid draft).
1. Build a `Budget` using `Budget.init` with the drafted `name` (post-trim, but the model stores the user's value as entered; trimming is for validation only), the drafted `currencyCode`, the drafted `period`, and the drafted `isCarryOverEnabled`.
2. Set `budget.startDate = calendar.startOfDay(for: viewModel.startDate!)`. The drafted `startDate` is non-`nil` by canSave (specific dates) or by the Add-mode pre-fill + `period.didSet` re-anchoring rule (recurring). For weekly / biweekly the drafted value may be the AppSettings-derived anchor (default) or a user-overridden date — both paths are stored as the budget's `startDate`, which becomes the per-budget cycle anchor per F-7.05.
3. Set `budget.endDate = viewModel.endDate.map { calendar.startOfDay(for: $0) }`. For `.specificDates`, `endDate` is non-`nil` by `canSave`. For recurring period types it is optional — `nil` is the common case for "no terminal date."
4. For `.specificDates` only, force-clamp `isCarryOverEnabled = false` before insert (the toggle is hidden on the Add/Edit sheet for this period type; without the clamp, a pre-toggle session default of `true` would persist a stale value that pollutes analytics cohorts that read `Budget.isCarryOverEnabled` directly).
5. Set `budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0` BEFORE inserting, so the fetch does not include the new instance.
6. Call `context.insert(budget)`.
7. Insert one initial `AllocationChange(effectiveFrom: budget.startDate!, amount: drafted allocation, lastModified: Date())` attached to the same budget.
8. Call `try? context.save()`.
9. Dismiss the sheet.

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

#### Scenario: Recurring Save uses pre-filled startDate

- **WHEN** the user creates a `.daily` budget without touching the Schedule disclosure
- **THEN** the inserted `Budget.startDate` equals `calendar.startOfDay(for: Date())` (the Add-mode pre-fill) AND the initial `AllocationChange.effectiveFrom` equals the same value AND `Budget.endDate` is `nil`

#### Scenario: Recurring Save honors a user-overridden startDate

- **WHEN** the user creates a `.weekly` budget, expands the Schedule disclosure, picks a Thursday three weeks ago via the start-date chip, and taps Save
- **THEN** the inserted `Budget.startDate` equals the picked Thursday at `startOfDay`, AND the initial `AllocationChange.effectiveFrom` equals the same value — the cycle anchor becomes Thursday per F-7.05 (`weekStart = budget.startDate.weekday`)

#### Scenario: Recurring Save persists an optional endDate

- **WHEN** the user creates a `.monthly` budget and picks an end date six months in the future via the Schedule disclosure
- **THEN** the inserted `Budget.endDate` equals the picked date at `startOfDay`

#### Scenario: Specific Dates Save writes both startDate and endDate

- **WHEN** the user creates a `.specificDates` budget with `startDate = 2026-05-08`, `endDate = 2026-05-25`, allocation `1500`
- **THEN** the inserted `Budget` has `startDate == startOfDay(2026-05-08)`, `endDate == startOfDay(2026-05-25)`, and one `AllocationChange(effectiveFrom: startDate, amount: 1500)`

#### Scenario: Recurring Save leaves endDate nil by default

- **WHEN** the user creates a `.daily`, `.weekly`, `.biweekly`, or `.monthly` budget without setting an end date in the Schedule disclosure
- **THEN** the inserted `Budget.endDate` is `nil`

### Requirement: Save in Edit mode mutates only changed fields and bumps lastModified once

When the user activates Save in Edit mode, the system SHALL compare each editable field on the existing `Budget` to its corresponding draft value. For each field whose stored value differs from the draft value, the system SHALL write the draft value back to the `Budget`. The system SHALL set `Budget.lastModified = Date()` exactly once if at least one field changed. If no field changed, the system SHALL NOT mutate `Budget.lastModified` and SHALL NOT call `context.save()`. After mutating any field, the system SHALL call `try? context.save()` and dismiss the sheet.

The fields compared are: `name`, `allocation`, `currencyCode`, `isCarryOverEnabled`, `startDate`, and `endDate`. `period` SHALL NOT be compared and SHALL NOT be written in Edit mode regardless of the draft value: a `Budget`'s Time Period is fixed at creation per F-2.03 and is enforced both by the UI (chips are non-interactive in Edit mode) and by the model layer (this requirement).

For `allocation`, the implementation SHALL update the `Budget` only when the draft `allocation` is non-`nil` and differs from `Budget.currentAllocation` (a `nil` draft cannot accompany a successful Save while Save remains gated on `canSave`).

For `startDate` and `endDate`, the implementation SHALL normalise the draft with `calendar.startOfDay(for:)` before comparison, regardless of period type. When a recurring budget's `startDate` changes, the implementation SHALL write `Budget.startDate` only — it SHALL NOT realign any `AllocationChange` row. The calculator's `allocationInEffect` fallback (`Domain/AllocationInEffect.swift`) extends the earliest row's amount backward to any `boundaryStart` that precedes its `effectiveFrom`, so back-dating credits the original allocation to the back-dated window without a data-mutation step; forward-dating works symmetrically via the walker starting at the new later `effectiveStartDate`.

For `.specificDates` only, when `startDate` changes the implementation SHALL also update `effectiveFrom` on the budget's most-recent `AllocationChange` to the new `startDate` (latest-wins semantics, see F-2.08). This single-period special-case does NOT apply to recurring period types.

For `endDate`, the implementation SHALL handle three cases for any period type:

- Draft and stored are both `nil` → no change.
- Draft is non-`nil` and differs from stored (normalised) → write the new value.
- Draft is `nil` and stored is non-`nil` (user cleared an optional end date — recurring only; `canSave` prevents this state for `.specificDates`) → set `Budget.endDate = nil`.

The system SHALL NOT touch any other persisted field of `Budget` (notably `sortOrder`, `createdAt`, `period`, `lastResetDate`).

The implementation SHALL emit `AnalyticsEvent.budgetEdited` with per-field change flags (see the "budget_edited analytics event carries per-field change flags" requirement).

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

#### Scenario: Recurring startDate edit writes Budget.startDate without realigning AllocationChange

- **WHEN** the user opens Edit for a `.weekly` budget with `startDate == 2026-04-13` and a single `AllocationChange(effectiveFrom: 2026-04-13, amount: 100)`, edits `startDate` to `2026-04-06` (one week back) via the Schedule disclosure, and taps Save
- **THEN** `Budget.startDate == startOfDay(2026-04-06)`, the `AllocationChange.effectiveFrom` remains `2026-04-13` (unchanged), and `Budget.lastModified` is bumped once. A subsequent `BudgetCalculator.snapshot` SHALL credit the 2026-04-06 to 2026-04-12 period at allocation 100 via `allocationInEffect`'s earliest-row fallback.

#### Scenario: Recurring endDate edit writes Budget.endDate

- **WHEN** the user opens Edit for a `.monthly` budget with `endDate == nil`, picks a future end date via the Schedule disclosure, and taps Save
- **THEN** `Budget.endDate` is updated to the picked date at `startOfDay`, `Budget.lastModified` is bumped once

#### Scenario: Recurring endDate clearing writes nil

- **WHEN** the user opens Edit for a `.monthly` budget with `endDate == 2026-12-31`, taps "Clear end date" in the Schedule disclosure, and taps Save
- **THEN** `Budget.endDate` is set to `nil`, `Budget.lastModified` is bumped once

#### Scenario: Specific Dates Edit changes endDate only

- **WHEN** the user opens Edit for a `.specificDates` budget and changes only `endDate` from `2026-05-25` to `2026-05-30`, then taps Save
- **THEN** `Budget.endDate` is updated to `startOfDay(2026-05-30)`, `Budget.lastModified` is bumped once, no `AllocationChange` row is mutated, and no other `Budget` fields are written

#### Scenario: Specific Dates Edit changes startDate (realignment preserved)

- **WHEN** the user opens Edit for a `.specificDates` budget with start `2026-05-08` and the most-recent `AllocationChange.effectiveFrom == 2026-05-08`, changes start to `2026-05-09`, and taps Save
- **THEN** `Budget.startDate` is updated to `startOfDay(2026-05-09)` AND the most-recent `AllocationChange.effectiveFrom` is updated to the same value, `Budget.lastModified` is bumped once, and `context.save()` is called exactly once

### Requirement: budget_edited analytics event carries per-field change flags

When `AddEditBudgetViewModel.saveEdit` writes one or more fields back to the existing `Budget`, the emitted `AnalyticsEvent.budgetEdited` properties bag SHALL include per-field boolean flags identifying which fields changed in this Save:

- `allocation_changed: Bool` — `true` iff the drafted `allocation` differed from `Budget.currentAllocation` and was written.
- `start_date_changed: Bool` — `true` iff the normalized `viewModel.startDate` differed from `Budget.startDate` and was written.
- `end_date_changed: Bool` — `true` iff the normalized `viewModel.endDate` differed from `Budget.endDate` and was written (this includes the "user cleared an optional end date" path, recurring only).

These flags SHALL be emitted **only** on `AnalyticsEvent.budgetEdited`. They SHALL NOT be added to `AnalyticsEvent.budgetCreated` (where every field is "new" by definition). They SHALL NOT alter other events.

The implementation SHALL replace the existing single `changed: Bool` accumulator in `saveEdit` with per-field locals (e.g. `nameChanged`, `allocationChanged`, `currencyChanged`, `carryOverToggleChanged`, dateEdits via `applyDateEdits` returning a tuple or struct exposing the two date diffs separately) and pass the F-8.02 subset (`allocation_changed`, `start_date_changed`, `end_date_changed`) through `budgetEventProperties(budget:edits:)`. The existing aggregate gating (write to `Budget.lastModified` and `context.save()` only when at least one field changed) SHALL continue to apply.

Property names SHALL match `docs/analytics-spec.md`'s F-8.02 declarations. The corresponding constants SHALL be added to `AnalyticsProperty` (e.g. `AnalyticsProperty.allocationChanged`, `.startDateChanged`, `.endDateChanged`).

#### Scenario: Editing only the name fires budget_edited with all date / allocation flags false

- **WHEN** the user opens Edit for a `.daily` budget and changes only the name, then taps Save
- **THEN** the emitted `AnalyticsEvent.budgetEdited` properties include `allocation_changed: false`, `start_date_changed: false`, `end_date_changed: false`

#### Scenario: Editing the recurring startDate fires budget_edited with start_date_changed=true

- **WHEN** the user opens Edit for a `.weekly` budget, edits `startDate` from one Monday to the prior Monday via the Schedule disclosure, and taps Save
- **THEN** `AnalyticsEvent.budgetEdited` fires with `start_date_changed: true`, `end_date_changed: false`, `allocation_changed: false`

#### Scenario: Clearing the recurring endDate fires budget_edited with end_date_changed=true

- **WHEN** the user opens Edit for a `.monthly` budget with `endDate` set, taps "Clear end date" in the Schedule disclosure, and taps Save
- **THEN** `Budget.endDate` is set to `nil` in storage, and `AnalyticsEvent.budgetEdited` fires with `end_date_changed: true`, `start_date_changed: false`

#### Scenario: budget_created is unaffected by this requirement

- **WHEN** the user creates a new budget via Save in Add mode
- **THEN** `AnalyticsEvent.budgetCreated` fires WITHOUT `start_date_changed`, `end_date_changed`, or `allocation_changed` flags in its properties

#### Scenario: No-op Save does not fire budget_edited

- **WHEN** the user opens Edit, makes no changes, and taps Save
- **THEN** no `AnalyticsEvent.budgetEdited` event is emitted (consistent with the existing "no-op Save does not bump lastModified" scenario)

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

The `AddEditBudgetViewModel` SHALL declare `startDate: Date?` and `endDate: Date?` as draft properties owned by the VM (not the view). The view SHALL bind the `DateColumn` buttons (in both the Schedule disclosure for recurring and the `Dates` card for `.specificDates`) to `$viewModel.startDate` and `$viewModel.endDate`.

**Add-mode defaults:**
- `startDate` is pre-filled at construction to the per-period anchor for the initial `.daily` period: `Calendar.autoupdatingCurrent.startOfDay(for: Date())`.
- `endDate` defaults to `nil`.

**Add-mode period-change re-anchoring (`period.didSet`):** When `period` changes in Add mode (`!isEditing`), the VM SHALL invoke a private `onPeriodChange()` helper that resets `startDate` and `endDate` per the new period type:

- `.specificDates` → `startDate = nil`, `endDate = nil` (the user must pick both).
- `.daily` → `startDate = calendar.startOfDay(for: Date())`, `endDate = nil`.
- `.weekly` / `.biweekly` → `startDate = the most-recent weekStartDay-aligned date at or before startOfDay(Date())` using the privately captured `weekStartDay`, `endDate = nil`.
- `.monthly` → `startDate = first of the current calendar month at startOfDay`, `endDate = nil`.

Edit mode SHALL NOT fire `onPeriodChange` even if `period` is somehow mutated (it should not be, since the chips are non-interactive in Edit mode; the `!isEditing` guard is defence-in-depth).

**Cross-coupling.** `startDate.didSet` SHALL snap `endDate` forward to preserve duration when `startDate` crosses past `endDate` (Apple Calendar pattern), applicable to both `.specificDates` and recurring budgets that happen to have both dates set. `didSet` does not fire during `init`, so seeding both dates in Edit mode is safe.

**Edit-mode init:**
- `startDate` is seeded from `Budget.startDate`.
- `endDate` is seeded from `Budget.endDate`.

#### Scenario: VM declares date drafts and weekStartDay capture

- **WHEN** `AddEditBudgetViewModel` is inspected
- **THEN** it declares stored properties `var startDate: Date?`, `var endDate: Date?`, and `private let weekStartDay: Weekday`; the date properties are observable

#### Scenario: Add mode startDate pre-fill for daily

- **WHEN** `AddEditBudgetViewModel(settings:)` is invoked
- **THEN** the constructed VM has `startDate == calendar.startOfDay(for: Date())`, `endDate == nil`

#### Scenario: Add mode period change to weekly re-anchors startDate

- **WHEN** `AddEditBudgetViewModel(settings:)` is invoked, then `period` is set to `.weekly`
- **THEN** `startDate` is reset to the most-recent `settings.weekStartDay`-aligned date at or before `startOfDay(Date())`, `endDate` is `nil`

#### Scenario: Add mode period change to specificDates clears both dates

- **WHEN** the user toggles `period` to `.specificDates`
- **THEN** both `startDate` and `endDate` become `nil`

#### Scenario: Edit mode period.didSet does not re-anchor dates

- **WHEN** `AddEditBudgetViewModel(editing: budget)` is invoked and `period` is mutated programmatically to a different value
- **THEN** `startDate` and `endDate` retain their seeded values (the `!isEditing` guard short-circuits `onPeriodChange`)

#### Scenario: Edit mode dates are seeded from the budget for any period type

- **WHEN** `AddEditBudgetViewModel(editing: budget)` is invoked for a `.weekly` budget with `budget.startDate == 2026-04-13` and `budget.endDate == nil`
- **THEN** the constructed VM has `startDate == 2026-04-13` and `endDate == nil`

- **WHEN** `AddEditBudgetViewModel(editing: budget)` is invoked for a `.specificDates` budget with `budget.startDate == 2026-05-08` and `budget.endDate == 2026-05-25`
- **THEN** the constructed VM has `startDate == 2026-05-08` and `endDate == 2026-05-25`

#### Scenario: startDate.didSet snaps endDate forward when crossing

- **WHEN** `viewModel.startDate == 2026-05-01`, `viewModel.endDate == 2026-05-10`, and the user sets `startDate = 2026-05-15`
- **THEN** `endDate` is snapped forward to preserve the original 9-day duration (i.e. `2026-05-24`)

### Requirement: Schedule disclosure card for recurring period types

When and only when `viewModel.period` is one of `.daily`, `.weekly`, `.biweekly`, `.monthly` (i.e. NOT `.specificDates`), the Add/Edit Budget screen SHALL render a `Schedule` card in the slot directly below the Period card and above the Carry-Over card. The card SHALL surface the budget's `startDate` and optional `endDate` via a collapsed-by-default disclosure.

The card SHALL be implemented in `simple-recurring-budgets/Views/AddEditBudgetView+Schedule.swift` as an extension on `AddEditBudgetView`, accessed by the main view's body composition (`if isSpecificDates { datesCard } else { scheduleCard; carryOverCard }`). The collapsed/expanded state SHALL be held in `AddEditBudgetView.isScheduleExpanded` (`@State var isScheduleExpanded: Bool = false`, cross-file-extension access).

**Collapsed-disclosure summary row.** The collapsed state SHALL render a single subdued summary line followed by a trailing `chevron.down` (SF Symbol, `.font(.caption)`, `.foregroundStyle(.secondary)`). The chevron SHALL rotate 180 degrees on expansion via `.rotationEffect(.degrees(isScheduleExpanded ? 180 : 0))`, animated with `.easeInOut(duration: 0.2)` keyed to `isScheduleExpanded`. The whole row SHALL be a single tap target (a `Button` with `.buttonStyle(.plain)` and `.contentShape(Rectangle())`).

The summary SHALL be built from two fragments concatenated with `" · "`:

- **Start fragment** — `"Starts {formatted}"` when `viewModel.startDate` is non-`nil` (key `addEditBudget.schedule.summary.start.set`, where `{formatted}` is `viewModel.startDate!.formatted(date: .abbreviated, time: .omitted)`); otherwise `"Starts today"` (key `addEditBudget.schedule.summary.start.today`).
- **End fragment** — `"Ends {formatted}"` when `viewModel.endDate` is non-`nil` (key `addEditBudget.schedule.summary.end.set`); otherwise `"No end date"` (key `addEditBudget.schedule.summary.end.none`).

**Expanded state.** When `isScheduleExpanded == true`, two `DateColumn` chips SHALL render side-by-side inside an `HStack(alignment: .top, spacing: 12)` directly below the disclosure row, separated by 12 pt of vertical padding. The `DateColumn` struct (defined in `AddEditBudgetView+SpecificDates.swift`) SHALL be reused as-is. The start-date chip SHALL bind to `$viewModel.startDate` with `minDate: nil` and placeholder key `addEditBudget.field.date.start.recurring.placeholder` (en-US source: "Today"). The end-date chip SHALL bind to `$viewModel.endDate` with `minDate: viewModel.startDate` and placeholder key `addEditBudget.field.date.end.recurring.placeholder` (en-US source: "No end date").

**Clear-end-date affordance.** When `viewModel.endDate != nil`, a small "Clear end date" button (key `addEditBudget.schedule.action.clearEndDate`, en-US source: "Clear end date") SHALL render below the chip row, right-aligned (`.frame(maxWidth: .infinity, alignment: .trailing)`), styled `.font(.caption).foregroundStyle(.secondary)`. Tapping it SHALL set `viewModel.endDate = nil`. The button SHALL NOT render for `.specificDates` budgets (which use a different card).

**Animation.** Expanded content SHALL appear with `.transition(.opacity.combined(with: .move(edge: .top)))` animated by `.easeInOut(duration: 0.2)` keyed to `isScheduleExpanded`.

**Accessibility.** The disclosure row SHALL declare an `accessibilityLabel` (key `addEditBudget.schedule.disclosure.accessibilityLabel.format`, en-US source: "Schedule. {summary}", where `{summary}` is the resolved summary text) and an `accessibilityHint` (key `addEditBudget.schedule.disclosure.accessibilityHint`, en-US source: "Tap to show or hide the start date and end date controls."). The expanded `DateColumn` chips inherit their existing accessibility wiring from the shared `DateColumn` struct.

**Specific Dates fallback.** This requirement applies only to recurring period types. For `.specificDates` the existing always-visible `Dates` card (see "Specific Dates conditional UI") continues to govern.

#### Scenario: Recurring Add opens with Schedule collapsed

- **WHEN** the user opens Add for a default-period (`.daily`) budget
- **THEN** the Schedule card renders directly below the Period card, the disclosure row reads "Starts {today, abbreviated} · No end date" (the start fragment uses the set form because `startDate` is pre-filled per the "Add mode seeds defaults" requirement), the trailing chevron points down, and the chip area is not rendered

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

### Requirement: Cancel dismisses without persisting any changes

When the user activates the Cancel toolbar button (in either Add or Edit mode), the system SHALL dismiss the sheet without inserting, mutating, or saving any `Budget`. Any in-flight draft state SHALL be discarded.

#### Scenario: Cancel from Add mode inserts no budget

- **WHEN** the user opens the Add sheet, types a name, sets an allocation, and taps Cancel
- **THEN** no `Budget` is inserted into the store

#### Scenario: Cancel from Edit mode does not mutate the budget

- **WHEN** the user opens the Edit sheet for an existing `Budget`, changes the name and allocation in the form, and taps Cancel
- **THEN** the `Budget` in the store retains its original values, and `lastModified` is unchanged

### Requirement: Currency picker is searchable and sourced from Foundation's catalog

The currency pill on the Allocation card SHALL present a `CurrencyPickerView` as a sheet-on-sheet (i.e. a child sheet hosted by the Add/Edit Budget sheet) when activated. The picker SHALL:

- Source its list of ISO-4217 codes from `Locale.commonISOCurrencyCodes` (Foundation-provided, system-maintained — this satisfies F-3.04's "stored outside source code" criterion in its updated form).
- Sort the list ascending by code.
- For each code, render the code on the leading edge and a localized currency name on the trailing edge. The localized name SHALL come from `Locale.current.localizedString(forCurrencyCode: code)`; if the lookup returns `nil` or an empty string, the row SHALL fall back to displaying only the code.
- Provide a `.searchable(text:)` field with prompt `"Search currencies"` (key `currencyPicker.search.prompt`). The filter SHALL match a search query against either the code (case-insensitive prefix or `localizedCaseInsensitiveContains`) OR the localized name (`localizedCaseInsensitiveContains`).
- Indicate the currently-selected code with a checkmark adornment and the `selected` accessibility value (key `currencyPicker.row.selected.accessibilityValue`).
- Tapping a row SHALL set the parent `AddEditBudgetViewModel.currencyCode` to that code and dismiss the picker. Tapping a leading toolbar Cancel button (key `addEditBudget.action.cancel` reused) SHALL dismiss the picker without changing the selection.

The picker's navigation title SHALL be the localized string `"Currency"` (key `currencyPicker.navigationTitle`), displayed inline.

The picker SHALL NOT introduce any project-owned currency catalog file. If a future change needs codes that Foundation's catalog does not provide, F-3.04's relaxed wording allows adding such a file then.

#### Scenario: Picker lists all Foundation-provided ISO codes

- **WHEN** the user opens the currency picker
- **THEN** the list contains exactly the codes returned by `Locale.commonISOCurrencyCodes`, sorted ascending, with no codes added or omitted by the app

#### Scenario: Selecting a row updates the parent and dismisses

- **WHEN** the user taps the row for `"GBP"` in the picker
- **THEN** the parent `AddEditBudgetViewModel.currencyCode` becomes `"GBP"`, the picker dismisses, and the Allocation card's currency pill displays `"GBP"`

#### Scenario: Cancel does not change the selection

- **WHEN** the user opens the picker with `"USD"` selected, taps a different row's chevron, then taps Cancel before tapping a row
- **THEN** the parent's `currencyCode` remains `"USD"` and the picker dismisses

#### Scenario: Search filters by code prefix

- **WHEN** the user types `"eu"` in the search field
- **THEN** the list contains rows whose code starts with `EU` (case-insensitive), e.g. `EUR`, AND any rows whose localized name contains `"eu"` (case-insensitive), e.g. `"Euro"`

#### Scenario: Localized name fallback

- **WHEN** `Locale.current.localizedString(forCurrencyCode:)` returns `nil` for some code
- **THEN** that row SHALL still render with the code and remain searchable by code

### Requirement: User-visible strings are registered in Localizable.xcstrings

Every user-visible string introduced by `AddEditBudgetView` and `CurrencyPickerView` SHALL use `String(localized: "key", defaultValue: "...", comment: "translator context")` (or `Text(LocalizedStringKey)` where idiomatic) with a stable kebab/dot-cased key, an English source default value, and a translator `comment`. Strings SHALL be present in `simple-recurring-budgets/Resources/Localizable.xcstrings` after the build.

The screen-namespaced key prefix SHALL be `addEditBudget.*` for the sheet itself and `currencyPicker.*` for the inner picker. Keys SHALL NOT be reused from unrelated namespaces (e.g., the existing `toolbar.addBudget.*` keys are list-screen toolbar buttons, not sheet content).

#### Scenario: Every label has a localizable key with a comment

- **WHEN** the app is built
- **THEN** `Localizable.xcstrings` contains one entry per user-visible string introduced by the Add/Edit Budget screen and the currency picker, each with a non-empty `comment` providing translator context

#### Scenario: Sheet titles use namespaced keys

- **WHEN** the sheet is opened in Add or Edit mode
- **THEN** the navigation title is sourced from `addEditBudget.title.add` or `addEditBudget.title.edit` respectively, not from a generic top-level English literal

### Requirement: Mockup files are removed once the production screen ships

The system SHALL NOT contain any of the throwaway mockup files under `simple-recurring-budgets/Views/_Mockups/AddEditBudget/` after this change is shipped. Specifically, the following files SHALL be removed:

- `Views/_Mockups/AddEditBudget/MockupA_GroupedForm.swift`
- `Views/_Mockups/AddEditBudget/MockupB_CardLayout.swift`
- `Views/_Mockups/AddEditBudget/MockupC_FlowLayout.swift`
- `Views/_Mockups/AddEditBudget/MockupShared.swift`

The `Views/_Mockups/AddEditBudget/` and `Views/_Mockups/` directories SHALL NOT exist after this change is shipped.

The deletion SHALL be reviewed by the implementer for residual references (e.g., `BudgetPeriod.mockPerLabel` defined in `MockupShared.swift`); no production file SHALL retain a reference to a deleted symbol after this change.

#### Scenario: Mockup directory is gone

- **WHEN** the change is applied
- **THEN** `simple-recurring-budgets/Views/_Mockups/` does not exist in the repository

#### Scenario: No production code references mockup symbols

- **WHEN** the change is applied
- **THEN** no production source file references `DraftBudget`, `CurrencyPickerStub`, `MockupA_GroupedForm`, `MockupB_CardLayout`, `MockupC_FlowLayout`, or `BudgetPeriod.mockPerLabel`

### Requirement: Screen escalates to an @Observable ViewModel per tech-design §2.1

The Add/Edit Budget screen SHALL use an `@Observable AddEditBudgetViewModel` owned by the view as `@State`. The VM SHALL hold draft state and pure logic only; it SHALL NOT store `ModelContext`, SHALL NOT store `AppSettings`, SHALL NOT hold `@Query` results, and SHALL NOT fetch.

The VM SHALL accept `AppSettings` only in `init(settings:)` for the Add-mode default seeding (specifically `isCarryOverEnabled = settings.defaultCarryOverEnabled`), and SHALL NOT retain a reference to it after `init` returns. The VM's save method takes `(context: ModelContext)` only — see the dedicated "VM exposes a save method that takes ModelContext at the call site" requirement above.

This pattern follows `docs/tech-design-doc.md` §2.1's VM rules, which apply because:

- Escalation criterion #1 — non-trivial draft/form state not persisted until commit — is satisfied.
- Grey-area trigger "more than 3 mutable form fields" is satisfied (5 fields).

#### Scenario: VM does not own ModelContext

- **WHEN** `AddEditBudgetViewModel` is inspected
- **THEN** it has no stored property of type `ModelContext` and no `init(context:)` taking a `ModelContext`; its `save(...)` method receives the context as a parameter at the call site

#### Scenario: VM does not retain AppSettings after init

- **WHEN** `AddEditBudgetViewModel` is inspected
- **THEN** it has no stored property of type `AppSettings`; `init(settings:)` reads `settings.defaultCarryOverEnabled` once for Add-mode seeding and does not capture the reference

#### Scenario: VM is testable in isolation

- **WHEN** a test constructs an `AddEditBudgetViewModel` and invokes `save(context:)` against an in-memory `ModelContainer`
- **THEN** the test exercises the full save logic without instantiating any SwiftUI view hierarchy and without needing an `AppSettings` instance for the save call

### Requirement: Delete Budget button is rendered only in Edit mode

The Add/Edit Budget screen SHALL render a destructive **Delete Budget** button beneath the four cards (Name, Allocation, Period, Carry-Over) when, and only when, the screen is in Edit mode (`viewModel.isEditing == true`). In Add mode the button SHALL NOT be rendered or rendered hidden — there must be no Delete affordance for a draft `Budget` that has not yet been inserted.

The button SHALL be rendered with `.buttonStyle(.bordered)`, tinted red (`.tint(.red)` / destructive role), with its label expanded across the available width via `.frame(maxWidth: .infinity)` to match a full-width destructive footer pattern. The label text SHALL come from the localized key `addEditBudget.action.delete` with English source value `"Delete Budget"`.

The button SHALL declare a VoiceOver hint sourced from `addEditBudget.action.delete.accessibilityHint` (English source `"Permanently deletes this budget and its expenses."`) so assistive-tech users learn the consequence of activation before tapping. No explicit `accessibilityLabel` override is needed; VoiceOver synthesises the label from the button's visible text (`addEditBudget.action.delete`).

#### Scenario: Add mode does not show the Delete button

- **WHEN** the sheet is presented in Add mode (`viewModel.isEditing == false`)
- **THEN** there is no Delete Budget button anywhere on the screen, in the toolbar, or beneath the cards

#### Scenario: Edit mode shows the Delete button below the cards

- **WHEN** the sheet is presented in Edit mode for some `Budget`
- **THEN** a destructive bordered button labeled `"Delete Budget"` (key `addEditBudget.action.delete`) is rendered beneath the four cards, full-width, with `.tint(.red)` and `role: .destructive`

#### Scenario: VoiceOver announces destructive hint

- **WHEN** VoiceOver focuses the Delete Budget button in Edit mode
- **THEN** it announces the hint from `addEditBudget.action.delete.accessibilityHint` in addition to its destructive button trait; the label is synthesised from the button's visible text and no separate `accessibilityLabel` override is applied

### Requirement: Delete Budget action requires a destructive confirmation dialog

Activating the Delete Budget button SHALL present a `confirmationDialog` with `titleVisibility: .visible`. The dialog SHALL expose exactly one explicit button: a destructive confirm button. SwiftUI's implicit Cancel button SHALL provide the cancel path; the implementation SHALL NOT add a redundant cancel button. No other dialog buttons SHALL be added.

- The dialog title SHALL come from `addEditBudget.deleteConfirmation.title` (English source `"Delete Budget?"`).
- The dialog message body SHALL come from `addEditBudget.deleteConfirmation.message` (English source `"This action cannot be undone."`) and SHALL be rendered as a `Text` view in the `message:` trailing closure of `confirmationDialog(_:isPresented:titleVisibility:actions:message:)`.
- The destructive confirm button label SHALL come from `addEditBudget.deleteConfirmation.confirm` (English source `"Delete Budget"`) with `role: .destructive`.

The dialog SHALL be presented from the `AddEditBudgetView` (sheet root) so it is anchored to the form, and SHALL be driven by a private `@State` flag on the view that the Delete button toggles to `true`.

#### Scenario: Tapping Delete opens the confirmation dialog without deleting

- **WHEN** the user taps the Delete Budget button in Edit mode
- **THEN** a confirmation dialog appears with the title from `addEditBudget.deleteConfirmation.title`, the message body from `addEditBudget.deleteConfirmation.message`, a destructive confirm button from `addEditBudget.deleteConfirmation.confirm`, and SwiftUI's implicit Cancel; no `Budget` has been deleted yet and the sheet remains on screen

#### Scenario: Cancelling the dialog leaves the budget intact

- **WHEN** the user opens the confirmation dialog and dismisses it via SwiftUI's implicit Cancel (e.g., taps Cancel or taps outside the dialog where the platform allows)
- **THEN** the editing `Budget` is not deleted, no `ModelContext.save()` is invoked as a result of the dialog interaction, and the sheet remains in Edit mode with all in-flight draft state intact

#### Scenario: Confirming the dialog deletes the budget and dismisses the sheet

- **WHEN** the user taps the destructive confirm button in the dialog
- **THEN** `viewModel.delete(context:)` is invoked with the view's `@Environment(\.modelContext)`, and the sheet is dismissed via `dismiss()` after the VM call returns

### Requirement: ViewModel exposes a delete method that takes ModelContext at the call site

The `AddEditBudgetViewModel` SHALL expose `func delete(context: ModelContext)` with the following contract:

- In **Edit mode**, the method SHALL invoke `context.delete(budget)` for the editing `Budget` and SHALL invoke `try? context.save()` once.
- In **Add mode**, the method SHALL be a no-op: it SHALL NOT call `context.delete`, SHALL NOT call `context.save`, and SHALL NOT mutate any state.

The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The VM SHALL NOT consult `AppSettings` from `delete(...)` — `AppSettings` is read only at construction time via `init(settings:)` for Add-mode seeding, consistent with the existing save contract on the same VM.

The method SHALL rely on the existing `Budget → ExpenseItem` cascade-delete relationship (`@Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)`) to remove the budget's `ExpenseItem` rows. The VM SHALL NOT manually fetch or delete child `ExpenseItem` instances.

#### Scenario: Delete in Edit mode removes the budget and saves once

- **WHEN** a test constructs an `AddEditBudgetViewModel` in Edit mode for an existing `Budget` and invokes `delete(context:)` against an in-memory `ModelContext`
- **THEN** the `Budget` is removed from the store, `context.save()` is invoked exactly once, and the in-memory `ModelContext` no longer returns the budget from a `FetchDescriptor<Budget>` query

#### Scenario: Delete is a no-op in Add mode

- **WHEN** a test constructs an `AddEditBudgetViewModel` in Add mode (`init(settings:)`) and invokes `delete(context:)` against an in-memory `ModelContext` that contains zero or more pre-existing `Budget` rows
- **THEN** the in-memory store contents are unchanged: no `Budget` is inserted, deleted, or mutated, and `context.save()` is not invoked as a result of the call

#### Scenario: Delete cascades to ExpenseItem rows in a single save

- **WHEN** a test constructs an `AddEditBudgetViewModel` in Edit mode for a `Budget` that owns one or more `ExpenseItem` rows, and invokes `delete(context:)` against an in-memory `ModelContext`
- **THEN** after the call returns, neither the `Budget` nor any of its `ExpenseItem` rows can be fetched from the store; the cascade SHALL be performed by the SwiftData relationship's `deleteRule: .cascade`, not by any manual VM-side traversal

### Requirement: Localizable.xcstrings registers the Delete Budget-related keys

`Localizable.xcstrings` SHALL contain entries for every user-visible string introduced by the Delete Budget feature, each with a non-empty translator `comment`:

- `addEditBudget.action.delete` — Delete Budget button label (also serves as the VoiceOver label via synthesis).
- `addEditBudget.action.delete.accessibilityHint` — VoiceOver hint announcing the destructive consequence.
- `addEditBudget.deleteConfirmation.title` — Confirmation dialog title.
- `addEditBudget.deleteConfirmation.message` — Confirmation dialog message body ("This action cannot be undone.").
- `addEditBudget.deleteConfirmation.confirm` — Destructive confirm button label inside the dialog.

Each key SHALL use the screen-namespaced `addEditBudget.*` prefix already defined for the Add/Edit Budget sheet.

#### Scenario: Catalog contains all Delete Budget localization keys with translator comments

- **WHEN** the app is built
- **THEN** `simple-recurring-budgets/Resources/Localizable.xcstrings` contains entries for `addEditBudget.action.delete`, `addEditBudget.action.delete.accessibilityHint`, `addEditBudget.deleteConfirmation.title`, `addEditBudget.deleteConfirmation.message`, and `addEditBudget.deleteConfirmation.confirm`, and every entry has a non-empty `comment`

#### Scenario: Delete keys reuse the addEditBudget namespace

- **WHEN** an inspector reads the keys introduced by the Delete Budget feature
- **THEN** every key starts with `addEditBudget.`; no key is hoisted into a generic top-level namespace, and no other namespace is reused for delete-related copy

