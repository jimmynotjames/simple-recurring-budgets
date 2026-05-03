## Context

[`docs/product-features-planning.md`](../../../docs/product-features-planning.md) F-8.02 is **Open**. The repo has scaffolding from an earlier partial wiring that contradicts the canonical contract in [`docs/analytics-spec.md`](../../../docs/analytics-spec.md):

- [`simple-recurring-budgets/Logging/MixpanelAnalyticsClient.swift`](../../../simple-recurring-budgets/Logging/MixpanelAnalyticsClient.swift) calls `Mixpanel.initialize(token:trackAutomaticEvents:)` synchronously inside its `init`. Every launch — including opted-out launches in strict-opt-in jurisdictions — currently constructs a `MixpanelInstance`, opens a flush channel, and incurs network activity, in violation of [`§2.1.8`](../../../docs/analytics-spec.md#21-constraints-applying-to-all-mixpanel-work-f-802-and-f-803), [`§8`](../../../docs/analytics-spec.md#8-architecture-two-independent-paths), and [`§16.1`](../../../docs/analytics-spec.md#161-implementation-starting-state-codebase-snapshot).
- [`simple-recurring-budgets/App/simple_recurring_budgetsApp.swift`](../../../simple-recurring-budgets/App/simple_recurring_budgetsApp.swift) hard-codes `isOptedIn: { false }`, so even though `analytics.track(AnalyticsEvent.appOpened)` is wired in `body.task`, no event is ever delivered to Mixpanel.
- There is no `AppSettings.analyticsOptIn`, no `AppSettings.analyticsDistinctId`, no `ConsentJurisdiction` helper, no Settings UI, and no first-run consent sheet.
- The `appLaunched` → `appOpened` rename was already completed in a precursor change (current source: `AnalyticsEvent.appOpened = "app_opened"` in [`AnalyticsClient.swift`](../../../simple-recurring-budgets/Logging/AnalyticsClient.swift)). No further rename is needed.

The OSLog↔`AnalyticsClient` boundary is already established by the just-shipped `oslog-diagnostic-logging` change (F-8.01). The `diagnostic-logging` capability spec carries a structural assertion that `AnalyticsClient` exposes no OSLog-shaped API, and the four destructive-action `Logger.ui.debug` call sites are codified there. F-8.02 must preserve this boundary verbatim.

[`docs/analytics-spec.md`](../../../docs/analytics-spec.md) is the implementation contract for this change. [`§2`](../../../docs/analytics-spec.md#2-canonical-constraints) lists the canonical constraints (locale-aware consent default, no PII, no `ExpenseItem` field by value, lazy SDK init, OSLog boundary, copy keying); [`§3`](../../../docs/analytics-spec.md#3-product-questions--phase-1) lists the Phase 1 product questions; [`§9`](../../../docs/analytics-spec.md#9-phase-1-events) / [`§10`](../../../docs/analytics-spec.md#10-phase-1-properties) lists the canonical events and properties; [`§5`](../../../docs/analytics-spec.md#5-privacy-contract--pii-and-field-level-rules) is the field-level allow/deny list; [`§7.2`](../../../docs/analytics-spec.md#72-strict-opt-in-jurisdictions-and-the-first-run-consent-sheet) is the strict-opt-in region table; [`§8.1`](../../../docs/analytics-spec.md#81-launch-and-consent-transition-ordering-canonical-sequence) is the launch / consent-transition ordering; [`§16.1`](../../../docs/analytics-spec.md#161-implementation-starting-state-codebase-snapshot) is the file-level refactor checklist; [`§18.1`](../../../docs/analytics-spec.md#181-concrete-unit-test-contracts-phase-1) is the ten unit-test contracts.

## Goals / Non-Goals

**Goals**

- Land the lazy-init refactor of `MixpanelAnalyticsClient` so an opted-out launch in a strict-opt-in jurisdiction creates **zero** `MixpanelInstance` and emits **zero** network bytes.
- Wire the locale-aware consent default through a new `ConsentJurisdiction` helper (region table mirrored from §7.2) and two new `AppSettings` properties (`analyticsOptIn`, `analyticsDistinctId`), both `NSUbiquitousKeyValueStore`-backed.
- Add a Settings "Diagnostics & Analytics" section with the toggle and a localized disclosure footer.
- Add a first-run consent sheet that presents only in strict-opt-in jurisdictions and only after the user creates their first Budget, with the no-retroactive-replay rule from §7.2.
- Implement every Phase 1 event from §9, every per-event property from §10.1, every super property from §10.2, and every people property from §10.3, at the canonical call site.
- Land the ten Swift Testing contracts from §18.1, plus call-site PII enforcement tests on `expense_*` events.
- Update `docs/tech-design-doc.md` §§4.5 / 7 / 9 and `docs/analytics-spec.md` §§16.1 / 19 in the same change per [`docs/analytics-spec.md` §19](../../../docs/analytics-spec.md#19-doc-updates-required-at-implementation-time).
- Flip F-8.02's status to **Implemented** in `docs/product-features-planning.md`.

**Non-Goals**

- **Building Phase 1 dashboards in Mixpanel.** Per F-8.02 Edge Cases ("Phase 1 dashboards […] are configuration in Mixpanel and are NOT a code change; they MAY land as a doc-only follow-up under the same change or as a tracked task that ships alongside the implementing change"). Tasks include a follow-up note pointing at the §11 dashboard list, but no dashboard YAML/screenshot lives in this OpenSpec change.
- **Moving Mixpanel project tokens to `xcconfig` / `Info.plist`.** Explicitly forbidden by [`docs/analytics-spec.md` §16](../../../docs/analytics-spec.md#16-build-hygiene) and F-8.02 Edge Cases. The existing `#if DEBUG` literal branch in `simple_recurring_budgetsApp.init()` is preserved.
- **`AppTrackingTransparency` / `NSUserTrackingUsageDescription`.** Out of scope per §16. We do not collect IDFA, do not enable Mixpanel autocapture or session replay, and do not enable cross-app tracking. No ATT prompt is added.
- **Identity aliasing across `NSUbiquitousKeyValueStore` sync delays.** Per §6 limitations, deferred to Phase 2 if Phase 1 evidence shows the split is meaningful. Phase 1 accepts that two devices that race the first `analyticsDistinctId` write will appear as two users until the iCloud key syncs.
- **Phase 2 surface (F-8.03).** No `add_expense_started`, `add_budget_started`, `screen_viewed`, `feature_flag_exposed`, or rating-prompt events. No `FeatureFlagClient` protocol or implementations. No `taps_from_budgets_list` / `cold_start_to_budgets_visible_ms` properties.
- **Refactoring the existing OSLog call sites or `diagnostic-logging` spec.** F-8.01 owns those; this change must not regress the structural boundary.
- **`expense_*` properties beyond `§10.1`.** No `expense.name`, `expense.amount`, or `expense.date` is transmitted; the deny-list in `§5.3` is enforced at the call site by code review and by the PII test (`§18.1` #8).
- **Reset Cadences instrumentation.** Per `docs/product-features-planning.md` F-2.03, Reset Cadences is **PAUSED**; the `reset_cadence` allow-listed property in `§5.2` is deferred until that feature un-pauses.

## Decisions

### D1. New capability spec `product-analytics` (cross-cutting, single owner)

**Decision.** Create one new capability spec at `openspec/specs/product-analytics/spec.md` that owns the product-analytics surface end-to-end:

- The `AnalyticsClient` protocol shape (`track(_:properties:)`, `identify(_:)`, `reset()`) — kept as-is from the precursor.
- `AnalyticsEvent` and `AnalyticsProperty` enums — every Phase 1 name from §9 and §10.1 lives as a typo-safe `static let` constant. Adding a new event or property is a spec change.
- `MixpanelAnalyticsClient` lazy-init contract — first opted-in `track` or `identify` triggers `Mixpanel.initialize(token:trackAutomaticEvents:false)`; subsequent calls reuse the singleton.
- `ConsentJurisdiction` helper — pure function from `Locale.Region?` (or `String?`) to `JurisdictionKind = .required | .auto_optin`; the §7.2 region table is the source of truth.
- Consent flow — Settings toggle (always on) and first-run consent sheet (strict-opt-in jurisdictions only, after first `budget_created`, no retroactive replay).
- Field-level allow/deny rules — mirror of §5; `expense_*` events carry no `ExpenseItem` field by value; `budget_*` events MAY carry `budget_name` (free-text) and `budget_allocation_amount` (paired with `currency_code`); no other money-shaped value or free-text field.
- Phase 1 event call sites (§9), per-event properties (§10.1), super properties (§10.2), and people properties (§10.3) — all with their canonical names and enumerated value domains.
- The `bundle_id` super property — registered explicitly via `registerSuperProperties`, not auto-attached, per §11 fork-pollution defense.
- Launch and consent-transition ordering (§8.1).
- The structural boundary with `Logger.*` already enforced by the `diagnostic-logging` capability — re-asserted here as a sibling clause so the obligation is discoverable from either side.

**Alternatives considered.**

- *Spread the surface across `app-settings` (toggle + distinct id), `settings-screen` (UI), `add-edit-budget-screen` / `add-edit-expense-screen` / `budget-detail-screen` (call sites), and a hypothetical "shared analytics constants" file.* Rejected: a future contributor adding a new event would have nowhere central to consult for the no-PII contract or the lazy-init invariant. Diagnostic logging took the same single-spec route in `diagnostic-logging`; product analytics deserves the same.
- *Embed the contract in `docs/analytics-spec.md` only.* analytics-spec.md is the source of truth, but it's prose without testable scenarios. The OpenSpec capability format gives `WHEN/THEN` scenarios that the test suite can mirror line-for-line.

**Rationale.** Cross-cutting concern; one cohesive spec is easier to extend (Phase 2 lands as a delta) and to verify. Screen-level specs stay focused on user-observable behavior.

### D2. `AppSettings.analyticsOptIn` — locale-aware default, lazy resolution

**Decision.** `analyticsOptIn` is read from `NSUbiquitousKeyValueStore` under key `"analyticsOptIn"`. If absent, the default is **resolved on first read** by calling `ConsentJurisdiction.kind(for: Locale.current.region)`:

- `.required` → default `false`.
- `.auto_optin` → default `true`.

The resolved default is **NOT** persisted to the store immediately. Persistence happens on the first explicit user toggle (or on first opt-in via the consent sheet). This avoids two side-effects of eager persistence:

1. A default-`true` write on first launch in an auto-opt-in jurisdiction would propagate via iCloud to a paired device, where it would override the strict-opt-in jurisdiction's `false` default if the paired device is in the EU. The user's iCloud-paired settings would no longer reflect their device-local jurisdiction.
2. A default-`false` write would similarly leak the strict-opt-in default into auto-opt-in devices.

By keeping the unset state local until the user makes a deliberate choice (toggle or consent sheet), the first-launch default each device experiences is the correct one for its own locale.

**Alternatives considered.**

- *Eagerly persist the default on first launch.* Rejected — see leakage scenarios above.
- *Persist the default but also persist the `consent_jurisdiction` snapshot, and restore the matching default on jurisdiction change.* Over-engineered; jurisdictions don't change for a single user often, and the explicit-toggle path is simpler.

**Rationale.** The default-on-read pattern is already used by `AppSettings.weekStartDay` (locale-default if no stored value); we reuse the established convention.

### D3. `AppSettings.analyticsDistinctId` — UUIDv4, generated once, internal setter

**Decision.** `analyticsDistinctId` is read from `NSUbiquitousKeyValueStore` under key `"analyticsDistinctId"`. If absent, `AppSettings` generates a `UUID().uuidString`, persists it via `synchronize()`, and returns it. Subsequent reads return the persisted value verbatim. The setter is **internal** (or `private(set)`); no caller outside `AppSettings` may overwrite it. The value syncs across the user's iCloud-paired devices via `NSUbiquitousKeyValueStore`.

`MixpanelAnalyticsClient` consumes the distinct id via a `@Sendable` closure provider (not a captured String) so SwiftUI's `@Observable` re-emission semantics (and external-change refreshes from iCloud) are respected.

**Alternatives considered.**

- *Public setter so tests can inject a deterministic UUID.* Rejected — tests use a `MockKeyValueStore` pre-populated with the desired UUID; that path is already tested for `defaultCarryOverEnabled` and `weekStartDay`, and it keeps the public surface tighter.
- *Persist as `Data` instead of `String`.* Rejected — `String` round-trips through `NSUbiquitousKeyValueStore` and Mixpanel without conversion; `Data` adds friction for no benefit.
- *Generate on first launch eagerly.* Acceptable but slightly worse: an opted-out launch in a strict-opt-in jurisdiction has no need for a distinct id until the user opts in. Lazy generation on first read keeps "no analytics work until opt-in" tighter. The cost of eager generation is one UUID per device-install regardless, so we go lazy.

**Rationale.** Per [`docs/analytics-spec.md` §6](../../../docs/analytics-spec.md#6-identity).

### D4. `MixpanelAnalyticsClient` lazy-init guard — `os_unfair_lock`

**Decision.** Defer `Mixpanel.initialize(token:trackAutomaticEvents:false)` to the first opted-in `track(_:properties:)` or `identify(_:)` invocation. Use `os_unfair_lock` (via `OSAllocatedUnfairLock<MixpanelInstance?>` on iOS 16+, or a manual `os_unfair_lock_t` wrapper) as a one-shot init guard:

```swift
final class MixpanelAnalyticsClient: AnalyticsClient {
  private let token: String
  private let isOptedIn: @Sendable () -> Bool
  private let distinctIdProvider: @Sendable () -> String?
  private let instance: OSAllocatedUnfairLock<MixpanelInstance?> = .init(initialState: nil)

  func track(_ event: String, properties: [String: any Sendable]?) {
    guard isOptedIn() else { return }
    let mp = ensureInitialized()
    let mixProps = properties?.compactMapValues { $0 as? MixpanelType }
    mp.track(event: event, properties: mixProps)
  }

  private func ensureInitialized() -> MixpanelInstance {
    instance.withLock { state in
      if let existing = state { return existing }
      let mp = Mixpanel.initialize(token: token, trackAutomaticEvents: false)
      registerSuperProperties(on: mp)            // §10.2
      if let id = distinctIdProvider() { mp.identify(distinctId: id) }
      state = mp
      return mp
    }
  }

  func reset() {
    instance.withLock { state in
      state?.reset()
      state = nil   // re-init on next opted-in track if user toggles back on
    }
  }
}
```

**Alternatives considered.**

- *Swift `actor` for the instance.* Would make every `track` call `async`, which forces every call site to `await` and plumbs `Task` boundaries through all the views. Out of proportion for a tight critical section.
- *`DispatchQueue.sync` serial queue.* Works but `os_unfair_lock` is the modern and cheaper option for "one-shot mutate" patterns.
- *Atomic flag + lazy-var `MixpanelInstance`.* Swift's `lazy var` on a class property is **not** thread-safe; concurrent first calls can double-initialize, which Mixpanel's SDK does not document handling.
- *Initialize on `analyticsOptIn` toggle-on instead of on first `track`.* Acceptable, but a `track` from somewhere unexpected (e.g., a future call site in a non-UI service) would still need the guard, so we keep "first track wins" as the contract.

**Rationale.** `os_unfair_lock` keeps the critical section to a single Mixpanel SDK call and a couple of property writes; first-track latency is bounded by `Mixpanel.initialize`. Concurrent first-calls don't double-init. `reset()` returns the guard to its initial state so a toggle-off → toggle-on cycle re-initializes cleanly (per §16.1 row #3). Test contract `§18.1` #4 asserts this invariant.

### D5. Consent sheet — `Router.sheet` enum case, fired on first `budget_created`

**Decision.** Add a new `.analyticsConsent` case to the existing `Router.sheet` enum (the same mechanism that hosts `.settings`, `.addBudget`, `.addExpense`). The Add/Edit Budget save-success path triggers `Router.sheet = .analyticsConsent` only when:

1. `ConsentJurisdiction.kind(for: Locale.current.region) == .required`, AND
2. `AppSettings.analyticsOptInExplicitlySet == false` (a derived flag indicating the user has not yet toggled or accepted/declined the sheet — implemented as "store contains no value for `\"analyticsOptIn\"`"), AND
3. The Budget save succeeded.

The sheet hosts an `AnalyticsConsentSheet` view with three controls:
- **Accept** — sets `AppSettings.analyticsOptIn = true` (which persists), fires `analytics_consent_changed(new_value: true)` on the now-initialized Mixpanel client, dismisses the sheet.
- **Decline** — leaves `AppSettings.analyticsOptIn` at `false` and persists `false` so the "explicitly set" guard returns `true` next launch and the sheet does not re-present.
- **System dismiss (swipe down)** — treat as decline (persists `false`).

**No retroactive event replay.** The triggering `budget_created` and the launch's notional `app_opened` are NOT replayed. Per §7.2, dashboards in `consent_jurisdiction = required` cohorts are anchored on `analytics_consent_changed`.

**Alternatives considered.**

- *Present the sheet on first launch instead of after first `budget_created`.* Rejected — §7.2 explicitly says "after the user creates their first Budget" so the user has tangible context for what we're asking to measure.
- *Custom UIViewController-backed sheet.* Rejected — the Router enum approach is the established pattern in the codebase; adding a fifth case is mechanical.
- *Per-launch presentation until accepted.* Rejected — §7.2 says "Declining keeps the default `false` and dismisses the sheet permanently." We respect that.

**Rationale.** Mirrors the established Router pattern. Persisting `false` on decline is necessary so the "no value yet" check returns `false` and the sheet does not re-present. The consent-sheet trigger lives in the Add/Edit Budget save path, not in the Router itself, keeping the Router enum a passive carrier.

### D6. Phase 1 events — call-site map

**Decision.** Each Phase 1 event from §9 is fired exactly once per logical user action at exactly one call site:

| Event                       | Call site                                                                                  |
| --------------------------- | ------------------------------------------------------------------------------------------ |
| `app_opened`                | `simple_recurring_budgetsApp.body`'s `.task` (already wired; preserved).                  |
| `budget_created`            | `AddEditBudgetViewModel.save(...)` Add-mode success branch.                                |
| `budget_edited`             | `AddEditBudgetViewModel.save(...)` Edit-mode success branch.                               |
| `budget_deleted`            | `AddEditBudgetViewModel.delete(context:)` after `try? context.save()`.                     |
| `budget_reset`              | `BudgetDetailView.resetBudget` after `try? context.save()`.                                |
| `carry_over_reset`          | `BudgetDetailView.resetCarryOver` after `try? context.save()`.                             |
| `expense_logged`            | `AddEditExpenseViewModel.save(...)` Add-mode success branch.                               |
| `expense_edited`            | `AddEditExpenseViewModel.save(...)` Edit-mode success branch.                              |
| `expense_deleted`           | `BudgetDetailView+ExpenseSection.deleteExpense(_:)` (single funnel for swipe + rotor, mirroring the `diagnostic-logging` site). |
| `settings_opened`           | `SettingsView.task` on first appearance per sheet presentation.                            |
| `setting_changed`           | `SettingsView` — at each `AppSettings` write that corresponds to a §10.1 enum value (`default_carry_over_enabled`, `week_start_day`, `currency_display_preference`). The opt-in toggle uses `analytics_consent_changed` instead and is excluded from `setting_changed` per §10.1. |
| `analytics_consent_changed` | `SettingsView` consent toggle change handler AND `AnalyticsConsentSheet` accept handler. Fired **before** `analyticsOptIn` flips to `false` on toggle-off so opt-outs are observable (per §7.3). |

**⚠️ Boundary-adjacent sites.** Four of the twelve events share their exact call-site method body with an existing `Logger.ui.debug` entry established by `oslog-diagnostic-logging` (F-8.01):

| Method                                              | Logger.ui.debug action | analytics.track event |
| --------------------------------------------------- | ---------------------- | ---------------------- |
| `AddEditBudgetViewModel.delete(context:)`           | `"deleteBudget"`       | `budget_deleted`       |
| `BudgetDetailView.resetBudget`                      | `"resetBudget"`        | `budget_reset`         |
| `BudgetDetailView.resetCarryOver`                   | `"resetCarryOver"`     | `carry_over_reset`     |
| `BudgetDetailView+ExpenseSection.deleteExpense(_:)` | `"deleteExpense"`      | `expense_deleted`      |

These four sites intentionally "cross the boundary" in the narrow sense that two systems (OSLog and Mixpanel) are both invoked from the same method body. This is permitted and expected — `docs/analytics-spec.md` §17 already notes "A single user action can produce both" — but the two calls must remain **independent sibling statements**: neither derives its arguments from the other's return value or from an OSLog-side observer.

The reason these co-locations exist is practical: the four methods are the single canonical funnels for the corresponding user action (established by F-8.01). Splitting them to avoid co-location would require introducing new delegation layers with no benefit. The `diagnostic-logging` capability spec itself anticipated this pattern (see its "Sibling call sites are allowed" scenario).

**Flagged for spec cleanup.** `docs/analytics-spec.md` §17 describes the two paths as "deliberately separate" and the boundary table states diagnostic events "never pass through `AnalyticsClient`". The phrasing is accurate but can be misread as forbidding co-location. A follow-up edit to §17 should make explicit that co-location in the same method body is the **expected and approved** pattern for user-action sites that need both a runtime-trace entry and a product-measurement event, provided the two calls remain independent. See task §19.

**Alternatives considered.**

- *Fire `expense_logged` from the view rather than the view model.* Rejected — the view model is the only path that knows the save succeeded. Firing in the view would risk firing on `Cancel`.
- *Fire from a centralized `AnalyticsObserver` listening to `ModelContext.willSave` / `.didSave`.* Rejected — would re-introduce a true cross-routing pattern (diagnostic data forwarded to product analytics), which `diagnostic-logging` forbids and which would be brittle (CloudKit-driven background saves would emit phantom events).
- *Extract a wrapper helper that calls both Logger and analytics in one call.* Rejected — this would be the definition of cross-routing even if the code lives in one place. Independent sibling statements at the call site are the only safe pattern.

**Rationale.** Each event has exactly one origination point. The four co-located sites are a practical constraint, not a design compromise, and they are safe because the two calls are independent.

### D7. Super properties — registered once on first init; mutable ones refreshed on change

**Decision.** Static super properties (`app_version`, `app_build`, `device_class`, `locale`, `region`, `consent_jurisdiction`, `bundle_id`) are passed to `Mixpanel.mainInstance().registerSuperProperties(...)` on the first lazy init. Mutable super properties (`week_start_day`, `currency_display_preference`, `icloud_state`, `budgets_count_bucket`, `carry_over_default_enabled`) are also registered on first init with their current values, and **refreshed** on the relevant change:

- `week_start_day`, `currency_display_preference`, `carry_over_default_enabled` — refreshed on the `AppSettings` change emission (a small observer in `MixpanelAnalyticsClient` or, simpler, a refresh call from `SettingsView` after each save).
- `icloud_state` — refreshed when `SyncStatus.rowState` transitions (we already have a notification handler in `SettingsView`).
- `budgets_count_bucket` — recomputed and refreshed on `budget_created` and `budget_deleted` immediately before the event call.

`bundle_id` is registered explicitly via `registerSuperProperties([...])` per §11 (the SDK's auto-attached `$app_id` is not relied upon; the explicit registration is the fork-pollution defense).

**Alternatives considered.**

- *Compute super properties dynamically per `track` call.* Mixpanel's super-property mechanism is designed for once-set, replace-on-change. Computing per call duplicates work and risks drift between super and per-event values.
- *Push every `AppSettings` change through Mixpanel proactively.* The settings-change → super-property update path could live in a dedicated `AnalyticsSuperPropertiesObserver`, but for Phase 1 the simpler pattern (refresh from the call site that wrote the settings change) is sufficient and easier to test.

**Rationale.** Matches §10.2's intent and Mixpanel's idiomatic super-property usage.

### D8. People properties — set on `identify`, refreshed on relevant events

**Decision.** The first lazy init invokes `identify(distinctId)` and immediately sets baseline people properties (`first_seen_at` if absent, `last_app_open_at`, `analytics_opt_in_at` if newly opted in, plus the cohort properties from §10.3). On subsequent events:

- `budget_created` / `budget_edited` / `budget_deleted` recompute and `set` `budgets_count_bucket`, `default_currency_code`, `dominant_period`, `uses_carry_over`, `has_disabled_carry_over`, `budgets_with_carry_over_on_count_bucket` from the current `Budget` collection (a SwiftData fetch on the main `ModelContext`).
- `app_opened` updates `last_app_open_at` to `Date()`.
- `analytics_consent_changed(new_value: true)` updates `analytics_opt_in_at`.
- `first_seen_at` is set with `setOnce` semantics (Mixpanel's `peopleSetOnce` — first write wins; subsequent calls are no-ops).

**Alternatives considered.**

- *Run people-property recomputation on a SwiftData notification observer.* More elegant but more complex; postponed to a Phase 2 polish if needed. For Phase 1 the immediate-after-mutation refresh in the view model is sufficient and easier to test.

**Rationale.** Matches §10.3.

### D9. PII enforcement — call-site assertion + structural surface

**Decision.** Three layers enforce the §5 contract:

1. **`AnalyticsProperty` enum is the only typo-safe key surface.** Call sites must assemble `properties` dictionaries using `AnalyticsProperty.budgetName.rawValue` etc. The enum domain is closed to §10.1; adding a new key requires a spec change.
2. **No `ExpenseItem`-to-properties helper.** No method in `AnalyticsClient` extension space, on `ExpenseItem`, or on a shared helper takes an `ExpenseItem` and returns a `[String: Any]`. The structural test in `§18.1` #8 asserts no such API exists.
3. **Call-site test fixtures.** Every Phase 1 event has at least one call-site test that passes a fixture entity and asserts the recorded `SpyAnalyticsClient` event carries only the §10.1 allow-listed keys.

Layer (3) is the strongest because it catches the case where a future contributor manually serializes `expense.name` into the properties dictionary at a call site (which (1) and (2) cannot prevent).

**Alternatives considered.**

- *Type the `AnalyticsClient.track` API as `track(_:properties: [AnalyticsProperty: any Sendable])` instead of `[String: any Sendable]`.* Tighter, but Mixpanel SDK consumes `[String: any MixpanelType]` and forces a remap at the boundary. Considered worth it but deferred for now to keep the precursor protocol shape.
- *SwiftLint custom rule rejecting `expense.name`/`expense.amount` interpolations near `analytics.track`.* Over-engineering for a single-developer codebase. The structural test plus code review is the right level of guardrail.

**Rationale.** Three independent layers; no single point of failure.

### D10. Doc updates — fold into the same change

**Decision.** Tasks list every doc update from `docs/analytics-spec.md §19` inline:

- `docs/tech-design-doc.md` §4.5 KV-key table — add `"analyticsOptIn"` (Bool) and `"analyticsDistinctId"` (String, UUIDv4) rows.
- `docs/tech-design-doc.md` §7 — confirm vendor named, opt-in toggle wired, lazy-init refactor complete; refresh the prose if needed (it already references §§2–8).
- `docs/tech-design-doc.md` §9 — drop or refresh the analytics row in the future-work table; add a Phase 2 (F-8.03) row.
- `docs/analytics-spec.md` §16.1 — flip the "Implementation starting state" subsection to a historical record (refactor complete; this subsection becomes a historical reference).
- `docs/analytics-spec.md` §19 — mark the F-8.02 rows as done (matching the `(done by …)` convention used for the F-8.01 row).
- `docs/product-features-planning.md` F-8.02 — flip status to **Implemented. Implemented by change `mixpanel-phase-1-foundation`.** Bump version + date in file header. Acceptance Criteria, Edge Cases, and Dependencies remain untouched.

**Rationale.** `openspec/config.yaml` and `AGENTS.md` both require docs updates to land in the same change when product / architecture content materially moves. Flipping a feature status and adding two KV keys both qualify.

### D11. Localization — every user-facing string keyed in `Localizable.xcstrings`

**Decision.** Every new user-facing string lands in `simple-recurring-budgets/Resources/Localizable.xcstrings` with a translator-friendly `comment:`, per F-3.03 and §2.1.6. The keys are:

| Key                                                  | Surface                                                                |
| ---------------------------------------------------- | ---------------------------------------------------------------------- |
| `settings.analytics.section.title`                   | Section header in `SettingsView`                                       |
| `settings.analytics.toggle.title`                    | Toggle label                                                           |
| `settings.analytics.toggle.footer`                   | Footer disclosure (mirrors §5 in plain language; locale-default note)  |
| `consent.analytics.sheet.title`                      | Consent sheet title                                                    |
| `consent.analytics.sheet.body`                       | Consent sheet body copy                                                |
| `consent.analytics.sheet.accept`                     | Accept button                                                          |
| `consent.analytics.sheet.decline`                    | Decline button                                                         |

`common.action.cancel` is reused if any Cancel-style button appears (none expected — Decline is its own button).

**Rationale.** Aligns with the localization audit and the F-3.03 invariants.

## Risks / Trade-offs

- **[Risk] Toggle-off ordering bug — `analytics_consent_changed` fires *after* `analyticsOptIn` flips to `false`.** Per §7.3 / §8.1 the consent-changed event MUST fire while still opted in so the opt-out is observable. → **Mitigation.** Test contract §18.1 #5 asserts the order. The consent toggle change handler in `SettingsView` calls `analytics.track("analytics_consent_changed", properties: [...])` first, then `analytics.reset()`, then `settings.analyticsOptIn = false` — with a comment pointing at §7.3.
- **[Risk] Lazy-init guard double-init under concurrent first-call `track` race.** → **Mitigation.** `os_unfair_lock` serializes the first call. Test contract §18.1 #4 (with the SDK init step replaced by a closure spy) asserts exactly-once invocation under many calls. The post-fix pattern is the same as we already use for SwiftUI `@MainActor`-isolated singletons.
- **[Risk] `NSUbiquitousKeyValueStore` sync delay creates duplicate `analyticsDistinctId` UUIDs across paired devices.** → **Mitigation.** Accepted per §6 limitations (Phase 2 may revisit). Phase 1 dashboards anchored on `consent_jurisdiction = required` use `analytics_consent_changed` as the cohort anchor instead of `app_opened` to dampen this issue in the strict-opt-in case.
- **[Risk] `ConsentJurisdiction` table drifts from §7.2.** → **Mitigation.** The `product-analytics` capability spec includes a `WHEN/THEN` scenario per region row in §7.2 (parameterized in code per §18.1 #1). Adding a region requires both source and spec to update.
- **[Risk] Token leak from a fork.** A user who forks the public repo will retain the dev or prod token if they don't change them. → **Mitigation.** Per §10.2 / §11 / §16, register `bundle_id` explicitly as a super property and apply a project-level Mixpanel filter on `bundle_id`. Forked builds with a different bundle ID are excluded from every dashboard. The residual case (forker who doesn't change bundle ID) is acknowledged as practically negligible — they cannot install on a second device or submit to App Store without a unique bundle ID.
- **[Risk] First-run consent sheet in a strict-opt-in jurisdiction never presents because the user doesn't create a Budget.** → **Mitigation.** Accepted. The user remains opted out (the safe default). The Settings toggle is the recovery path; if the user ever opens Settings they can opt in there. Phase 1 dashboards account for this by anchoring strict-opt-in retention on `analytics_consent_changed`.
- **[Trade-off] No retroactive event replay after consent.** Strict-opt-in users' `app_opened` and triggering `budget_created` are lost. **Accepted** per §7.2; dashboards in `consent_jurisdiction = required` use `analytics_consent_changed` as the anchor.
- **[Trade-off] Phase 1 dashboards are not in the OpenSpec change.** Tasks include a follow-up pointer at the §11 list. This is consistent with F-8.02's Edge Cases note that Phase 1 dashboards "MAY land as a doc-only follow-up under the same change or as a tracked task." The change's archive criteria do **not** require dashboards to be live; the change ships when code + specs + docs are in the repo, and the dashboards are a tracked follow-up.
- **[Trade-off] Settings section ordering: Diagnostics & Analytics goes between iCloud Sync and Support.** **Accepted.** This places privacy-relevant controls (iCloud sync state ↔ analytics opt-in) adjacent without disturbing the Support and About sections.

## Migration Plan

This is an additive change: no schema migration, no data migration, no breaking API change.

- **Persistence.** Two new `NSUbiquitousKeyValueStore` keys (`"analyticsOptIn"`, `"analyticsDistinctId"`). Existing installs will read no value on first launch post-update and resolve the locale-aware default; `analyticsDistinctId` will be generated on first opt-in. No migration code is required. The store's eventual consistency is accepted (§6 limitations).
- **TestFlight rollout.** Same Release codepath as production with the prod token; default opt-in state follows the same locale-aware rule.
- **Rollback.** The change can be reverted in source. Existing installs that wrote `"analyticsOptIn"` / `"analyticsDistinctId"` to `NSUbiquitousKeyValueStore` will leave those values orphaned in the store; they are harmless leftovers (mirroring the `"seededV1"` precedent in `docs/tech-design-doc.md` §4.5). On re-application of the change, the same keys are re-read.

## Open Questions

- **None at proposal time.** All §3 product questions are answered by the §9–§11 surface, the lazy-init refactor scope is fully specified in §16.1, the consent flow is canonical in §7 / §8.1, and the test contracts are enumerated in §18.1. If new questions surface during implementation they should land in the tasks file as `TODO`s blocking the verify step.

## Doc alignment

- [`docs/main-prd.md`](../../../docs/main-prd.md) §6.3 — aligned. Locale-aware consent default is exactly what the PRD mandates.
- [`docs/product-features-planning.md`](../../../docs/product-features-planning.md) F-8.02 — status flips to **Implemented** at archive (task in `tasks.md`).
- [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §§4.5 / 7 / 9 — all three updated at implementation time per §19 (tasks list each explicitly).
- [`docs/analytics-spec.md`](../../../docs/analytics-spec.md) — implementation contract; §16.1 rewritten to historical record and §19 rows marked done at archive (tasks list each).
- [`docs/ux-design-brief.md`](../../../docs/ux-design-brief.md) — no UX surface changes that conflict.

No conflicts.
