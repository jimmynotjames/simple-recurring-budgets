# Analytics Spec

| Field              | Value      |
| ------------------ | ---------- |
| **Version**        | 0.1        |
| **Last Updated**   | 2026-04-30 |
| **Author / Owner** | Jimmy Ho   |

> Companion design + instrumentation spec for **F-8.02** (Mixpanel Phase 1) and **F-8.03** (Mixpanel Phase 2) in [product-features-planning.md](product-features-planning.md). The features doc carries the high-level constraints and the product questions the work must answer; this doc captures the detailed instrumentation, identity, consent, and architectural decisions that produce those answers. Phase 1 establishes the measurement foundation and answers first-tier product questions; Phase 2 reacts to Phase 1 evidence and adds an experimentation seam.

---

## 1. Vendor Choice

**Mixpanel** is the chosen product analytics vendor for the app's behavioral data.

**Strengths we lean on**

- Event-shaped behavioral data with built-in funnel, retention, cohort, and flow reports.
- Cross-device user identity unification through `distinct_id`.
- Mixpanel feature flags / experiments as a controlled A/B testing seam (Phase 2 only).
- Generous free tier that fits this app's expected scale through public launch.

**Weaknesses we sidestep — routed elsewhere**

- Mixpanel is **not** a crash reporter. Crash and reliability data stays on `OSLog` (F-8.01) and Apple-native frameworks (MetricKit, system Crash Reporter).
- Mixpanel is **not** a time-series technical telemetry log. Diagnostic and lifecycle events stay on `OSLog`.
- Mixpanel is **not** a raw-event log store. High-frequency or per-tap events are sampled or dropped before they reach Mixpanel.
- Mixpanel does not currently offer iOS session replay; we don't try to replicate it.

---

## 2. Product Questions — Phase 1

Phase 1 is the smallest viable instrumentation that lets us answer the questions below. Each subsection links to the events / properties that produce the answer (mapped in §§8–10) and to the dashboard that delivers it (§11).

### 2.1 Reach and engagement

- Are people opening the app at all? DAU, WAU, MAU on `app_opened`.
- Sessions per active user.
- Hour-of-day distribution of `expense_logged` so we know when users actually use the app.

### 2.2 Activation

- Activation funnel: `app_opened → budget_created → expense_logged`. Where do new users drop off?
- Time from first `app_opened` to first `budget_created`.
- Time from first `budget_created` to first `expense_logged` (bucketed; see §9.1).

### 2.3 Composition of usage

- Average and distribution of Budgets per user (via `budgets_count_bucket` super property).
- Breakdown of Budget Period (`daily` / `weekly` / `biweekly` / `monthly`) two ways:
  - Share of users whose dominant period is X.
  - Share of all Budgets that are X.
- Currency-code breakdown across users and across Budgets.
- Locale / region breakdown; iOS / device-class breakdown.
- Share of users with carry-over enabled (default-on retained) versus explicitly turned off.

### 2.4 Retention

- 1-day, 7-day, and 30-day retention anchored on `expense_logged` (the core value loop).
- 1-day, 7-day, and 30-day retention anchored on `app_opened` (engagement floor).

### 2.5 Settings and destructive actions

- Settings open rate (`settings_opened` per active user).
- Frequency of destructive actions — `budget_reset`, `carry_over_reset`, and `budget_deleted` — to gauge how often users course-correct, and which destructive flow they reach for.
- Frequency of `expense_edited` and `expense_deleted` to see whether logging is "right first time" or routinely corrected after the fact.

### 2.6 Privacy and consent

- Opt-in rate, broken down by `consent_jurisdiction` (regions that legally require an explicit consent sheet vs the rest).
- Opt-out rate over time (transitions to `false` on `analytics_consent_changed`).

---

## 3. Product Questions — Phase 2

Phase 2 deepens Phase 1's picture and adds the experimentation seam. Phase 2 questions assume Phase 1 dashboards already exist; some Phase 2 properties may be dropped or replaced once Phase 1 evidence shows whether the underlying signal is there.

### 3.1 Funnel abandonment

- Where in the Add Expense flow do users drop off? Funnel step `add_expense_started → expense_logged`.
- Where in the Add Budget flow do users drop off? Optional `add_budget_started → budget_created`, only if Phase 1 evidence motivates it.

### 3.2 UX validation

