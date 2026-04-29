<!--
  This delta introduces the `add-edit-budget-screen` capability for the first
  time. It codifies the F-2.03 acceptance criteria as implemented by this
  change, EXCLUDING the paused Reset Cadence bullets (per docs/main-prd.md §6.7
  and the F-2.03 PAUSED callout in docs/product-features-planning.md). The
  capability owns the screen-level requirements for Add and Edit modes,
  validation, persistence semantics, the in-sheet currency picker, the
  carry-over toggle's behaviour on this screen (per F-2.07's Add/Edit Budget
  acceptance criterion only — Settings-screen behaviour is out of scope), and
  the screen's accessibility / localization expectations.

  This capability does NOT redefine global currency policy (F-3.04) or the
  carry-over math (PRD §6.7 / `budget-lifecycle`); those remain authoritative
  in their own specs.
-->

## ADDED Requirements

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

The Add/Edit Budget screen SHALL collect exactly five user-editable fields, organised into four cards (Name, Allocation, Period, Carry-Over) per `docs/ux-design-brief.md` and the chosen design (`MockupB_CardLayout`). Reset Cadence SHALL NOT appear on this screen while the feature is paused (per `docs/main-prd.md` §6.7 PAUSED callout).

The fields are:

- **Name** (`String`) — bound to a single-line `TextField` in the Name card. Placeholder `"Budget"` (key `addEditBudget.field.name.placeholder`). Accessibility label `"Budget name"` (key `addEditBudget.field.name.accessibilityLabel`).
- **Allocation** (`Decimal`) — bound to a `Decimal`-typed `TextField` (using SwiftUI's `TextField(_:value:format:)` with `.number` format style and `.fractionLength(0...2)`) in the Allocation card. Placeholder `"0"`. Keyboard type SHALL be `.decimalPad`. Accessibility label SHALL announce the formatted amount with the budget's currency code (key `addEditBudget.field.allocation.accessibilityLabel`). The formatted amount SHALL be produced by the canonical `Decimal.formatted(currencyCode:display:locale:)` method, passing `display: settings.currencyDisplay` so the announcement honours the user's app-wide currency-display preference (`AppSettings.currencyDisplay`, governed by the `app-settings` capability). The view SHALL read `AppSettings` via `@Environment(AppSettings.self)` and recompute the label whenever `settings.currencyDisplay`, `viewModel.allocation`, or `viewModel.currencyCode` changes.
- **Currency** (`String`, ISO-4217 code) — selected via a currency pill button on the Allocation card; the pill displays the current code with a `chevron.up.chevron.down` SF Symbol and opens the currency picker on activation. Accessibility label `"Currency, <code>"` (key `addEditBudget.field.currency.accessibilityLabel`); accessibility hint `"Opens currency picker"` (key `addEditBudget.field.currency.accessibilityHint`).
- **Period** (`BudgetPeriod`) — selected via a 2×2 grid of chip buttons in the Period card, one per `BudgetPeriod` case (`.daily`, `.weekly`, `.biweekly`, `.monthly`). The selected chip SHALL render with the accent colour fill and white foreground, with `.fontWeight(.semibold)`; unselected chips SHALL render with a low-opacity secondary background and primary foreground, with `.fontWeight(.regular)`. Each chip SHALL declare `.accessibilityAddTraits(.isSelected)` when it is the active selection. Each chip SHALL provide a per-period accessibility label (key `addEditBudget.chip.period.accessibilityLabel`, e.g. `"Daily period"`).
- **Carry-Over** (`Bool`) — a `Toggle` in the Carry-Over card titled `"Carry-Over"` (key `addEditBudget.section.carryOver`). The toggle SHALL be tinted with the accent colour. A short caption (key `addEditBudget.note.carryOver`) SHALL render below the toggle in both on and off states (per `docs/main-prd.md` §6.7: the underlying carry-over figure is maintained internally even when display is off, so the caption remains accurate either way).

#### Scenario: All five fields render in their cards

- **WHEN** the sheet is visible in either Add or Edit mode
- **THEN** the screen displays four cards in this order: Name, Allocation, Period, Carry-Over; the Allocation card contains both the amount field and the currency pill; the Period card contains the 2×2 chip grid; the Carry-Over card contains the toggle and the caption

#### Scenario: Reset Cadence is not surfaced

- **WHEN** the sheet is visible in either Add or Edit mode
- **THEN** there is no UI that lets the user view, select, or change a Reset Cadence; the Carry-Over card contains only the toggle and caption (Reset Cadence is paused per `docs/main-prd.md` §6.7)

#### Scenario: Allocation field uses a Decimal-typed binding with locale-aware format

- **WHEN** the user enters a number in the Allocation `TextField`
- **THEN** SwiftUI parses it via the `.number` `FormatStyle` against the user's current `Locale`, accepting locale-appropriate decimal separators (e.g. `.` or `,`); the underlying state is `Decimal`, never `String`

#### Scenario: Allocation accessibility label respects AppSettings.currencyDisplay

- **WHEN** the user changes `AppSettings.currencyDisplay` (e.g. from `.symbol` to `.code`) while the Add/Edit Budget sheet is open
- **THEN** the Allocation field's VoiceOver label SHALL re-render so its formatted-amount component reflects the new preference (e.g. `"USD 25.00"` for `.code` instead of `"$25.00"` for `.symbol` when the budget's `currencyCode` is `"USD"`); the announcement SHALL be produced by `Decimal.formatted(currencyCode: viewModel.currencyCode, display: settings.currencyDisplay)` and not by any other formatter

