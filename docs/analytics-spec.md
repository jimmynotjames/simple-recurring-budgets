# Analytics Spec

| Field              | Value      |
| ------------------ | ---------- |
| **Version**        | 1.0        |
| **Last Updated**   | 2026-06-22 |
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

## 2. Canonical Constraints

This section is the **single source of truth** for the constraints that apply to Mixpanel-touching work — F-8.02 (Phase 1) and F-8.03 (Phase 2) in [product-features-planning.md](product-features-planning.md). The features doc points here rather than restating them. Each constraint links to the section that operationalizes it; if a constraint moves, this index moves with it.

### 2.1 Constraints applying to all Mixpanel work (F-8.02 and F-8.03)

1. **Locale-aware consent default.** In strict-opt-in jurisdictions (canonical list in [§7.2](#72-strict-opt-in-jurisdictions-and-the-first-run-consent-sheet) — EU/EEA/UK/Switzerland under GDPR/UK GDPR/PECR/revFADP, plus South Korea PIPA, China PIPL, Brazil LGPD, Turkey KVKK, Thailand PDPA, Quebec Law 25), analytics is **default off** and requires an explicit opt-in via the first-run consent sheet and the Settings toggle. In all other locales, analytics is **default on (auto opt-in)** and the user can opt out at any time via the Settings toggle. Mandated by [main-prd.md](main-prd.md) §6.3 and [tech-design-doc.md](tech-design-doc.md) §7. Operationalized in [§5](#5-privacy-contract--pii-and-field-level-rules) and [§7](#7-consent).
2. **First-run consent sheet only in strict-opt-in jurisdictions.** Outside those jurisdictions no sheet is shown; the Settings toggle (default on) is sufficient surfacing. Operationalized in [§7.2](#72-strict-opt-in-jurisdictions-and-the-first-run-consent-sheet).
3. **No PII ever transmitted.** The field-level allow/deny list and the two accepted-risk exceptions (`budget_name`, `budget_allocation_amount`) are authoritative in [§5](#5-privacy-contract--pii-and-field-level-rules). Any new event or property must conform to that contract; adding a field that doesn't fit requires updating §5 in the same change.
4. **No `ExpenseItem` field is ever transmitted by value.** Hard ban — see [§5.3](#53-explicitly-denied-deny-list).
5. **Diagnostic / OSLog telemetry is never forwarded to Mixpanel.** Bootstrap, `cloudKit`, and `ui` log categories bypass `AnalyticsClient` entirely. Operationalized in [§8](#8-architecture-two-independent-paths) and [§17](#17-boundary-with-f-801-oslog); F-8.01 in the features doc carries the OSLog side.
6. **All consent and Settings copy is keyed in `Localizable.xcstrings`** per F-3.03. Operationalized in [§7.1](#71-always-on-settings-toggle).
7. **No engagement-pressure events.** Streaks, "missed days," and push nudges are out of scope per [main-prd.md](main-prd.md) §3 and [ux-design-brief.md](ux-design-brief.md). The instrumentation surface is observational; it never feeds engagement-pressure UX.
8. **Lazy SDK init.** The Mixpanel SDK is instantiated lazily so an opted-out launch incurs no `MixpanelInstance` creation and no network activity ([§8](#8-architecture-two-independent-paths)).

### 2.2 Constraints additionally applying to Phase 2 (F-8.03)

1. **Same opt-in and no-PII guarantees as Phase 1.** Phase 2 may not introduce any field that becomes identifying when combined with Phase 1 properties.
2. **Mixpanel feature flags are pull-only and cached for offline starts.** No app launch is blocked on a flag fetch. Operationalized in [§15](#15-experimentation-seam-phase-2).

---

## 3. Product Questions — Phase 1

Phase 1 is the smallest viable instrumentation that lets us answer the questions below. Each subsection links to the events / properties that produce the answer (mapped in §§9–11) and to the dashboard that delivers it (§12).

### 3.1 Reach and engagement

- Are people opening the app at all? DAU, WAU, MAU on `app_opened`.
- Sessions per active user.

### 3.2 Activation

- Activation funnel: `app_opened → budget_created → expense_logged`. Where do new users drop off?
- Time from first `app_opened` to first `budget_created`.
- Time from first `budget_created` to first `expense_logged` (bucketed; see §10.1).

### 3.3 Composition of usage

- Average and distribution of Budgets per user (via `budgets_count_bucket` super property; see §10.2).
- Breakdown of Budget Period (`daily` / `weekly` / `biweekly` / `monthly` / `specific_dates`) two ways:
  - Share of users whose dominant period is X.
  - Share of all Budgets that are X.
- Currency-code breakdown across users and across Budgets.
- Locale / region breakdown; iOS / device-class breakdown.
- Share of users with carry-over enabled (default-on retained) versus explicitly turned off.
- Share of all Budgets that have carry-over enabled versus turned off (per-Budget view, complementing the per-user view above).

### 3.4 Retention

Retention is configured per Mixpanel Retention report by choosing a "born" event and a "returning" event (a specific event, or "Any Event") — it is not hardwired to one event. Phase 1 builds two views:

- 1/7/30-day retention with returning-event = `expense_logged` — the core value loop. A return that doesn't log an expense does not count; this is the retention signal to act on.
- 1/7/30-day retention with returning-event = `app_opened` — check-in engagement. The user reopened the app, which is meaningful on its own: the Budgets list surfaces remaining amounts above the fold, so a bare foreground is often glanceable budget-checking, even with no further action.

### 3.5 Settings and destructive actions

- Settings open rate (`settings_opened` per active user).
- Which settings users actually change, when those changes are observable through dedicated events or super-property transitions (e.g. `analytics_consent_changed`, `carry_over_default_enabled` flipping). Phase 1 does not instrument every Settings field; the spec adds events only where the change has product meaning.
- Frequency of destructive actions — `budget_reset`, `carry_over_reset`, and `budget_deleted` — to gauge how often users course-correct, and which destructive flow they reach for.
- Frequency of `expense_edited` and `expense_deleted` to see whether logging is "right first time" or routinely corrected after the fact.

### 3.6 Privacy and consent

- Opt-in rate in strict-opt-in jurisdictions (regions that legally require an explicit consent sheet; `consent_jurisdiction = required`).
- Opt-out rate in auto-opt-in jurisdictions (`consent_jurisdiction = auto_optin`) — transitions from default `true` to `false` on `analytics_consent_changed`.
- Opt-out rate over time across all jurisdictions.

---

## 4. Product Questions — Phase 2

Phase 2 deepens Phase 1's picture and adds the experimentation seam. Phase 2 questions assume Phase 1 dashboards already exist; some Phase 2 properties may be dropped or replaced once Phase 1 evidence shows whether the underlying signal is there.

### 4.1 Funnel abandonment

- Where in the Add Expense flow do users drop off? Funnel step `add_expense_started → expense_logged`.
- Where in the Add Budget flow do users drop off? Optional `add_budget_started → budget_created`, only if Phase 1 evidence motivates it.

### 4.2 UX validation

- Does the [ux-design-brief.md](ux-design-brief.md) "Signature Element: Fast expense logging" promise hold up? Median (and p50 / p90) `taps_from_budgets_list` to a successful `expense_logged`.
- Cold-start latency to a usable Budgets list (`cold_start_to_budgets_visible_ms` on `app_opened`).

### 4.3 Cohort retention

- Retention by `dominant_period` cohort.
- Retention by `uses_carry_over`.
- Retention by `has_multiple_budgets`.
- Retention by `uses_multiple_currencies`.

### 4.4 Rating prompt (F-6.03)

- When do users meet the "meaningful usage" threshold defined by F-6.03? (`rating_prompt_eligible`.)
- Of the users who become eligible, for how many do we actually call `requestReview` (`rating_prompt_requested`), and how long after eligibility?
- **Outcome (shown / dismissed / rated) is intentionally not a question we can answer.** F-6.03 uses Apple's native `requestReview` (`@Environment(\.requestReview)`), which neither reports whether StoreKit decided to present the dialog nor the user's choice. There is no callback. We deliberately do **not** add a custom pre-prompt to manufacture that signal (review-gating hurts ratings and conflicts with the no-engagement-pressure constraint in §2.1.7). The deepest observable point is `rating_prompt_requested`.

### 4.5 Experimentation

- For any active Mixpanel feature flag, conversion / retention by variant. F-8.03 ships the seam, not a live experiment.

---

## 5. Privacy Contract — PII and Field-Level Rules

Mixpanel consent is **locale-aware** (see §7 for the canonical jurisdiction list and rules). In jurisdictions known to legally require explicit prior consent for product analytics, the default is **off** and an explicit opt-in via a first-run consent sheet and/or Settings toggle is required before any event is sent. In all other jurisdictions the default is **on (auto opt-in)**, and the user may opt out at any time via the Settings toggle. Mandated by [tech-design-doc.md](tech-design-doc.md) §7 and [main-prd.md](main-prd.md) §6.3.

The field-level rules below are **global**: they apply identically regardless of jurisdiction or opt-in default. They are the authoritative allow/deny list. The features doc (F-8.02 in [product-features-planning.md](product-features-planning.md)) defers to this section.

### 5.1 General principle

The default is **deny**. A field may only be transmitted to Mixpanel if it appears in the explicit allow-list below (§5.2 and §5.3) or in §§10 and 13 (which themselves must conform to this section). If a new event or property is added that doesn't fit, this section must be updated in the same change.

### 5.2 Explicitly allowed (allow-list)

| Field / category                                       | Allowed                                                                                                                              | Rationale                                                                                                                                                          |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Categorical / bucketed properties on the Budget entity | `period`, `currency_code`, `carry_over_enabled`, `is_first_budget`, `reset_cadence` (when un-paused) — see §10                        | Low-cardinality, no PII risk, directly answers product questions in §3.                                                                                            |
| App and device super properties                        | `app_version`, `app_build`, `ios_version`, `device_model`, `locale`, `region`, `consent_jurisdiction`, etc. — see §10.2               | SDK-auto-populated or trivially derivable; no PII content; necessary baselines for any analytic breakdown.                                                         |
| Bucketed counts and durations                          | `budgets_count_bucket`, `time_since_budget_created_bucket`                                                                           | Bucketed before send; not user-typed.                                                                                                                              |
| **Budget allocation amount**                           | The numeric allocation per Budget (e.g. `budget_allocation_amount`, paired with `currency_code`)                                     | **Explicitly allow-listed.** Allocation is a configured cap, not a transaction; it carries strong product signal (median allocation, allocation-vs-period mix) that no bucket can replicate well. Accepted as low-PII-risk because it's a self-set ceiling, not an itemized purchase. |
| **Budget name** (raw string)                           | The user-typed name of a Budget (e.g. `budget_name`)                                                                                 | **Accepted-risk exception** — see §5.4. Allow-listed despite being free-text.                                                                                      |
| **Persistence-save failure diagnostics**               | `operation` (static `PersistenceOperation` enum value), `error_domain` (`NSError.domain`), `error_code` (`NSError.code`) on the `persistence_save_failed` event only | **Narrowly-scoped diagnostic event** — see §8 boundary note and §17. No user-derived content (the operation is a compile-time enum; domain/code come from Apple framework `NSError`). Strictly bounded to these three properties; expansion requires a spec update. |

### 5.3 Explicitly denied (deny-list)

| Field / category                              | Denied                                                                                                                                                              | Rationale                                                                                                                |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **Any field on `ExpenseItem`**                | Expense name, amount, date, notes, attachments, or any other field on an Expense entity. **No event may carry an Expense field by value.**                         | Expenses are itemized purchases — the highest-PII-risk surface in the app (location-via-merchant, health, legal, social context). Hard ban. |
| Free-text user input outside the Budget name  | Expense names, expense notes, settings free-text, search queries, anything the user types into a text field other than `Budget.name`                                | Same incidental-PII risk as Budget name without a corresponding accepted product justification.                          |
| Currency amounts other than `Budget` allocation | Expense amounts, carry-over balances, remaining-for-period values, totals of any kind                                                                              | Money-shaped values per Expense or per period are itemized financial data; high re-identification and sensitivity risk.  |
| Identity                                       | Apple ID, iCloud user record id, email, phone, full name, postal address                                                                                            | Strict PII.                                                                                                              |
| Precise timestamps from user input             | Raw `Date` values for expense dates or any user-entered date field. (System-generated `app_opened` timestamps are fine; bucketed durations are fine.)               | Free-form dates can re-identify (birthdays, anniversaries) and have no analytic value as raw values.                     |
| Precise location                               | Coordinates, geofences, IP-derived city beyond what Mixpanel auto-derives from request IP. We do not collect location ourselves.                                    | The app has no location feature; nothing to collect. Listed for completeness.                                            |

### 5.4 Accepted-risk exceptions

Two fields cross the strict "no free-text / no money" line. They are explicitly accepted as product trade-offs and called out here so the trade-off is auditable.

#### Budget name (free-text, allow-listed)

A Budget name (`Budget.name`) is **not PII by definition** — it's a label the user typed for a Budget. It can incidentally contain PII or sensitive context (a name, an address fragment, a health condition). We accept that risk for Phase 1 because:

- Budgets are coarse, persistent, low-cardinality entities (a typical user has 1–8 of them) — qualitatively unlike Expense names which are per-transaction and dense.
- The product question "what do users name their budgets" (templates, emoji, language patterns) is genuinely useful and has no good bucketed proxy.
- No `Budget.name` value ever appears alongside an Expense field, an amount other than the Budget's own allocation, or any other deny-listed field.

If Phase 1 evidence shows users routinely put obvious PII in budget names (real names, addresses), this exception will be revisited in F-8.03 and either revoked or replaced with a derived signal (length bucket, template-match enum) per the option deferred in this spec's history.

#### Budget allocation amount (money-shaped, allow-listed)

`budget_allocation_amount` is **explicitly allow-listed** even though all other money-shaped values are denied. It's a self-set ceiling, not an itemized purchase, and aggregating allocation distributions (median allocation by `period`, by `currency_code`, by `region`) is a core Phase 1 product question that no bucket replicates faithfully without distortion. It is always paired with `currency_code` so dashboards don't mix currencies.

All other currency amounts (Expense amounts, carry-over balances, remaining-for-period, totals) remain on the deny-list.

### 5.5 Enforcement

- `MixpanelAnalyticsClient` carries the §5.2 / §5.3 / §5.4 contract verbatim in its doc comment and is reviewed at every PR that touches it.
- The `AnalyticsClient` API surface (event names, property keys) is constrained to the constants listed in §§9, 10, 12, 13. Adding a new property key requires updating this section first.
- Any property whose value is derived from `ExpenseItem` is rejected at the call site by code review; no helper exists for serializing an `ExpenseItem` to analytics properties.

---

## 6. Identity

A UUIDv4 generated at first launch is persisted in `NSUbiquitousKeyValueStore` under key `"analyticsDistinctId"` and used as Mixpanel's `distinct_id`. Because `NSUbiquitousKeyValueStore` syncs across the user's iCloud-paired devices ([tech-design-doc.md §4.5](tech-design-doc.md)), a single human is unified across their devices without us collecting any Apple-issued identifier.

`identify(_:)` is called once analytics is enabled. `reset()` is called when the user opts out.

**Limitations** — accepted as Phase 1 trade-offs:

- The distinct id is not rotated automatically. If the user signs out of iCloud or wipes the app, a new UUID is generated.
- `NSUbiquitousKeyValueStore` is eventually consistent. If the same Apple ID opens the app on a second device before the `"analyticsDistinctId"` value has synced, that device generates and writes its own UUID; later events from that device are then attributable to a separate user in Mixpanel until the first device's key wins. Handling this cleanly (e.g., calling `identify(_:)` to alias on later sync) is deferred to Phase 2 if Phase 1 evidence shows the split is meaningful.

---

## 7. Consent

### 7.1 Always-on Settings toggle

`AppSettings.analyticsOptIn: Bool`, persisted in `NSUbiquitousKeyValueStore` under key `"analyticsOptIn"`. The **default value is locale-aware**, resolved on first launch by `ConsentJurisdiction` (see §7.2):

- In **strict-opt-in jurisdictions**: default `false`. The toggle must be flipped on (typically via the first-run consent sheet) before any event fires.
- In **auto-opt-in jurisdictions**: default `true`. Events fire on first launch; the user can opt out at any time via the toggle.

The Settings screen (F-2.05) gains a **Diagnostics & Analytics** section with:

- A single toggle bound to `AppSettings.analyticsOptIn`.
- A short disclosure of what is and is not sent (mirroring §5), and a one-line note that the initial state was set automatically based on the device locale and can be changed at any time.
- All copy keyed in `Localizable.xcstrings` per F-3.03.

### 7.2 Strict-opt-in jurisdictions and the first-run consent sheet

In strict-opt-in jurisdictions a one-time consent sheet appears immediately after the user creates their first Budget. The user must explicitly accept before `analyticsOptIn` flips to `true`. Declining keeps the default `false` and dismisses the sheet permanently (the Settings toggle remains the recovery path).

**No retroactive event replay.** Events that the app would otherwise have fired before the toggle flipped to `true` (most notably the launch's `app_opened` and any pre-consent `budget_created`) are **not** replayed once consent is granted. Phase 1 accepts this as a measurement trade-off: dashboards in `consent_jurisdiction = required` cohorts are anchored on `analytics_consent_changed` (opt-in transition) rather than on `app_opened`, and `is_first_budget = true` on `budget_created` remains the canonical "first Budget" signal regardless of jurisdiction. The implementing change SHOULD note this in any §3.4 retention dashboard caption.

**Canonical strict-opt-in jurisdiction list** (resolved from `Locale.current.region.identifier` at app launch by a `ConsentJurisdiction` helper, so additions or removals are a one-line edit):

| Jurisdiction                    | Region codes                                                                                                                                               | Basis                                |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| European Union                  | AT, BE, BG, HR, CY, CZ, DK, EE, FI, FR, DE, GR, HU, IE, IT, LV, LT, LU, MT, NL, PL, PT, RO, SK, SI, ES, SE                                                  | GDPR + ePrivacy Directive            |
| EEA (non-EU)                    | IS, LI, NO                                                                                                                                                  | GDPR via EEA agreement               |
| United Kingdom                  | GB (and UK crown dependencies if surfaced by `Locale`: GG, JE, IM)                                                                                          | UK GDPR + PECR                       |
| Switzerland                     | CH                                                                                                                                                          | revFADP                              |
| South Korea                     | KR                                                                                                                                                          | PIPA — explicit prior consent for personal info collection |
| China (mainland)                | CN                                                                                                                                                          | PIPL — separate consent for analytics-style processing |
| Brazil                          | BR                                                                                                                                                          | LGPD — consent treated as the safe default for product analytics |
| Turkey                          | TR                                                                                                                                                          | KVKK — explicit consent              |
| Thailand                        | TH                                                                                                                                                          | PDPA — explicit consent              |
| Quebec (Canada)                 | CA when the system language/region indicates Quebec (e.g. `fr_CA`); pragmatically apply CA-wide if Quebec sub-region is not reliably surfaced               | Law 25 — express consent             |

> The list is intentionally conservative and based on widely-cited privacy regimes that require **prior, affirmative consent** for non-essential product analytics. It can be tightened or expanded as legal guidance evolves; the spec, not the code, is the source of truth and any change must update this table and `ConsentJurisdiction` together.

Locales not in the table above are **auto-opt-in** jurisdictions (e.g. United States, Canada outside Quebec, Japan, Australia, New Zealand, India, most of LATAM and Africa not listed above, etc.). Auto-opt-in does **not** weaken any other guarantee in §5 — no PII, no free text, no money, categorical/bucketed properties only.

`consent_jurisdiction` super property (§10.2) is extended to `required` / `auto_optin` to make the split queryable in dashboards.

### 7.3 Toggle-off behavior

When the user disables analytics:

1. `analytics_consent_changed` fires **before** disabling so opt-outs are observable.
2. `MixpanelAnalyticsClient.reset()` clears the local distinct id state.
3. All subsequent `.product` events are dropped at the client.

---

## 8. Architecture: Two Independent Paths

Diagnostic and product analytics are deliberately separate:

- **Diagnostic logging** — operational events (container bootstrap, CloudKit sync, UI traces) are written directly via `OSLog.Logger` constants defined in [simple-recurring-budgets/Logging/AppLoggers.swift](../simple-recurring-budgets/Logging/AppLoggers.swift). They never pass through `AnalyticsClient`.
- **Product analytics** — the `AnalyticsClient` protocol in [simple-recurring-budgets/Logging/AnalyticsClient.swift](../simple-recurring-budgets/Logging/AnalyticsClient.swift) is product-only. It has no concept of diagnostic channels or log levels. Phase 1 implements `MixpanelAnalyticsClient: AnalyticsClient` next to [simple-recurring-budgets/Logging/ConsoleAnalyticsClient.swift](../simple-recurring-budgets/Logging/ConsoleAnalyticsClient.swift).

Selection is made once at app entry in [simple-recurring-budgets/App/simple_recurring_budgetsApp.swift](../simple-recurring-budgets/App/simple_recurring_budgetsApp.swift):

| Build configuration | Opt-in state | Client                                                                                                                                            |
| ------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| DEBUG               | any          | `MixpanelAnalyticsClient` pointed at the **dev** Mixpanel project (separate token), gated by `isOptedIn`. Drop-through default for previews / tests is `ConsoleAnalyticsClient`. |
| Release             | opted-out    | `MixpanelAnalyticsClient` constructed but `isOptedIn` returns `false`; all `.product` events are dropped at the client and no SDK init occurs.    |
| Release             | opted-in     | `MixpanelAnalyticsClient` pointed at the **prod** Mixpanel project, with lazy SDK init.                                                           |

DEBUG and Release use the same client class; physical separation of dev-vs-prod data is enforced by the **Mixpanel project token**, not by swapping client types. Two separate Mixpanel projects (dev and prod) are provisioned. `ConsoleAnalyticsClient` remains in the codebase as the SwiftUI `@Entry` default in `[Logging/AnalyticsEnvironment.swift](../simple-recurring-budgets/Logging/AnalyticsEnvironment.swift)` so SwiftUI Previews and unit tests that don't go through the app entry pick up a no-op-in-Release / console-in-DEBUG fallback.

The Mixpanel SDK is instantiated **lazily** so an opted-out launch incurs no `MixpanelInstance` creation and no network activity. In auto-opt-in jurisdictions the default opted-in state means the SDK is initialized on first launch unless the user has explicitly opted out. In DEBUG this means launching the app on a developer machine — once opt-in is observed `true` — sends events to the dev Mixpanel project, which is the desired end-to-end-validation behavior.

TestFlight builds use the same Release codepath and the **prod** token. The default opt-in state follows the same locale-aware rule as production; there is no override. Internal validation in a strict-opt-in locale is done by an internal tester explicitly opting in.

### 8.1 Launch and consent-transition ordering (canonical sequence)

The contract below is the source of truth for `MixpanelAnalyticsClient` and the app-entry wiring in `simple_recurring_budgetsApp`. All steps are on the main actor unless explicitly offloaded by the SDK.

**Release build, auto-opt-in jurisdiction, first launch, no prior opt-out:**

1. App `init` resolves `ConsentJurisdiction` from `Locale.current.region.identifier` (§7.2).
2. `AppSettings` reads `analyticsOptIn` from `NSUbiquitousKeyValueStore`; absent → default per jurisdiction (here: `true`).
3. App entry constructs `MixpanelAnalyticsClient` but does **not** call `Mixpanel.initialize` yet. The client holds the token and an opt-in closure.
4. First time `analyticsOptIn` is observed `true` and a `track` / `identify` is requested, the client lazy-initializes the SDK (`Mixpanel.initialize(token:trackAutomaticEvents: false)`).
5. `identify(distinctId)` is called with the value resolved from `AppSettings.analyticsDistinctId` (§6).
6. `track(app_opened)` fires.

**Release build, strict-opt-in jurisdiction, first launch, default `false`:**

1–2. Same as above; `analyticsOptIn` resolves to `false`.

3. App entry constructs `ConsoleAnalyticsClient` (or a no-op variant) — **not** `MixpanelAnalyticsClient`. No SDK token is read; no `MixpanelInstance` is created; no `app_opened` is sent.
4. After the user creates their first Budget, the consent sheet is presented per §7.2.
5. **On accept**: set `analyticsOptIn = true` → swap the environment's `AnalyticsClient` to a freshly-constructed `MixpanelAnalyticsClient` (or flip an internal flag if the same instance is retained — implementation choice, but the SDK MUST not initialize until this transition) → call `identify(distinctId)` → fire `analytics_consent_changed(new_value: true)`. Do **not** retroactively fire `app_opened` or `budget_created` (see §7.2 "No retroactive event replay").
6. **On decline**: `analyticsOptIn` stays `false`; nothing is sent; the sheet does not re-present in this app install.

**Toggle-off transition (any jurisdiction, opted-in → opted-out):**

1. Fire `analytics_consent_changed(new_value: false, old_value: true)` **first**, while the client is still opted in, so the opt-out is observable in dashboards.
2. Call `MixpanelAnalyticsClient.reset()` to clear the SDK's local distinct-id state.
3. Set `analyticsOptIn = false`. Subsequent `track(_:)` calls are dropped at the client.

**DEBUG builds:** Same client-selection and ordering rules as Release (`MixpanelAnalyticsClient`, lazy SDK init, identify, `app_opened`, consent gating), but the SDK is initialized against the **dev Mixpanel project token** (`MixpanelTokenSource.activeToken` → `AppConfig.mixpanelDevToken` in `#if DEBUG`, injected from `config/Secrets.local.xcconfig` per §16) so dev-machine events land in a separate Mixpanel project from production. When tokens are not configured (placeholder sentinels), `ConsoleAnalyticsClient` is used instead and no SDK is initialized. The first-run consent sheet still appears in strict-opt-in jurisdictions; suppressing it for dev convenience is not done because doing so would diverge the DEBUG path from the Release path under test.

---

## 9. Phase 1 Events

Canonical event names live as constants in `AnalyticsEvent` (in [simple-recurring-budgets/Logging/AnalyticsClient.swift](../simple-recurring-budgets/Logging/AnalyticsClient.swift)) so call sites are typo-safe. All names are `snake_case`.

| Event                       | Fired when                                                                                                                              | Answers                                  |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| `app_opened`                | Cold launch, and each return to the foreground from background (a true `.background → .active` transition; transient `.inactive` interruptions like the notification shade or Face ID do not fire). Not client-side deduplicated by a session window — a bare foreground counts as an open, since the user is often just checking budget amounts above the fold (§3.4). Mixpanel owns sessionization server-side. Supersedes `app.launched` for the product channel; the `bootstrap` event remains on OSLog. | §3.1, §3.4                               |
| `budget_created`            | New Budget saved successfully.                                                                                                          | §3.2, §3.3                               |
| `budget_edited`             | Existing Budget edited and saved.                                                                                                       | §3.5                                     |
| `budget_deleted`            | Budget deleted from the Add/Edit Budget sheet.                                                                                          | §3.5                                     |
| `budget_reset`              | Reset Budget invoked (destructive: zeros carry-over and deletes all expenses for that budget; see [main-prd.md §6.7](main-prd.md#67-carry-over-behavior)). | §3.5                                     |
| `budget_paused`             | Budget paused via Pause Budget toolbar item or primary action slot (F-7.06). Properties: `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount`. | F-7.06, F-8.02 |
| `budget_resumed`            | Budget resumed via Resume Budget toolbar item or primary action slot (F-7.06). Properties: same as `budget_paused`. | F-7.06, F-8.02 |
| `carry_over_reset`          | Reset Carry-Over invoked (zeros carry-over only).                                                                                       | §3.5                                     |
| `expense_logged`            | Expense saved successfully (Add mode).                                                                                                  | §3.1, §3.2, §3.4                         |
| `expense_edited`            | Existing Expense edited and saved.                                                                                                      | §3.5                                     |
| `expense_deleted`           | Expense deleted (swipe-to-delete or otherwise).                                                                                         | §3.5                                     |
| `expense_recent_reused`     | User tapped a Recents suggestion tile in Add Expense or Edit Expense (F-7.04). Fires on tap regardless of whether the user later Saves; pairs with the subsequent `expense_logged` / `expense_edited` if Save happens. Fires whether the tap filled the amount or preserved a user-typed one (provenance rule). Exactly one event per physical interaction: the double-tap full replace does **not** emit a second event (its first tap already did). Answers the "do users actually reuse recents?" question. See `from_screen` to distinguish Add-vs-Edit reuse. | F-7.04, §3.1                             |
| `settings_opened`           | Settings sheet presented.                                                                                                               | §3.5                                     |
| `setting_changed`           | An enumerated **product-meaningful** setting transitions to a new value. See §10.1 for the canonical `setting_name` enum.               | §3.5                                     |
| `analytics_consent_changed` | Analytics opt-in toggle changes state. Sent **before** disabling so opt-outs are observable. (Kept distinct from `setting_changed` because consent transitions gate every other event.) | §3.6                                     |
| `persistence_save_failed`   | SwiftData `context.save()` threw, surfaced by the shared persistence-save helper. **Narrowly-scoped diagnostic event** — see §8 boundary note and §17. Payload restricted to `operation`, `error_domain`, `error_code` (§5.2 / §10.1). Consent-gated, hence best-effort. | Issue #9 — dashboard visibility for save failures |

---

## 10. Phase 1 Properties

### 10.1 Per-event properties

| Event(s)         | Property                            | Values                                       | Notes                                                                  |
| ---------------- | ----------------------------------- | -------------------------------------------- | ---------------------------------------------------------------------- |
| `budget_*`       | `period`                            | `daily` / `weekly` / `biweekly` / `monthly` / `specific_dates`  | Categorical. `specific_dates` is the fixed-window Budget type (`BudgetPeriod.specificDates`); it always pairs with `carry_over_enabled = false`. |
| `budget_*`       | `carry_over_enabled`                | Bool                                         |                                                                        |
| `budget_*`       | `currency_code`                     | ISO 4217                                     |                                                                        |
| `budget_created` | `is_first_budget`                   | Bool                                         | True if this was the user's first-ever Budget.                         |
| `budget_created` | `time_since_first_app_open_bucket`  | `<5m` / `<1h` / `<1d` / `<7d` / `≥7d`        | Only attached when `is_first_budget = true`. Answers §3.2 "time from first launch to first Budget" without relying on Mixpanel funnel time-to-convert. |
| `budget_*`       | `budget_name`                       | String, raw                                  | **Accepted-risk allow-listed** per §5.4. Only sent on `budget_`* events; never on `expense_*` or any other event. |
| `budget_*`       | `budget_allocation_amount`          | Number, in `currency_code`'s minor units (or decimal as defined by `currency_code`) | **Allow-listed** per §5.4. Always paired with `currency_code`. Per-Budget allocation only — no other money-shaped value is permitted. |
| `budget_edited`  | `allocation_changed`                | Bool                                         | `true` iff the drafted allocation differed from the stored `Budget.currentAllocation` and was written in this Save. Lets analytics distinguish a name edit from an allocation edit. Emitted only on `budget_edited`; never on `budget_created`. |
| `budget_edited`  | `start_date_changed`                | Bool                                         | `true` iff the normalised drafted `startDate` differed from `Budget.startDate` and was written in this Save. Covers F-7.05 (per-budget Start Date) edits across both recurring and Specific Dates period types. Emitted only on `budget_edited`. |
| `budget_edited`  | `end_date_changed`                  | Bool                                         | `true` iff the normalised drafted `endDate` differed from `Budget.endDate` (including the user-cleared-an-optional-end-date path for recurring period types). Covers F-7.07 (per-budget End Date) edits. Emitted only on `budget_edited`. |
| `budget_edited`  | `orphaned_expense_count`            | Int (conditional — present iff > 0)          | Number of items in `Budget.expenseItems` whose `date` is before the post-save `Budget.startDate`. Lets analytics measure how often a user proceeds through the orphan-expense Save-time confirmation alert on Edit Budget (shipped by `add-orphan-expense-warning`). Absence of the key denotes "save did not produce an orphaned state"; the key is omitted (not emitted as `0`). Emitted only on `budget_edited`. |
| `expense_*`      | `period`                            | (as above)                                   | Period of the parent Budget.                                           |
| `expense_*`      | `is_add_funds`                      | Bool                                         | F-6.01 add-funds path.                                                 |
| `expense_*`      | `from_screen`                       | `budget_detail` / `add_sheet`                |                                                                        |
| `expense_logged` | `time_since_budget_created_bucket`  | `<5m` / `<1h` / `<1d` / `≥1d`                | Bucketed to prevent timing fingerprints.                               |
| `expense_recent_reused` | `period`                     | (as above)                                   | Period of the parent Budget.                                           |
| `expense_recent_reused` | `recents_visible_count`      | `0` / `1` / `2-3` / `4-7` / `8+`             | Bucketed count of tiles in the Recents row at tap time. Answers "do users tap into a dense or sparse row?" Bucket boundaries are coarse on purpose to avoid pseudo-identifying signatures; the top bucket is open-ended because the F-7.04 display cap is 30 tiles. |
| `expense_recent_reused` | `recents_tap_position`       | `0` / `1` / `2-4` / `5+`                     | Bucketed 0-indexed position of the tapped tile. Positions `0` and `1` are kept separate because the canonical product question is "do users overwhelmingly tap the first one?" — collapsing them would erase that signal. |
| `expense_recent_reused` | `name_query_length`          | `0` / `1-2` / `3+`                           | Bucketed length of the typed Description query at the moment of the tap, captured before `name` is overwritten by the suggestion. Distinguishes "open-and-tap" (`0`) from "type-then-tap" (everything else). Never surfaces the raw character count or the typed string. |
| `expense_recent_reused` | `from_screen`                | `add_sheet` / `budget_detail`                 | Surface where the tap occurred: `add_sheet` (Add Expense sheet) or `budget_detail` (Edit Expense, pushed from Budget Detail). Allows add-vs-edit reuse to be distinguished in analysis. |
| `setting_changed` | `setting_name`                     | `default_carry_over_enabled` / `week_start_day` / `currency_display_preference` | Enumerated. Adding a new value requires updating §5 (no free-text). `analytics_opt_in` is **not** included here — it has its own dedicated event (`analytics_consent_changed`). |
| `setting_changed` | `new_value`                        | Categorical, scoped to `setting_name`        | E.g. for `default_carry_over_enabled`: `true` / `false`. For `week_start_day`: `monday` / `sunday` / etc. Never raw user input. |
| `setting_changed` | `old_value`                        | Categorical, scoped to `setting_name`        | Same domain as `new_value`. Optional on first-set transitions.         |
| `persistence_save_failed` | `operation`                | Enumerated `PersistenceOperation` raw value (snake_case): `budget_create` / `budget_edit` / `budget_delete` / `expense_create` / `expense_edit` / `expense_delete` / `reorder` / `lifecycle_pause` / `lifecycle_resume` / `lifecycle_allocation_edit` / `lifecycle_reset_carry_over` / `lifecycle_reset_budget` / `lifecycle_rollover` / `app_launch_dedup` | Identifies the failing call site. Static enum value — not user-derived. |
| `persistence_save_failed` | `error_domain`             | String, the underlying `NSError.domain` (e.g. `NSCocoaErrorDomain`) | Apple framework diagnostic — not user-derived. |
| `persistence_save_failed` | `error_code`               | Int, the underlying `NSError.code`           | Apple framework diagnostic — not user-derived. **No** other properties may be added to this event; the allow-list is strict (§8 boundary note). |

No `ExpenseItem` field is ever transmitted by value — `expense_*` events carry only categorical context (`period`, `is_add_funds`, `from_screen`) and bucketed durations. Free-text other than `budget_name`, currency amounts other than `budget_allocation_amount`, and raw user-entered dates remain banned. See §5 for the canonical allow/deny list.

### 10.2 Super properties (auto-attached to every event)

| Super property                | Source                                                                              |
| ----------------------------- | ----------------------------------------------------------------------------------- |
| `app_version` / `app_build`   | Bundle.                                                                             |
| `ios_version`, `device_model` | Mixpanel SDK auto-populated.                                                        |
| `device_class`                | `phone` / `pad` / `mac`, derived from `UIDevice.current.userInterfaceIdiom` (or platform on macOS Catalyst). Coarser than `device_model`; lets §3.3 ask "iPhone vs iPad mix" without grouping `device_model` strings. |
| `locale`, `region`            | `Locale.current`.                                                                   |
| `week_start_day`              | `AppSettings.weekStartDay`.                                                         |
| `currency_display_preference` | `AppSettings.currencyDisplay`.                                                      |
| `icloud_state`                | `SyncStatus.rowState` (`checking` / `available` / `paused` / `unavailable`).        |
| `budgets_count_bucket`        | `0` / `1` / `2-3` / `4-7` / `8+`, derived from current `Budget` count.              |
| `carry_over_default_enabled`  | `AppSettings.defaultCarryOverEnabled`.                                              |
| `consent_jurisdiction`        | `required` / `auto_optin`, from `ConsentJurisdiction` (see §7.2).                   |

### 10.3 People properties (set on `identify`, refreshed on relevant changes)

| People property                              | Refreshed on                                                                                                                                  |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `first_seen_at`                              | First `identify`.                                                                                                                             |
| `analytics_opt_in_at`                        | Toggle-on transition.                                                                                                                         |
| `budgets_count_bucket`                       | Any `budget_created` / `budget_deleted`.                                                                                                      |
| `default_currency_code`                      | Recomputed on `budget_created` / `budget_edited` / `budget_deleted` (most-used currency by count).                                            |
| `last_app_open_at`                           | Every `app_opened`.                                                                                                                           |
| `dominant_period`                            | Most-used Budget Period across the user's Budgets. Recomputed on `budget_created` / `budget_edited` / `budget_deleted`. Answers §3.3 "share of users whose dominant period is X." |
| `uses_carry_over`                            | Bool. True if the user has at least one Budget with `carry_over_enabled = true`. Recomputed on `budget_*` events. Answers §3.3 carry-over share.       |
| `has_disabled_carry_over`                    | Bool. True if the user has at least one Budget with `carry_over_enabled = false`. Recomputed on `budget_*` events. Pairs with `uses_carry_over` so the four user-cohorts (`only_on` / `only_off` / `mixed` / `none_yet`) are recoverable. |
| `budgets_with_carry_over_on_count_bucket`    | `0` / `1` / `2-3` / `4-7` / `8+`. Recomputed on `budget_*` events. Answers §3.3 "share of all Budgets with carry-over on/off" via people-property aggregation, without per-Budget tracking. |

---

## 11. Phase 1 Dashboards

Dashboards are built in Mixpanel. **Mixpanel is the source of truth** — the table below is a planning record and may drift from what's actually in Mixpanel, since boards are edited there directly by humans. On any mismatch, Mixpanel wins; update this doc to match.

### 11.1 Mixpanel projects and tooling

Two Mixpanel projects are provisioned (see §8 for the token wiring that routes events to each):

| Project              | Receives events from                                              |
| -------------------- | ---------------------------------------------------------------- |
| **Wren App - Prod**  | Production builds — App Store and TestFlight.                     |
| **Wren App - Dev**   | Debug builds — e.g. the iOS Simulator and developer devices.     |

The **Dev** project does not have to mirror Prod; use it to try out experimental dashboards before (or instead of) building them in Prod.

The **Mixpanel MCP server is connected**, so an agent — or a human in an MCP-enabled client — can create and edit boards, run queries, and read project schema directly. See [docs.mixpanel.com/docs/mcp](https://docs.mixpanel.com/docs/mcp).

### 11.2 Building boards via the Mixpanel MCP

> **Agents:** the *how* of building or editing these boards — the MCP call sequence, the Wren project ids, and the Free-vs-Growth cap handling — lives in the **`mixpanel-build-boards`** skill (invoke `/mixpanel-build-boards`). This section stays canonical for board *conventions*; §11.3 / §11.4 for *which* boards; §9 / §10 / §5 for events, properties, and the PII contract. The skill defers back to this spec, so keep the two in sync.

Boards are for humans. When an agent (or anyone) creates or edits a board through the Mixpanel MCP:

- **Write for a human reader.** Names and descriptions are short, plain, and about the **user behavior** the board shows — not the build process. No phase numbers, ticket IDs, "built via MCP", filter mechanics, or other housekeeping in names/descriptions. One short doc reference (e.g. "§3.1") for traceability is the only meta detail worth including.
- **Be concise.** At most a one-line framing card per board; don't over-explain.
- **Don't force what the MCP can't do.** The MCP query API can't express everything the Mixpanel UI can. If a board aspect can't be configured straightforwardly through the MCP and it's minor, **drop it from this spec** — just remove it, rather than forcing an awkward proxy or documenting the gap. We're constrained by Mixpanel and this is a small app; we don't push hard for any particular analytics shape.
- **Hand worth-keeping UI-only aspects back to the human.** If an aspect can't be done via the MCP but a person can set it up in the Mixpanel UI and it's worth keeping, add a one- or two-line self-service note as a text card on the board telling them how (e.g. "Hour-of-day view: open this report in Insights → group by Hour of Day → add back to this board").

**Plan & the saved-report cap (read before adding or removing boards).** Wren App - Prod is on Mixpanel's **Growth** plan, which allows **unlimited saved reports** and costs **$0/month while under the 1M-events/month free allotment** (then $0.28 per 1K events; volume discounts apply). That upgrade is what makes the full §11.3 set possible — at Wren's expected volume it is effectively free. Mixpanel's **Free** plan instead caps saved reports at **5 per project, per user** (every chart tile = one saved report; boards and text cards are free). Source: [docs.mixpanel.com/docs/pricing](https://docs.mixpanel.com/docs/pricing) and [mixpanel.com/pricing](https://mixpanel.com/pricing/) (the docs word the Free cap as "5 per user account," but it was confirmed empirically on 2026-06-22 to bind **per project**: Jimmy held 4 reports in Prod **and** 4 in Dev at the same time, and a 6th in Prod was rejected with `User has reached their limit of saved reports for this project`).

**If the project is ever downgraded back to Free**, the 5-report-per-project cap returns and all but five report tiles must be deleted — keep the five "survivors" listed in [§11.4](#114-free-tier-fallback--the-five-reports-to-keep-if-you-downgrade) and drop the rest. Notes that hold on any plan:

- Auto-generated "🌱 Starter Board" reports are owned by the **Mixpanel** system user and do **not** count against the Free quota.
- `Run-Query` drafts that are never attached to a board do not persist as saved reports (they don't show in `Search-Entities`).
- The Free cap is **per project**, so deleting reports/boards in other projects (Dev, deprecated) frees nothing in Prod. There is **no** standalone delete-report MCP tool — free a slot with `Update-Dashboard` (cell `delete`), or delete the whole board with `Delete-Dashboard`.
- The Mixpanel MCP endpoint occasionally returns transient `502`s under burst load; space out report-creation calls and retry (drafts and attached reports survive a brief outage).

### 11.3 Built dashboards

All ten Phase 1 boards are **built** in Wren App - Prod (30 report tiles in total), made possible by the Growth plan (§11.2). "Answers" is the §3 question the board serves; "Status" tracks the **production** project only. **"Keep on Free"** marks the single report to retain on each board if the project is ever downgraded to Free — the five prioritized survivors (see §11.4).

| Dashboard                            | Contents (as shipped)                                                                                                                                                                                 | Answers | Status    | Keep on Free          |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | --------- | --------------------- |
| Reach                                | DAU / WAU / MAU on `app_opened`; sessions-per-user.                                                                                                                                                  | §3.1    | **Built** | ✅ DAU / WAU / MAU      |
| Activation funnel                    | `app_opened → budget_created → expense_logged` steps + time-to-convert.                                                                                                                              | §3.2    | **Built** | ✅ funnel steps         |
| Time to first budget & first expense | `time_since_first_app_open_bucket` (first budget) and `time_since_budget_created_bucket` distributions.                                                                                              | §3.2    | **Built** | —                     |
| Budget composition                   | Share of `budget_created` by `period`, by `currency_code`, by `carry_over_enabled`.                                                                                                                  | §3.3    | **Built** | ✅ by `period`          |
| User composition                     | Active users by `dominant_period`, `default_currency_code`, `uses_carry_over`, `has_disabled_carry_over`, `budgets_count_bucket`, `budgets_with_carry_over_on_count_bucket`, `device_class`, `region`, `locale`. | §3.3    | **Built** | —                     |
| Budget allocations                   | Median `budget_allocation_amount` by `currency_code`, by `period`, by `region`.                                                                                                                      | §3.3    | **Built** | —                     |
| Retention                            | Born `app_opened`; returning `expense_logged` (value loop) **and** `app_opened` (check-in); 1d / 7d / 30d.                                                                                           | §3.4    | **Built** | ✅ `expense_logged` view |
| Settings: opens & changes            | `settings_opened` per active user; `setting_changed` by `setting_name` × `new_value`.                                                                                                                | §3.5    | **Built** | —                     |
| Destructive actions                  | Totals of `budget_reset`, `carry_over_reset`, `budget_deleted`, `expense_edited`, `expense_deleted`; mix of the three destructive flows.                                                             | §3.5    | **Built** | —                     |
| Consent                              | `analytics_consent_changed` by `consent_jurisdiction` × direction; by `region` × direction; opt-outs over time.                                                                                      | §3.6    | **Built** | ✅ jurisdiction × direction |

Each board carries a one-line framing text card per §11.2. Boards show no data yet for events not yet flowing to Prod (e.g. `budget_*`, the destructive actions, `setting_changed`) — the definitions are correct and will populate as data arrives. Currency-mixed views (allocation by `period` / `region`) are rough-shape only, since allocation is always paired with its `currency_code`.

### 11.4 Free-tier fallback — the five reports to keep if you downgrade

The Growth plan (§11.2) is what makes the full §11.3 set possible. **If Wren App - Prod is ever moved back to the Free plan, the 5-saved-reports-per-project cap returns** and all but five report tiles must be deleted. Keep exactly these five — the prioritized survivors that cover the most decision-useful §3 questions — and delete every other tile:

| Keep (the top 5)                                          | Board              | Answers |
| --------------------------------------------------------- | ------------------ | ------- |
| DAU / WAU / MAU                                            | Reach              | §3.1    |
| Activation funnel — `open → budget → expense` steps       | Activation funnel  | §3.2    |
| Retention — `app_opened → expense_logged` (value loop)    | Retention          | §3.4    |
| Budgets by `period`                                       | Budget composition | §3.3    |
| Consent — `consent_jurisdiction` × direction              | Consent            | §3.6    |

Everything else in §11.3 — the other five boards plus the richer per-board views (sessions-per-user, time-to-convert, the `app_opened` check-in retention, currency/carry-over composition, allocations, per-user composition, settings, destructive actions, the region/opt-out-trend consent views) — is **nice-to-have**: remove it first when reclaiming slots. Free a slot with `Update-Dashboard` cell `delete`, or delete the whole board with `Delete-Dashboard`. (If still on Growth, there is no need to delete anything — the full set stays.)

(A "Reach" board previously existed in the **Dev** project as an experiment; it was deleted on 2026-06-22 while diagnosing the cap. Per §11.1 the Dev project is not tracked here.)

---

## 12. Phase 2 Events (planned)

Final scope is re-validated against actual Phase 1 dashboard evidence; this is the working list.

| Event                          | Fired when                                                                                                                                                                              | Answers          |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `first_run_seen`               | Empty-state Budgets list displayed for the first time.                                                                                                                                  | §4.1 (floor)     |
| `add_expense_started`          | Add Expense sheet presented. Paired with `expense_logged` to size abandonment.                                                                                                          | §4.1             |
| `add_budget_started`           | Add Budget sheet presented. Optional; only if Phase 1 evidence motivates it.                                                                                                            | §4.1             |
| `screen_viewed`                | Top-level screen presented. `screen_name` is enum. Optional and sampled if event volume is high.                                                                                        | (flow analysis)  |
| `rating_prompt_eligible`       | The first time a user meets the F-6.03 "meaningful usage" threshold. Fires **once per user** — gated by the `rating_prompt_first_eligible_at` people property in §13.2. **Shipped with F-6.03** (`rating-prompt`), pulled forward from Phase 2. | §4.4             |
| `rating_prompt_requested`      | The app calls Apple's native `requestReview` after an eligible user completes a qualifying action (F-6.03). Fires when we **request** a review — StoreKit then decides whether to actually present the dialog and reports nothing back, so this is the deepest observable point. De-duplicated per app version (matching the local once-per-version guard in F-6.03). **No `outcome` is observable** — see §4.4. **Shipped with F-6.03** (`rating-prompt`), pulled forward from Phase 2. | §4.4             |
| `feature_flag_exposed`         | First time per app session per flag that the client reads a flag value with effect on UI / behavior. Carries `flag_key` and `variant` (see §13.1). De-duplicated client-side per session to keep volume bounded. | §4.5             |

---

## 13. Phase 2 Properties (planned)

### 13.1 Per-event additions

| Event                    | Property                            | Notes                                                                                              |
| ------------------------ | ----------------------------------- | -------------------------------------------------------------------------------------------------- |
| `app_opened`             | `cold_start_to_budgets_visible_ms`  | Measured via `os_signpost` between app entry and Budgets first body render.                        |
| `expense_logged`         | `taps_from_budgets_list`            | Validates the [ux-design-brief.md](ux-design-brief.md) fast-logging promise.                       |
| `rating_prompt_requested` | `time_since_first_eligible_bucket` | `<1d` / `<7d` / `<30d` / `≥30d`. Bucketed gap between `rating_prompt_first_eligible_at` and the request. Answers §4.4 "how long after eligibility do we ask?" without a raw timestamp. |
| `feature_flag_exposed`   | `flag_key`                          | Categorical, matches the keys defined for `FeatureFlagClient` in §15.                              |
| `feature_flag_exposed`   | `variant`                           | Categorical (e.g. `control` / `variant_a`). `null` / absent if the flag returned a default fallback. |

### 13.2 Cohort-driving people properties

(Phase 1 §10.3 already carries `dominant_period`, `uses_carry_over`, `has_disabled_carry_over`, and `budgets_with_carry_over_on_count_bucket` — they were promoted forward to keep the §3.3 questions answerable in Phase 1. The remaining cohort properties are Phase 2.)

| Property                          | Definition                                                                                                                                  |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `has_multiple_budgets`            | Bool. True if `budgets_count_bucket >= "2-3"`. Cheap to compute alongside the existing bucket; powers §4.3 multi-budget cohort retention.   |
| `uses_multiple_currencies`        | Bool. True if more than one distinct `currency_code` across the user's Budgets. Recomputed alongside `default_currency_code`.               |
| `last_expense_logged_at`          | Timestamp; used for retention math only. **Not** surfaced in-app as a streak metric per [ux-design-brief.md](ux-design-brief.md).           |
| `rating_prompt_first_eligible_at` | Timestamp set the first time the F-6.03 threshold is met. Gates the one-shot `rating_prompt_eligible` event so it fires at most once.       |
| `rating_prompt_last_requested_at` | Timestamp refreshed each time the app calls `requestReview` (fires `rating_prompt_requested`). Lets dashboards segment retention by whether/when we asked. **No outcome is stored** — StoreKit does not report dismiss/rate (see §4.4). |

---

## 14. Phase 2 Dashboards (planned)

| Dashboard                                  | Primary report type                                                                                                                                | Answers |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| Activation funnel with abandonment step    | Funnels — `app_opened → add_budget_started → budget_created → add_expense_started → expense_logged`, with each "started" step revealing drop-off. | §4.1    |
| Fast-logging UX validation                 | Insights — distribution / median / p90 of `taps_from_budgets_list` on `expense_logged`; `cold_start_to_budgets_visible_ms` on `app_opened`.        | §4.2    |
| Cohort retention                           | Retention — anchored on `expense_logged`, segmented by `dominant_period`, `uses_carry_over`, `has_multiple_budgets`, `uses_multiple_currencies`.   | §4.3    |
| Rating-prompt eligibility timeline         | Insights — `rating_prompt_eligible` over time; people-property histogram of `rating_prompt_first_eligible_at` vs `first_seen_at`.                  | §4.4    |
| Rating-prompt request rate                 | Funnels — `rating_prompt_eligible → rating_prompt_requested`, with `time_since_first_eligible_bucket` distribution. **No outcome step** — StoreKit does not report whether the dialog was shown, dismissed, or rated (see §4.4). | §4.4    |
| Feature-flag exposure & impact             | Insights — `feature_flag_exposed` totals by `flag_key` × `variant`; Retention / Funnels segmented by `variant` for any active flag (the experimentation seam itself; no live experiment ships in F-8.03). | §4.5    |

---

## 15. Experimentation Seam (Phase 2)

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

## 16. Build Hygiene

- **Mixpanel project tokens are externalized to xcconfig** — no longer hardcoded in source. Token values live in `config/Secrets.local.xcconfig` (gitignored, maintainer-only) and are injected into the app bundle at build time via `config/Secrets.xcconfig` + `Info.plist` variable substitution. The committed `config/Secrets.xcconfig` contains safe placeholder sentinels (`PLACEHOLDER_MIXPANEL_DEV_TOKEN` / `PLACEHOLDER_MIXPANEL_PROD_TOKEN`). Two Mixpanel projects remain provisioned — bound to the dev and prod tokens, respectively.

  **Open-source trigger fulfilled:** The original §16 noted "Revisit if the repo is open-sourced." That trigger was met by the `public-repo-secrets-and-license` change, which externalized tokens so a fresh-clone fork gets placeholder defaults and sends no events. The Mixpanel tokens have since been **rotated and are now treated as secret**: the previously-committed tokens are revoked, and the live dev/prod tokens exist only in `config/Secrets.local.xcconfig` (gitignored, maintainer-only) — they are no longer committed to source control. Because a public-repo fork therefore cannot obtain a working token, the former fork-pollution risk no longer applies and the `bundle_id` event filter has been retired (see Revision History). See `[CONTRIBUTING.md](../CONTRIBUTING.md)` for fork Mixpanel setup.

- **Unconfigured (fresh-clone) behavior:** when tokens are still the committed placeholder sentinels — `MixpanelTokenSource.isConfigured` returns `false` — the app entry (`simple_recurring_budgetsApp.init()`) substitutes `ConsoleAnalyticsClient` instead of `MixpanelAnalyticsClient`. No Mixpanel SDK init, no network traffic. The app launches and runs normally on a Simulator with no secrets file.

- **Release ship guard:** `scripts/verify_release_secrets.sh` (called by Fastlane `beta`/`release` and the Xcode Release-only Run Script phase) blocks archives that still carry placeholder sentinels before spending time on archive/sign/upload.

- DEBUG and Release builds both use `MixpanelAnalyticsClient` when configured. Physical separation of dev-vs-prod data is enforced by the active token (`MixpanelTokenSource.activeToken` branches on `#if DEBUG`), which routes events to the dev project on developer builds and the prod project on App Store / TestFlight builds; see §8 for the full client-selection table. `ConsoleAnalyticsClient` remains the SwiftUI `@Entry` default for previews / tests that don't run through the app entry, AND is used on any build where tokens are unconfigured.
- The Mixpanel SDK is added via SPM (latest stable `mixpanel-swift`); the package dependency is already present in `simple-recurring-budgets.xcodeproj`. No SPM-add task is needed.
- The SDK is initialized with `trackAutomaticEvents: false`. We never collect IDFA, do not use Mixpanel's session-replay or autocapture, and do not enable cross-app tracking — therefore App Tracking Transparency (`AppTrackingTransparency.framework` / `NSUserTrackingUsageDescription`) is **out of scope** and the implementing change SHALL NOT add an ATT prompt.
- Mixpanel batching is tuned for iOS Low Data Mode (`Mixpanel.flushBatchSize` conservative).
- All Phase 1 events are user-initiated and low-frequency (no per-tap, per-scroll, or per-frame events). No client-side sampling is required for Phase 1; Phase 2 may revisit this for `screen_viewed` if event volume becomes a concern.

### 16.1 Implementation starting state (codebase snapshot) — historical record

> **This subsection is now a historical record.** F-8.02 (`mixpanel-phase-1-foundation`) has been implemented. The table below reflects the pre-implementation state for reference; the "Required action" column is now complete.

This subsection captures what existed in the repo before implementing F-8.02.

**Pre-F-8.02 state — all refactors now complete:**

| File | Pre-F-8.02 state | Action taken by F-8.02 |
|---|---|---|
| `[simple-recurring-budgets/Logging/AnalyticsClient.swift](../simple-recurring-budgets/Logging/AnalyticsClient.swift)` | `AnalyticsClient` protocol + `AnalyticsEvent` enum with `appOpened = "app_opened"`. | Extended with Phase 1 event constants + new `AnalyticsProperty` enum; all constants marked `nonisolated` for Swift 6 `@MainActor` default-isolation compatibility. |
| `[simple-recurring-budgets/Logging/ConsoleAnalyticsClient.swift](../simple-recurring-budgets/Logging/ConsoleAnalyticsClient.swift)` | DEBUG `print` impl. | Unchanged; remains the DEBUG default and test fallback. |
| `[simple-recurring-budgets/Logging/MixpanelAnalyticsClient.swift](../simple-recurring-budgets/Logging/MixpanelAnalyticsClient.swift)` | Eagerly called `Mixpanel.initialize` in `init`. | Fully refactored: lazy `NSLock`-guarded init; accepts full set of `@Sendable` closure providers for super/people properties; `refreshSuperProperties()` and `refreshCohortPeopleProperties(budgets:)` added; `@unchecked Sendable`. |
| `[simple-recurring-budgets/Logging/AnalyticsEnvironment.swift](../simple-recurring-budgets/Logging/AnalyticsEnvironment.swift)` | `@Entry var analytics: any AnalyticsClient = ConsoleAnalyticsClient()`. | Unchanged. |
| `[simple-recurring-budgets/App/simple_recurring_budgetsApp.swift](../simple-recurring-budgets/App/simple_recurring_budgetsApp.swift)` | Hardcoded `{ false }` opt-in closure. | Wired to `AppSettings.analyticsOptIn`; `identify(distinctId)` call added per §6 / §8.1; `MixpanelTokenSource` helper extracts token literals. |
| `[simple-recurring-budgets/Logging/AppLoggers.swift](../simple-recurring-budgets/Logging/AppLoggers.swift)` | `Logger.bootstrap`, `Logger.cloudKit`, `Logger.ui` constants. | Untouched by F-8.02. |
| `[simple-recurring-budgetsTests/Logging/SpyAnalyticsClient.swift](../simple-recurring-budgetsTests/Logging/SpyAnalyticsClient.swift)` | Existing test double. | Extended with `recordSuperProperties`, `recordPeopleSet`, `recordPeopleSetOnce` helpers for Phase 1 test contracts. |

**Created by F-8.02:**

- `simple-recurring-budgets/Settings/ConsentJurisdiction.swift` — pure jurisdiction classifier from region identifier.
- `AppSettings` analytics properties: `analyticsOptIn`, `analyticsDistinctId`, `analyticsFirstOpenAt` (all `NSUbiquitousKeyValueStore`-backed, `@Observable`, locale-aware defaults).
- `simple-recurring-budgets/Views/Consent/AnalyticsConsentSheet.swift` — first-run consent sheet for strict-opt-in jurisdictions.
- `simple-recurring-budgets/App/SheetRoute.swift` + `RootView.swift` — `.analyticsConsent` case added.
- `simple-recurring-budgets/Logging/Analytics+DomainExtensions.swift` — `analyticsValue` helpers for domain types.
- `simple-recurring-budgets/Logging/MixpanelTokenSource.swift` — `#if DEBUG` token branch abstraction.
- Phase 1 call-site instrumentation in `AddEditBudgetViewModel`, `AddEditExpenseView`, `BudgetDetailView`, `BudgetDetailView+ExpenseSection`, `SettingsView`.
- 10 Swift Testing suites in `simple-recurring-budgetsTests/Logging/` covering all §18.1 contracts.

---

## 17. Boundary with F-8.01 (OSLog)

| Concern                                                                            | Routing                                                                                |
| ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| App lifecycle (launch, container creation, CloudKit fallback)                      | OSLog (`bootstrap` / `cloudkit` categories) — F-8.01.                                  |
| Crash and reliability                                                              | Apple-native (MetricKit / system Crash Reporter) — out of scope for both F-8.01 and F-8.02. |
| User-initiated UI actions whose **product behavior** we want to measure            | Mixpanel `.product` channel — F-8.02 / F-8.03.                                         |
| User-initiated UI actions whose **runtime trace** we want for debugging            | OSLog (`ui` category) — F-8.01.                                                        |

A single user action can produce both — e.g., a successful Add Expense sends `expense_logged` to Mixpanel **and** writes an `ui`-category entry to OSLog. The two paths are independent and never cross.

**Narrow allow-listed diagnostic event — `persistence_save_failed`.** A SwiftData `context.save()` failure is the one place where a diagnostic concern is also surfaced on the product-analytics channel. The shared persistence-save helper (`ModelContext.saveChanges(operation:analytics:)`) emits **one** `Logger.persistence.error` line **and** fires **one** `persistence_save_failed` event as sibling statements built from the same plain values (the `PersistenceOperation` identifier and the `NSError` domain/code). Rationale: an unreachable `OSLog.error` is invisible in the wild; routing one diagnostic event into the product stream gives the developer dashboard visibility into a failure that otherwise blocks the user. The event is restricted to **only** `operation`, `error_domain`, `error_code` — see §5.2 / §10.1. Because the event is consent-gated like all `AnalyticsClient` traffic, it is a best-effort signal; the on-device `OSLog.persistence` line is the complete record. This is the **only** approved diagnostic event in the product stream and SHALL NOT be generalized into a back-door for other diagnostic data.

**Co-location (sibling-call) pattern — F-8.02 destructive-action funnels.** Four methods in the codebase contain both a `Logger.ui.debug(...)` call (F-8.01) and an `analytics.track(...)` call (F-8.02) in the same method body:

| Method | Logger call | Analytics call |
|--------|-------------|----------------|
| `AddEditBudgetViewModel.delete(context:analytics:)` | `Logger.ui.debug("ui.action: deleteBudget …")` | `analytics.track(AnalyticsEvent.budgetDeleted, …)` |
| `BudgetDetailView.resetBudget(…)` | `Logger.ui.debug("ui.action: resetBudget …")` | `analytics.track(AnalyticsEvent.budgetReset, …)` |
| `BudgetDetailView.resetCarryOver(…)` | `Logger.ui.debug("ui.action: resetCarryOver …")` | `analytics.track(AnalyticsEvent.carryOverReset, …)` |
| `BudgetDetailView+ExpenseSection.deleteExpense(_:)` | `Logger.ui.debug("ui.action: deleteExpense …")` | `analytics.track(AnalyticsEvent.expenseDeleted, …)` |
| `ModelContext.saveChanges(operation:analytics:)` (failure path) | `Logger.persistence.error("persistence.save.failed …")` | `analytics.track(AnalyticsEvent.persistenceSaveFailed, …)` |

These are **independent sibling statements** — the Logger call does not feed the analytics call and vice versa. Each carries its own independently assembled arguments. This is the approved pattern for funnels where both diagnostic tracing and product measurement are warranted at the same action point. The "never cross" rule above means: the Logger argument MUST NOT be derived from an analytics property bag, and the analytics property bag MUST NOT be derived from a Logger call.

---

## 18. Test Strategy

- The existing `SpyAnalyticsClient` continues to back call-site unit tests.
- `MixpanelAnalyticsClient` has no diagnostic routing to contract-test; the separation is structural — diagnostic calls never reach `AnalyticsClient` at all.
- A single integration smoke test verifies a real `MixpanelInstance` can be initialized and a sample event enqueued. Run manually before Mixpanel-touching releases.

### 18.1 Concrete unit test contracts (Phase 1)

The implementing change MUST land tests covering at least the following — written with Swift Testing per `docs/tech-design-doc.md` §5.3, using `SpyAnalyticsClient` and `MockKeyValueStore` so no Mixpanel network call occurs:

1. **`ConsentJurisdiction` resolution** — parameterized test over the §7.2 region table: every listed code resolves to `.required`; a representative sample of unlisted codes (`US`, `CA` non-Quebec, `JP`, `AU`, `IN`, `nil`) resolves to `.auto_optin`.
2. **`AppSettings.analyticsOptIn` defaults** — fresh store + jurisdiction `required` → `false`; fresh store + jurisdiction `auto_optin` → `true`; persisted explicit value overrides the default.
3. **`AppSettings.analyticsDistinctId`** — fresh store generates a UUIDv4 once and persists it; subsequent reads return the same value; the setter is not exposed publicly (resolution is internal to `AppSettings`).
4. **Lazy-init invariant** — using a `MixpanelAnalyticsClient` test seam (with the SDK init step replaced by a `@Sendable` closure spy), assert: `init` does **not** invoke the SDK-init closure; `track(_:)` with `isOptedIn = false` does not invoke it; `track(_:)` with `isOptedIn = true` invokes it exactly once across many calls.
5. **Toggle-off ordering** — assert that flipping `analyticsOptIn` from `true` to `false` results in `track("analytics_consent_changed", ...)` being delivered to Mixpanel **before** `reset()` is called and **before** subsequent events are dropped.
6. **Toggle-on (strict-opt-in)** — assert that flipping `analyticsOptIn` from `false` to `true` triggers, in order: SDK lazy-init → `identify(distinctId)` → `track("analytics_consent_changed", new_value: true)` → no retroactive `app_opened`.
7. **`app_opened` event constant** — `AnalyticsEvent.appOpened == "app_opened"`. (The prior `appLaunched = "app.launched"` constant was renamed in a precursor change; this test guards against regression.)
8. **PII enforcement (compile-time and call-site)** — call-site tests verify that `expense_logged` / `expense_edited` / `expense_deleted` event invocations carry only the §10.1 allow-listed properties and never include `expense.name`, `expense.amount`, or `expense.date`. (No serializer helper from `ExpenseItem` to properties is exposed; this is a structural test that asserts no such API exists in `AnalyticsClient` extension space.)
9. **Super-property attachment** — every tracked event in a fixture run carries the §10.2 super-property keys (`app_version`, `device_class`, `consent_jurisdiction`, `budgets_count_bucket`, `carry_over_default_enabled`, etc.); the `budgets_count_bucket` value transitions correctly across the bucket boundaries `0` / `1` / `2-3` / `4-7` / `8+`.
10. **Token source branch is correct** — confirm `MixpanelTokenSource.activeToken` returns `AppConfig.mixpanelDevToken` in DEBUG and `AppConfig.mixpanelProdToken` in Release (per §16). Verified via pure unit tests against `MixpanelTokenSource.isConfigured(dev:prod:)` with known-good vs placeholder sentinel inputs — no live bundle assertions. Both configurations use `MixpanelAnalyticsClient` when tokens are configured; `ConsoleAnalyticsClient` is substituted when `isConfigured` is `false` (fresh-clone / placeholder scenario). The two placeholder sentinels SHALL NOT equal a valid token (length and content checks suffice).

---

## 19. Doc Updates Required at Implementation Time

Both F-8.02 and F-8.03 must land paired updates in [tech-design-doc.md](tech-design-doc.md) per its standing maintenance protocol:

| When           | What to update                                                                                       |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| ~~F-8.01 ships~~ ✓ (done by `oslog-diagnostic-logging`) | `tech-design-doc.md` §7 — confirm the OSLog category list (`bootstrap`, `cloudkit`, `ui`) matches `AppLoggers.swift` and add a sentence pointing at this spec's §17 boundary. |
| ~~F-8.02 ships~~ ✓ (done by `mixpanel-phase-1-foundation`) | `tech-design-doc.md` §7 — name vendor as Mixpanel; document opt-in toggle and privacy contract; reference §8 / §8.1 client-selection and ordering. |
| ~~F-8.02 ships~~ ✓ (done by `mixpanel-phase-1-foundation`) | `tech-design-doc.md` §4.5 KV-key table — added `"analyticsOptIn"` (Bool), `"analyticsDistinctId"` (String, UUIDv4), and `"analyticsFirstOpenAt"` (Double). |
| ~~F-8.02 ships~~ ✓ (done by `mixpanel-phase-1-foundation`) | `tech-design-doc.md` §9 — refresh future-work table; added Phase 2 row pointing at F-8.03. |
| ~~F-8.02 ships~~ ✓ (done by `mixpanel-phase-1-foundation`) | `analytics-spec.md` §16.1 — rewritten as historical record; post-implementation state documented. |
| ~~F-8.02 ships~~ ✓ (done by `mixpanel-phase-1-foundation`) | OpenSpec `app-settings` capability — delta adding `analyticsOptIn`, `analyticsDistinctId`, and `analyticsFirstOpenAt` requirements alongside the existing settings. |
| ~~F-8.02 ships~~ ✓ (done by `mixpanel-phase-1-foundation`) | OpenSpec `settings-screen` capability — delta adding the "Diagnostics & Analytics" section (toggle, disclosure copy, footer note). |
| ~~F-8.02 ships~~ ✓ (done by `mixpanel-phase-1-foundation`) | `product-features-planning.md` F-8.02 — flipped status to **Implemented**. |
| ~~F-8.02 ships~~ ✓ (done by `mixpanel-phase-1-foundation`) | Source rename: `AnalyticsEvent.appLaunched = "app.launched"` → `AnalyticsEvent.appOpened = "app_opened"` (per §9). Done in precursor to this change. |
| ~~F-8.02 ships~~ ✓ (done by `mixpanel-phase-1-foundation`) | `analytics-spec.md` §17 — formalized the co-location (sibling-call) pattern at four destructive-action funnels. |
| F-8.03 ships   | `tech-design-doc.md` §7 — note the feature-flag surface and reference `FeatureFlagClient`.           |
| F-8.03 ships   | `tech-design-doc.md` §9 — drop / refresh the Phase 2 row. Update cross-refs to analytics-spec.md §12–15 if Phase 2 surface changes. |

---

## Appendix

### A. Revision History

| Version | Date       | Author   | Changes                                                                                          |
| ------- | ---------- | -------- | ------------------------------------------------------------------------------------------------ |
| 0.24    | 2026-06-22 | Jimmy Ho | Extended `expense_recent_reused` to fire in Edit/View mode (blank-Description-gated reveal, F-7.04). Updated event catalog description. Added `from_screen` property (`add_sheet` / `budget_detail`) to `expense_recent_reused` so add-vs-edit reuse is distinguishable. |
| 0.23    | 2026-06-22 | Jimmy Ho | Upgraded Wren App - Prod to the **Growth** plan (unlimited saved reports; $0/month under the 1M-events free allotment), lifting the 5-report Free cap that 0.22 worked around. Built out the **full Phase 1 set — all 10 boards, 30 report tiles** — restoring the views 0.22 had trimmed (sessions-per-user, time-to-convert, `app_opened` check-in retention, currency/carry-over composition, per-user composition, allocations, settings, destructive actions, region/opt-out-trend consent). Reframed §11.2 (plan + cap, now Growth-aware, with the [pricing](https://mixpanel.com/pricing/) link), §11.3 (all 10 Built, with a "Keep on Free" survivor column), and §11.4 (now a **Free-tier fallback** listing the 5 reports to keep if ever downgraded). |
| 0.22    | 2026-06-22 | Jimmy Ho | Built Phase 1 boards in **Wren App - Prod** via the Mixpanel MCP and reconciled §11 to reality. Discovered the **Free plan caps saved reports at 5 per project** (confirmed empirically; [docs.mixpanel.com/docs/pricing](https://docs.mixpanel.com/docs/pricing)) — documented as a hard constraint in §11.2 with rules for future agents (free a slot before adding; per-project scope; starter/draft reports don't count). Split §11.3 into the **five shipped boards** (Reach, Activation funnel, Retention, Budget composition, Consent — one report each, marked Built) and a new §11.4 **deferred/nice-to-have** catalogue (the other five boards + the trimmed-off richer views) that agents must not build without sacrificing a shipped report. Deleted the auto-generated Prod/Dev "🌱 Starter Board"s and the experimental Dev Reach board during diagnosis. |
| 0.21    | 2026-06-22 | Jimmy Ho | Reworked §11.2 into an agent guide for building boards via the Mixpanel MCP: human-readable/concise naming, and a "don't push hard" rule — minor aspects the MCP can't configure are dropped from the spec (no gap-documenting); worth-keeping UI-only aspects get a short self-service note on the board. Applied it by removing the hour-of-day / day-of-week breakdowns. |
| 0.20    | 2026-06-21 | Jimmy Ho | §11.3 status now tracks the **Prod** project only (the canonical analytics surface); the Dev project is an untracked experiment scratchpad. All rows are *Planned* (nothing built in Prod yet); Reach reverted from "Built — Dev (partial)" to *Planned*. Replaced the Dev-board note accordingly. |
| 0.19    | 2026-06-21 | Jimmy Ho | Redefined `app_opened` (§9): fires on cold launch and on each real `.background → .active` return, ignoring transient `.inactive` interruptions; removed the prior client-side session-gap dedup (a hardcoded 30-min constant that duplicated Mixpanel's server-side session setting). Mixpanel owns sessionization. §3.4 retention reworked: retention is configured per Mixpanel report (born + returning event); `expense_logged` retention is the value-loop signal, `app_opened` retention is check-in engagement (glanceable budget-checking above the fold is meaningful on its own). Code: `AppOpenTracker` now a scenePhase-transition gate; tests updated. |
| 0.18    | 2026-06-21 | Jimmy Ho | Implementation-audit reconciliation: the code emits two enum values the spec omitted. Added `specific_dates` to the §10.1 `period` values (the `BudgetPeriod.specificDates` fixed-window type; always pairs with `carry_over_enabled = false`) and to the §3.3 period-breakdown list, and added `checking` to the §10.2 `icloud_state` values. No code change. |
| 0.17    | 2026-06-21 | Jimmy Ho | Restructured §11 (Dashboards). Added §11.1 (the two Mixpanel projects — Prod ← App Store/TestFlight, Dev ← debug/Simulator — that Dev need not mirror Prod, and the connected Mixpanel MCP server), §11.2 (board conventions: human-readable, brief, no housekeeping/phase labels in board names), and §11.3 (a Status column tracking which boards are built and in which project). Noted that Mixpanel is the source of truth and this doc may drift. Reach board built (partial) in Dev. |
| 0.16    | 2026-06-21 | Jimmy Ho | Retired the `bundle_id` fork-pollution filter. Mixpanel project tokens were **rotated and are now kept secret** (out of source control), so a public-repo fork can no longer obtain a working token and cannot pollute the maintainer's projects. Removed the `bundle_id` super-property row from §10.2 and the "Universal project filter" paragraph from §11, and reframed the §16 token-secrecy note accordingly. Code updated to match: dropped the `bundle_id` entry from `MixpanelAnalyticsClient.registerSuperProperties(on:)`, removed the `AnalyticsProperty.bundleId` constant, and updated the two affected tests. |
| 0.15    | 2026-06-02 | Jimmy Ho | F-6.03 implemented by change `rating-prompt`. The two rating-prompt events (`rating_prompt_eligible`, `rating_prompt_requested`) and their `rating_prompt_first_eligible_at` / `rating_prompt_last_requested_at` people properties are **pulled forward from Phase 2 (F-8.03)** and ship with F-6.03; §12, §13.2 annotated accordingly. No PII-contract change. |
| 0.14    | 2026-06-02 | Jimmy Ho | F-6.03 rating-prompt analytics reconciled with Apple's native `requestReview` API, which reports neither whether the dialog was shown nor the user's choice. Replaced the unobservable `rating_prompt_shown` / `rating_prompt_resolved` events (and their `outcome` / `time_to_resolution_bucket` properties and `rating_prompt_last_outcome` people property) with a single observable `rating_prompt_requested` event (+ `time_since_first_eligible_bucket` property, `rating_prompt_last_requested_at` people property). `rating_prompt_eligible` retained. §4.4, §12, §13.1, §13.2, §14 updated; §4.4 records that no custom pre-prompt will be added to manufacture an outcome signal. |
| 0.13    | 2026-05-03 | Jimmy Ho | F-8.02 implemented by change `mixpanel-phase-1-foundation`. §16.1 rewritten as historical record. §17 — formalized co-location (sibling-call) pattern at four destructive-action funnels. §19 — all F-8.02 rows marked done. |
| 0.12    | 2026-05-02 | Jimmy Ho | §19 F-8.01 row marked done (implemented by change `oslog-diagnostic-logging`). |
| 0.11    | 2026-05-02 | Jimmy Ho | Fork-pollution defense. Added `bundle_id` to §10.2 super-property table — registered explicitly via `registerSuperProperties`, not auto-attached — with rationale (fork filtering) and §11 / §16 cross-references. Added "Universal project filter" paragraph in §11 instructing every Mixpanel dashboard to filter on `bundle_id`, with a note on the residual case (forker who doesn't change bundle ID) and its practical negligibility. |
| 0.1     | 2026-04-30 | Jimmy Ho | Initial draft to support T-8 / F-8.02 / F-8.03 in [product-features-planning.md](product-features-planning.md). |
| 0.2     | 2026-05-02 | Jimmy Ho | Locale-aware consent default: auto-opt-in outside known strict-opt-in jurisdictions; canonical jurisdiction table in §6.2; `consent_jurisdiction` values updated to `required` / `auto_optin`. |
| 0.3     | 2026-05-02 | Jimmy Ho | Restructured §4 into a field-level allow/deny PII contract. Accepted-risk exceptions: `budget_name` (raw) and `budget_allocation_amount`. Hard ban on any `ExpenseItem` field by value and on all other free-text and money-shaped values. §9.1 and §10 updated to match. |
| 0.4     | 2026-05-02 | Jimmy Ho | Added unnumbered "Canonical Constraints" section (§C.1 / §C.2) as the single source of truth for F-8.02 / F-8.03 constraints; features doc now points here. Filled gaps in §2 Phase 1 product questions (per-Budget carry-over share, "which settings get changed"). |
| 0.5     | 2026-05-02 | Jimmy Ho | Renumbered all sections for coherence: Canonical Constraints → §2; former §§2–17 → §§3–18 (shifts all cross-references). Updated all internal links in analytics-spec.md and cross-references in product-features-planning.md. |
| 0.6     | 2026-05-02 | Jimmy Ho | Cleanup pass left over from 0.5: removed duplicate Phase 2 product-questions section, fixed §3.x subsection numbering. Audited Events / Properties / Dashboards against §3 and §4 product questions; added what was missing: Phase 1 — `setting_changed` event, `time_since_first_app_open_bucket` per-event property, `device_class` super property, and Phase-1-promoted people properties (`dominant_period`, `uses_carry_over`, `has_disabled_carry_over`, `budgets_with_carry_over_on_count_bucket`); Phase 2 — `rating_prompt_eligible`/`shown`/`resolved` and `feature_flag_exposed` events with corresponding properties and `rating_prompt_first_eligible_at` / `rating_prompt_last_outcome` people properties. Phase 1 dashboards split into per-Budget vs per-user composition; Phase 2 dashboards split rating-prompt eligibility vs outcomes. |
| 0.7     | 2026-05-02 | Jimmy Ho | Plan-readiness pass for F-8.01 / F-8.02. §7.2 added "no retroactive event replay" clause for strict-opt-in jurisdictions. §8.1 new — canonical launch-time and consent-transition ordering (auto-opt-in first launch, strict-opt-in accept / decline, toggle-off, DEBUG). §16 expanded with token-via-Info.plist sourcing, `trackAutomaticEvents: false`, ATT out-of-scope, and Phase 1 sampling not required. §16.1 new — implementation starting-state codebase snapshot distinguishing refactor vs build-new. §18.1 new — concrete unit-test contracts (10 items). §19 expanded — added F-8.01 row, OpenSpec capability deltas (`app-settings`, `settings-screen`), and the `appLaunched`→`appOpened` source rename. |
| 0.8     | 2026-05-02 | Jimmy Ho | Aligned spec with current implementation: §8 client-selection table now has DEBUG and Release both use `MixpanelAnalyticsClient` (separated by dev-vs-prod project token), with `ConsoleAnalyticsClient` retained as the SwiftUI `@Entry` default for previews / tests; §8.1 DEBUG paragraph updated to match; §16 first bullet updated; §16.1 simple_recurring_budgetsApp refactor row no longer demands swapping to `ConsoleAnalyticsClient` in DEBUG; §18.1 #10 reframed as token-resolution test instead of client-class swap test. Also: source rename `AnalyticsEvent.appLaunched` → `AnalyticsEvent.appOpened` is now complete; spec text updated accordingly. |
| 0.9     | 2026-05-02 | Jimmy Ho | Mixpanel project tokens stay hardcoded in source via `#if DEBUG`. §16 first bullet rewritten with the rationale (project tokens are write-only client identifiers, not classical secrets), the dev-vs-prod-project mapping (both Mixpanel projects already provisioned), and the explicit revisit triggers. §16.1 refactor row no longer requires moving tokens to `xcconfig` / `Info.plist` and explicitly forbids it in F-8.02 scope. §8.1 DEBUG paragraph and §18.1 #10 reframed against the `#if DEBUG` literal branch instead of an Info.plist seam. F-8.02 starting-state bullet in product-features-planning.md updated accordingly. |
| 0.10    | 2026-05-02 | Jimmy Ho | Lazy SDK init confirmed as the spec contract. Added an `[!IMPORTANT]` "Current implementation gap" callout in §8 making the violation visible alongside the constraint and pointing at §16.1 for refactor scope and §18.1 #4 for the contract test. §16.1 `MixpanelAnalyticsClient.swift` row rewritten with itemized refactor steps (deferred init, thread-safe one-shot init guard, reset behavior, constructor shape, super-property and people-property registration). No code changes in this revision. |
| 0.11    | 2026-05-02 | Jimmy Ho | Fork-pollution defense. Added `bundle_id` to §10.2 super-property table — registered explicitly via `registerSuperProperties`, not auto-attached — with rationale (fork filtering) and §11 / §16 cross-references. Added "Universal project filter" paragraph in §11 instructing every Mixpanel dashboard to filter on `bundle_id`, with a note on the residual case (forker who doesn't change bundle ID) and its practical negligibility. |