- Does the [ux-design-brief.md](ux-design-brief.md) "Signature Element: Fast expense logging" promise hold up? Median (and p50 / p90) `taps_from_budgets_list` to a successful `expense_logged`.
- Cold-start latency to a usable Budgets list (`cold_start_to_budgets_visible_ms` on `app_opened`).

### 3.3 Cohort retention

- Retention by `dominant_period` cohort.
- Retention by `uses_carry_over`.
- Retention by `has_multiple_budgets`.
- Retention by `uses_multiple_currencies`.

### 3.4 Rating prompt (F-6.03)

- When do users meet the "meaningful usage" threshold defined by F-6.03?
- Once F-6.03 ships: distribution of rating-prompt outcomes (shown / dismissed / rated).

### 3.5 Experimentation

- For any active Mixpanel feature flag, conversion / retention by variant. F-8.03 ships the seam, not a live experiment.

---

## 4. Privacy Contract

Mixpanel is strictly opt-in, default off in every region. Mandated by [tech-design-doc.md](tech-design-doc.md) §7 and [main-prd.md](main-prd.md) §6.3.

**What is sent**

- Categorical or bucketed properties only (period, currency code, boolean toggles, count buckets).
- App and device super properties (auto-populated by the SDK).

**What is never sent**

- Budget names, expense names, expense dates, expense notes — anything free-text.
- Currency amounts, allocations, balances — anything money-shaped.
- Apple ID, iCloud user record, email address.

`MixpanelAnalyticsClient` carries this contract in its doc comment and is reviewed at every PR that touches it.

---

## 5. Identity

A UUIDv4 generated at first launch is persisted in `NSUbiquitousKeyValueStore` under key `"analyticsDistinctId"` and used as Mixpanel's `distinct_id`. Because `NSUbiquitousKeyValueStore` syncs across the user's iCloud-paired devices ([tech-design-doc.md §4.5](tech-design-doc.md)), a single human is unified across their devices without us collecting any Apple-issued identifier.

`identify(_:)` is called once analytics is enabled. `reset()` is called when the user opts out.

**Limitations** — accepted as Phase 1 trade-offs:

- The distinct id is not rotated automatically. If the user signs out of iCloud or wipes the app, a new UUID is generated.
- `NSUbiquitousKeyValueStore` is eventually consistent. If the same Apple ID opens the app on a second device before the `"analyticsDistinctId"` value has synced, that device generates and writes its own UUID; later events from that device are then attributable to a separate user in Mixpanel until the first device's key wins. Handling this cleanly (e.g., calling `identify(_:)` to alias on later sync) is deferred to Phase 2 if Phase 1 evidence shows the split is meaningful.

---

## 6. Consent

### 6.1 Always-on Settings toggle

`AppSettings.analyticsOptIn: Bool`, default `false`, persisted in `NSUbiquitousKeyValueStore` under key `"analyticsOptIn"`.

The Settings screen (F-2.05) gains a **Diagnostics & Analytics** section with:

- A single toggle bound to `AppSettings.analyticsOptIn`.
- A short disclosure of what is and is not sent (mirroring §4).
- All copy keyed in `Localizable.xcstrings` per F-3.03.

### 6.2 First-run consent sheet (consent-required jurisdictions only)

A one-time consent sheet appears immediately after the user creates their first Budget — but only in jurisdictions that legally require explicit opt-in consent.

**Default jurisdiction list**: EU + EEA + UK + Switzerland, derived from `Locale.current.region.identifier` at app launch. Lives in a `ConsentJurisdiction` helper so future legal changes are a one-line edit.

Outside those regions the Settings toggle alone is sufficient surfacing. The global rule is opt-in default-off regardless.

### 6.3 Toggle-off behavior

When the user disables analytics:

1. `analytics_consent_changed` fires **before** disabling so opt-outs are observable.
2. `MixpanelAnalyticsClient.reset()` clears the local distinct id state.
3. All subsequent `.product` events are dropped at the client.

---

## 7. Architecture: AnalyticsClient Seam

The existing `AnalyticsClient` protocol in [simple-recurring-budgets/Logging/AnalyticsClient.swift](../simple-recurring-budgets/Logging/AnalyticsClient.swift) already separates routing by channel:

| Channel                          | Routing                                                  |
| -------------------------------- | -------------------------------------------------------- |
| `.bootstrap`, `.cloudKit`, `.ui` | `OSLog` only (F-8.01) — never forwarded to Mixpanel.     |
| `.product`                       | Mixpanel, gated on opt-in. Silent no-op when opted out.  |

