# product-analytics Specification

## Purpose
TBD - created by archiving change mixpanel-phase-1-foundation. Update Purpose after archive.
## Requirements
### Requirement: AnalyticsClient protocol surface

The system SHALL expose an `AnalyticsClient` protocol in [`simple-recurring-budgets/Logging/AnalyticsClient.swift`](../../../simple-recurring-budgets/Logging/AnalyticsClient.swift) with exactly these methods:

- `func track(_ event: String, properties: [String: any Sendable]?)` — fires a product event with optional categorical/bucketed properties.
- `func identify(_ distinctId: String?)` — associates the current session with a stable user identifier.
- `func reset()` — clears the local SDK state for the configured client.

The protocol SHALL conform to `AnyObject` and `Sendable` so the client can be passed across actor boundaries safely.

The protocol SHALL provide a `track(_ event: String)` convenience extension that forwards to `track(_:properties: nil)`.

The protocol SHALL NOT expose any method whose parameter type is `os.Logger`, `OSLogEntry`, `OSLogEntryLog`, `OSLogMessage`, or any other OSLog-shaped type (this restates the cross-cutting boundary established by the `diagnostic-logging` capability).

#### Scenario: AnalyticsClient method surface is exactly three calls plus the convenience overload

- **WHEN** a contributor inspects `AnalyticsClient` and its `Sendable` extension space
- **THEN** the surface contains `track(_:properties:)`, `identify(_:)`, `reset()`, and the `track(_:)` convenience overload — and nothing else

#### Scenario: AnalyticsClient exposes no OSLog-shaped API

- **WHEN** a contributor inspects `AnalyticsClient` and all conforming implementations under `simple-recurring-budgets/Logging/`
- **THEN** no method takes a parameter of type `os.Logger`, `OSLogEntry`, `OSLogEntryLog`, or `OSLogMessage`

---

### Requirement: AnalyticsEvent canonical name catalog

