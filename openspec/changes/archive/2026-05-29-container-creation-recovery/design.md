## Context

`simple_recurring_budgetsApp.init()` calls `Self.makeModelContainer()` which dispatches between a DEBUG launch-mode override and the production path. The production path (`makeProductionModelContainer`) tries CloudKit (`cloudKitDatabase: .automatic`), falls back to local-only (`cloudKitDatabase: .none`), and if **both** throw calls `fatalError(_:)`. The `@main` App struct then assigns the returned container to a stored `var sharedModelContainer: ModelContainer` and uses it as `.modelContainer(sharedModelContainer)` in `body`.

This is the only crash path in the codebase that's reachable from a user device. It is rare, but a crash is the worst possible UX and leaves the user nowhere to go (no Retry, no Send Feedback). The architecture audit (#5) calls it out and asks for a recovery surface.

Constraints we must respect:
- **MVVM / `@Observable` ownership rules** (tech-design §2.1): screens read state from an `@Observable` source-of-truth; methods that need to write take the dependency at the call site.
- **`diagnostic-logging` spec — CloudKit container backing entries**: today asserts the failure-path `Logger.cloudKit.error(...)` line emits "before `fatalError(_:)` terminates the process". We must update that requirement to drop the `fatalError` wording while preserving the log line.
- **Analytics boundary** (`docs/analytics-spec.md` §8/§17): the only diagnostic event currently allowed in the product-analytics stream is `persistence_save_failed`. Adding `container_creation_failed` would require another amendment. We intentionally defer it (see Decision 5).
- **Cross-cutting concerns** (`docs/main-prd.md` §6.8): accessibility, localized source strings, translations.

## Goals / Non-Goals

**Goals:**
- The app no longer crashes when `makeProductionModelContainer` fails on both paths.
- A minimal, accessible error screen with **Retry** and **Send Feedback**.
- Retry actually re-runs container creation (the failure can be transient, e.g. a brief permissions issue).
- Send Feedback opens a mailto carrying only the underlying NSError domain/code — no user data, consistent with the §5 allow-list philosophy.
- Existing `Logger.cloudKit.error` diagnostic still fires (audit + verify-time grep still finds it).

