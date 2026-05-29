# container-creation-recovery Specification

## Purpose
TBD - created by archiving change container-creation-recovery. Update Purpose after archive.
## Requirements
### Requirement: makeProductionModelContainer does not crash on failure

`simple_recurring_budgetsApp.makeProductionModelContainer()` SHALL be a throwing function that returns the created `ModelContainer` on success and `throws` on failure. When both the CloudKit-backed creation and the local-only fallback fail, the function SHALL NOT call `fatalError(_:)` (or any other process-terminating API). The diagnostic `Logger.cloudKit.error("cloudkit.container.failed: …")` line SHALL still be emitted per the `diagnostic-logging` capability before the error is propagated to the caller. The successful CloudKit / local-fallback paths SHALL behave identically to before this change.

#### Scenario: Both creation paths failing throws instead of crashing

- **WHEN** both the CloudKit-backed and local-only `ModelContainer` creation attempts throw
- **THEN** `makeProductionModelContainer` rethrows the underlying error to its caller AND the process is not terminated AND no `fatalError(_:)` is invoked

#### Scenario: Successful CloudKit-backed creation is unchanged

- **WHEN** CloudKit-backed `ModelContainer` creation succeeds on the first try
- **THEN** `makeProductionModelContainer` returns the container and its `containerBacking == .cloudKit`, identically to the pre-change behavior

#### Scenario: Local fallback is unchanged

- **WHEN** CloudKit-backed creation fails and the local-only fallback succeeds
- **THEN** `makeProductionModelContainer` returns the container and its `containerBacking == .localFallback`, identically to the pre-change behavior

---

### Requirement: AppStartup owns container-creation result

The app SHALL expose an `@Observable` `AppStartup` model in `simple-recurring-budgets/App/AppStartup.swift` with the following surface:

- `container: ModelContainer?` — the live container on the success path; `nil` while the failure surface is presented.
- `containerBacking: ContainerBacking?` — the resolved backing (`cloudKit` / `localFallback`) on success; `nil` on failure.
- `error: ContainerCreationFailure?` — a typed value carrying the underlying `NSError`'s `domain: String` and `code: Int`; `nil` on success.
- `func retry()` — re-runs `simple_recurring_budgetsApp.makeProductionModelContainer()` on the main actor and updates `container` / `containerBacking` / `error` accordingly. A successful retry clears `error` and populates `container` + `containerBacking`.

`AppStartup` SHALL NOT store an `AnalyticsClient` or transmit any analytics event on failure (see design.md §5). The diagnostic OSLog entry continues to be the on-device record.

#### Scenario: Successful first attempt populates container

- **WHEN** the first container-creation attempt succeeds
- **THEN** `AppStartup.container` is non-`nil`, `AppStartup.containerBacking` equals the resolved backing, and `AppStartup.error` is `nil`

#### Scenario: Failed first attempt populates error

- **WHEN** the first container-creation attempt throws
- **THEN** `AppStartup.container` is `nil`, `AppStartup.containerBacking` is `nil`, and `AppStartup.error` is non-`nil` with `errorDomain` and `errorCode` matching the underlying `NSError`

#### Scenario: Successful retry replaces error with container

- **WHEN** `AppStartup.error` is non-`nil` and `retry()` is invoked and the new attempt succeeds
- **THEN** `AppStartup.error` is cleared to `nil` and `AppStartup.container` is non-`nil`

#### Scenario: Failed retry updates the error

- **WHEN** `AppStartup.error` is non-`nil` and `retry()` is invoked and the new attempt throws
- **THEN** `AppStartup.error` is updated with the new attempt's `errorDomain` and `errorCode`, `AppStartup.container` remains `nil`, and no crash occurs

---

### Requirement: App body branches on AppStartup state

`simple_recurring_budgetsApp.body` SHALL branch on `AppStartup.container`:

