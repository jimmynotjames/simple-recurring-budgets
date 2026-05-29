## MODIFIED Requirements

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
