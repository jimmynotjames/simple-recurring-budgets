## ADDED Requirements

### Requirement: Orphan-expense warning on Save when startDate moves past existing expenses

When the user activates the Save toolbar button in Edit mode on a recurring-period budget AND the drafted `viewModel.startDate` (normalized via `calendar.startOfDay`) is **after** the `date` of at least one item in `Budget.expenseItems`, the system SHALL present a confirmation alert before invoking `viewModel.save(...)`. The user SHALL be able to either cancel (returning to the form with all draft state intact) or confirm (proceeding to the existing save path unchanged).

The alert's title SHALL be the localized string for key `addEditBudget.orphanWarning.title` (en-US source: `"Start date is after \(count) logged expenses"`, where `count` is the number of items in `Budget.expenseItems` whose `date` is before the drafted `startDate`). The alert's message SHALL be the localized string for key `addEditBudget.orphanWarning.message` (en-US source: `"Those expenses still show in your list but won't be counted by this budget."`). The cancel button SHALL use key `addEditBudget.orphanWarning.cancel` (en-US source: `"Cancel"`, `role: .cancel`). The confirm button SHALL use key `addEditBudget.orphanWarning.confirm` (en-US source: `"Save Changes"`) and SHALL invoke the same `viewModel.save(...)` + `dismiss()` sequence the bare Save toolbar button invokes today.

The count SHALL be exposed on `AddEditBudgetViewModel` as a computed property `var orphanedExpenseCount: Int` that returns `0` in Add mode (no bound budget) and when `startDate == nil`, and otherwise returns `budget.expenseItems.count(where: { $0.date < startDate })` (equivalent to `filter { ... }.count`; the predicate is the contract). The view SHALL gate the Save toolbar button's action through this property: if `orphanedExpenseCount > 0` it SHALL set a presentation-state `@State var showOrphanWarning = true`; otherwise it SHALL invoke save directly.

The alert SHALL NOT replace or duplicate any existing save-side-effect behavior — the existing `viewModel.save(context:analytics:settings:router:)` method, its persistence logic, and the `dismiss()` call SHALL fire from the confirm branch exactly as they fire today from a bare Save tap.

The alert SHALL NOT fire in Add mode (where `orphanedExpenseCount` is always `0`).

The alert SHALL fire across every period type — including `.specificDates` — wherever an Edit-mode `startDate` change orphans at least one existing expense. (The inline Schedule-disclosure warning is recurring-only, because Specific Dates uses the Dates card rather than the Schedule disclosure; the Save-time alert is the cross-period surface.)

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

#### Scenario: orphanedExpenseCount is zero when startDate equals the earliest expense date

- **WHEN** the drafted `startDate` is exactly equal to the `date` of the earliest expense (boundary equality, not strictly after)
- **THEN** `orphanedExpenseCount == 0` and no alert is presented (the filter is `$0.date < startDate`, half-open at the start)

## MODIFIED Requirements

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

**Auto-expand on appear.** The main view's `onAppear` SHALL set `isScheduleExpanded = true` when `viewModel.orphanedExpenseCount > 0` at the moment the sheet appears. This ensures a user re-opening Edit on a budget already in the orphaning state sees the inline warning without an extra tap. The auto-expand SHALL NOT fire when `orphanedExpenseCount == 0` (the collapsed default is preserved for the common case). It SHALL fire after the existing `onAppear` side effects (`initialCurrencyCode` capture, name-field focus seeding).

**Animation.** Expanded content SHALL appear with `.transition(.opacity.combined(with: .move(edge: .top)))` animated by `.easeInOut(duration: 0.2)` keyed to `isScheduleExpanded`.

**Accessibility.** The disclosure row SHALL declare an `accessibilityLabel` (key `addEditBudget.schedule.disclosure.accessibilityLabel.format`, en-US source: "Schedule. {summary}", where `{summary}` is the resolved summary text) and an `accessibilityHint` (key `addEditBudget.schedule.disclosure.accessibilityHint`, en-US source: "Tap to show or hide the start date and end date controls."). The expanded `DateColumn` chips inherit their existing accessibility wiring from the shared `DateColumn` struct. The inline orphan warning SHALL be a plain `Text` and inherit default VoiceOver behavior.

**Specific Dates fallback.** This requirement applies only to recurring period types. For `.specificDates` the existing always-visible `Dates` card (see "Specific Dates conditional UI") continues to govern. The inline orphan warning SHALL NOT render for `.specificDates` (the Schedule card is not rendered for that period type at all).

#### Scenario: Recurring Add opens with Schedule collapsed

- **WHEN** the user opens Add for a default-period (`.daily`) budget
- **THEN** the Schedule card renders directly below the Period card, the disclosure row reads "Starts {today, abbreviated} · No end date" (the start fragment uses the set form because `startDate` is pre-filled per the "Add mode seeds defaults" requirement), the trailing chevron points down, the chip area is not rendered, and (because Add mode has no `expenseItems`) the auto-expand-on-orphan behavior does not fire

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

#### Scenario: Re-opening Edit on a non-orphaning budget preserves the collapsed default