#### Scenario: Period chip selection is exclusive and announced to VoiceOver

- **WHEN** the user taps a period chip
- **THEN** that period becomes the selected one; the previously-selected chip drops its `isSelected` accessibility trait; the new chip gains the `isSelected` trait; only one chip carries the trait at any time

### Requirement: Add mode seeds defaults from Budget.init and AppSettings

In Add mode, the form fields SHALL be initialised with the following defaults at sheet-open time, all of which are evaluated **once** when the `AddEditBudgetViewModel` is constructed:

- `name = "Budget"` (matches `Budget.init`).
- `allocation = 10` (`Decimal`; matches `Budget.init`).
- `currencyCode = Locale.current.currency?.identifier ?? "USD"` (matches `Budget.init`).
- `period = BudgetPeriod.daily` (matches `Budget.init` and F-2.03).
- `isCarryOverEnabled = settings.defaultCarryOverEnabled` (per F-2.07: new budgets pick up the global default at construction time).

The defaults SHALL NOT update reactively in response to changes in `AppSettings` after the sheet opens; the user can flip the per-budget Carry-Over toggle on the sheet if they want a value different from the global default.

#### Scenario: Add mode opens with documented defaults

- **WHEN** the sheet opens in Add mode with `settings.defaultCarryOverEnabled == true`
- **THEN** the form shows: name `"Budget"`, allocation `10`, currency code from the user's locale (or `"USD"` if locale lookup returns `nil`), period `Daily` selected, Carry-Over toggle ON

#### Scenario: Add mode picks up the AppSettings carry-over default at construction

- **WHEN** the sheet is constructed while `settings.defaultCarryOverEnabled == false`
- **THEN** the Carry-Over toggle initial value is `false`

### Requirement: Edit mode seeds form fields from the existing Budget

In Edit mode, every editable form field SHALL be seeded from the corresponding field of the `Budget` passed to the sheet, evaluated **once** at sheet-open time:

- `name` from `Budget.name`.
- `allocation` from `Budget.allocation`.
- `currencyCode` from `Budget.currencyCode`.
- `period` from `BudgetPeriod(rawValue: Budget.period) ?? .daily` (defensive decoding for forward-compat with unknown raw values).
- `isCarryOverEnabled` from `Budget.isCarryOverEnabled`.

The view SHALL hold a reference to the passed-in `Budget` so that Save in Edit mode can mutate the same instance. Cancel SHALL NOT mutate the `Budget`.

#### Scenario: Edit mode pre-fills from the budget

