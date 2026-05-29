## 1. Foundation: AppStartup + non-crashing container creation

- [x] 1.1 Refactor `simple_recurring_budgetsApp.makeProductionModelContainer()` to `throws -> (ModelContainer, ContainerBacking)`. Keep the existing success/notice/info `Logger.cloudKit` log lines untouched; preserve the `Logger.cloudKit.error("cloudkit.container.failed: …")` line; remove the trailing `fatalError(_:)` call and `throw` the local-fallback error instead.
- [x] 1.2 Add `simple-recurring-budgets/App/AppStartup.swift` — `@Observable @MainActor` model with `container: ModelContainer?`, `containerBacking: ContainerBacking?`, `error: ContainerCreationFailure?`, and `func retry()`. `ContainerCreationFailure` carries `errorDomain: String` and `errorCode: Int`; `init(underlying: any Error)` bridges through `NSError`.
- [x] 1.3 Update `simple_recurring_budgetsApp.init()` to construct `AppStartup` via the new throwing path, populating either the success or the failure branch without crashing. Keep the DEBUG launch-mode dispatch (`makeModelContainer`) intact for non-production paths.
- [x] 1.4 Swift Testing: `AppStartupTests` covering the four scenarios in `container-creation-recovery` spec (success first attempt; failed first attempt → typed error; successful retry clears error; failed retry updates error without crash). Use a stub `makeContainer: () throws -> (ModelContainer, ContainerBacking)` closure to avoid hitting real CloudKit.

## 2. Container-failure mailto

- [x] 2.1 Add `FeedbackMailto.containerFailureURL(errorDomain:errorCode:)` mirroring `diagnosticURL`. Localized subject prefix + English `" — container failure (<domain> <code>)"` suffix; localized intro/closing prompt with `Error domain:` / `Error code:` English labels.
- [x] 2.2 Register the 3 new localizable keys (`containerFailure.email.subjectSuffix` if needed — or reuse `feedback.email.subject`; `containerFailure.email.body.intro`; `containerFailure.email.body.prompt`) with translator comments.
- [x] 2.3 Swift Testing: `FeedbackMailtoContainerFailureTests` — subject contains the expected English diagnostic suffix; body contains only the diagnostic labels + values; no user-data sentinels (`budget_name`, `amount`, etc.) appear.

## 3. ContainerFailureView

- [x] 3.1 Add `simple-recurring-budgets/Views/ContainerFailureView.swift` — `VStack` centered: title, body, `Retry` button (`.borderedProminent`), `Send Feedback` button (`.bordered`). Reads `\.openURL` from environment. Takes `error: ContainerCreationFailure` and `onRetry: () -> Void` at init.
- [x] 3.2 Register the localizable keys for title, body, Retry, and Send Feedback (`containerFailure.title`, `containerFailure.body`, `containerFailure.action.retry`, `containerFailure.action.sendFeedback`) with translator comments.
- [x] 3.3 Accessibility: explicit `accessibilityLabel` / `accessibilityHint` on each button; verify Dynamic Type scaling; respect `accessibilityReduceMotion` (no in-view animations).
- [x] 3.4 DEBUG SwiftUI preview showing the view with a stub error.

## 4. Wire the App body branch

- [x] 4.1 Update `simple_recurring_budgetsApp.body` to branch on `startup.container`. Success path runs `RootView()` with `.modelContainer(container)` and the existing environment + `.task { analytics.track(.appOpened) }`. Failure path runs `ContainerFailureView(error:, onRetry:)`. Failure path does NOT construct `RootView`, `Router`, `AppSettings`, `SyncStatus`, or pass the analytics environment.
- [x] 4.2 Manually verify (DEBUG run): the success path is unchanged; force a failure (e.g. via a transient throwing override) and confirm the failure view appears, Retry re-attempts, and Send Feedback opens the mailto with only domain/code in the body.

## 5. Docs + translations

- [x] 5.1 Mark risk #5 (`fatalError on container creation`) resolved in `docs/audits/architecture-audit-2026-04-30.md` with a pointer to this change.
- [x] 5.2 Skim `docs/tech-design-doc.md` §7 — no logger category change here; only narrative note that the error line precedes a recovery surface, not a crash.
- [x] 5.3 Translations: run the `translate-new-strings` skill on the new `containerFailure.*` + `containerFailure.email.*` keys; bring all 38 storefront locales current.
- [x] 5.4 Verify `scripts/check_translations.py` exits 0.

## 6. Build gate + verify

- [x] 6.1 `make format`.
- [x] 6.2 `make lint-fix`.
- [x] 6.3 `make build`.
- [x] 6.4 `make test`.
- [x] 6.5 Run `/opsx:verify` and fix anything it flags.
