## ADDED Requirements

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

## MODIFIED Requirements

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
