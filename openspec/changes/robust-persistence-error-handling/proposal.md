## Why

Every `context.save()` in production today uses `try?`, silently discarding the error (catalogued as the #1 risk in `docs/audits/architecture-audit-2026-04-30.md`). The interactive screens then call `dismiss()` unconditionally, so a failed save is indistinguishable from a successful one: the sheet closes, the in-memory row appears, and the data is gone on next launch or CloudKit sync. There is no logging, no user-facing error state, and no signal that reaches the developer. A user whose store is wedged has a silently unusable app. This resolves issue #9 (Parts A–C; the container-creation `fatalError` recovery is tracked separately in #132).

## What Changes

- **Throwable saves (foundation).** Introduce a single persistence-save path that surfaces failure to the caller. All production `try? context.save()` sites route through it; `DebugData.swift` and `BudgetDetailFixtures.swift` (debug/preview only) are excluded.
- **Diagnostic logging.** Add a fourth `OSLog` category (`persistence`) to `AppLoggers.swift` and log every save failure at `.error` with the operation identifier and the framework error description (privacy-public), per the `diagnostic-logging` spec's "add a category ⇒ add a requirement" rule.
- **Interactive error UX.** View-model `save`/`delete` and the interactive lifecycle write-paths report success/failure to the view. On failure the sheet does **not** dismiss; a standard save-error alert appears with **Retry** (input preserved). After 3 consecutive failed retries of the same operation, the alert additionally offers **Send Feedback**, opening the existing Settings mailto prefilled with non-PII error context.
- **Background save behaviour.** Lifecycle/background saves with no presenting sheet (e.g. `BudgetLifecycleService` rollovers invoked off a refresh, app-launch dedup) log and fire the diagnostic analytics event but show no alert.
- **Diagnostic analytics event.** Add one narrowly-scoped product-analytics event, `persistence_save_failed`, carrying only an operation/screen identifier and a bucketed error domain/code — **no** budget/expense field, money value, or free text. Fired at every save-failure site (interactive + background). Consent-gated, hence best-effort.
- **BREAKING (internal API only):** `AddEditBudgetViewModel.save`, `AddEditExpenseViewModel.save`, their `delete` methods, and the `BudgetLifecycleService` write-paths change signatures to report failure. No persisted-data or public behavior break.

## Capabilities

### New Capabilities
- `persistence-error-handling`: the cross-cutting persistence-save contract — the throwing save path, the interactive save-error UX (alert + Retry + escalation to Send Feedback after 3 failures, no dismiss-on-failure, input preserved), the background-save (log-only) behaviour, and the `persistence_save_failed` diagnostic analytics event with its strict allow-listed payload.

### Modified Capabilities
- `diagnostic-logging`: add the `persistence` logger category (was exactly three) and a new requirement for save-failure logging; add a boundary scenario confirming a save failure may emit a sibling `Logger.persistence.error` and a `persistence_save_failed` analytics event without cross-routing.
- `add-edit-budget-screen`: save (Add + Edit) and delete report failure; the view dismisses only on success and otherwise shows the save-error alert.
- `add-edit-expense-screen`: save (Add + Edit) and delete report failure; dismiss only on success.
- `budget-detail-screen`: inline expense save and swipe-to-delete surface save failures instead of silently dropping them.
- `budgets-screen`: drag-to-reorder persistence surfaces a save failure instead of silently leaving the reorder unpersisted.
- `budget-lifecycle`: the pause, resume, allocation-edit, reset-carry-over, and reset-budget write-paths report save failure to their callers (interactive callers present the alert; background callers log only).

## Impact

- Code: `simple-recurring-budgets/Domain` (new persistence helper + `PersistenceError`; `BudgetLifecycleService`), `Logging/AppLoggers.swift`, `Logging/AnalyticsClient.swift` (+ `Analytics+DomainExtensions.swift`), `Views/AddEditBudgetViewModel.swift`, `Views/AddEditExpenseView.swift`, `Views/BudgetDetailView*.swift`, `Views/BudgetsView.swift`, `App/simple_recurring_budgetsApp.swift`, plus a reusable save-error alert view modifier.
- Strings: new user-visible strings (alert title/body/buttons) in `Localizable.xcstrings` ⇒ translations queue via the `translate-new-strings` skill.
- Docs: `docs/analytics-spec.md` (§8/§9/§10/§17 — register `persistence_save_failed` and amend the OSLog↔analytics boundary to permit the sibling diagnostic event), `docs/tech-design-doc.md` §7 (fourth logger category), and the architecture-audit follow-up. No data-model or schema change; no CloudKit container change.

## Doc alignment

Skimmed `docs/main-prd.md`, `docs/product-features-planning.md`, `docs/tech-design-doc.md`, `docs/analytics-spec.md`.
- `main-prd.md` §6.8 cross-cutting concerns (accessibility, localized strings, translations, analytics) all apply and are addressed.
- `analytics-spec.md` §8/§17 currently mandate a strict OSLog↔analytics separation with no diagnostic events in the product stream. Adding `persistence_save_failed` **intentionally amends** this: a single, payload-restricted diagnostic event is permitted, emitted as a sibling of the OSLog line (not cross-routed). This doc update is in scope and listed under Impact.
- `tech-design-doc.md` §7 lists the OSLog categories and must gain `persistence`.
No conflict with `product-features-planning.md` feature IDs.