- **WHEN** the user opens Edit for a budget whose persisted `Budget.startDate` is at or before every `expenseItems.date` (or there are no expenses)
- **THEN** on `onAppear` the Schedule disclosure is rendered collapsed (the default behavior); the auto-expand does not fire

### Requirement: budget_edited analytics event carries per-field change flags

When `AddEditBudgetViewModel.saveEdit` writes one or more fields back to the existing `Budget`, the emitted `AnalyticsEvent.budgetEdited` properties bag SHALL include per-field boolean flags identifying which fields changed in this Save:

- `allocation_changed: Bool` — `true` iff the drafted `allocation` differed from `Budget.currentAllocation` and was written.
- `start_date_changed: Bool` — `true` iff the normalized `viewModel.startDate` differed from `Budget.startDate` and was written.
- `end_date_changed: Bool` — `true` iff the normalized `viewModel.endDate` differed from `Budget.endDate` and was written (this includes the "user cleared an optional end date" path, recurring only).

Additionally, when at least one item in `Budget.expenseItems` has a `date` before the **written** `Budget.startDate` (post-save state), the properties bag SHALL include:

- `orphaned_expense_count: Int` — the number of items in `Budget.expenseItems` whose `date` is before the new `Budget.startDate`. This property SHALL be omitted (not emitted as `0`) when the count is zero, so the absence of the property denotes "save did not produce an orphaned state" and any present value denotes a deliberate orphan-confirmation save. The constant SHALL be added as `AnalyticsProperty.orphanedExpenseCount`.

These flags SHALL be emitted **only** on `AnalyticsEvent.budgetEdited`. They SHALL NOT be added to `AnalyticsEvent.budgetCreated` (where every field is "new" by definition and `expenseItems` is empty). They SHALL NOT alter other events.

The implementation SHALL replace the existing single `changed: Bool` accumulator in `saveEdit` with per-field locals (e.g. `nameChanged`, `allocationChanged`, `currencyChanged`, `carryOverToggleChanged`, dateEdits via `applyDateEdits` returning a tuple or struct exposing the two date diffs separately) and pass the F-8.02 subset (`allocation_changed`, `start_date_changed`, `end_date_changed`, plus the conditional `orphaned_expense_count`) through `budgetEventProperties(budget:edits:)`. The existing aggregate gating (write to `Budget.lastModified` and `context.save()` only when at least one field changed) SHALL continue to apply.

Property names SHALL match `docs/analytics-spec.md`'s F-8.02 declarations. The corresponding constants SHALL be added to `AnalyticsProperty` (e.g. `AnalyticsProperty.allocationChanged`, `.startDateChanged`, `.endDateChanged`, `.orphanedExpenseCount`).

#### Scenario: Editing only the name fires budget_edited with all date / allocation flags false

- **WHEN** the user opens Edit for a `.daily` budget and changes only the name, then taps Save
- **THEN** the emitted `AnalyticsEvent.budgetEdited` properties include `allocation_changed: false`, `start_date_changed: false`, `end_date_changed: false`, and `orphaned_expense_count` is **not** present in the bag

#### Scenario: Editing the recurring startDate fires budget_edited with start_date_changed=true

- **WHEN** the user opens Edit for a `.weekly` budget, edits `startDate` from one Monday to the prior Monday via the Schedule disclosure, and taps Save
- **THEN** `AnalyticsEvent.budgetEdited` fires with `start_date_changed: true`, `end_date_changed: false`, `allocation_changed: false`; `orphaned_expense_count` is **not** present in the bag (moving startDate earlier never orphans expenses)

#### Scenario: Clearing the recurring endDate fires budget_edited with end_date_changed=true

- **WHEN** the user opens Edit for a `.monthly` budget with `endDate` set, taps "Clear end date" in the Schedule disclosure, and taps Save
- **THEN** `Budget.endDate` is set to `nil` in storage, and `AnalyticsEvent.budgetEdited` fires with `end_date_changed: true`, `start_date_changed: false`

#### Scenario: budget_created is unaffected by this requirement

- **WHEN** the user creates a new budget via Save in Add mode
- **THEN** `AnalyticsEvent.budgetCreated` fires WITHOUT `start_date_changed`, `end_date_changed`, `allocation_changed`, or `orphaned_expense_count` flags in its properties

#### Scenario: No-op Save does not fire budget_edited

- **WHEN** the user opens Edit, makes no changes, and taps Save
- **THEN** no `AnalyticsEvent.budgetEdited` event is emitted (consistent with the existing "no-op Save does not bump lastModified" scenario)

#### Scenario: Confirming the orphan-warning alert emits orphaned_expense_count

- **WHEN** the user moves `startDate` forward past 2 existing expenses, taps Save, confirms the orphan-warning alert via `Save Changes`
- **THEN** `AnalyticsEvent.budgetEdited` fires with `start_date_changed: true` AND `orphaned_expense_count: 2`

#### Scenario: Cancelling the orphan-warning alert emits no event

- **WHEN** the user moves `startDate` forward past existing expenses, taps Save, and taps `Cancel` on the orphan-warning alert
- **THEN** no `AnalyticsEvent.budgetEdited` event is emitted (the save did not commit)
