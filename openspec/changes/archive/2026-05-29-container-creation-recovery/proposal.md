## Why

`makeProductionModelContainer` in `simple_recurring_budgetsApp.swift` tries CloudKit, falls back to local-only, and if **both** fail calls `fatalError(_:)` — the app crashes with no recovery path. This is risk #5 in `docs/audits/architecture-audit-2026-04-30.md`. The failure mode is rare (a corrupted SQLite store or a permissions issue), but a crash is the worst possible UX and the user has no path to retry or reach out for help. Resolves issue #132 (split out from #9 part D).

## What Changes

- Introduce an `@Observable AppStartup` model owning container creation and its result. The model exposes `container: ModelContainer?`, a typed `error: ContainerCreationFailure?` (with `errorDomain: String`, `errorCode: Int`), and `func retry()` that re-runs `makeProductionModelContainer` and updates state.
- Rework `simple_recurring_budgetsApp.init()` so it constructs `AppStartup` *without* crashing on container failure. The body branches: success → `RootView()` with `.modelContainer(container)` as today; failure → a new `ContainerFailureView`.
- Add `ContainerFailureView`: minimal SwiftUI screen with title ("Couldn't open your data"), an explanatory body, a **Retry** button (calls `AppStartup.retry()`), and a **Send Feedback** button (opens a new `FeedbackMailto.containerFailureURL(errorDomain:errorCode:)` carrying only the NSError domain + code — never user data).
- **BREAKING (internal):** `makeProductionModelContainer` no longer terminates the process. Drop `fatalError(_:)` and return the error to the caller. The existing `Logger.cloudKit.error("cloudkit.container.failed: …")` line still fires before surfacing the error.
- No analytics event in this scope. The failure mode is rare; OSLog already records it; adding `container_creation_failed` would require another amendment to `docs/analytics-spec.md` §8/§17 and is deferred unless dashboard visibility becomes a need.

## Capabilities

### New Capabilities
- `container-creation-recovery`: the contract for the container-failure surface — no crash, the error screen, Retry semantics, Send Feedback CTA, and the strict NSError-domain/code allow-list on the mailto body.

### Modified Capabilities
- `diagnostic-logging`: the existing "CloudKit container backing log entries" requirement scenario asserts the error line fires "before `fatalError(_:)` terminates the process". That wording goes — the error line still fires before the failure is surfaced to `AppStartup`, but no `fatalError` follows.

## Impact

- Code: `simple-recurring-budgets/App/simple_recurring_budgetsApp.swift` (App struct + `makeProductionModelContainer`); new `simple-recurring-budgets/App/AppStartup.swift`; new `simple-recurring-budgets/Views/ContainerFailureView.swift`; small addition to `simple-recurring-budgets/Domain/FeedbackMailto.swift` (`containerFailureURL`).
- Strings: new user-visible strings (title, body, Retry, Send Feedback) plus the container-failure mailto subject + body intro / closing prompt → translations queue via `translate-new-strings`.
- Docs: `docs/audits/architecture-audit-2026-04-30.md` (mark risk #5 resolved); optional cross-reference in `docs/tech-design-doc.md` §7 if needed. No change to `docs/analytics-spec.md`, `docs/main-prd.md`, `docs/product-features-planning.md`, the data model, or the CloudKit container configuration.

## Doc alignment

Skimmed `docs/main-prd.md`, `docs/product-features-planning.md`, `docs/tech-design-doc.md`, and the architecture audit. No conflict: the audit explicitly calls for replacing the `fatalError` with a recovery surface (§3.7 "fatalError is unrecoverable"). Cross-cutting checklist (`docs/main-prd.md` §6.8) addressed — accessibility, localized source strings, translations queue all handled; Mixpanel event intentionally skipped per the rationale above and documented in design.md.
