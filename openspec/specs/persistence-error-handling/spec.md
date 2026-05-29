# persistence-error-handling Specification

## Purpose
TBD - created by archiving change robust-persistence-error-handling. Update Purpose after archive.
## Requirements
### Requirement: Single throwing save path for all production writes

The app SHALL provide one persistence-save helper — `ModelContext.saveChanges(operation:analytics:)` (or equivalent) in `simple-recurring-budgets/Domain` — that wraps `try context.save()`. Every production write site that previously used `try? context.save()` SHALL route through this helper. The helper SHALL, on a thrown error: (a) emit `Logger.persistence.error` per the `diagnostic-logging` capability, (b) fire the `persistence_save_failed` analytics event per the requirement below, and (c) rethrow a `PersistenceError` value that carries the originating `PersistenceOperation` identifier and the underlying error's domain and code. On success the helper SHALL return normally without logging or tracking.

`DebugData.swift` and `BudgetDetailFixtures.swift` are DEBUG/preview-only seeding paths and are exempt; they MAY retain `try?`. No other production file under `simple-recurring-budgets/` SHALL contain `try? context.save()`.

The helper SHALL NOT store the `ModelContext` or the `AnalyticsClient`; both are passed at the call site every invocation, consistent with the call-site-injection rule in `docs/tech-design-doc.md` §2.1.

#### Scenario: Successful save is silent

- **WHEN** a production write site calls the save helper and `context.save()` succeeds
- **THEN** the helper returns normally, emits no `Logger.persistence` line, and fires no analytics event

#### Scenario: Failed save logs, tracks, and rethrows

- **WHEN** a production write site calls the save helper and `context.save()` throws
- **THEN** the helper emits exactly one `Logger.persistence.error` line, fires exactly one `persistence_save_failed` analytics event, and rethrows a `PersistenceError` carrying the operation identifier plus the underlying error domain and code

#### Scenario: No silent try? saves remain in production

- **WHEN** a contributor greps production code under `simple-recurring-budgets/` (excluding `DebugData.swift` and `BudgetDetailFixtures.swift`) for `try? context.save()`
- **THEN** no matches are found

---

### Requirement: Interactive save failures keep the sheet open and offer Retry

A write that originates from a presenting sheet or screen (Add/Edit Budget, Add/Edit Expense, inline expense add/edit, swipe-to-delete, drag-to-reorder, and the user-tap-triggered lifecycle write-paths) is *interactive*. When an interactive write fails, the system SHALL NOT dismiss the presenting sheet and SHALL NOT clear the user's in-progress input. Instead it SHALL present a save-error alert offering **Retry** and a non-destructive dismiss-the-alert action (e.g. **Cancel** / **OK**) that returns the user to the unchanged form. Activating **Retry** SHALL re-attempt the identical write operation.

A successful write (including a successful retry) SHALL dismiss the sheet (where the screen dismisses on save) and clear any save-error state.

#### Scenario: Failed interactive save does not dismiss

- **WHEN** the user taps Save on the Add/Edit Budget or Add/Edit Expense sheet and the save fails
- **THEN** the sheet remains open with the user's entered values intact AND a save-error alert is presented

#### Scenario: Retry re-attempts the same operation

- **WHEN** the save-error alert is shown and the user taps Retry
- **THEN** the system re-runs the same save operation against the model context

#### Scenario: Successful retry dismisses and clears the error

- **WHEN** the user taps Retry and the save succeeds
- **THEN** the save-error alert is cleared and the sheet dismisses as a normal successful save would

#### Scenario: Cancelling the alert preserves the form

- **WHEN** the save-error alert is shown and the user dismisses it without retrying
- **THEN** the sheet remains open with the user's input unchanged and no data is persisted

---

### Requirement: Save-error alert escalates to Send Feedback after three consecutive failures

The save-error alert SHALL track the number of consecutive failures for the same operation. While that count is less than 3, the alert offers only Retry and the dismiss action. When the count reaches 3 or more, the alert SHALL additionally offer a **Send Feedback** action that opens the app's existing feedback `mailto:` URL (the one used by Settings) with a subject/body prefilled with only the `PersistenceOperation` identifier and the error domain and code. The feedback body SHALL NOT contain any `Budget` or `ExpenseItem` field, money value, or other user-derived content. A subsequent successful save SHALL reset the consecutive-failure count.

#### Scenario: Send Feedback appears on the third failure

- **WHEN** the same save operation has failed three times in a row (initial attempt plus two Retry attempts, all failing)
- **THEN** the save-error alert additionally presents a Send Feedback action

#### Scenario: Send Feedback opens prefilled mail with no user data

- **WHEN** the user taps Send Feedback from the escalated alert
- **THEN** the app opens the feedback mailto URL whose subject/body contains only the operation identifier and the error domain and code, and contains no budget name, expense name, amount, date, or notes

#### Scenario: Success resets the failure count

- **WHEN** a save operation has failed twice and a third attempt succeeds
- **THEN** the consecutive-failure count is reset, so a later first failure of the same operation does not immediately show Send Feedback

---

### Requirement: Background save failures log and track without UI

A write that has no presenting sheet — `BudgetLifecycleService` rollover saves invoked from an eager lifecycle refresh, and the app-launch deduplication save in `simple_recurring_budgetsApp` — is *background*. When a background write fails, the system SHALL route it through the save helper (so it is logged and the `persistence_save_failed` event fires) and SHALL NOT present any alert or block the UI. The failed mutation MAY be re-attempted by the next natural refresh; the system SHALL NOT crash or surface a user-visible error for a background save failure.

#### Scenario: Background rollover save failure is logged, not shown

- **WHEN** a `BudgetLifecycleService` rollover save invoked from an eager refresh fails
- **THEN** a `Logger.persistence.error` line and a `persistence_save_failed` event are emitted AND no alert is presented to the user

#### Scenario: App-launch dedup save failure does not crash

- **WHEN** the app-launch deduplication save fails
- **THEN** the failure is logged and tracked, the app continues launching, and no alert is shown

---

### Requirement: persistence_save_failed analytics event payload is allow-list restricted

The `persistence_save_failed` event SHALL carry only: `operation` (the `PersistenceOperation` raw value, a static snake_case identifier such as `budget_create`, `budget_edit`, `expense_create`, `expense_edit`, `expense_delete`, `budget_delete`, `reorder`, `lifecycle_pause`, `lifecycle_resume`, `lifecycle_allocation_edit`, `lifecycle_reset_carry_over`, `lifecycle_reset_budget`, `app_launch_dedup`), `error_domain` (the `NSError` domain string), and `error_code` (the `NSError` code integer). It SHALL NOT carry any `Budget` field (including `budget_name` or `budget_allocation_amount`), any `ExpenseItem` field, any money value, any free text, or any model identifier. The event is consent-gated like all `AnalyticsClient` traffic and is therefore a best-effort signal, not a complete record.

#### Scenario: Event carries only operation and error classification

- **WHEN** `persistence_save_failed` is emitted
- **THEN** its properties are exactly `operation`, `error_domain`, and `error_code`, and contain no budget name, allocation amount, expense field, money value, free text, or model identifier

#### Scenario: Opted-out users emit nothing

- **WHEN** a save fails for a user who has not consented to analytics
- **THEN** no `persistence_save_failed` event is transmitted, while the `Logger.persistence.error` line is still emitted on-device