- **WHEN** the sheet is presented for an existing `Budget` named "Coffee" with allocation `7`, currency `"USD"`, period `.weekly`, and carry-over enabled
- **THEN** the form shows: name `"Coffee"`, allocation `7`, currency `USD`, the Weekly chip selected, Carry-Over toggle ON

#### Scenario: Edit mode tolerates unknown stored period raw values

- **WHEN** the sheet is presented for a `Budget` whose stored `period` raw value does not match any `BudgetPeriod` case (e.g., a value introduced by a future schema)
- **THEN** the form falls back to selecting `Daily` rather than crashing

### Requirement: Save is enabled only when validation passes

The Save toolbar button SHALL be enabled if and only if **both** of the following are true:

- The trimmed name is non-empty: `name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false`.
- The allocation is strictly positive: `allocation > 0`.

When either condition fails, the Save button SHALL be disabled. Disabled state SHALL use the system disabled appearance; no inline error text is displayed in either MockupB or this implementation.

#### Scenario: Empty name disables Save

- **WHEN** the user clears the Name field, leaving only whitespace or an empty string
- **THEN** the Save button is disabled

#### Scenario: Zero allocation disables Save

- **WHEN** the user sets the allocation to `0`
- **THEN** the Save button is disabled, even if the name is non-empty

#### Scenario: Positive allocation and non-empty name enable Save

- **WHEN** the trimmed name is non-empty AND the allocation is `> 0`
- **THEN** the Save button is enabled

### Requirement: VM exposes a save method that takes ModelContext at the call site

The `AddEditBudgetViewModel` SHALL expose `func save(context: ModelContext)` that performs the Add or Edit branch documented below. The view SHALL read `@Environment(\.modelContext)` and invoke `viewModel.save(context: context)` from inside `body`, then call `dismiss()`. The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The save body SHALL NOT consult `AppSettings` — `AppSettings` is read only at construction time via `init(settings:)` to seed the Add-mode Carry-Over default (per `docs/tech-design-doc.md` §2.1: "Methods that need to write take `(context: ModelContext, ...)` at the call site (and `AppSettings` similarly when relevant)" — for the save body, `AppSettings` is not relevant).

#### Scenario: Save method signature does not include AppSettings

- **WHEN** the `AddEditBudgetViewModel.save(...)` method is inspected
- **THEN** its signature SHALL be `func save(context: ModelContext)`; `AppSettings` SHALL NOT be a parameter of `save`

### Requirement: Save in Add mode inserts a new Budget with the next sortOrder

When the user activates Save in Add mode, the system SHALL:

1. Build a `Budget` using `Budget.init(name:allocation:currencyCode:period:resetCadence:isCarryOverEnabled:)` with: the drafted `name` (post-trim, but the model stores the user's value as entered; trimming is for validation only), the drafted `allocation`, the drafted `currencyCode`, the drafted `period`, `resetCadence: nil` (Reset Cadence is paused; `Budget.init` defaults to `.never`), and the drafted `isCarryOverEnabled`.
2. Set `budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0` BEFORE inserting, so the fetch does not include the new instance.
3. Call `context.insert(budget)`.
4. Call `try? context.save()`.
5. Dismiss the sheet.

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

### Requirement: Save in Edit mode mutates only changed fields and bumps lastModified once

When the user activates Save in Edit mode, the system SHALL compare each editable field on the existing `Budget` to its corresponding draft value. For each field whose stored value differs from the draft value, the system SHALL write the draft value back to the `Budget`. The system SHALL set `Budget.lastModified = Date()` exactly once if at least one field changed. If no field changed, the system SHALL NOT mutate `Budget.lastModified` and SHALL NOT call `context.save()`. After mutating any field, the system SHALL call `try? context.save()` and dismiss the sheet.

The fields compared are: `name`, `allocation`, `currencyCode`, `period` (compared as raw values), and `isCarryOverEnabled`. The system SHALL NOT touch any other persisted field of `Budget` (notably `carryOverAmount`, `carryOverLastProcessedDate`, `carryOverLastResetDate`, `resetCadence`, `sortOrder`, `createdAt`).

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
