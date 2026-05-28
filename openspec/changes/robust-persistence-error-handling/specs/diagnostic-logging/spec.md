## MODIFIED Requirements

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

## ADDED Requirements

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