Phase 1 implements `MixpanelAnalyticsClient: AnalyticsClient` next to [simple-recurring-budgets/Logging/ConsoleAnalyticsClient.swift](../simple-recurring-budgets/Logging/ConsoleAnalyticsClient.swift). Like `ConsoleAnalyticsClient`, it routes diagnostic channels (`.bootstrap`, `.cloudKit`, `.ui`) to `OSLog` and only forwards `.product` events to Mixpanel — so swapping clients never silences runtime diagnostics. The diagnostic routing is asserted by a contract test (§17).

Selection is made once at app entry in [simple-recurring-budgets/App/simple_recurring_budgetsApp.swift](../simple-recurring-budgets/App/simple_recurring_budgetsApp.swift):

| Build configuration | Opt-in state | Client                                                                  |
| ------------------- | ------------ | ----------------------------------------------------------------------- |
| DEBUG               | any          | `ConsoleAnalyticsClient` (always — never pollutes production data).     |
| Release             | opted-out    | `ConsoleAnalyticsClient` (release `.product` is `#if DEBUG`-gated).     |
| Release             | opted-in     | `MixpanelAnalyticsClient` with lazy SDK init.                           |

The Mixpanel SDK is instantiated **lazily** so an opted-out launch incurs no `MixpanelInstance` creation and no network activity.

TestFlight builds use the same Release codepath: opt-in default-off, no override. Internal validation is done by an internal tester explicitly opting in.

---

## 8. Phase 1 Events

Canonical event names live as constants in `AnalyticsEvent` (in [simple-recurring-budgets/Logging/AnalyticsClient.swift](../simple-recurring-budgets/Logging/AnalyticsClient.swift)) so call sites are typo-safe. All names are `snake_case`.

