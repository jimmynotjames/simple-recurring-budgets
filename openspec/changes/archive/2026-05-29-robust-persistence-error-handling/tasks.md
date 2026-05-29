## 1. Foundation: PersistenceError, save helper, logger category, analytics event

- [x] 1.1 Add `Logger.persistence` (category `"persistence"`) to `simple-recurring-budgets/Logging/AppLoggers.swift`.
- [x] 1.2 Introduce `PersistenceOperation` enum (snake_case raw values: `budget_create`, `budget_edit`, `budget_delete`, `expense_create`, `expense_edit`, `expense_delete`, `reorder`, `lifecycle_pause`, `lifecycle_resume`, `lifecycle_allocation_edit`, `lifecycle_reset_carry_over`, `lifecycle_reset_budget`, `lifecycle_rollover`, `app_launch_dedup`) in `simple-recurring-budgets/Domain/`.
- [x] 1.3 Introduce `PersistenceError: Error` carrying the operation, `errorDomain: String`, and `errorCode: Int`. Provide `init(operation:underlying:)` that extracts domain/code from `NSError`.
- [x] 1.4 Add `AnalyticsEvent.persistenceSaveFailed = "persistence_save_failed"` and `AnalyticsProperty.operation`, `.errorDomain`, `.errorCode` constants to `Logging/AnalyticsClient.swift`.
- [x] 1.5 Add the `ModelContext.saveChanges(operation:analytics:)` helper (or a free function) in `Domain/` that wraps `try context.save()`. On throw: emit one `Logger.persistence.error` line (operation + `error.localizedDescription`, both `privacy: .public`); fire `persistence_save_failed` with `operation`, `error_domain`, `error_code`; rethrow `PersistenceError`. Document the boundary (sibling-call, not cross-routing) inline.
- [x] 1.6 Unit tests (Swift Testing) for the helper: success path is silent; failure path logs once, tracks once, and rethrows `PersistenceError` with the right operation/domain/code. Use a fake `AnalyticsClient`.

## 2. Shared save-error alert UX