The system SHALL define an `AnalyticsEvent` enum (or `enum`-shaped namespace) in [`simple-recurring-budgets/Logging/AnalyticsClient.swift`](../../../simple-recurring-budgets/Logging/AnalyticsClient.swift) carrying the canonical Phase 1 event-name string constants. Every constant SHALL be `snake_case`, matching the canonical names in [`docs/analytics-spec.md` §9](../../../docs/analytics-spec.md#9-phase-1-events):

| Constant                       | Raw value                       |
| ------------------------------ | ------------------------------- |
| `appOpened`                    | `"app_opened"`                  |
| `budgetCreated`                | `"budget_created"`              |
| `budgetEdited`                 | `"budget_edited"`               |
| `budgetDeleted`                | `"budget_deleted"`              |
| `budgetReset`                  | `"budget_reset"`                |
| `carryOverReset`               | `"carry_over_reset"`            |
| `expenseLogged`                | `"expense_logged"`              |
| `expenseEdited`                | `"expense_edited"`              |
| `expenseDeleted`               | `"expense_deleted"`             |
| `settingsOpened`               | `"settings_opened"`             |
| `settingChanged`               | `"setting_changed"`             |
| `analyticsConsentChanged`      | `"analytics_consent_changed"`   |

Adding a new event constant SHALL require a corresponding update to this requirement and to the `Phase 1 event call sites` requirement below in the same change. Removing or renaming a constant SHALL require a `MODIFIED Requirements` block.

#### Scenario: app_opened raw value

- **WHEN** `AnalyticsEvent.appOpened` is read
- **THEN** the raw value SHALL equal `"app_opened"`

#### Scenario: All Phase 1 event constants exist

- **WHEN** a contributor inspects `AnalyticsEvent`
- **THEN** all twelve canonical constants listed above SHALL be defined and SHALL produce the listed raw values

---

### Requirement: AnalyticsProperty canonical key catalog

The system SHALL define an `AnalyticsProperty` enum (or `enum`-shaped namespace) carrying the canonical Phase 1 property-key string constants from [`docs/analytics-spec.md` §10.1](../../../docs/analytics-spec.md#101-per-event-properties), §10.2, and §10.3. Call sites SHALL assemble property dictionaries using these constants rather than ad-hoc string literals.

The enum SHALL include at least:

- Per-event keys (§10.1): `period`, `carryOverEnabled`, `currencyCode`, `isFirstBudget`, `timeSinceFirstAppOpenBucket`, `budgetName`, `budgetAllocationAmount`, `isAddFunds`, `fromScreen`, `timeSinceBudgetCreatedBucket`, `settingName`, `newValue`, `oldValue`.
- Super-property keys (§10.2): `appVersion`, `appBuild`, `iosVersion`, `deviceModel`, `deviceClass`, `locale`, `region`, `weekStartDay`, `currencyDisplayPreference`, `icloudState`, `budgetsCountBucket`, `carryOverDefaultEnabled`, `consentJurisdiction`, `bundleId`.
- People-property keys (§10.3): `firstSeenAt`, `analyticsOptInAt`, `defaultCurrencyCode`, `lastAppOpenAt`, `dominantPeriod`, `usesCarryOver`, `hasDisabledCarryOver`, `budgetsWithCarryOverOnCountBucket`.

Each constant's raw value SHALL match the snake_case key in the analytics spec exactly.

#### Scenario: Per-event key raw values are snake_case

- **WHEN** `AnalyticsProperty.budgetAllocationAmount.rawValue` is read
- **THEN** the value SHALL equal `"budget_allocation_amount"`

#### Scenario: bundle_id constant exists for explicit super-property registration

- **WHEN** a contributor inspects `AnalyticsProperty`
- **THEN** a `bundleId` constant SHALL exist whose raw value is `"bundle_id"`, used by the explicit super-property registration in `MixpanelAnalyticsClient` (per the §11 fork-pollution defense in `docs/analytics-spec.md`)

---

### Requirement: ConsentJurisdiction helper

The system SHALL expose a `ConsentJurisdiction` helper (location: alongside `AppSettings`, e.g. `simple-recurring-budgets/Settings/ConsentJurisdiction.swift`) that resolves a region identifier to one of two cases of a `JurisdictionKind` enum:

- `.required` — strict-opt-in jurisdictions.
- `.auto_optin` — every other locale.

The helper SHALL expose a static function `func kind(for region: Locale.Region?) -> JurisdictionKind` (or equivalent that accepts a `String?` region identifier). The function SHALL return `.required` if and only if the region identifier is a member of the strict-opt-in region table mirrored from [`docs/analytics-spec.md` §7.2](../../../docs/analytics-spec.md#72-strict-opt-in-jurisdictions-and-the-first-run-consent-sheet):

`AT, BE, BG, HR, CY, CZ, DK, EE, FI, FR, DE, GR, HU, IE, IT, LV, LT, LU, MT, NL, PL, PT, RO, SK, SI, ES, SE, IS, LI, NO, GB, GG, JE, IM, CH, KR, CN, BR, TR, TH, CA`

> Note on `CA` (Canada): per §7.2 ("pragmatically apply CA-wide if Quebec sub-region is not reliably surfaced"), `CA` is treated as `.required` for Phase 1. If `Locale` later surfaces a reliable Quebec sub-region, this requirement is updated to scope to Quebec only.

For any region identifier not in the table — including `nil`, the empty string, `"US"`, `"JP"`, `"AU"`, `"NZ"`, `"IN"`, `"MX"`, `"ZA"`, and any other unlisted code — the helper SHALL return `.auto_optin`.

The helper SHALL be a pure function with no side effects, no static state, and no dependency on `Locale.current` (callers pass `Locale.current.region` explicitly so tests can supply a deterministic region).

#### Scenario: EU member state resolves to required

- **WHEN** `ConsentJurisdiction.kind(for: Locale.Region("DE"))` is called
- **THEN** the function SHALL return `.required`

#### Scenario: UK resolves to required

- **WHEN** `ConsentJurisdiction.kind(for: Locale.Region("GB"))` is called
- **THEN** the function SHALL return `.required`

#### Scenario: Switzerland resolves to required

- **WHEN** `ConsentJurisdiction.kind(for: Locale.Region("CH"))` is called
- **THEN** the function SHALL return `.required`

#### Scenario: South Korea resolves to required

- **WHEN** `ConsentJurisdiction.kind(for: Locale.Region("KR"))` is called
- **THEN** the function SHALL return `.required`

#### Scenario: China mainland resolves to required

- **WHEN** `ConsentJurisdiction.kind(for: Locale.Region("CN"))` is called
- **THEN** the function SHALL return `.required`

#### Scenario: Brazil resolves to required

- **WHEN** `ConsentJurisdiction.kind(for: Locale.Region("BR"))` is called
- **THEN** the function SHALL return `.required`

#### Scenario: Canada resolves to required (Phase 1 CA-wide pragmatism)

- **WHEN** `ConsentJurisdiction.kind(for: Locale.Region("CA"))` is called
- **THEN** the function SHALL return `.required` for Phase 1

#### Scenario: United States resolves to auto-opt-in

- **WHEN** `ConsentJurisdiction.kind(for: Locale.Region("US"))` is called
- **THEN** the function SHALL return `.auto_optin`

#### Scenario: Japan resolves to auto-opt-in

- **WHEN** `ConsentJurisdiction.kind(for: Locale.Region("JP"))` is called
- **THEN** the function SHALL return `.auto_optin`

#### Scenario: Nil region resolves to auto-opt-in

- **WHEN** `ConsentJurisdiction.kind(for: nil)` is called
- **THEN** the function SHALL return `.auto_optin`

#### Scenario: Unknown future region code resolves to auto-opt-in

- **WHEN** `ConsentJurisdiction.kind(for: Locale.Region("XX"))` is called
- **THEN** the function SHALL return `.auto_optin`

---

### Requirement: MixpanelAnalyticsClient lazy SDK initialization

`MixpanelAnalyticsClient` SHALL defer the call to `Mixpanel.initialize(token:trackAutomaticEvents:)` until the first opted-in `track(_:properties:)` or `identify(_:)` invocation. The constructor SHALL accept `(token: String, isOptedIn: @escaping @Sendable () -> Bool, distinctIdProvider: @escaping @Sendable () -> String?)` and SHALL NOT call `Mixpanel.initialize(...)` during `init`.

The first opted-in call SHALL trigger `Mixpanel.initialize(token:trackAutomaticEvents: false)`, register the §10.2 super properties (per the `Phase 1 super properties` requirement), call `Mixpanel.mainInstance().identify(distinctId:)` with the value returned by `distinctIdProvider()`, and set the §10.3 baseline people properties (per the `Phase 1 people properties` requirement).

The initialization SHALL be guarded by a thread-safe one-shot mechanism (`os_unfair_lock` or `OSAllocatedUnfairLock` on supported platforms) so concurrent first-call `track`s SHALL NOT double-initialize the SDK.

`reset()` SHALL clear the SDK's local distinct-id state via `Mixpanel.mainInstance().reset()` (when the instance exists) AND SHALL clear the one-shot init guard so a subsequent toggle-on after a toggle-off re-initializes cleanly.

`trackAutomaticEvents` SHALL always be `false`. The client SHALL NOT enable Mixpanel autocapture, session replay, IDFA collection, or any cross-app tracking surface.

#### Scenario: Init does not invoke the SDK

- **WHEN** `MixpanelAnalyticsClient(token:isOptedIn:distinctIdProvider:)` is constructed
- **THEN** `Mixpanel.initialize(token:trackAutomaticEvents:)` SHALL NOT be invoked

#### Scenario: Opted-out track is a no-op

- **WHEN** `track(_:properties:)` is invoked while `isOptedIn()` returns `false`
- **THEN** the SDK init guard SHALL NOT fire, no `MixpanelInstance` SHALL be created, and no event SHALL be enqueued

#### Scenario: First opted-in track lazy-initializes the SDK exactly once

- **WHEN** `track(_:properties:)` is invoked many times in rapid succession after `isOptedIn()` returns `true`
- **THEN** `Mixpanel.initialize(token:trackAutomaticEvents:)` SHALL be invoked exactly once across all calls

#### Scenario: First opted-in identify lazy-initializes the SDK

- **WHEN** the first opted-in invocation is `identify(_:)` rather than `track(_:properties:)`
- **THEN** `Mixpanel.initialize(token:trackAutomaticEvents:)` SHALL be invoked exactly once and the supplied distinct id SHALL be passed to `Mixpanel.mainInstance().identify(distinctId:)`

#### Scenario: Reset clears state and the init guard

- **WHEN** `reset()` is invoked after the SDK has been lazy-initialized, then `track(_:properties:)` is invoked again with `isOptedIn()` returning `true`
- **THEN** `Mixpanel.initialize(token:trackAutomaticEvents:)` SHALL be invoked again exactly once on the post-reset call

#### Scenario: trackAutomaticEvents is false

- **WHEN** `Mixpanel.initialize(...)` is invoked by the lazy-init guard
- **THEN** the `trackAutomaticEvents` argument SHALL be `false`

---

### Requirement: Build-configuration token branch

The token passed to `MixpanelAnalyticsClient` SHALL be selected by a `#if DEBUG` literal branch in [`simple-recurring-budgets/App/simple_recurring_budgetsApp.swift`](../../../simple-recurring-budgets/App/simple_recurring_budgetsApp.swift):

- `#if DEBUG` — the dev project token literal.
- `#else` — the prod project token literal.

Both literals SHALL be non-empty and SHALL NOT be equal. Tokens SHALL remain in source per [`docs/analytics-spec.md` §16](../../../docs/analytics-spec.md#16-build-hygiene); they SHALL NOT be moved to `xcconfig`, `Info.plist`, or any other build-input mechanism in this scope.

DEBUG and Release builds SHALL both use `MixpanelAnalyticsClient`. Physical separation of dev-vs-prod data SHALL be enforced by the token branch alone (two separate Mixpanel projects), not by swapping client types. `ConsoleAnalyticsClient` SHALL remain as the SwiftUI `@Entry` default in `AnalyticsEnvironment.swift` for previews and unit tests that don't run through the app entry.

#### Scenario: Tokens are non-empty and distinct

- **WHEN** the source literals for the dev and prod tokens are inspected
- **THEN** both literals SHALL be non-empty strings and SHALL NOT be equal

#### Scenario: DEBUG build uses dev token

- **WHEN** the app is built with the DEBUG configuration and `simple_recurring_budgetsApp.init()` constructs `MixpanelAnalyticsClient`
- **THEN** the constructor SHALL be invoked with the dev project token literal

#### Scenario: Release build uses prod token

- **WHEN** the app is built with the Release configuration and `simple_recurring_budgetsApp.init()` constructs `MixpanelAnalyticsClient`
- **THEN** the constructor SHALL be invoked with the prod project token literal

---

### Requirement: App-entry wiring of opt-in and distinct id

[`simple-recurring-budgets/App/simple_recurring_budgetsApp.swift`](../../../simple-recurring-budgets/App/simple_recurring_budgetsApp.swift) `init()` SHALL construct `MixpanelAnalyticsClient` with:

- `token:` — resolved by the `#if DEBUG` literal branch above.
- `isOptedIn:` — a `@Sendable` closure that reads `settings.analyticsOptIn` from the app's shared `AppSettings` instance. The closure SHALL NOT capture a snapshot Boolean; it SHALL re-read the current value each invocation so toggle changes take effect on the next event.
- `distinctIdProvider:` — a `@Sendable` closure that returns `settings.analyticsDistinctId` from the same shared `AppSettings` instance. The closure SHALL NOT capture a snapshot value.

The `analytics` property SHALL be assigned to the constructed client, and the SwiftUI environment injection (`.environment(\.analytics, analytics)`) SHALL remain in place.

The hard-coded `isOptedIn: { false }` previously present in `init()` SHALL be removed in this change.

#### Scenario: isOptedIn closure reads the current AppSettings value

- **WHEN** `analyticsOptIn` is `false` and a `track` call occurs, then `analyticsOptIn` is set to `true` and another `track` call occurs
- **THEN** the first call SHALL be a no-op and the second call SHALL deliver the event to the SDK

#### Scenario: distinctIdProvider returns the current AppSettings value

- **WHEN** the `MixpanelAnalyticsClient` lazy-init invokes `distinctIdProvider()`
- **THEN** the closure SHALL return the current value of `settings.analyticsDistinctId`

#### Scenario: Hard-coded isOptedIn closure is gone

- **WHEN** a contributor inspects `simple_recurring_budgetsApp.init()`
- **THEN** there SHALL NOT be a `MixpanelAnalyticsClient(token:..., isOptedIn: { false })` literal anywhere in the source

---

### Requirement: app_opened event call site

The app SHALL fire `analytics.track(AnalyticsEvent.appOpened)` exactly once per session from `simple_recurring_budgetsApp.body`'s top-level `.task` modifier. The call SHALL NOT pass per-event properties; the §10.2 super properties cover the rendering metadata. No other code in the app SHALL fire `app_opened`.

#### Scenario: appOpened fires from body.task

- **WHEN** the app's top-level `WindowGroup` body's `.task` runs after launch
- **THEN** `analytics.track(AnalyticsEvent.appOpened)` SHALL be invoked exactly once

#### Scenario: appOpened is not fired from elsewhere

- **WHEN** a contributor greps `simple-recurring-budgets/` for `track(AnalyticsEvent.appOpened` (or its raw string)
- **THEN** the only match SHALL be the `body.task` site

---

### Requirement: Phase 1 event call sites

The app SHALL fire each of the canonical Phase 1 events at exactly the canonical call site. Each call SHALL pass the §10.1 properties listed for that event and no others. The call sites are:

| Event                       | Call site                                                                                  | Per-event properties                                                                              |
| --------------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `budget_created`            | `AddEditBudgetViewModel.save(...)` Add-mode success branch                                 | `period`, `carry_over_enabled`, `currency_code`, `is_first_budget`, `time_since_first_app_open_bucket` (only when `is_first_budget = true`), `budget_name`, `budget_allocation_amount` |
| `budget_edited`             | `AddEditBudgetViewModel.save(...)` Edit-mode success branch                                | `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount`        |
| `budget_deleted`            | `AddEditBudgetViewModel.delete(context:)` after successful save                            | `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount`        |
| `budget_reset`              | `BudgetDetailView.resetBudget` after successful save                                       | `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount`        |
| `carry_over_reset`          | `BudgetDetailView.resetCarryOver` after successful save                                    | `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount`        |
| `expense_logged`            | `AddEditExpenseViewModel.save(...)` Add-mode success branch                                | `period`, `is_add_funds`, `from_screen`, `time_since_budget_created_bucket`                       |
| `expense_edited`            | `AddEditExpenseViewModel.save(...)` Edit-mode success branch                               | `period`, `is_add_funds`, `from_screen`                                                            |
| `expense_deleted`           | `BudgetDetailView+ExpenseSection.deleteExpense(_:)` (single funnel)                        | `period`, `is_add_funds`, `from_screen`                                                            |
| `settings_opened`           | `SettingsView.task` on appearance                                                          | (none)                                                                                            |
| `setting_changed`           | `SettingsView` setting-write paths for `default_carry_over_enabled`, `week_start_day`, `currency_display_preference` | `setting_name`, `new_value`, `old_value`                                                          |
| `analytics_consent_changed` | `SettingsView` analytics-toggle change handler AND `AnalyticsConsentSheet` accept handler   | `new_value`, `old_value` (when applicable)                                                        |

Per-event properties SHALL be assembled using `AnalyticsProperty` constants. No `expense_*` event SHALL carry any field on `ExpenseItem` (name, amount, date, notes, attachments, or any other field) by value. The free-text and money-shaped exceptions for `budget_*` events (`budget_name` and `budget_allocation_amount`) are accepted-risk allow-listed exceptions per [`docs/analytics-spec.md` §5.4](../../../docs/analytics-spec.md#54-accepted-risk-exceptions); they SHALL NOT be transmitted on any other event.

`analytics_consent_changed` on a toggle-off transition SHALL be fired BEFORE `MixpanelAnalyticsClient.reset()` is called and BEFORE `AppSettings.analyticsOptIn` is set to `false`, so the opt-out is observable in dashboards.

`expense_deleted` SHALL fire exactly once per logical delete regardless of whether the delete originated from a swipe action or a VoiceOver rotor `accessibilityAction` (mirroring the single-funnel pattern established by `diagnostic-logging`).

A single user action MAY produce both an `analytics.track(...)` call and a sibling `Logger.*` call (the F-8.01 destructive sites continue to log via `Logger.ui.debug`). The two calls SHALL be sibling statements at the same call site; neither SHALL be derived from the other.

#### Scenario: budget_created carries the correct property set

- **WHEN** the user creates a new Budget and `AddEditBudgetViewModel.save(...)` reaches the success branch
- **THEN** `analytics.track("budget_created", ...)` SHALL be invoked with property keys exactly `{period, carry_over_enabled, currency_code, is_first_budget, budget_name, budget_allocation_amount}` (plus `time_since_first_app_open_bucket` when `is_first_budget == true`)

#### Scenario: expense_logged carries no ExpenseItem-by-value field

- **WHEN** the user logs a new expense and `AddEditExpenseViewModel.save(...)` reaches the Add-mode success branch
- **THEN** `analytics.track("expense_logged", ...)` SHALL be invoked with property keys drawn only from `{period, is_add_funds, from_screen, time_since_budget_created_bucket}`, and SHALL NOT include `expense.name`, `expense.amount`, `expense.date`, or any other field on `ExpenseItem`

#### Scenario: expense_edited carries no ExpenseItem-by-value field

- **WHEN** the user edits an existing expense and `AddEditExpenseViewModel.save(...)` reaches the Edit-mode success branch
- **THEN** `analytics.track("expense_edited", ...)` SHALL be invoked with property keys drawn only from `{period, is_add_funds, from_screen}`, and SHALL NOT include any `ExpenseItem` field by value

#### Scenario: expense_deleted single-funnel via swipe

- **WHEN** the user performs a full trailing swipe on an expense row and the row is deleted
- **THEN** `analytics.track("expense_deleted", ...)` SHALL be invoked exactly once via `BudgetDetailView+ExpenseSection.deleteExpense(_:)`

#### Scenario: expense_deleted single-funnel via rotor

- **WHEN** a VoiceOver user invokes the rotor `accessibilityAction(named:)` mirror of the swipe-delete gesture
- **THEN** `analytics.track("expense_deleted", ...)` SHALL be invoked exactly once via the same `deleteExpense(_:)` funnel

#### Scenario: setting_changed excludes the analytics opt-in toggle

- **WHEN** the user toggles `AppSettings.analyticsOptIn`
- **THEN** the system SHALL fire `analytics_consent_changed`, and SHALL NOT fire `setting_changed` for that change

#### Scenario: Toggle-off ordering — consent fires before reset and before flip

- **WHEN** the user flips `AppSettings.analyticsOptIn` from `true` to `false` via the Settings toggle
- **THEN** the order of operations SHALL be: (1) `analytics.track("analytics_consent_changed", ...)` with `new_value: false`; (2) `MixpanelAnalyticsClient.reset()`; (3) `settings.analyticsOptIn = false`

#### Scenario: Sibling Logger and analytics calls at destructive sites

- **WHEN** the user confirms a destructive action (`Reset Budget`, `Reset Carry-Over`, `Delete Budget`, `Delete Expense`)
- **THEN** the call site SHALL invoke both `analytics.track(...)` (from this capability) and `Logger.ui.debug(...)` (from the `diagnostic-logging` capability) as sibling statements, neither derived from the other

#### Scenario: budget_name not present on expense events

- **WHEN** any of `expense_logged`, `expense_edited`, or `expense_deleted` is fired
- **THEN** the property dictionary SHALL NOT contain the key `"budget_name"`

---

### Requirement: Phase 1 super properties

`MixpanelAnalyticsClient` SHALL register the §10.2 super properties on first lazy SDK initialization via `Mixpanel.mainInstance().registerSuperProperties(...)`. The super properties SHALL be:

| Key                               | Source                                                                                        | Mutable    |
| --------------------------------- | --------------------------------------------------------------------------------------------- | ---------- |
| `app_version`                     | `Bundle.main.infoDictionary["CFBundleShortVersionString"]`                                    | No         |
| `app_build`                       | `Bundle.main.infoDictionary["CFBundleVersion"]`                                               | No         |
| `device_class`                    | `phone` / `pad` / `mac`, derived from `UIDevice.current.userInterfaceIdiom` (or platform)     | No         |
| `locale`                          | `Locale.current.identifier`                                                                   | No         |
| `region`                          | `Locale.current.region?.identifier`                                                           | No         |
| `consent_jurisdiction`            | `required` / `auto_optin`, from `ConsentJurisdiction.kind(for: Locale.current.region)`        | No         |
| `bundle_id`                       | `Bundle.main.bundleIdentifier`                                                                | No         |
| `week_start_day`                  | `AppSettings.weekStartDay` raw value (`monday`, `sunday`, etc.)                               | Yes        |
| `currency_display_preference`     | `AppSettings.currencyDisplay` raw value                                                       | Yes        |
| `icloud_state`                    | `SyncStatus.rowState` raw value (`available` / `paused` / `unavailable` / `checking`)         | Yes        |
| `budgets_count_bucket`            | `0` / `1` / `2-3` / `4-7` / `8+`, derived from current `Budget` count                         | Yes        |
| `carry_over_default_enabled`      | `AppSettings.defaultCarryOverEnabled` (Bool)                                                  | Yes        |

`bundle_id` SHALL be registered explicitly via `registerSuperProperties` even though Mixpanel's SDK may auto-attach a similarly-named property; the explicit registration is the canonical fork-pollution filter per §11.

Mutable super properties SHALL be refreshed (re-registered) when their underlying source value changes:

- `week_start_day`, `currency_display_preference`, `carry_over_default_enabled` — refreshed after `SettingsView` writes the new value to `AppSettings`.
- `icloud_state` — refreshed when `SyncStatus.rowState` transitions.
- `budgets_count_bucket` — recomputed and refreshed immediately before `budget_created` / `budget_deleted` is fired.

#### Scenario: Static super properties are registered on first lazy init

- **WHEN** the lazy SDK initialization fires for the first time
- **THEN** `Mixpanel.mainInstance().registerSuperProperties(...)` SHALL be invoked with the seven static keys (`app_version`, `app_build`, `device_class`, `locale`, `region`, `consent_jurisdiction`, `bundle_id`) and the five mutable keys at their current values

#### Scenario: bundle_id is registered explicitly

- **WHEN** the super-property dictionary registered on first init is inspected
- **THEN** the dictionary SHALL contain a `"bundle_id"` entry whose value equals `Bundle.main.bundleIdentifier`

#### Scenario: budgets_count_bucket transitions across boundaries

- **WHEN** the user creates Budgets in sequence such that the count crosses each bucket boundary `0 → 1 → 2 → 3 → 4 → 7 → 8`
- **THEN** the next `budget_created` event SHALL carry a refreshed `budgets_count_bucket` super property reflecting the bucket that contains the post-create count (`1`, `2-3`, `2-3`, `2-3`, `4-7`, `4-7`, `8+`)

#### Scenario: icloud_state refreshes on transition

- **WHEN** `SyncStatus.rowState` transitions from `checking` to `available`
- **THEN** the next event fired SHALL carry an `icloud_state = available` super property

---

### Requirement: Phase 1 people properties

`MixpanelAnalyticsClient` SHALL set the §10.3 people properties at the canonical refresh sites. On the first lazy SDK initialization (which calls `Mixpanel.mainInstance().identify(distinctId:)` immediately after registering super properties), the client SHALL set the baseline people properties using a mix of `peopleSet` and `peopleSetOnce` semantics:

| Property                                        | Refresh trigger                                                                                    | Semantics       |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------- | --------------- |
| `first_seen_at`                                 | First identify after lazy init                                                                     | `setOnce`       |
| `analytics_opt_in_at`                           | Toggle-on transition (consent sheet accept OR Settings toggle flips `false → true`)                | `set`           |
| `last_app_open_at`                              | Every `app_opened` event                                                                            | `set`           |
| `budgets_count_bucket`                          | Every `budget_created` and `budget_deleted` event (refreshed before the event fires)                | `set`           |
| `default_currency_code`                         | Every `budget_created` / `budget_edited` / `budget_deleted` event (most-used currency by count)     | `set`           |
| `dominant_period`                               | Every `budget_created` / `budget_edited` / `budget_deleted` event (most-used Budget Period)         | `set`           |
| `uses_carry_over`                               | Every `budget_*` event — `true` if the user has at least one Budget with `carry_over_enabled = true` | `set`           |
| `has_disabled_carry_over`                       | Every `budget_*` event — `true` if the user has at least one Budget with `carry_over_enabled = false` | `set`           |
| `budgets_with_carry_over_on_count_bucket`       | Every `budget_*` event — `0` / `1` / `2-3` / `4-7` / `8+`                                          | `set`           |

`first_seen_at` SHALL use `setOnce` semantics so that re-installs or re-initializations after `reset()` do not overwrite the original first-seen timestamp on the same `distinct_id`.

#### Scenario: first_seen_at uses setOnce

- **WHEN** the lazy SDK init fires and identifies the user
- **THEN** `first_seen_at` SHALL be set via Mixpanel's `peopleSetOnce` (or equivalent) so subsequent identifies on the same distinct id SHALL NOT overwrite the value

#### Scenario: last_app_open_at refreshes on every app_opened

- **WHEN** `app_opened` is fired
- **THEN** the people property `last_app_open_at` SHALL be set to the current timestamp

#### Scenario: Cohort properties refresh on budget mutations

- **WHEN** the user creates, edits, or deletes a Budget
- **THEN** `budgets_count_bucket`, `default_currency_code`, `dominant_period`, `uses_carry_over`, `has_disabled_carry_over`, and `budgets_with_carry_over_on_count_bucket` SHALL be recomputed from the current `Budget` collection and set as people properties on the same distinct id

#### Scenario: analytics_opt_in_at is set on toggle-on

- **WHEN** the user accepts the consent sheet OR flips the Settings analytics toggle from `false` to `true`
- **THEN** `analytics_opt_in_at` SHALL be set to the current timestamp

---

### Requirement: First-run consent sheet (strict-opt-in jurisdictions only)

The app SHALL present an `AnalyticsConsentSheet` view exactly once per app install, immediately after the user successfully creates their first Budget, when ALL of the following conditions are true:

1. `ConsentJurisdiction.kind(for: Locale.current.region) == .required`.
2. The user has not previously made an explicit choice — i.e., the backing `NSUbiquitousKeyValueStore` contains no value under the key `"analyticsOptIn"`.

The sheet SHALL be presented via the existing `Router.sheet` mechanism (a new `.analyticsConsent` case on the sheet enum, mirroring the `.settings` / `.addBudget` / `.addExpense` cases).

The sheet SHALL contain three controls:

- **Accept** — sets `AppSettings.analyticsOptIn = true` (which persists), fires `analytics_consent_changed(new_value: true)`, dismisses the sheet.
- **Decline** — sets `AppSettings.analyticsOptIn = false` (which persists, so the "no value yet" guard returns `true` going forward), dismisses the sheet permanently for this install.
- **System dismiss (swipe down)** — equivalent to Decline.

The sheet SHALL NOT cause retroactive event replay. Any `app_opened` that the app would otherwise have fired before the toggle flipped to `true` SHALL NOT be re-fired after consent is granted; the triggering `budget_created` SHALL NOT be re-fired either. Dashboards in the `consent_jurisdiction = required` cohort SHALL be anchored on `analytics_consent_changed` rather than on `app_opened` or `budget_created` (a documentation contract enforced in `docs/analytics-spec.md` §7.2 and §11).

In auto-opt-in jurisdictions (`ConsentJurisdiction.kind == .auto_optin`), the sheet SHALL NOT be presented at any time. The Settings toggle is the only opt-out path in those locales.

#### Scenario: Strict-opt-in user creates first Budget

- **WHEN** the device is in a strict-opt-in jurisdiction, the user has never made an analytics choice, and `AddEditBudgetViewModel.save(...)` reaches the Add-mode success branch for the first Budget
- **THEN** the system SHALL set `Router.sheet = .analyticsConsent` and present `AnalyticsConsentSheet`

#### Scenario: Auto-opt-in user creates first Budget

- **WHEN** the device is in an auto-opt-in jurisdiction (e.g. US) and the user creates their first Budget
- **THEN** the consent sheet SHALL NOT be presented; `analyticsOptIn` SHALL remain at its default `true` value

#### Scenario: Strict-opt-in user has already declined

- **WHEN** the device is in a strict-opt-in jurisdiction, the user previously declined the consent sheet (so `"analyticsOptIn" = false` is persisted), and the user creates a subsequent Budget
- **THEN** the consent sheet SHALL NOT be re-presented

#### Scenario: Strict-opt-in user accepts

- **WHEN** the user taps Accept on `AnalyticsConsentSheet`
- **THEN** `AppSettings.analyticsOptIn` SHALL be set to `true`, `analytics.track("analytics_consent_changed", properties: [new_value: true])` SHALL fire (lazy-initializing the SDK), and the sheet SHALL dismiss

#### Scenario: Strict-opt-in user declines

- **WHEN** the user taps Decline on `AnalyticsConsentSheet`
- **THEN** `AppSettings.analyticsOptIn` SHALL be set to `false` and persisted, no `analytics_consent_changed` event SHALL fire (the SDK is not initialized), and the sheet SHALL dismiss

#### Scenario: System dismiss is treated as decline

- **WHEN** the user dismisses `AnalyticsConsentSheet` via swipe-down
- **THEN** the behavior SHALL match the Decline path

#### Scenario: No retroactive replay after accept

- **WHEN** the user accepts the consent sheet immediately after creating their first Budget
- **THEN** the system SHALL NOT re-fire `app_opened` or `budget_created` for events that occurred before consent was granted

---

### Requirement: PII enforcement — no helper consumes ExpenseItem

The app SHALL NOT expose any function, method, or extension under `simple-recurring-budgets/` that takes an `ExpenseItem` (or any `ExpenseItem` field by value) and returns a property dictionary suitable for `analytics.track`. Specifically, no extension on `AnalyticsClient`, on `ExpenseItem`, or on a shared analytics helper SHALL accept an `ExpenseItem` parameter and produce a `[String: any Sendable]` (or equivalent property bag) intended for analytics consumption.

`expense_*` events SHALL be assembled at the call site from categorical/bucketed sources only: `period` (from the parent `Budget`), `is_add_funds` (from the `ExpenseItem.isAddFunds` Bool), `from_screen` (a static enum), and `time_since_budget_created_bucket` (a bucketed duration). Free-text fields, money-shaped values, and raw dates from `ExpenseItem` SHALL NOT appear in the property dictionary.

#### Scenario: No expense-to-properties helper exists

- **WHEN** a contributor inspects `simple-recurring-budgets/Logging/`, `simple-recurring-budgets/Domain/`, and the `AnalyticsClient` extension space
- **THEN** no method's parameter list contains `ExpenseItem` AND a return type of `[String: any Sendable]` (or any equivalent property-bag shape)

#### Scenario: expense_logged property keys are bounded

- **WHEN** the call site test fires `expense_logged` against a fully-populated `ExpenseItem` fixture (with name, amount, date, notes, attachment)
- **THEN** the recorded `SpyAnalyticsClient` event SHALL contain only keys from `{period, is_add_funds, from_screen, time_since_budget_created_bucket}` and SHALL NOT contain `expense_name`, `expense_amount`, `expense_date`, `expense_notes`, or any other key

---

### Requirement: Boundary with Logger.* (no cross-routing into AnalyticsClient)

No code under `simple-recurring-budgets/` SHALL invoke both `Logger.*` and `AnalyticsClient.track(...)` for the same conceptual event with the intent of cross-routing one to the other. No `AnalyticsClient` method SHALL accept an OSLog-shaped value as a parameter. No call site SHALL derive its `analytics.track(...)` arguments from a `Logger.*` callback, and no `Logger.*` call site SHALL invoke `AnalyticsClient.track(_:)` (or its equivalents) as a deterministic side-effect of the log emission. This requirement re-asserts, from the product-analytics side, the cross-routing prohibition already established by the `diagnostic-logging` capability so the obligation is discoverable from either spec.

A single user action MAY independently produce one `Logger.*` line and one `AnalyticsClient` event (the Phase 1 destructive-action sites in `Phase 1 event call sites` are exactly this pattern). When both are emitted in the same method body, the two calls SHALL be sibling statements; neither's arguments SHALL be derived from the other's return value or closure capture.

#### Scenario: Sibling pattern at destructive sites

- **WHEN** the user confirms `Reset Budget` (or any other destructive action listed in `Phase 1 event call sites`)
- **THEN** the source method body SHALL contain `Logger.ui.debug(...)` and `analytics.track(...)` as sibling statements, neither derived from the other's return value or closure capture

#### Scenario: No cross-routing helper

- **WHEN** a contributor inspects `simple-recurring-budgets/Logging/`
- **THEN** no helper SHALL exist that subscribes to `OSLogStore`, observes `Logger.*` emissions, or accepts an OSLog-shaped value and forwards it into `analytics.track`

---

### Requirement: Localization of analytics-related copy

Every user-facing string introduced by this capability SHALL be keyed in `simple-recurring-budgets/Resources/Localizable.xcstrings` with a translator-friendly `comment:`, per F-3.03 / [`docs/analytics-spec.md` §2.1.6](../../../docs/analytics-spec.md#21-constraints-applying-to-all-mixpanel-work-f-802-and-f-803). The required keys are:

| Key                                  | Surface                                                                |
| ------------------------------------ | ---------------------------------------------------------------------- |
| `settings.analytics.section.title`   | Section header on `SettingsView`                                       |
| `settings.analytics.toggle.title`    | Toggle label                                                           |
| `settings.analytics.toggle.footer`   | Footer disclosure (mirrors §5 in plain language; locale-default note)  |
| `consent.analytics.sheet.title`      | Title of `AnalyticsConsentSheet`                                       |
| `consent.analytics.sheet.body`       | Body copy of the consent sheet                                         |
| `consent.analytics.sheet.accept`     | Accept button                                                          |
| `consent.analytics.sheet.decline`    | Decline button                                                         |

No hard-coded English literal SHALL appear in the new Settings section or in `AnalyticsConsentSheet` for any of these surfaces.

#### Scenario: Settings section uses keyed strings

- **WHEN** a contributor inspects the Diagnostics & Analytics section in `SettingsView`
- **THEN** every visible label SHALL resolve through `Text("settings.analytics....", comment:)` or `LocalizedStringKey`, and SHALL NOT contain a raw English literal

#### Scenario: Consent sheet uses keyed strings

- **WHEN** a contributor inspects `AnalyticsConsentSheet`
- **THEN** every visible label SHALL resolve through `Text("consent.analytics.sheet....", comment:)` or `LocalizedStringKey`, and SHALL NOT contain a raw English literal

---

### Requirement: Doc alignment — analytics-spec and tech-design-doc

[`docs/analytics-spec.md` §16.1](../../../docs/analytics-spec.md#161-implementation-starting-state-codebase-snapshot) SHALL be flipped to a historical record reflecting the post-implementation state (refactor complete) when this change ships. [`docs/analytics-spec.md` §19](../../../docs/analytics-spec.md#19-doc-updates-required-at-implementation-time) SHALL have its F-8.02-row entries marked done.

[`docs/tech-design-doc.md` §4.5](../../../docs/tech-design-doc.md) — the KV-key table SHALL include rows for `"analyticsOptIn"` (Bool, owned by `AppSettings`) and `"analyticsDistinctId"` (String, owned by `AppSettings`). [`docs/tech-design-doc.md` §7](../../../docs/tech-design-doc.md) SHALL accurately describe the lazy-init refactor and reference `docs/analytics-spec.md` §§2–8. [`docs/tech-design-doc.md` §9](../../../docs/tech-design-doc.md) SHALL refresh or remove any stale "analytics future-work" row and SHALL list F-8.03 as the planned Phase 2 row.

[`docs/product-features-planning.md`](../../../docs/product-features-planning.md) F-8.02 SHALL have its `**Status:**` line flipped from "Open" to "**Implemented.** Implemented by change `mixpanel-phase-1-foundation`."

#### Scenario: tech-design-doc §4.5 lists both new keys

- **WHEN** a reader inspects `docs/tech-design-doc.md` §4.5 KV-key table
- **THEN** the table SHALL contain rows for `"analyticsOptIn"` and `"analyticsDistinctId"` with their types and `AppSettings` owner

#### Scenario: analytics-spec §16.1 is a historical record

- **WHEN** a reader inspects `docs/analytics-spec.md` §16.1 after this change ships
- **THEN** the subsection SHALL describe the previous starting state as completed history (refactor complete) rather than as work to be done

#### Scenario: F-8.02 status reflects the implementing change

- **WHEN** a reader inspects `docs/product-features-planning.md` F-8.02
- **THEN** the `Status` line SHALL read `**Implemented.** Implemented by change `mixpanel-phase-1-foundation`.`

