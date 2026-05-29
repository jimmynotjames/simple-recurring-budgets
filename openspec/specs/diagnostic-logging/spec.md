# Capability: diagnostic-logging

## Purpose

Governs all on-device diagnostic logging via Apple's unified logging system (`OSLog`) in the `simple-recurring-budgets` app. Defines canonical `Logger` categories, call-site placement, privacy-annotation rules, and the strict architectural boundary with `AnalyticsClient` (product analytics). See `docs/analytics-spec.md` §17 for the full boundary contract.

---
## Requirements
### Requirement: AppLoggers categories

The app SHALL expose exactly four `os.Logger` constants in `simple-recurring-budgets/Logging/AppLoggers.swift`, each scoped to the app's bundle subsystem (or the fallback `"simple-recurring-budgets"` when `Bundle.main.bundleIdentifier` is nil):

- `Logger.bootstrap` — category `"bootstrap"`. Covers app startup, container creation, and resolution of the launch mode.
- `Logger.cloudKit` — category `"cloudkit"`. Covers CloudKit container backing decisions and iCloud account-status transitions.
- `Logger.ui` — category `"ui"`. Covers user-initiated UI actions (Phase 1 limited to destructive actions; see the `Destructive UI logging` requirement below).
- `Logger.persistence` — category `"persistence"`. Covers SwiftData write failures surfaced by the shared save helper (see the `Persistence save-failure logging` requirement below).

These four categories are the canonical set. Adding a new category to `AppLoggers.swift` SHALL be accompanied by a new requirement in this spec in the same change. Removing or renaming a category SHALL be accompanied by a `MODIFIED Requirement` block in the same change.

#### Scenario: All four logger constants are reachable from app code

- **WHEN** application code references `Logger.bootstrap`, `Logger.cloudKit`, `Logger.ui`, or `Logger.persistence`
- **THEN** the constants resolve to `os.Logger` values whose `subsystem` equals `Bundle.main.bundleIdentifier ?? "simple-recurring-budgets"` and whose `category` equals `"bootstrap"`, `"cloudkit"`, `"ui"`, or `"persistence"` respectively

#### Scenario: AppLoggers exposes no fifth category

- **WHEN** a contributor inspects `AppLoggers.swift`
- **THEN** exactly four `Logger` constants are declared, named `bootstrap`, `cloudKit`, `ui`, and `persistence`

---

### Requirement: Bootstrap launch-mode log entry

The app SHALL emit exactly one `Logger.bootstrap.info` entry per launch, after the `ModelContainer` has been resolved in `simple_recurring_budgetsApp.init()`, recording the resolved `AppDatabaseLaunchMode`. In Release builds the value is always `.normal`. In DEBUG builds the value is the active case from the `appDatabaseLaunchMode` dev override (`.normal` / `.emptyInMemory` / `.emptyPersistedThenClear` / `.debugDataSeededInMemory`). The interpolated enum case name SHALL use `privacy: .public` because it is a static, non-PII value. The message format SHALL be a single line with a stable prefix (e.g., `"bootstrap.launchMode: <case>"`) so log filtering by substring is reliable.

#### Scenario: Release launch logs `.normal`

- **WHEN** the app launches in a Release build
- **THEN** exactly one `Logger.bootstrap.info` line is emitted whose interpolated value is the case name `normal`

#### Scenario: DEBUG launch logs the active override

- **WHEN** the app launches in a DEBUG build with `appDatabaseLaunchMode = .debugDataSeededInMemory`
- **THEN** exactly one `Logger.bootstrap.info` line is emitted whose interpolated value is the case name `debugDataSeededInMemory`

#### Scenario: Bootstrap line is single per launch

- **WHEN** the app launches and `init()` runs to completion
- **THEN** no more than one `Logger.bootstrap.info` line is emitted from `simple_recurring_budgetsApp.init()` regardless of how many times `body` re-renders

---

### Requirement: CloudKit container backing log entries

The app SHALL retain the four existing `Logger.cloudKit` call sites inside `simple_recurring_budgetsApp.makeProductionModelContainer()`, emitting one entry per code path:

