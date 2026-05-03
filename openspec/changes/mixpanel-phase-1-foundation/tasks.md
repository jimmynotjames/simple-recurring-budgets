## 1. Pre-flight

- [ ] 1.1 Re-skim [`docs/main-prd.md`](../../../docs/main-prd.md) §6.3, [`docs/product-features-planning.md`](../../../docs/product-features-planning.md) F-8.02, [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §§4.5 / 7 / 9, and [`docs/analytics-spec.md`](../../../docs/analytics-spec.md) §§2 / 3 / 5 / 6 / 7 / 8 / 8.1 / 9 / 10 / 16 / 16.1 / 17 / 18.1 / 19 to confirm no doc has shifted since the proposal was written.
- [ ] 1.2 Re-skim [`openspec/specs/diagnostic-logging/spec.md`](../../../openspec/specs/diagnostic-logging/spec.md) (`oslog-diagnostic-logging` capability) to confirm the F-8.01 boundary contract is unchanged. Confirm the four destructive-action `Logger.ui.debug` call sites are still in place at `BudgetDetailView.resetBudget`, `BudgetDetailView.resetCarryOver`, `AddEditBudgetViewModel.delete(context:)`, and `BudgetDetailView+ExpenseSection.deleteExpense(_:)`.
- [ ] 1.3 Confirm the implementation starting state matches [`docs/analytics-spec.md` §16.1](../../../docs/analytics-spec.md#161-implementation-starting-state-codebase-snapshot): `MixpanelAnalyticsClient.swift` calls `Mixpanel.initialize` in `init`; `simple_recurring_budgetsApp.init()` constructs `MixpanelAnalyticsClient(token:isOptedIn: { false })`; `AnalyticsEvent.appOpened = "app_opened"` already exists.
- [ ] 1.4 Confirm `mixpanel-swift` SPM dependency is resolved in `simple-recurring-budgets.xcodeproj` and no package add is required.

## 2. ConsentJurisdiction helper

- [ ] 2.1 Create `simple-recurring-budgets/Settings/ConsentJurisdiction.swift` with a `JurisdictionKind` enum (`required`, `auto_optin`) and a static `kind(for:)` function accepting `Locale.Region?` (or equivalent `String?` region identifier). Mirror the §7.2 region table from [`docs/analytics-spec.md`](../../../docs/analytics-spec.md#72-strict-opt-in-jurisdictions-and-the-first-run-consent-sheet) into a private static `Set<String>` of region codes.
- [ ] 2.2 Implementation note: For Phase 1, treat `CA` (Canada) as `.required` per §7.2's pragmatism clause. Comment cites §7.2 so the trade-off is discoverable.
- [ ] 2.3 Verify `ConsentJurisdiction` is `Sendable`-clean (pure function, no static state) and has no dependency on `Locale.current` (the caller passes the region in).

## 3. AppSettings extensions

- [ ] 3.1 In `simple-recurring-budgets/Settings/AppSettings.swift`, add `static let analyticsOptInKey = "analyticsOptIn"` and `static let analyticsDistinctIdKey = "analyticsDistinctId"` alongside the existing key constants.
- [ ] 3.2 Add an `analyticsOptIn: Bool` property. On read from `NSUbiquitousKeyValueStore`: if absent, resolve via `ConsentJurisdiction.kind(for: Locale.current.region)` — `.required` → `false`, `.auto_optin` → `true`. **Do NOT persist the resolved default.** Persistence happens only on explicit write (toggle or consent decision). Wire `@Observable` change notifications.
- [ ] 3.3 Add a derived read-only `var analyticsOptInExplicitlySet: Bool` (or equivalent — naming choice should match the existing `defaultCarryOverEnabledExplicitlySet` convention if one exists; otherwise introduce this as a new pattern). Returns `true` iff the backing store contains a value for `"analyticsOptIn"`. This is consumed by the consent-sheet trigger (Section 6 below).
- [ ] 3.4 Add an `analyticsDistinctId: String` property with `internal(set)` (or `private(set)`) on the setter. On read: if the backing store contains no value for `"analyticsDistinctId"`, generate via `UUID().uuidString`, write to the store, call `synchronize()`, and return. Otherwise return the stored value verbatim.
- [ ] 3.5 Wire `"analyticsOptIn"` and `"analyticsDistinctId"` into the `didChangeExternallyNotification` reload path so iCloud-paired writes propagate. Confirm both properties emit `@Observable` change notifications when the external value differs from the in-memory value.
- [ ] 3.6 Confirm both new keys are listed in the `KeyValueStore` protocol's read/write surface (no protocol change should be needed since `String` set/get is already supported).

## 4. AnalyticsClient surface — events and properties

- [ ] 4.1 In `simple-recurring-budgets/Logging/AnalyticsClient.swift`, extend `AnalyticsEvent` with the Phase 1 constants from [`docs/analytics-spec.md` §9](../../../docs/analytics-spec.md#9-phase-1-events): `budgetCreated = "budget_created"`, `budgetEdited = "budget_edited"`, `budgetDeleted = "budget_deleted"`, `budgetReset = "budget_reset"`, `carryOverReset = "carry_over_reset"`, `expenseLogged = "expense_logged"`, `expenseEdited = "expense_edited"`, `expenseDeleted = "expense_deleted"`, `settingsOpened = "settings_opened"`, `settingChanged = "setting_changed"`, `analyticsConsentChanged = "analytics_consent_changed"`. Preserve the existing `appOpened = "app_opened"` constant.
- [ ] 4.2 Add a new `AnalyticsProperty` enum (or `enum`-shaped namespace) carrying the §10.1 / §10.2 / §10.3 keys per the `product-analytics` capability spec's `AnalyticsProperty canonical key catalog` requirement. Use `static let` constants whose raw values match the snake_case keys exactly.
- [ ] 4.3 Confirm the `AnalyticsClient` protocol shape (track / identify / reset / convenience overload) is unchanged; the surface stays minimal.

## 5. MixpanelAnalyticsClient — lazy init refactor

- [ ] 5.1 Refactor `simple-recurring-budgets/Logging/MixpanelAnalyticsClient.swift` to accept `(token: String, isOptedIn: @escaping @Sendable () -> Bool, distinctIdProvider: @escaping @Sendable () -> String?)` in its constructor. **Remove** the `Mixpanel.initialize(...)` call from `init`.
- [ ] 5.2 Introduce a one-shot init guard. Use `OSAllocatedUnfairLock<MixpanelInstance?>` (preferred) or a hand-wrapped `os_unfair_lock` over a `MixpanelInstance?` cell. The `withLock` block stores the lazily-initialized instance.
- [ ] 5.3 In `track(_:properties:)`: guard on `isOptedIn()`; if true, call `ensureInitialized()` and forward the event to the returned `MixpanelInstance`. Reuse the existing `MixpanelType` filter for property values.
- [ ] 5.4 In `identify(_:)`: guard on `isOptedIn()`; if true, call `ensureInitialized()` (the lazy-init flow already calls identify with the provider value, so explicit identifies typically pass the same value but the path remains supported for future callers).
- [ ] 5.5 Implement `ensureInitialized()`:
  - Take the lock.
  - If state is non-nil, return it.
  - Call `Mixpanel.initialize(token: token, trackAutomaticEvents: false)` to create the instance.
  - Call `registerSuperProperties(on: instance)` (Section 7) with the §10.2 super-property dictionary.
  - If `distinctIdProvider()` returns a non-nil string, call `instance.identify(distinctId:)` with it AND set the §10.3 baseline people properties (`first_seen_at` via `peopleSetOnce`, `last_app_open_at`, etc.).
  - Store the instance in the lock state and return.
- [ ] 5.6 In `reset()`: take the lock; if state is non-nil, call `state.reset()`; set the lock state back to `nil` so a subsequent opted-in track re-initializes cleanly.
- [ ] 5.7 Add `registerSuperProperties(on:)` and `peopleProperties(...)` helpers per Sections 7 and 8.
- [ ] 5.8 Add `Mixpanel.flushBatchSize` tuning for Low Data Mode per [`docs/analytics-spec.md` §16](../../../docs/analytics-spec.md#16-build-hygiene) (a conservative value documented in code comment).

## 6. App-entry wiring + consent sheet plumbing

- [ ] 6.1 In `simple-recurring-budgets/App/simple_recurring_budgetsApp.swift`, replace the hard-coded `MixpanelAnalyticsClient(token:isOptedIn: { false })` construction with one that captures `[settings]` and reads `settings.analyticsOptIn` AND `settings.analyticsDistinctId` lazily inside the closures. The `analytics` property wiring and the `body.task { analytics.track(AnalyticsEvent.appOpened) }` call SHALL remain.
- [ ] 6.2 The `#if DEBUG` token branch (dev token literal) / `#else` (prod token literal) SHALL remain unchanged. **DO NOT** move tokens to `xcconfig` or `Info.plist` — explicitly forbidden by [`docs/analytics-spec.md` §16](../../../docs/analytics-spec.md#16-build-hygiene) and F-8.02 Edge Cases.
- [ ] 6.3 Add a `case .analyticsConsent` to the existing `Router.sheet` enum (location: wherever the sheet enum lives — likely `simple-recurring-budgets/Views/Routing/`). Wire the new case into the sheet host's `switch` so presenting `Router.sheet = .analyticsConsent` shows `AnalyticsConsentSheet`.
- [ ] 6.4 Create `simple-recurring-budgets/Views/Consent/AnalyticsConsentSheet.swift` with a SwiftUI `View` that shows the title + body + Accept + Decline buttons. Inject `AppSettings` via `@Environment(AppSettings.self)` and `analytics` via `@Environment(\.analytics)`.
  - **Accept** action: `settings.analyticsOptIn = true` (which persists), then `analytics.track(AnalyticsEvent.analyticsConsentChanged, properties: [AnalyticsProperty.newValue.rawValue: true])`, then dismiss.
  - **Decline** action: `settings.analyticsOptIn = false` (persists), dismiss. **Do NOT** fire `analytics_consent_changed` on decline (the SDK is not initialized; there is no live session to record on).
  - Treat `.interactiveDismissDisabled(false)` swipe-down as Decline (set `settings.analyticsOptIn = false` then dismiss).
- [ ] 6.5 Wire the consent-sheet trigger into `AddEditBudgetViewModel.save(...)` Add-mode success branch (or wherever the post-save side-effect lands today). After firing `budget_created`, check `ConsentJurisdiction.kind(for: Locale.current.region) == .required` AND `settings.analyticsOptInExplicitlySet == false`; if both true, set `Router.sheet = .analyticsConsent`. **Do not** retroactively re-fire `app_opened` or `budget_created` after consent.
- [ ] 6.6 Verify (manual or via a Preview) that in an auto-opt-in jurisdiction (US locale), no consent sheet appears after the first Budget save.
- [ ] 6.7 Verify (manual or via a Preview) that in a strict-opt-in jurisdiction (DE locale), the consent sheet appears once after the first Budget save and never re-appears after Decline.

## 7. Super-property registration

- [ ] 7.1 Implement `registerSuperProperties(on instance: MixpanelInstance)` inside `MixpanelAnalyticsClient`. Build a `[String: any MixpanelType]` dictionary using the `AnalyticsProperty` keys for each entry per the `Phase 1 super properties` requirement in the `product-analytics` capability spec.
- [ ] 7.2 Pull values:
  - `app_version`: `Bundle.main.infoDictionary["CFBundleShortVersionString"] as? String ?? "—"`
  - `app_build`: `Bundle.main.infoDictionary["CFBundleVersion"] as? String ?? "—"`
  - `device_class`: derived helper that returns `"phone"` / `"pad"` / `"mac"` from `UIDevice.current.userInterfaceIdiom` (or `"mac"` on Catalyst)
  - `locale`: `Locale.current.identifier`
  - `region`: `Locale.current.region?.identifier ?? ""`
  - `consent_jurisdiction`: `"required"` / `"auto_optin"` from `ConsentJurisdiction.kind(for: Locale.current.region)`
  - `bundle_id`: `Bundle.main.bundleIdentifier ?? ""` — registered explicitly per [§11 fork-pollution defense](../../../docs/analytics-spec.md#11-phase-1-dashboards) regardless of Mixpanel SDK auto-attached `$app_id` behavior
  - `week_start_day`, `currency_display_preference`, `carry_over_default_enabled`: from `AppSettings` (capture a snapshot at registration time)
  - `icloud_state`: from the latest `SyncStatus.rowState`
  - `budgets_count_bucket`: derived from a SwiftData fetch on `Budget` count using the `0` / `1` / `2-3` / `4-7` / `8+` mapping
- [ ] 7.3 Call `instance.registerSuperProperties(...)` once with the assembled dictionary.
- [ ] 7.4 For mutable super properties, add refresh hooks:
  - In `SettingsView`, after each `AppSettings` write that affects `week_start_day`, `currency_display_preference`, or `carry_over_default_enabled`, call a small refresh entrypoint on the `analytics` client (e.g., `analytics.refreshSuperProperties()` if exposed, or re-register via a new method on `MixpanelAnalyticsClient`). Decision: **add a `refreshSuperProperties()` method** to `MixpanelAnalyticsClient` (not the protocol — it's an implementation detail; expose it on the concrete type and feature-test it via `as?` cast).
  - In `SettingsView`'s `SyncStatus` observer, on `rowState` transition, call `refreshSuperProperties()`.
  - Immediately before firing `budget_created` and `budget_deleted` in their respective view models, recompute `budgets_count_bucket` and call `refreshSuperProperties()` (or pass the up-to-date bucket as a per-event property — the spec calls it a super property, so refresh is the right path).
- [ ] 7.5 Confirm via a unit test that all twelve super-property keys are present in the registered dictionary on first lazy init.

## 8. People-property setters

- [ ] 8.1 Implement `setBaselinePeopleProperties(on instance: MixpanelInstance)` invoked from `ensureInitialized()` after `identify(distinctId:)`. This SHALL:
  - Set `first_seen_at` via `instance.people.setOnce([...])` to the current timestamp.
  - Set `last_app_open_at` via `instance.people.set([...])` to the current timestamp.
  - If the user just opted in (i.e., this is a toggle-on or accept transition), set `analytics_opt_in_at` to the current timestamp. (Detecting "just opted in" can be passed via a constructor/refresh argument or inferred by checking a transient flag set by the consent flow.)
- [ ] 8.2 Implement `refreshCohortPeopleProperties(modelContext: ModelContext)` that recomputes the §10.3 cohort properties from the current `Budget` collection:
  - `budgets_count_bucket`
  - `default_currency_code` (most-used currency by count)
  - `dominant_period` (most-used `BudgetPeriod`)
  - `uses_carry_over` (Bool — at least one Budget has `carry_over_enabled = true`)
  - `has_disabled_carry_over` (Bool — at least one Budget has `carry_over_enabled = false`)
  - `budgets_with_carry_over_on_count_bucket`
- [ ] 8.3 Wire `refreshCohortPeopleProperties(...)` to be called immediately after every `analytics.track("budget_created" / "budget_edited" / "budget_deleted", ...)` call site in the view models.
- [ ] 8.4 Wire `last_app_open_at` to be re-set on every `app_opened` event. Implementation: either inside `track(_:properties:)` when `event == AnalyticsEvent.appOpened` (cleanest), or at the call site in `simple_recurring_budgetsApp.body.task`.

## 9. Settings — Diagnostics & Analytics section

- [ ] 9.1 Add a new section to `simple-recurring-budgets/Views/SettingsView.swift` titled "Diagnostics & Analytics" (keyed: `settings.analytics.section.title`) between the existing iCloud Sync section and the Support section.
- [ ] 9.2 The section SHALL contain a single toggle bound to `settings.analyticsOptIn` (via `@Bindable var settings`). Toggle title key: `settings.analytics.toggle.title`. Tint with `Color.accentColor` to match the existing default-carry-over toggle convention.
- [ ] 9.3 The section footer SHALL use key `settings.analytics.toggle.footer` and contain:
  - A short summary of what is and is not transmitted (mirroring §5: never any expense field, never any iCloud or Apple ID identifier, only categorical Budget metadata and bucketed counts).
  - A one-line note that the initial state was set automatically based on the device locale and can be changed at any time.
- [ ] 9.4 Implement the toggle change handler with the canonical ordering from the `product-analytics` `Phase 1 event call sites` requirement:
  - **Toggle-on (`false → true`):** set `settings.analyticsOptIn = true`, then `analytics.track(AnalyticsEvent.analyticsConsentChanged, properties: [AnalyticsProperty.newValue.rawValue: true, AnalyticsProperty.oldValue.rawValue: false])`.
  - **Toggle-off (`true → false`):** FIRST `analytics.track(AnalyticsEvent.analyticsConsentChanged, properties: [AnalyticsProperty.newValue.rawValue: false, AnalyticsProperty.oldValue.rawValue: true])` while still opted in; THEN call a method to invoke `MixpanelAnalyticsClient.reset()` (e.g., a typed cast or a `analytics.reset()` protocol call); THEN set `settings.analyticsOptIn = false`.
  - Add an inline source comment citing [`docs/analytics-spec.md` §7.3](../../../docs/analytics-spec.md#73-toggle-off-behavior) so the order is discoverable in the source.
- [ ] 9.5 Confirm the toggle change does NOT also fire `setting_changed` (per the `setting_changed` requirement, opt-in is excluded).
- [ ] 9.6 Add new keys to `simple-recurring-budgets/Resources/Localizable.xcstrings`:
  - `settings.analytics.section.title` — `"Diagnostics & Analytics"`
  - `settings.analytics.toggle.title` — `"Share Anonymous Usage Data"`
  - `settings.analytics.toggle.footer` — `"…full disclosure copy…"` (TBD wording — short, friendly, plain-language summary of §5 plus the locale-default note). Each key carries a translator-friendly `comment:`.

## 10. Consent sheet — view + i18n keys

- [ ] 10.1 Implement `simple-recurring-budgets/Views/Consent/AnalyticsConsentSheet.swift` per task 6.4. Use a vertical `VStack` with a section title, a paragraph of body copy, and bordered/borderedProminent buttons for Accept and Decline. Dismiss via `@Environment(\.dismiss)`.
- [ ] 10.2 Add `Localizable.xcstrings` keys:
  - `consent.analytics.sheet.title` — sheet title.
  - `consent.analytics.sheet.body` — sheet body (mirrors §5 in plain language; explicitly mentions that no Budget or Expense names, amounts, or dates are shared by default — the locally-typed Budget name is a tradeoff disclosed in a one-liner).
  - `consent.analytics.sheet.accept` — Accept button.
  - `consent.analytics.sheet.decline` — Decline button.
- [ ] 10.3 Confirm there are no hard-coded English literals anywhere in `AnalyticsConsentSheet.swift`.
- [ ] 10.4 Add a SwiftUI `Preview` for both Accept-default and Decline-default focus states; pin a deterministic `Locale` for visual testing.

## 11. Phase 1 event call sites

For each event below, fire `analytics.track(...)` with the canonical property dictionary defined in the `Phase 1 event call sites` requirement. Use `AnalyticsProperty` constants for all keys; never inline string literals.

- [ ] 11.1 `budget_created` — in `AddEditBudgetViewModel.save(...)` Add-mode success branch. Properties: `period`, `carry_over_enabled`, `currency_code`, `is_first_budget`, `budget_name`, `budget_allocation_amount` (and `time_since_first_app_open_bucket` only when `is_first_budget == true`). Compute `is_first_budget` by querying `Budget` count before save: `count == 0` → first. Refresh super and people properties (Section 7.4 / 8.3) after the track call.
- [ ] 11.2 `budget_edited` — in the same view model's Edit-mode success branch. Properties: `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount`. Refresh cohort people properties after.
- [ ] 11.3 `budget_deleted` — in `AddEditBudgetViewModel.delete(context:)` after `try? context.save()`. Properties: `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount`. Capture the Budget snapshot BEFORE deletion since the entity is destroyed by the save. Refresh cohort people properties after.
  > **⚠️ Boundary-adjacent (sibling pattern).** This method already contains a `Logger.ui.debug("deleteBudget")` call from F-8.01. Add `analytics.track(AnalyticsEvent.budgetDeleted, ...)` as an independent sibling statement — do NOT nest it inside the Logger call or derive its arguments from the Logger call. See design.md D6 boundary-adjacent table and task §19 for the analytics-spec cleanup.
- [ ] 11.4 `budget_reset` — in `BudgetDetailView.resetBudget` after the save. Properties: `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount`.
  > **⚠️ Boundary-adjacent (sibling pattern).** This method already contains a `Logger.ui.debug("resetBudget")` call from F-8.01. Add `analytics.track(AnalyticsEvent.budgetReset, ...)` as an independent sibling statement. See design.md D6 and task §19.
- [ ] 11.5 `carry_over_reset` — in `BudgetDetailView.resetCarryOver` after the save. Same property set as `budget_reset`.
  > **⚠️ Boundary-adjacent (sibling pattern).** This method already contains a `Logger.ui.debug("resetCarryOver")` call from F-8.01. Add `analytics.track(AnalyticsEvent.carryOverReset, ...)` as an independent sibling statement. See design.md D6 and task §19.
- [ ] 11.6 `expense_logged` — in `AddEditExpenseViewModel.save(...)` Add-mode success branch. Properties: `period` (from parent Budget), `is_add_funds`, `from_screen`, `time_since_budget_created_bucket` (bucket of `Date().timeIntervalSince(budget.createdAt)` — `<5m` / `<1h` / `<1d` / `≥1d`). **Verify NO `ExpenseItem` field is in the dictionary.**
- [ ] 11.7 `expense_edited` — in the same view model's Edit-mode success branch. Properties: `period`, `is_add_funds`, `from_screen`. **Verify NO `ExpenseItem` field is in the dictionary.**
- [ ] 11.8 `expense_deleted` — in `BudgetDetailView+ExpenseSection.deleteExpense(_:)` (single funnel for swipe + rotor, mirroring the `diagnostic-logging` site). Properties: `period`, `is_add_funds`, `from_screen`. **Verify NO `ExpenseItem` field is in the dictionary.**
  > **⚠️ Boundary-adjacent (sibling pattern).** This method already contains a `Logger.ui.debug("deleteExpense")` call from F-8.01. Add `analytics.track(AnalyticsEvent.expenseDeleted, ...)` as an independent sibling statement. See design.md D6 and task §19.
- [ ] 11.9 `settings_opened` — in `SettingsView.task` (or `.onAppear`) on first appearance per sheet presentation. No properties.
- [ ] 11.10 `setting_changed` — in `SettingsView` write handlers for `default_carry_over_enabled`, `week_start_day`, `currency_display_preference`. Properties: `setting_name` (one of the three enumerated values), `new_value`, `old_value`. **Do NOT** fire for `analyticsOptIn`.
- [ ] 11.11 `analytics_consent_changed` — at two sites: the Settings toggle (Section 9.4) AND the consent sheet's Accept handler (Section 6.4). Properties: `new_value`, `old_value` (when applicable).
- [ ] 11.12 Audit: grep `simple-recurring-budgets/` for `analytics.track(` and confirm every call site listed above is present and no extra call site exists.
- [ ] 11.13 Audit: grep `simple-recurring-budgets/` for `expense.name`, `expense.amount`, `expense.date`, `expense.notes` adjacent to `analytics.track(` and confirm zero matches.

## 12. PII enforcement structural surface

- [ ] 12.1 Confirm no extension on `AnalyticsClient`, on `ExpenseItem`, or on a shared analytics helper takes an `ExpenseItem` parameter and returns a `[String: any Sendable]` (or any property-bag shape). Run a structural audit by grepping `simple-recurring-budgets/` for the regex `func .*\(.*ExpenseItem.*\) -> \[String:`.
- [ ] 12.2 Add a doc comment on `AnalyticsClient` re-stating the §5 allow/deny list verbatim (or summarized with a §5 cross-reference) so PR review against the protocol surface catches violations.

## 13. SpyAnalyticsClient extensions

- [ ] 13.1 In `simple-recurring-budgetsTests/Logging/SpyAnalyticsClient.swift`, extend the spy to record:
  - `superProperties: [String: Any]` — captured on the spy's equivalent of `registerSuperProperties` (add a new method to the spy without changing the protocol).
  - `peopleProperties: [String: Any]` and `peopleSetOnceProperties: [String: Any]` — captured on the spy's equivalents.
- [ ] 13.2 Decide: **do NOT** add the super/people methods to the `AnalyticsClient` protocol (per task 7.4 decision they live on the concrete `MixpanelAnalyticsClient`). Tests that need to assert super-property attachment can either (a) test against a fresh `MixpanelAnalyticsClient` with the SDK init step replaced by a closure spy, or (b) test against an extended spy that opts into the same shape via duck-typing.

## 14. Unit tests — `§18.1` contracts (1–10)

Add new Swift Testing suites under `simple-recurring-budgetsTests/`. All ten contracts from [`docs/analytics-spec.md` §18.1](../../../docs/analytics-spec.md#181-concrete-unit-test-contracts-phase-1):

- [ ] 14.1 `simple-recurring-budgetsTests/Settings/ConsentJurisdictionTests.swift` — parameterized test over the §7.2 region table. Every listed code resolves to `.required`; representative unlisted codes (`US`, `JP`, `AU`, `IN`, `MX`, `nil`) resolve to `.auto_optin`. (§18.1 #1)
- [ ] 14.2 `simple-recurring-budgetsTests/Settings/AppSettingsAnalyticsOptInTests.swift` — fresh store + jurisdiction `.required` → `analyticsOptIn` reads `false`; fresh store + jurisdiction `.auto_optin` → `true`; persisted explicit `true` overrides the locale default `false`; default-on-read does not persist; explicit write does persist; `analyticsOptInExplicitlySet` reflects backing store presence. Use `MockKeyValueStore`. (§18.1 #2)
- [ ] 14.3 `simple-recurring-budgetsTests/Settings/AppSettingsAnalyticsDistinctIdTests.swift` — fresh store generates a non-empty UUID-format string and persists it; subsequent reads return the same value; setter not exposed publicly (compile-time check or `internal(set)` semantic test). (§18.1 #3)
- [ ] 14.4 `simple-recurring-budgetsTests/Logging/MixpanelLazyInitTests.swift` — using a `MixpanelAnalyticsClient` test seam (extract the SDK-init step into a `@Sendable` closure parameter for testability OR test the existing class with a counter passed via a wrapping fake), assert: `init` does NOT invoke the SDK-init closure; `track(_:)` with `isOptedIn = false` does not invoke it; `track(_:)` with `isOptedIn = true` invokes it exactly once across many calls; `reset()` followed by another opted-in `track` invokes it again exactly once. (§18.1 #4)
- [ ] 14.5 `simple-recurring-budgetsTests/Logging/AnalyticsConsentOrderingTests.swift` — toggle-off ordering: flipping `analyticsOptIn` from `true` to `false` results in `track("analytics_consent_changed", ...)` delivered to Mixpanel BEFORE `reset()` is called and BEFORE subsequent events are dropped. (§18.1 #5)
- [ ] 14.6 In the same file (or split): toggle-on (strict-opt-in) ordering — flipping from `false` to `true` triggers, in order: SDK lazy-init → `identify(distinctId)` → `track("analytics_consent_changed", new_value: true)` → no retroactive `app_opened`. (§18.1 #6)
- [ ] 14.7 `simple-recurring-budgetsTests/Logging/AnalyticsEventConstantsTests.swift` — asserts `AnalyticsEvent.appOpened == "app_opened"` plus the eleven other Phase 1 constants. (§18.1 #7)
- [ ] 14.8 `simple-recurring-budgetsTests/Logging/PIIEnforcementCallSiteTests.swift` — call-site tests verify that `expense_logged` / `expense_edited` / `expense_deleted` event invocations against fully-populated `ExpenseItem` fixtures carry only the §10.1 allow-listed properties and never include `expense_name`, `expense_amount`, or `expense_date`. Structural test: no API in `AnalyticsClient` extension space serializes `ExpenseItem`. (§18.1 #8)
- [ ] 14.9 `simple-recurring-budgetsTests/Logging/SuperPropertyAttachmentTests.swift` — every tracked event in a fixture run carries the §10.2 super-property keys (`app_version`, `device_class`, `consent_jurisdiction`, `budgets_count_bucket`, `carry_over_default_enabled`, `bundle_id`, etc.); `budgets_count_bucket` value transitions correctly across `0` / `1` / `2-3` / `4-7` / `8+` boundaries. (§18.1 #9)
- [ ] 14.10 `simple-recurring-budgetsTests/Logging/MixpanelTokenBranchTests.swift` — verify the `#if DEBUG` token literal and the `#else` literal in `simple_recurring_budgetsApp.init()` are non-empty AND not equal. Exposed via a small testable helper that returns the active token literal under the active build configuration. (§18.1 #10)

## 15. Build / lint / test

- [ ] 15.1 Run the four-step build/test procedure from [`AGENTS.md` > Build and test](../../../AGENTS.md): `make format && make lint-fix && make build && make test`. Each step MUST pass before continuing.
- [ ] 15.2 If a `make build` failure surfaces a new SwiftLint violation introduced by the call-site refactors, fix it manually (do not disable the rule).
- [ ] 15.3 Run the structural boundary test from `oslog-diagnostic-logging` and confirm it still passes. The test asserts that `AnalyticsClient` has no OSLog-shaped API; this remains true after the refactor.

## 16. Doc updates

- [ ] 16.1 Update [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §4.5 KV-key table: add a row for `"analyticsOptIn"` (Bool, owned by `AppSettings`) and a row for `"analyticsDistinctId"` (String, UUIDv4, owned by `AppSettings`). Bump the file's revision history table at the bottom.
- [ ] 16.2 Update [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §7: confirm the prose accurately describes the lazy-init flow that just shipped, the consent flow, and the Settings toggle. The §7 paragraph already references analytics-spec §§2–8; if any sentence implies the old (eager-init) behavior, rewrite it. Bump revision history if substantive prose changes land.
- [ ] 16.3 Update [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §9 future-work table: drop or refresh any stale "analytics future-work" row (the F-8.02 bullet, if present); add a row for F-8.03 (Phase 2) pointing at `docs/analytics-spec.md` §§4 / 12–15.
- [ ] 16.4 Update [`docs/analytics-spec.md`](../../../docs/analytics-spec.md) §16.1: rewrite the subsection so it reads as a historical record. The `MixpanelAnalyticsClient.swift`, `simple_recurring_budgetsApp.swift`, and `AnalyticsClient.swift` rows should reflect the post-implementation state (refactor complete). Add a one-line note at the top of §16.1 indicating this section is now historical and pointing at the implementing change.
- [ ] 16.5 Update [`docs/analytics-spec.md`](../../../docs/analytics-spec.md) §19: mark the F-8.02 rows as done using the same convention as the F-8.01 row (e.g., `~~F-8.02 ships~~ ✓ (done by `mixpanel-phase-1-foundation`)`). Update the Revision History at the bottom of the file with a new row for this version.
- [ ] 16.6 Update [`docs/product-features-planning.md`](../../../docs/product-features-planning.md) F-8.02: flip `**Status:**` from "Open" to "**Implemented.** Implemented by change `mixpanel-phase-1-foundation`." Bump the file's `Last Updated` date and version. Leave the Description, Acceptance Criteria, Edge Cases / Notes, and Dependencies sections untouched (they remain the canonical specification).
- [ ] 16.7 Confirm no other `docs/*.md` file needs an update: `main-prd.md` is unchanged (no global product or UX rule moves); `ux-design-brief.md` is unchanged.

## 17. Phase 1 dashboards (follow-up tracker)

Per F-8.02 Edge Cases, Phase 1 dashboards are configuration in Mixpanel and ship as a tracked task alongside or shortly after the implementing change.

- [ ] 17.1 In Mixpanel, set the **project-level filter** to `bundle_id = <the app's production bundle identifier>` per [`docs/analytics-spec.md` §11](../../../docs/analytics-spec.md#11-phase-1-dashboards) "Universal project filter" instructions. Apply this to both the dev and prod projects.
- [ ] 17.2 Build each Phase 1 dashboard listed in [`docs/analytics-spec.md` §11](../../../docs/analytics-spec.md#11-phase-1-dashboards): Reach, Activation funnel, Time-to-first-budget / first-expense, Per-Budget composition, Per-user composition, Allocation distribution, Retention, Settings — opens & changes, Destructive actions, Consent.
- [ ] 17.3 Once dashboards are live, paste the dashboard URLs back into [`docs/analytics-spec.md` §11](../../../docs/analytics-spec.md#11-phase-1-dashboards) under the existing table (or under a new "Live dashboards" subsection). This is a doc-only follow-up.

> Tasks 17.1–17.3 are intentionally NOT gating the change archive — the implementing change ships when code + specs + docs land per F-8.02 Edge Cases. Dashboards may land in a follow-up commit on the same branch or in a separate doc-only PR.

## 19. analytics-spec.md §17 cleanup — formalize the co-location (sibling-call) pattern

> This task addresses the ⚠️ flag raised in design.md D6. The current `docs/analytics-spec.md` §17 language is accurate but can be misread as prohibiting co-location.

- [ ] 19.1 In [`docs/analytics-spec.md` §17 (Boundary with F-8.01)](../../../docs/analytics-spec.md#17-boundary-with-f-801-oslog), add a clarifying sub-note (or update the existing closing paragraph) that reads approximately:

  > **Co-location is permitted and expected at the four destructive-action funnels.** The methods `AddEditBudgetViewModel.delete(context:)`, `BudgetDetailView.resetBudget`, `BudgetDetailView.resetCarryOver`, and `BudgetDetailView+ExpenseSection.deleteExpense(_:)` each contain both a `Logger.ui.debug(...)` entry (F-8.01, for runtime tracing) and an `analytics.track(...)` call (F-8.02, for product measurement). This is the intended design: the two calls are independent sibling statements in the same method body; neither derives its arguments from the other. This co-location does NOT violate the boundary — the boundary prohibits routing, not physical proximity. Any future contributor adding a new user-action funnel that warrants both a diagnostic trace and a product event SHOULD follow the same sibling-statement pattern.

- [ ] 19.2 Bump the `docs/analytics-spec.md` revision history with a short entry: `"§17 — formalize co-location (sibling-call) pattern at four destructive-action funnels; done by change mixpanel-phase-1-foundation"`.
- [ ] 19.3 Confirm `docs/diagnostic-logging` capability spec's "Sibling call sites are allowed" scenario language is consistent with the updated §17 prose; no change to the `diagnostic-logging` spec is expected.

## 18. Verify and archive readiness

- [ ] 18.1 Run `openspec validate --change mixpanel-phase-1-foundation` to confirm proposal, design, specs, and tasks are consistent.
- [ ] 18.2 Manual review: every Acceptance Criterion in F-8.02 has a corresponding requirement in `specs/product-analytics/spec.md` (or a delta in `specs/app-settings/spec.md` / `specs/settings-screen/spec.md`) and at least one task in §§2–11 of this file. Cross-reference each canonical event in [`docs/analytics-spec.md` §9](../../../docs/analytics-spec.md#9-phase-1-events) to its task entry in §11.
- [ ] 18.3 Manual review: every test contract in [`docs/analytics-spec.md` §18.1](../../../docs/analytics-spec.md#181-concrete-unit-test-contracts-phase-1) (#1–#10) maps to a task entry in §14.
- [ ] 18.4 Mark all tasks in §§1–16 complete; §17 may remain pending (not gating). Proceed to OpenSpec archive (`openspec archive mixpanel-phase-1-foundation` or skill equivalent). The archive step should not need additional doc-drift work because §16 was completed in this change.