| Event                       | Fired when                                                                                                                              | Answers                                  |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| `app_opened`                | First foreground per session. Supersedes `app.launched` for the product channel; the `bootstrap` event remains on OSLog.                | §2.1, §2.4                               |
| `budget_created`            | New Budget saved successfully.                                                                                                          | §2.2, §2.3                               |
| `budget_edited`             | Existing Budget edited and saved.                                                                                                       | §2.5                                     |
| `budget_deleted`            | Budget deleted from the Add/Edit Budget sheet.                                                                                          | §2.5                                     |
| `budget_reset`              | Reset Budget invoked (destructive: zeros carry-over and deletes all expenses for that budget; see [main-prd.md §6.7](main-prd.md#67-carry-over-behavior)). | §2.5                                     |
| `carry_over_reset`          | Reset Carry-Over invoked (zeros carry-over only).                                                                                       | §2.5                                     |
| `expense_logged`            | Expense saved successfully (Add mode).                                                                                                  | §2.1, §2.2, §2.4                         |
| `expense_edited`            | Existing Expense edited and saved.                                                                                                      | §2.5                                     |
| `expense_deleted`           | Expense deleted (swipe-to-delete or otherwise).                                                                                         | §2.5                                     |
| `settings_opened`           | Settings sheet presented.                                                                                                               | §2.5                                     |
| `analytics_consent_changed` | Toggle changes state. Sent **before** disabling.                                                                                        | §2.6                                     |

---

## 9. Phase 1 Properties

### 9.1 Per-event properties

| Event(s)         | Property                            | Values                                       | Notes                                                                  |
| ---------------- | ----------------------------------- | -------------------------------------------- | ---------------------------------------------------------------------- |
| `budget_*`       | `period`                            | `daily` / `weekly` / `biweekly` / `monthly`  | Categorical.                                                           |
| `budget_*`       | `carry_over_enabled`                | Bool                                         |                                                                        |
| `budget_*`       | `currency_code`                     | ISO 4217                                     |                                                                        |
| `budget_created` | `is_first_budget`                   | Bool                                         | True if this was the user's first-ever Budget.                         |
| `expense_*`      | `period`                            | (as above)                                   | Period of the parent Budget.                                           |
| `expense_*`      | `is_add_funds`                      | Bool                                         | F-6.01 add-funds path.                                                 |
| `expense_*`      | `from_screen`                       | `budget_detail` / `add_sheet`                |                                                                        |
| `expense_logged` | `time_since_budget_created_bucket`  | `<5m` / `<1h` / `<1d` / `≥1d`                | Bucketed to prevent timing fingerprints.                               |

Amounts, names, dates, and notes are **never** included.

### 9.2 Super properties (auto-attached to every event)

| Super property                | Source                                                                              |
| ----------------------------- | ----------------------------------------------------------------------------------- |
| `app_version` / `app_build`   | Bundle.                                                                             |
| `ios_version`, `device_model` | Mixpanel SDK auto-populated.                                                        |
| `locale`, `region`            | `Locale.current`.                                                                   |
| `week_start_day`              | `AppSettings.weekStartDay`.                                                         |
| `currency_display_preference` | `AppSettings.currencyDisplay`.                                                      |
| `icloud_state`                | `SyncStatus.rowState` (`available` / `paused` / `unavailable`).                     |
| `budgets_count_bucket`        | `0` / `1` / `2-3` / `4-7` / `8+`, derived from current `Budget` count.              |
| `carry_over_default_enabled`  | `AppSettings.defaultCarryOverEnabled`.                                              |
| `consent_jurisdiction`        | `required` / `optional`, from `ConsentJurisdiction`.                                |

### 9.3 People properties (set on `identify`, refreshed on relevant changes)

| People property         | Refreshed on                                                                                       |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| `first_seen_at`         | First `identify`.                                                                                  |
| `analytics_opt_in_at`   | Toggle-on transition.                                                                              |
| `budgets_count_bucket`  | Any `budget_created` / `budget_deleted`.                                                           |
| `default_currency_code` | Recomputed on `budget_created` / `budget_edited` / `budget_deleted` (most-used currency by count). |
| `last_app_open_at`      | Every `app_opened`.                                                                                |

---

## 10. Phase 1 Dashboards

Built in Mixpanel and linked from this doc once provisioned.

| Dashboard                                  | Primary report type                                                                                       | Answers |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------- | ------- |
| Reach                                      | Insights — DAU / WAU / MAU on `app_opened`.                                                               | §2.1    |
| Activation funnel                          | Funnels — `app_opened → budget_created → expense_logged`.                                                 | §2.2    |
| Time-to-first-budget / first-expense       | Insights — `time_since_budget_created_bucket` distribution + people-property histograms.                  | §2.2    |
| Composition                                | Insights — breakdowns on `period`, `currency_code`, `budgets_count_bucket`, `carry_over_default_enabled`, `locale`. | §2.3    |
| Retention                                  | Retention — anchored on `app_opened` and `expense_logged`; 1d / 7d / 30d.                                 | §2.4    |
| Settings & destructive                     | Insights — totals of `settings_opened`, `budget_reset`, `carry_over_reset`, `budget_deleted`, `expense_edited`, `expense_deleted` per user. | §2.5    |
| Consent                                    | Insights — opt-in / opt-out rates by `consent_jurisdiction`.                                              | §2.6    |

---

## 11. Phase 2 Events (planned)

Final scope is re-validated against actual Phase 1 dashboard evidence; this is the working list.

| Event                          | Fired when                                                                                       | Answers          |
| ------------------------------ | ------------------------------------------------------------------------------------------------ | ---------------- |
| `first_run_seen`               | Empty-state Budgets list displayed for the first time.                                           | §3.1 (floor)     |
| `add_expense_started`          | Add Expense sheet presented. Paired with `expense_logged` to size abandonment.                   | §3.1             |
| `add_budget_started`           | Add Budget sheet presented. Optional; only if Phase 1 evidence motivates it.                     | §3.1             |
| `screen_viewed`                | Top-level screen presented. `screen_name` is enum. Optional and sampled if event volume is high. | (flow analysis)  |

---

## 12. Phase 2 Properties (planned)

### 12.1 Per-event additions

| Event             | Property                          | Notes                                                                                              |
| ----------------- | --------------------------------- | -------------------------------------------------------------------------------------------------- |
| `app_opened`      | `cold_start_to_budgets_visible_ms` | Measured via `os_signpost` between app entry and Budgets first body render.                        |
| `expense_logged`  | `taps_from_budgets_list`           | Validates the [ux-design-brief.md](ux-design-brief.md) fast-logging promise.                       |

### 12.2 Cohort-driving people properties

| Property                  | Definition                                                                                                                       |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `dominant_period`         | Most-used Budget Period.                                                                                                         |
| `has_multiple_budgets`    | Bool.                                                                                                                            |
| `uses_carry_over`         | At least one Budget with carry-over enabled.                                                                                     |
| `uses_multiple_currencies` | More than one distinct `currency_code` across Budgets.                                                                          |
| `last_expense_logged_at`  | Timestamp; used for retention math only. **Not** surfaced in-app as a streak metric per [ux-design-brief.md](ux-design-brief.md). |

---

## 13. Phase 2 Dashboards (planned)

| Dashboard                                  | Answers |
| ------------------------------------------ | ------- |
| Activation funnel with abandonment step    | §3.1    |
| Fast-logging UX validation                 | §3.2    |
| Cohort retention                           | §3.3    |
| Rating-prompt eligibility timeline         | §3.4    |
| Feature-flag exposure scaffold             | §3.5    |

---

## 14. Experimentation Seam (Phase 2)

Mixpanel feature flags wire through a thin protocol so future experiments don't require rebuilding the surface:

```swift
protocol FeatureFlagClient {
  func bool(_ key: String, default fallback: Bool) -> Bool
  func string(_ key: String, default fallback: String) -> String
}
```

Two implementations:

- `MixpanelFeatureFlagClient` — production. Pull-only, cached for offline starts. Never blocks `app_opened`.
- `StaticFeatureFlagClient` — test / preview seam, takes a fixed dictionary.

**No live experiment ships in F-8.03 itself.** This is the seam for future features (e.g., F-4.x theme defaults, F-6.03 rating-prompt thresholds, copy A/B tests).

---

## 15. Build Hygiene

- Mixpanel project token lives in build settings (`MIXPANEL_TOKEN`), not committed source. A separate staging project + token (`MIXPANEL_TOKEN_STAGING`) is provisioned for opt-in validation.
- DEBUG builds always use `ConsoleAnalyticsClient` so dev runs do not pollute production data.
- The Mixpanel SDK is added via SPM (latest stable `mixpanel-swift`).
- Mixpanel batching is tuned for iOS Low Data Mode (`Mixpanel.flushBatchSize` conservative).

---

## 16. Boundary with F-8.01 (OSLog)

| Concern                                                                            | Routing                                                                                |
| ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| App lifecycle (launch, container creation, CloudKit fallback)                      | OSLog (`bootstrap` / `cloudkit` categories) — F-8.01.                                  |
| Crash and reliability                                                              | Apple-native (MetricKit / system Crash Reporter) — out of scope for both F-8.01 and F-8.02. |
| User-initiated UI actions whose **product behavior** we want to measure            | Mixpanel `.product` channel — F-8.02 / F-8.03.                                         |
| User-initiated UI actions whose **runtime trace** we want for debugging            | OSLog (`ui` category) — F-8.01.                                                        |

A single user action can produce both — e.g., a successful Add Expense logs `expense_logged` to Mixpanel **and** an `ui` info entry to OSLog. The two channels are independent; events never cross.

---

## 17. Test Strategy

- The existing `SpyAnalyticsClient` continues to back call-site unit tests.
- A contract test on `MixpanelAnalyticsClient` asserts that `.bootstrap` / `.cloudKit` / `.ui` events are **not** forwarded — the keystone of the routing boundary.
- A single integration smoke test verifies a real `MixpanelInstance` can be initialized and a sample event enqueued. Run manually before Mixpanel-touching releases.

---

## 18. Doc Updates Required at Implementation Time

Both F-8.02 and F-8.03 must land paired updates in [tech-design-doc.md](tech-design-doc.md) per its standing maintenance protocol:

| When           | What to update                                                                                       |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| F-8.02 ships   | §7 — name vendor as Mixpanel; document opt-in toggle and privacy contract.                           |
| F-8.02 ships   | §4.5 KV-key table — add `"analyticsOptIn"` and `"analyticsDistinctId"`.                              |
| F-8.02 ships   | §9 — refresh future-work table; add Phase 2 row pointing at F-8.03.                                  |
| F-8.03 ships   | §7 — note the feature-flag surface and reference `FeatureFlagClient`.                                |
| F-8.03 ships   | §9 — drop / refresh the Phase 2 row.                                                                 |

---

## Appendix

### A. Revision History

| Version | Date       | Author   | Changes                                                                                          |
| ------- | ---------- | -------- | ------------------------------------------------------------------------------------------------ |
| 0.1     | 2026-04-30 | Jimmy Ho | Initial draft to support T-8 / F-8.02 / F-8.03 in [product-features-planning.md](product-features-planning.md). |