- `Logger.cloudKit.info("cloudkit.container.backed")` — CloudKit-backed container creation succeeded.
- `Logger.cloudKit.notice("cloudkit.container.localFallback")` — CloudKit-backed creation failed; falling back to local-only.
- `Logger.cloudKit.info("cloudkit.container.localSuccess")` — local-only container creation succeeded.
- `Logger.cloudKit.error("cloudkit.container.failed: \(error.localizedDescription, privacy: .public)")` — both creation paths failed; about to surface the error to `AppStartup` for presentation in `ContainerFailureView` (see the `container-creation-recovery` capability). The process is **not** terminated.

The error site SHALL interpolate `error.localizedDescription` with `privacy: .public` because Apple framework error descriptions are reviewable diagnostics and contain no user-derived content.

#### Scenario: CloudKit success path

- **WHEN** `makeProductionModelContainer` successfully creates a CloudKit-backed container
- **THEN** `Logger.cloudKit.info("cloudkit.container.backed")` is emitted exactly once for that call

#### Scenario: CloudKit fallback path

- **WHEN** `makeProductionModelContainer` fails to create a CloudKit-backed container and succeeds on the local-only fallback
- **THEN** `Logger.cloudKit.notice("cloudkit.container.localFallback")` is emitted, followed by `Logger.cloudKit.info("cloudkit.container.localSuccess")`

#### Scenario: CloudKit failure path

- **WHEN** both container-creation paths throw
- **THEN** `Logger.cloudKit.error` is emitted with the localized error description interpolated at `privacy: .public`, before the error is surfaced to `AppStartup`; the process is not terminated and no `fatalError(_:)` call follows

### Requirement: iCloud account-status transition log entry

`SettingsView` SHALL emit one `Logger.cloudKit.notice` entry whenever `SyncStatus.accountStatus` transitions to a different value as a result of `loadICloudStatus()` (initial load or notification-driven refresh from `CKAccountChanged` / `NSUbiquityIdentityDidChange`). The message SHALL include the previous and new `AccountStatus` enum case names, both interpolated at `privacy: .public`. The user's iCloud identity (Apple ID, container record id, free-form identity tokens) SHALL NOT appear in the log line. If `old == new`, no entry is emitted.

#### Scenario: First load resolves a definite status

- **WHEN** the Settings sheet opens and `loadICloudStatus()` resolves the initial account status from `.checking` to `.available`
- **THEN** one `Logger.cloudKit.notice` line is emitted whose payload contains `checking` and `available` interpolated at `privacy: .public`

#### Scenario: Notification-driven transition

- **WHEN** `CKAccountChanged` or `NSUbiquityIdentityDidChange` fires and `loadICloudStatus()` re-resolves to a different `AccountStatus` value
- **THEN** one `Logger.cloudKit.notice` line is emitted recording the old → new transition

#### Scenario: No-op refresh emits nothing

- **WHEN** `loadICloudStatus()` re-resolves and the new value equals the previous value
- **THEN** no `Logger.cloudKit` line is emitted for the transition

---

### Requirement: Destructive UI action log entries

The app SHALL emit exactly one `Logger.ui.debug` entry at each of the four user-initiated destructive call sites listed in `docs/main-prd.md` §6.7. Each entry SHALL interpolate (a) the affected entity's `persistentModelID` at `privacy: .private` and (b) a static action-name literal at `privacy: .public`. The four sites are:

| Action             | Call site                                                           | Entity ID     |
| ------------------ | ------------------------------------------------------------------- | ------------- |
| `Reset Budget`     | `BudgetDetailView.resetBudget`                                      | `Budget`      |
| `Reset Carry-Over` | `BudgetDetailView.resetCarryOver`                                   | `Budget`      |
| `Delete Budget`    | `AddEditBudgetViewModel.delete(context:)` (Edit-mode confirm path)  | `Budget`      |
| `Delete Expense`   | `BudgetDetailView+ExpenseSection.deleteExpense(_:)`                 | `ExpenseItem` |

`Delete Expense` SHALL be logged at the `deleteExpense(_:)` funnel exactly once per logical delete, regardless of whether the call originated from the trailing-edge swipe action or the VoiceOver rotor `accessibilityAction`. No additional `Logger.ui` lines SHALL be added in this scope for non-destructive UI traces.

