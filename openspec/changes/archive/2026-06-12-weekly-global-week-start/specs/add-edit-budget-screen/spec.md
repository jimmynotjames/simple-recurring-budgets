# add-edit-budget-screen delta — weekly-global-week-start

## MODIFIED Requirements

### Requirement: VM exposes a save method that takes ModelContext at the call site

The `AddEditBudgetViewModel` SHALL expose a `save` method that takes `ModelContext` at the call site and performs the Add or Edit branch documented below. The method SHALL surface a persistence-save failure to its caller — it SHALL be marked `throws` (or otherwise report failure), routing its `context.save()` through the shared persistence-save helper rather than `try? context.save()`. The view SHALL read `@Environment(\.modelContext)`, invoke the save method from inside `body`, and dismiss the sheet **only** when the call returns without error; on a thrown persistence error the view SHALL present the standard save-error alert and SHALL NOT dismiss (see the `persistence-error-handling` capability). The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The save body SHALL NOT consult `AppSettings` for any budget field value or draft default — those are read only at construction time via `init(settings:)` to seed the Add-mode Carry-Over default and week-start anchor. The save signature does accept `settings: AppSettings` (passed at the call site, never stored) for three concerns: reading `analyticsFirstOpenAt` to compute the `time_since_first_app_open_bucket` property on a first-budget `budget_created` event (Add branch), reading `analyticsOptInExplicitlySet` to decide whether to present the analytics-consent sheet in consent-required jurisdictions (Add branch), and reading `weekStartDay` to thread the global weekly grid into `BudgetLifecycleService.applyAllocationEdit(...)` (Edit branch, per the `budget-lifecycle` capability). The Edit branch SHALL NOT read any other `settings` member.

#### Scenario: Save reports failure to the caller

- **WHEN** the `AddEditBudgetViewModel` save method is inspected
- **THEN** it surfaces a persistence-save failure to its caller (e.g. it is marked `throws`) and routes its save through the shared persistence-save helper, not `try? context.save()`

#### Scenario: View dismisses only on a successful save

- **WHEN** the user activates Save and the save method returns without error
- **THEN** the sheet dismisses; **AND WHEN** the save method throws a persistence error, the sheet stays open and the save-error alert is shown

### Requirement: Save in Add mode inserts a new Budget with the next sortOrder

When the user activates Save in Add mode, the system SHALL:

0. **Guard:** If validation would disable Save (`!canSave`), the implementation SHALL return without inserting a `Budget` (defence in depth if the save method is invoked without a valid draft).
1. Build a `Budget` using `Budget.init` with the drafted `name` (post-trim, but the model stores the user's value as entered; trimming is for validation only), the drafted `currencyCode`, the drafted `period`, and the drafted `isCarryOverEnabled`.
2. Set `budget.startDate = calendar.startOfDay(for: viewModel.startDate!)`. The drafted `startDate` is non-`nil` by canSave (specific dates) or by the Add-mode pre-fill + `period.didSet` re-anchoring rule (recurring). For weekly / biweekly the drafted value may be the AppSettings-derived default or a user-overridden date — both paths are stored as the budget's `startDate`, which defines when the budget begins and (for biweekly) anchors the 14-day cycle per F-7.05. The weekly grid itself is global (`AppSettings.weekStartDay` per the `budget-math` capability); a weekly `startDate` that falls mid-grid simply clips the first period.
3. Set `budget.endDate = viewModel.endDate.map { calendar.startOfDay(for: $0) }`. For `.specificDates`, `endDate` is non-`nil` by `canSave`. For recurring period types it is optional — `nil` is the common case for "no terminal date."
4. For `.specificDates` only, force-clamp `isCarryOverEnabled = false` before insert (the toggle is hidden on the Add/Edit sheet for this period type; without the clamp, a pre-toggle session default of `true` would persist a stale value that pollutes analytics cohorts that read `Budget.isCarryOverEnabled` directly).
5. Set `budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0` BEFORE inserting, so the fetch does not include the new instance.
6. Call `context.insert(budget)`.
7. Insert one initial `AllocationChange(effectiveFrom: budget.startDate!, amount: drafted allocation, lastModified: Date())` attached to the same budget.
8. Persist via the shared persistence-save helper (operation `budget_create`), which throws on failure; the method propagates that error to the caller instead of swallowing it with `try?`.
9. On success, the view dismisses the sheet. On a thrown persistence error, the view presents the save-error alert and does not dismiss; the just-inserted (but unsaved) `Budget` remains in the context so a Retry re-attempts the same save.

The new budget SHALL appear in the Budgets screen list immediately due to the existing `@Query(sort: \Budget.sortOrder)` reactivity once the save succeeds. CloudKit sync SHALL propagate the new row through the existing pipeline; no new container or schema changes are introduced.

#### Scenario: First budget gets sortOrder 0

- **WHEN** the store is empty and the user creates a `Budget` via Save
- **THEN** the inserted `Budget` has `sortOrder == 0`

#### Scenario: Subsequent budget gets next sortOrder

- **WHEN** the store contains budgets with `sortOrder` values up to `N`, and the user creates a `Budget` via Save
- **THEN** the inserted `Budget` has `sortOrder == N + 1`

#### Scenario: Save inserts exactly one budget

- **WHEN** the user activates Save in Add mode and the save succeeds
- **THEN** the store contains exactly one new `Budget` whose fields match the drafted values

#### Scenario: Failed Add-mode save keeps the sheet open

- **WHEN** the user activates Save in Add mode and the persistence-save helper throws
- **THEN** the sheet remains open with the drafted values intact and the save-error alert is presented

#### Scenario: Recurring Save uses pre-filled startDate

- **WHEN** the user creates a `.daily` budget without touching the Schedule disclosure
- **THEN** the inserted `Budget.startDate` equals `calendar.startOfDay(for: Date())` (the Add-mode pre-fill) AND the initial `AllocationChange.effectiveFrom` equals the same value AND `Budget.endDate` is `nil`

#### Scenario: Recurring Save honors a user-overridden startDate

- **WHEN** the user creates a `.weekly` budget, expands the Schedule disclosure, picks a Thursday three weeks ago via the start-date chip, and taps Save
- **THEN** the inserted `Budget.startDate` equals the picked Thursday at `startOfDay`, AND the initial `AllocationChange.effectiveFrom` equals the same value — the budget's window begins that Thursday, while its weekly grid follows the global `AppSettings.weekStartDay` (the first period is clipped at the Thursday `startDate` if it falls mid-grid, per the `budget-math` capability)

#### Scenario: Recurring Save persists an optional endDate

- **WHEN** the user creates a `.monthly` budget and picks an end date six months in the future via the Schedule disclosure
- **THEN** the inserted `Budget.endDate` equals the picked date at `startOfDay`

#### Scenario: Specific Dates Save writes both startDate and endDate

- **WHEN** the user creates a `.specificDates` budget with `startDate = 2026-05-08`, `endDate = 2026-05-25`, allocation `1500`
- **THEN** the inserted `Budget` has `startDate == startOfDay(2026-05-08)`, `endDate == startOfDay(2026-05-25)`, and one `AllocationChange(effectiveFrom: startDate, amount: 1500)`

#### Scenario: Recurring Save leaves endDate nil by default

- **WHEN** the user creates a `.daily`, `.weekly`, `.biweekly`, or `.monthly` budget without setting an end date in the Schedule disclosure
- **THEN** the inserted `Budget.endDate` is `nil`