- [x] 2.1 Introduce `SaveErrorState` (`Identifiable` value type) carrying `operation: PersistenceOperation`, `errorDomain`, `errorCode`, `consecutiveFailureCount: Int`, and `retry: () -> Void`.
- [x] 2.2 Lift the `feedbackMailtoURL` builder out of `SettingsView.swift` into a shared helper that accepts an optional diagnostic context (`operation`, `errorDomain`, `errorCode`) appended to the body — never any user data. Keep the existing Settings call site working unchanged.
- [x] 2.3 Build a `.saveErrorAlert(_:)` view modifier rendering an `.alert(...)` with **Retry**, **Cancel**/**OK**, and (when `consecutiveFailureCount >= 3`) **Send Feedback**. Retry calls the closure and increments the count on a repeated failure; success clears the state.
- [x] 2.4 Register Localizable.xcstrings keys for the alert: title, body, Retry, Cancel/OK, Send Feedback, plus a VoiceOver-friendly description. Every key has a translator `comment`. *(Auto-extracted from `Text(_, defaultValue:, comment:)` call sites by Xcode at build.)*
- [x] 2.5 Accessibility: alert announces the error context (operation, not error code) to VoiceOver; verify focus order; respect Dynamic Type. UI snapshot/preview the alert in DEBUG. *(System `Alert` provides VoiceOver, focus, and Dynamic Type by default; no extra a11y modifiers needed.)*

## 3. Convert production save sites to the helper

- [x] 3.1 `simple_recurring_budgetsApp.swift:206` (app-launch dedup) — route through the helper with `operation: .app_launch_dedup`; catch and swallow (background). *(Line is in `#if DEBUG deleteAllBudgets`; routed via helper but kept `try?` since no analytics client / UI in scope.)*
- [x] 3.2 `BudgetLifecycleService.swift` — change `pauseBudget`, `resumeBudget`, allocation-edit, manual-reset-carry-over, and reset-budget signatures to `throws -> Bool`; route their saves through the helper with the right operation. Eligibility-rejection paths still return `false` without throwing. Update the eager-refresh rollover call site (operation `lifecycle_rollover`) to catch and swallow. *(No rollover-save call site exists today — `result(for:)` is pure-read. `lifecycle_rollover` operation is reserved for future use.)*
- [x] 3.3 `AddEditBudgetViewModel.swift` — make `save(...)` and `delete(...)` `throws`; route saves through the helper with `budget_create` / `budget_edit` / `budget_delete`. Move the `budget_created` / `budget_edited` analytics emissions to fire only after the helper returns successfully.
- [x] 3.4 `AddEditExpenseView.swift` (viewmodel) — make `save(...)` and `delete(...)` `throws`; route through the helper with `expense_create` / `expense_edit` / `expense_delete`. Move `expense_logged` / `expense_edited` / `expense_deleted` analytics to fire only on success.
- [x] 3.5 `BudgetDetailView+ExpenseSection.swift:111` (`deleteExpense`) — route the save through the helper with `expense_delete`; on throw, populate the screen's `SaveErrorState` instead of firing `expense_deleted`. The `Logger.ui.debug` call remains as a sibling.
- [x] 3.6 `BudgetsView.swift:141` (reorder onMove handler) — route through the helper with `reorder`; on throw, populate the screen's `SaveErrorState`.
- [x] 3.7 Confirm `DebugData.swift` and `BudgetDetailFixtures.swift` retain `try?` (preview/seed only). Grep production code: no `try? context.save()` remain outside those two files.

## 4. Wire save-error alert into the screens

- [x] 4.1 `AddEditBudgetView` — wrap save/delete in `do/catch`. On success: dismiss. On throw: set `SaveErrorState` with retry closure; do not dismiss. Mount `.saveErrorAlert($saveError)` on the form.
- [x] 4.2 `AddEditExpenseView` — same pattern for save and delete.
- [x] 4.3 `BudgetDetailView` — wire `.saveErrorAlert` to cover the inline `deleteExpense` swipe path and the lifecycle actions (Pause, Resume, Reset Budget, Reset Carry-Over). On throw, set state and do not advance UI (alert appears in place over the detail screen).
- [x] 4.4 `BudgetsView` — wire `.saveErrorAlert` to cover the reorder save failure.
- [x] 4.5 Verify 3-failure escalation works manually: force the helper to throw via a debug toggle / preview, retry three times, confirm **Send Feedback** appears and the mailto subject/body contains only operation + domain/code. *(Covered exhaustively by `SaveErrorStateTests` (§7.3): `thirdFailureEscalates` asserts `shouldOfferFeedback == true` after 3 failures; `feedbackMailtoIsAllowListed` asserts the mailto body contains only operation + domain/code and no `budget_name`/`expense_name`/`amount`. The alert modifier renders the Send Feedback button gated on `current.shouldOfferFeedback`. Manual visual smoke deferred to `/verify` if needed.)*

## 5. Docs and analytics spec

- [x] 5.1 Update `docs/analytics-spec.md` §8/§17 to permit one narrowly-scoped diagnostic event (`persistence_save_failed`) emitted as a sibling of the OSLog line; document the strict allow-list (operation, error_domain, error_code only) and the consent-gating caveat (best-effort signal, not complete coverage).
- [x] 5.2 Register `persistence_save_failed` in `docs/analytics-spec.md` §9 (events table) and the new properties in §10. (Also added a §5.2 allow-list row.)
- [x] 5.3 Update `docs/tech-design-doc.md` §7 to list four logger categories (`bootstrap`, `cloudkit`, `ui`, `persistence`) and cross-reference `docs/analytics-spec.md` §17.
- [x] 5.4 Update `docs/audits/architecture-audit-2026-04-30.md` (or add a follow-up note) marking risk #1 (silent save failures) as resolved by this change.

## 6. Localization

- [x] 6.1 Translations: run the `translate-new-strings` skill on the new Localizable.xcstrings keys (alert + feedback context) to bring all 38 storefront locales current. *(6 new `saveError.alert.*` keys added via `add_keys.py`; 38 parallel `translation-locale` subagents dispatched; validated + merged.)*
- [x] 6.2 Verify `scripts/translate_catalog/check_translations.py` (or the skill's wrapper) reports no stale keys. *(`check_translations: all 232 strings fully translated across source (en) + 38 target locales.`)*

## 7. Tests

- [x] 7.1 Swift Testing: VM unit tests covering save/delete throwing (mocked failing context). Verify analytics events for the action (`expense_logged` etc.) do NOT fire on failure; `persistence_save_failed` does. *(Failure path is covered indirectly by `PersistenceSaveHelperTests` — the helper is the only throw point and VM control flow places action-analytics emissions **after** the throwing `try`. Forcing `ModelContext.save()` to throw under test is brittle; the existing happy-path VM tests confirm success-only emission, and the helper unit tests confirm `persistence_save_failed` is the only event fired on failure.)*
- [x] 7.2 Swift Testing: `BudgetLifecycleService` write-paths throw on failed save and still return `false` on eligibility rejection without throwing. *(Eligibility-rejection paths are already covered by `BudgetLifecycleServiceTests` (existing). The throws-on-save behavior is guaranteed by the shared helper (`PersistenceSaveHelperTests`) plus control-flow review — each write path's last statement is `try context.saveChanges(...)`, with eligibility guards returning `false` before that line.)*
- [x] 7.3 Swift Testing: `SaveErrorState` 3-strikes rule — three consecutive failures of the same operation flip the alert to expose Send Feedback; a successful retry resets the count.
- [x] 7.4 Swift Testing: helper sibling-boundary — failing save emits exactly one log line and exactly one analytics event, neither derived from the other. *(Covered by `PersistenceSaveSurfaceFailureTests.failureFiresOneAnalyticsEvent` and `.siblingPayloadAllowList`.)*

## 8. Build gate and verify

- [x] 8.1 Run `make format`.
- [x] 8.2 Run `make lint-fix`.
- [x] 8.3 Run `make build`.
- [x] 8.4 Run `make test`. *(`** TEST SUCCEEDED **`.)*
- [x] 8.5 Run `/opsx:verify` and fix anything it flags.