#### Scenario: Reset Budget confirmation logs once

- **WHEN** the user confirms the Reset Budget destructive dialog on the Budget detail screen
- **THEN** one `Logger.ui.debug` line is emitted with the budget's `persistentModelID` at `privacy: .private` and the action name at `privacy: .public`

#### Scenario: Reset Carry-Over confirmation logs once

- **WHEN** the user confirms the Reset Carry-Over destructive alert
- **THEN** one `Logger.ui.debug` line is emitted with the budget's `persistentModelID` at `privacy: .private` and the action name at `privacy: .public`

#### Scenario: Delete Budget confirmation logs once

- **WHEN** the user confirms the Delete Budget destructive button on the Add/Edit Budget sheet in Edit mode
- **THEN** one `Logger.ui.debug` line is emitted with the budget's `persistentModelID` at `privacy: .private` and the action name at `privacy: .public`

#### Scenario: Delete Expense via swipe logs once

- **WHEN** the user performs a full trailing swipe on an expense row, or taps the revealed destructive button
- **THEN** one `Logger.ui.debug` line is emitted with the expense's `persistentModelID` at `privacy: .private` and the action name at `privacy: .public`

#### Scenario: Delete Expense via VoiceOver rotor logs once

- **WHEN** a VoiceOver user invokes the rotor `accessibilityAction(named:)` mirror of the swipe-to-delete gesture
- **THEN** one `Logger.ui.debug` line is emitted with the expense's `persistentModelID` at `privacy: .private` and the action name at `privacy: .public`

#### Scenario: Non-destructive UI events do not log

- **WHEN** the user adds an expense, edits a budget, opens Settings, or triggers any other non-destructive UI action
- **THEN** no `Logger.ui` line is emitted for that action in Phase 1

---

### Requirement: Explicit privacy argument on every interpolated value

Every `Logger.*` call site under `simple-recurring-budgets/` that interpolates a value SHALL set an explicit `privacy:` argument. Static string literals with no interpolation are exempt because there is no value to redact. Values derived from user input (`Budget.name`, `ExpenseItem.name`, free text), model identifiers (`persistentModelID`, UUIDs, CloudKit record ids), or any user-derived content SHALL use `privacy: .private`. Static enum case names, Apple framework error descriptions surfaced via `error.localizedDescription`, bundle metadata, and other non-user-derived diagnostic values MAY use `privacy: .public`.

#### Scenario: User-derived value is private

- **WHEN** a contributor adds a `Logger.*` call site that interpolates a `persistentModelID`, a `Budget.name`, an `ExpenseItem.name`, or any user-typed string
- **THEN** the interpolation uses `privacy: .private`

#### Scenario: Static enum name is public

- **WHEN** a `Logger.*` call site interpolates a static enum case name (`AppDatabaseLaunchMode`, `AccountStatus`, `BudgetPeriod`, etc.)
- **THEN** the interpolation uses `privacy: .public`

#### Scenario: Static literal needs no privacy argument

- **WHEN** a `Logger.*` call site emits a string literal with no interpolation (e.g., `Logger.cloudKit.info("cloudkit.container.backed")`)
- **THEN** no `privacy:` argument is required

---

### Requirement: Boundary with AnalyticsClient (no cross-routing)

No code under `simple-recurring-budgets/` SHALL invoke both `Logger.*` and `AnalyticsClient.track(...)` for the same conceptual event with the intent of cross-routing one to the other. The `AnalyticsClient` API surface SHALL NOT expose any method whose parameter type is `os.Logger`, `OSLogEntry`, `OSLogEntryLog`, `OSLogMessage`, or any other OSLog-shaped type. Conversely, no `Logger.*` call site SHALL invoke `AnalyticsClient.track(_:)` (or its equivalents) as a deterministic side-effect of the log emission.

A single user action MAY independently produce one `Logger.*` line and one `AnalyticsClient` event (e.g., a destructive action that logs a `Logger.ui.debug` entry today and, when F-8.02 ships, also fires a Mixpanel event). The two calls SHALL be at sibling call sites in the imperative method body, not nested or derived from each other.

