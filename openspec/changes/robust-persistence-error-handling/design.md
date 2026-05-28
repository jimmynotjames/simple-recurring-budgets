## Context

Every production `context.save()` is `try?` (≈10 sites). Saves are `Void`-returning, so callers can't tell success from failure, and the interactive sheets call `dismiss()` unconditionally — a failed save looks like a success and the data vanishes on relaunch/sync. There is no logging, no user-facing error surface, and no developer signal. `docs/audits/architecture-audit-2026-04-30.md` ranks this the #1 risk.

Constraints we must respect:
- **MVVM / `@Observable`** (tech-design §2.1): view models expose write methods taking `ModelContext` at the call site; they don't store the context.
- **OSLog ↔ analytics boundary** (`diagnostic-logging` spec; `analytics-spec.md` §17): the two channels are independent and must not cross-route. The `diagnostic-logging` spec also requires that adding an OSLog category come with a new spec requirement in the same change.
- **Analytics allow/deny** (`analytics-spec.md` §5): no `ExpenseItem` field, no free text beyond `budget_name`, no money value beyond `budget_allocation_amount`.
- **Cross-cutting concerns** (main-prd §6.8): accessibility, localized strings, translations, analytics.

## Goals / Non-Goals

**Goals:**
- A single throwing save path that every production write uses; no silent `try?` saves remain in production code.
- Save failures are logged (`OSLog.error`) and reported to callers.
- Interactive failures keep the sheet open, show a Retry alert with input preserved, and escalate to a Send Feedback CTA after 3 consecutive failures of the same operation.
- Background failures log + emit the diagnostic analytics event without UI.
- A payload-restricted `persistence_save_failed` analytics event for dashboard visibility.

**Non-Goals:**
- Container-creation `fatalError` recovery (issue #132).
- Automatic retry/back-off, transactional rollback, or store-repair tooling.
- Changing the persisted schema, the CloudKit container, or conflict-resolution behavior.
- Routing OSLog data through analytics, or vice-versa.

## Decisions

### 1. `PersistenceError` + a thin throwing save helper
Add a `ModelContext.saveChanges(operation:)` helper (in `Domain`) that wraps `try context.save()`, and on throw: logs `Logger.persistence.error` with the operation id (public) + `error.localizedDescription` (public), fires the `persistence_save_failed` analytics event, and rethrows a `PersistenceError` carrying the operation id and a bucketed error domain/code.

- *Why:* one funnel guarantees every failure is logged + tracked identically; call sites just `try ctx.saveChanges(operation: .budgetCreate)`. Operation ids are a `PersistenceOperation` enum (compile-time, also the analytics `operation` value).
- *Analytics from the helper:* the helper needs the `AnalyticsClient`. View models already receive `analytics` at the call site; the helper takes `analytics` as a parameter (not stored), keeping the no-stored-dependency rule. Background callers pass their injected client.
- *Boundary compliance:* the OSLog line and the analytics event are **sibling** statements built from the same plain values (operation id, error domain/code) — neither derives from the other and no OSLog-shaped type crosses into `AnalyticsClient`. This is the "sibling call sites are allowed" case in the `diagnostic-logging` boundary requirement; we add a scenario making it explicit.
- *Alternative considered:* `Result`-returning saves. Rejected — `throws` composes better with the existing imperative write bodies and lets one `do/catch` at the call site drive the UI.

### 2. View models report failure; views own the UX
`save`/`delete` change from `Void` to `throws` (or to returning a discardable success flag). The view wraps the call in `do/catch`; on success it dismisses, on `catch` it populates a `SaveErrorState` and does not dismiss.

- *Why:* keeps presentation in the view (dismiss, alert, mailto) and persistence concerns in the VM/helper, matching the existing `save(context:)`-at-call-site contract.

### 3. Reusable `.saveErrorAlert` view modifier
A `SaveErrorState` (`@Observable` or a small struct in `@State`) holds: the failing operation, a `retry: () -> Void` closure, and a `consecutiveFailureCount`. A `.saveErrorAlert(_:)` modifier renders the alert: **Retry** (re-runs `retry`, increments count on repeat failure), **Cancel** (keeps the sheet open, input intact). When `consecutiveFailureCount >= 3`, the alert also shows **Send Feedback**, opening `feedbackMailtoURL` (lifted from `SettingsView` to a shared location) with the operation id + error domain/code appended to the subject/body — no user data.

- *Why a shared modifier:* Add/Edit Budget, Add/Edit Expense, Budget detail (inline add, swipe delete), and Budgets (reorder) all need identical behavior; a single modifier keeps copy, a11y, and the 3-strikes rule in one place.
- *Retry semantics:* "the same operation" = the same `retry` closure identity per presentation; a successful retry resets the count by clearing the state.

### 4. `persistence_save_failed` event shape
Properties: `operation` (enum raw value, e.g. `budget_create`, `expense_edit`, `reorder`, `lifecycle_reset`, `app_launch_dedup`), `error_domain` (string, e.g. `NSCocoaErrorDomain`), `error_code` (Int). No names, amounts, dates, ids. Registered in `analytics-spec.md` §9/§10 and added to `AnalyticsEvent`/`AnalyticsProperty`.

- *Why these fields:* enough to triage on a dashboard (which operation, what class of failure) while staying within the §5 allow-list. Error code is a small enum-like integer, not user-derived.

### 5. Interactive vs background classification
A save is *interactive* iff it originates from a sheet/screen with a `dismiss`/presentation context: Add/Edit Budget, Add/Edit Expense, inline expense add/edit, swipe-delete, reorder, and the lifecycle write-paths triggered by explicit user taps (pause/resume/reset/allocation-edit). *Background* = saves with no presenting UI: `BudgetLifecycleService` rollover saves invoked from an eager refresh, and the app-launch dedup in `simple_recurring_budgetsApp`. Background callers still go through the helper (log + analytics) but don't construct a `SaveErrorState`.

- *Lifecycle nuance:* `BudgetLifecycleService` methods become `throws`; UI callers catch and present, the eager-refresh caller catches and logs (the rollover self-heals on the next refresh, so swallowing-after-logging is acceptable there).

## Risks / Trade-offs

- **Scope breadth (every write path touched)** → Mitigate with the single helper so each site is a one-line change; specs modified are limited to the save/delete/persist requirements, not full rewrites.
- **Analytics event is consent-gated, so under-reports** → Documented as best-effort; OSLog remains the complete on-device record. Not a regression (today there's neither).
- **Retry re-runs the whole save body** → Save bodies are idempotent for Edit (diff-then-write) and for Add the not-yet-saved object is already inserted, so a retried `save()` re-attempts the same `context.save()` without duplicating inserts. Verified per-site in tasks.
- **Boundary perception (diagnostic event in product stream)** → Explicitly amend `analytics-spec.md` §8/§17 and add a `diagnostic-logging` scenario so the allowance is documented, not implicit.
- **mailto with error context** → Only operation id + error domain/code go in the body; no budget/expense content.

## Migration Plan

Pure additive/internal-refactor; no data migration. Land helper + `PersistenceError` + logger category + analytics event first (compiles, behavior-neutral except logging), then convert call sites and wire the alert modifier, then docs + translations. Rollback = revert the branch; no persisted state changes.

## Open Questions

None blocking. (Container `fatalError` recovery intentionally deferred to #132.)