- When `AppStartup.container` is non-`nil`, the body SHALL host `RootView` with `.modelContainer(container)` and the existing `Router`, `AppSettings`, `SyncStatus`, and analytics environment bindings, identical to the pre-change success path.
- When `AppStartup.container` is `nil` AND `AppStartup.error` is non-`nil`, the body SHALL host the new `ContainerFailureView`, passing the error and a closure that calls `AppStartup.retry()`. The failure branch SHALL NOT construct or pass `RootView`, `Router`, `AppSettings`, `SyncStatus`, or the analytics client (per design.md §3 — those are not safe to use in the wedged-store state).

#### Scenario: Success path is identical to pre-change

- **WHEN** container creation succeeds at launch (or after a successful retry)
- **THEN** the app body presents `RootView()` with `.modelContainer(container)` and the existing environment objects; no `ContainerFailureView` is presented

#### Scenario: Failure path presents ContainerFailureView

- **WHEN** container creation has failed and `AppStartup.error` is non-`nil`
- **THEN** the app body presents `ContainerFailureView` with the typed error and a retry closure; `RootView` is not constructed in this branch

---

### Requirement: ContainerFailureView presents Retry and Send Feedback

The app SHALL provide `ContainerFailureView` in `simple-recurring-budgets/Views/`. The view SHALL render:

- A localized title (default English: "Couldn't open your data").
- A localized body sentence reassuring the user and inviting Retry or Send Feedback. The body SHALL NOT display the underlying `NSError` domain or code to the user.
- A localized **Retry** button that invokes the injected retry closure.
- A localized **Send Feedback** button that opens `FeedbackMailto.containerFailureURL(errorDomain:errorCode:)` via the `\.openURL` environment.

The view SHALL set explicit `accessibilityLabel` / `accessibilityHint` on each button. The view SHALL respect Dynamic Type (no fixed font sizes). The view SHALL NOT animate in a way that ignores `accessibilityReduceMotion`.

#### Scenario: Retry invokes the injected closure

- **WHEN** the user taps the Retry button
- **THEN** the injected retry closure is invoked exactly once

#### Scenario: Send Feedback opens the container-failure mailto

- **WHEN** the user taps Send Feedback
- **THEN** the `\.openURL` environment is invoked with the URL returned by `FeedbackMailto.containerFailureURL(errorDomain:errorCode:)` for the current error

#### Scenario: View does not surface the error code to the user

- **WHEN** a user reads the body of `ContainerFailureView`
- **THEN** the visible text contains no `NSError.domain` value and no `NSError.code` value — those are carried only by the mailto body

---

### Requirement: Container-failure mailto payload is allow-list restricted

`FeedbackMailto.containerFailureURL(errorDomain:errorCode:)` SHALL build a `mailto:` URL whose subject is the localized `feedback.email.subject` followed by an English `" — container failure (<domain> <code>)"` suffix, and whose body contains only:

- A localized intro sentence.
- The English diagnostic block `Error domain: <domain>` and `Error code: <code>`.
- A localized closing user-prompt sentence.

The URL SHALL NOT carry any budget name, expense field, money value, free-text user content, or model identifier. The subject's diagnostic suffix and the body's `Error domain:` / `Error code:` labels stay in English so the maintainer's inbox is consistent across locales (mirroring `FeedbackMailto.diagnosticURL` from the `persistence-error-handling` capability).

#### Scenario: Subject contains the localized prefix and English diagnostic suffix

- **WHEN** `containerFailureURL(errorDomain: "NSCocoaErrorDomain", errorCode: 134_030)` is invoked
- **THEN** the URL's subject begins with the value of `feedback.email.subject` for the active locale and contains the literal substring `" — container failure (NSCocoaErrorDomain 134030)"`

#### Scenario: Body carries only domain + code as diagnostic values

- **WHEN** `containerFailureURL(errorDomain: D, errorCode: C)` is invoked
- **THEN** the URL's body contains exactly the localized intro, the literal `Error domain: D` and `Error code: C`, and the localized closing prompt — and contains no `budget_name`, `expense_name`, amount, date, notes, or model identifier