The shared persistence-save helper's failure path is a permitted instance of this allowance: it emits a `Logger.persistence.error` line and fires a `persistence_save_failed` analytics event as sibling statements, each built independently from the operation identifier and the underlying error's domain/code. Neither call consumes the other's return value and no OSLog-shaped type is passed to `AnalyticsClient`.

#### Scenario: AnalyticsClient exposes no OSLog-shaped API

- **WHEN** a contributor inspects the `AnalyticsClient` protocol and all conforming implementations under `simple-recurring-budgets/Logging/`
- **THEN** no method takes a parameter of type `os.Logger`, `OSLogEntry`, `OSLogEntryLog`, or `OSLogMessage`

#### Scenario: Sibling call sites are allowed

- **WHEN** a destructive action emits `Logger.ui.debug(...)` and the same method body also invokes `AnalyticsClient.track(...)` independently
- **THEN** the change is allowed, provided the two calls are sibling statements and neither derives its arguments from the other's return value or from an OSLog-side observer

#### Scenario: Save-failure log and analytics event are sibling, not cross-routed

- **WHEN** the persistence-save helper handles a failed `context.save()` by emitting `Logger.persistence.error` and firing `persistence_save_failed`
- **THEN** the two emissions are sibling statements built from the same plain operation/error values, no OSLog-shaped value is passed into `AnalyticsClient`, and neither call derives from the other's result

#### Scenario: Cross-routing helper is forbidden

- **WHEN** a contributor proposes a helper that subscribes to `OSLogStore`, observes `Logger.*` emissions, or accepts an OSLog-shaped value and forwards it to `AnalyticsClient.track`
- **THEN** the helper is rejected at code review and SHALL NOT be merged

---

### Requirement: Doc alignment for AppLoggers categories

`docs/tech-design-doc.md` §7 SHALL list the same four category strings (`bootstrap`, `cloudkit`, `ui`, `persistence`) as `AppLoggers.swift`. Any change to the category set in `AppLoggers.swift` SHALL update §7 in the same OpenSpec change. Cross-reference to `docs/analytics-spec.md` §17 (the OSLog ↔ `AnalyticsClient` boundary) SHALL be present in §7 so a reader of either doc can find the other.

#### Scenario: Tech-design-doc §7 matches AppLoggers.swift

- **WHEN** a reader inspects `docs/tech-design-doc.md` §7
- **THEN** the four categories listed there are exactly `bootstrap`, `cloudkit`, `ui`, and `persistence`, matching `AppLoggers.swift`

#### Scenario: Tech-design-doc §7 references the analytics boundary

- **WHEN** a reader inspects `docs/tech-design-doc.md` §7
- **THEN** §7 cross-references `docs/analytics-spec.md` §17 for the boundary contract with `AnalyticsClient`

### Requirement: Persistence save-failure logging

The shared persistence-save helper SHALL emit exactly one `Logger.persistence.error` entry whenever `context.save()` throws. The entry SHALL interpolate (a) the `PersistenceOperation` identifier at `privacy: .public` (a static, non-user-derived snake_case value) and (b) the underlying error's `localizedDescription` at `privacy: .public` (an Apple framework diagnostic with no user-derived content). The entry SHALL NOT interpolate any `Budget` field, `ExpenseItem` field, money value, or model identifier. On a successful save the helper SHALL emit no `Logger.persistence` line.

#### Scenario: Failed save emits one persistence error line

- **WHEN** the save helper's wrapped `context.save()` throws for operation `budget_create`
- **THEN** exactly one `Logger.persistence.error` line is emitted interpolating `budget_create` and the error's `localizedDescription`, both at `privacy: .public`

#### Scenario: Persistence log line carries no user data

- **WHEN** any `Logger.persistence.error` line is emitted by the save helper
- **THEN** it contains no budget name, expense name, amount, date, notes, or `persistentModelID`

#### Scenario: Successful save emits nothing on the persistence channel

- **WHEN** the save helper's wrapped `context.save()` succeeds
- **THEN** no `Logger.persistence` line is emitted for that call