**Non-Goals:**
- Recovering the wedged store (we don't know how — that's a deep-data-repair problem we punt on).
- Adding a `container_creation_failed` analytics event (separate spec amendment if dashboard visibility becomes worth it).
- Changing CloudKit container configuration, schema migration, or write-path error handling (delivered in #9).
- Async/await rewrites of startup: container creation stays synchronous in the App `init`, just non-crashing.

## Decisions

### 1. `@Observable AppStartup` owns container + error state
Add `simple-recurring-budgets/App/AppStartup.swift`. The model exposes:
- `container: ModelContainer?` — `nil` while the failure screen is up.
- `containerBacking: ContainerBacking?` — `cloudKit` / `localFallback`, or `nil` on failure.
- `error: ContainerCreationFailure?` — typed struct with `errorDomain: String`, `errorCode: Int`.
- `func retry()` — re-runs `simple_recurring_budgetsApp.makeProductionModelContainer()` on the main actor and updates state.

The App struct holds the `AppStartup` as an `@State` value (or `@Observable` reference type captured via `@State`). `body` branches on `startup.container`.

**Why:** mirrors the @Observable pattern already used for `SyncStatus`, `AppSettings`, `Router`. Avoids a sentinel-Container hack and keeps the failure-state contract testable.

**Alternative considered:** make `sharedModelContainer` an optional `Optional<ModelContainer>` stored on the App struct directly. Rejected — the App struct can't easily own a mutable "current attempt" state without `@State`, and adding a Retry path requires a place to hang it; `AppStartup` gives us both.

### 2. Container creation moves to a static throwing function
Refactor `simple_recurring_budgetsApp.makeProductionModelContainer()` to `throws` and return `(ModelContainer, ContainerBacking)` on success. The body keeps the CloudKit → local-fallback sequence and the existing `Logger.cloudKit` log lines unchanged for the success and notice/info paths. On the both-failed branch, the existing `Logger.cloudKit.error(...)` line still fires; then we `throw` the local-fallback error instead of `fatalError(_:)`.

`AppStartup` catches the throw and populates `error`. `AppStartup.retry()` calls the same function again.

### 3. Body branch + sheet hosting
`simple_recurring_budgetsApp.body`'s `WindowGroup` becomes:
```
if let container = startup.container {
  RootView()
    .modelContainer(container)
    .environment(router) … etc
    .task { analytics.track(.appOpened) }
} else if let error = startup.error {
  ContainerFailureView(error: error, onRetry: startup.retry)
}
```
- On success path: identical to today. No regressions.
- On failure path: `RootView`, `Router`, `Settings`, analytics tracking are all skipped (we don't know if `AppSettings` / NSUbiquitousKeyValueStore can even be safely used in the wedged state). The failure view stands alone.

### 4. `ContainerFailureView` minimal contract
- `NavigationStack`-free `VStack` centered on the screen.
- Title (localized), body (localized — generic, no error code shown), Retry button (`.borderedProminent`), Send Feedback button (`.bordered`).
- `accessibilityElement(children: .combine)` on the title group; explicit `.accessibilityLabel` / `.accessibilityHint` on the two buttons.
- Send Feedback opens `FeedbackMailto.containerFailureURL(errorDomain:errorCode:)` via `openURL`.
- Dynamic Type supported (no fixed-size text); respects `accessibilityReduceMotion` (no animation we'd need to gate).

**Why no error code shown to the user:** users don't act on `134070`. The code is in the mailto body for triage; the visible body just reassures the user and offers Retry. Matches Apple's HIG voice for first-party error screens.

### 5. No `container_creation_failed` analytics event (this PR)
The `persistence_save_failed` precedent already documented one diagnostic event in the product-analytics stream as a narrow exception. Adding a second would require:
1. An `analytics-spec.md` §8/§17 amendment.
2. An `AnalyticsEvent.containerCreationFailed` constant and properties.
3. A sibling pattern at the throw site, plus consent-state assumptions during launch (we don't even know if `AnalyticsClient` is initialized at the moment of failure today).

Cost > value at this rarity. `Logger.cloudKit.error` already fires on-device; the failure path is also obvious to support (the user is staring at the failure view and clicked Send Feedback). Decision: skip in this PR; document the option in proposal.md for a future spec amendment.

### 6. `FeedbackMailto.containerFailureURL` variant
Add a sibling helper to `diagnosticURL`:
```
static func containerFailureURL(errorDomain: String, errorCode: Int) -> URL
```
- Subject: `"\(defaultSubject) — container failure (\(errorDomain) \(errorCode))"` — localized prefix, English suffix, same pattern as `diagnosticURL`.
- Body: localized intro + the diagnostic block `Error domain: …` / `Error code: …` (English labels) + localized closing prompt.
- No `Operation:` field because there's no `PersistenceOperation` here.

This stays inside the same payload allow-list philosophy (NSError domain/code only — no user data, no model identifiers, no free text). Doc note in `persistence-error-handling` spec is unaffected because that capability scopes to `context.save()`; this is a sibling mailto, not a sibling analytics event.

## Risks / Trade-offs

- **`AppSettings` / `SyncStatus` not constructed on failure path** → `RootView` and downstream views never see them, so this is safe. The failure view doesn't depend on either.
- **Retry could spin if the failure is permanent** → benign; the user can always close the app. We don't auto-retry. Pure user-driven gesture.
- **Synchronous container creation blocks `init()` briefly during Retry** → matches current launch latency; recreating a container is fast in the failure case (it throws quickly). No async refactor needed.
- **Migrations** → `makeProductionModelContainer` already passes `migrationPlan: BudgetMigrationPlan.self`. Migration-driven failures fall under the same Retry-or-Send-Feedback surface (with no recovery on our end — `Send Feedback` is the escape hatch).
- **What if the user has no Mail account configured** → the `mailto:` URL still opens whatever handler is registered; iOS Mail prompts. We don't detect this — same posture as the existing Settings Send Feedback link.

## Migration Plan

Pure additive code change. No data migration. No schema change. Rollback = revert the branch. The success path is bit-for-bit identical to today (same container creation, same log lines, same RootView wiring). Only behavior change is on the previously-crashing failure path.

## Open Questions

None blocking.
