## Why

The app ships a manual **Rate the App** button in Settings, but never proactively asks happy users for a review — the single highest-leverage lever on App Store rating volume, and a direct input to the PRD KPI "minimal complaints in App Store reviews." F-6.03 adds **automatic, eligibility-gated** prompting that fires Apple's native review dialog at a genuine positive moment, without nagging.

## What Changes

- Introduce a **rating-prompt coordinator** that tracks eligibility signals (install age, distinct logging days, lifetime expense count, once-per-version guard) and decides when to ask.
- After a **successful Add-mode expense log** on an **active** budget whose resulting Remaining is **≥ 0** (non-deficit), evaluate eligibility; when met, request a review via Apple's native `requestReview` (`@Environment(\.requestReview)`).
- Present the request from the **root view** after the Add Expense sheet dismisses (decouples "decide" from "present", avoids the sheet-dismissal race), gated to once per app version on top of Apple's automatic ≤ 3/year throttle.
- Persist eligibility counters in the iCloud key-value store (the existing `KeyValueStore` abstraction), **independent of analytics consent** so eligibility works for users who declined analytics.
- Add two analytics events — `rating_prompt_eligible` (once per user) and `rating_prompt_requested` (per version) — pulled forward from the Phase 2 (F-8.03) catalog because they are this feature's learning loop. **No custom pre-prompt / "do you like the app?" dialog** is added (review-gating is banned per the no-engagement-pressure constraint).
- **No new user-facing strings**: the native review dialog and the existing Settings button are system-/already-localized.

## Capabilities

### New Capabilities
- `rating-prompt`: eligibility-signal tracking, trigger evaluation, the once-per-version guard, the deferred "request pending" signal, and the native `requestReview` invocation. Owns the persisted counters and all the decision logic (the unit-tested core).

### Modified Capabilities
- `add-edit-expense-screen`: on a successful **Add-mode** save, record the log into the rating-prompt coordinator (passing whether the post-save period is non-deficit and the budget is active) so eligibility can advance.
- `app-navigation`: the root view hosts the rating-prompt presenter — it reads `@Environment(\.requestReview)`, and when a request is pending and the scene is active, presents the dialog, records the asked version, and fires `rating_prompt_requested`.
- `product-analytics`: add the `rating_prompt_eligible` and `rating_prompt_requested` event constants (+ the `time_since_first_eligible_bucket` property and `rating_prompt_first_eligible_at` / `rating_prompt_last_requested_at` people properties), conforming to the §5 PII contract (no new PII; all categorical/bucketed).

## Impact

- **New code:** a `RatingPromptCoordinator` (`@MainActor @Observable`) + a small persisted `RatingPromptState` (KV-backed, mirroring `AppSettings`), a root-level presenter view modifier, environment wiring in `simple_recurring_budgetsApp` / `RootView`.
- **Touched code:** `AddEditExpenseView` save path (records the log), `AnalyticsClient` event/property constants, `MixpanelAnalyticsClient` people-property refresh.
- **No schema/CloudKit change** (counters are KV-store, not SwiftData). **No new dependency** (`requestReview` is StoreKit via the SwiftUI environment, already used in Settings).
- **Testing:** Swift Testing unit tests for the coordinator/eligibility math; the native dialog itself is not testable in simulator/TestFlight, so no new XCUITest screen object.

## Doc alignment

Skimmed `docs/main-prd.md`, `docs/product-features-planning.md` (F-6.03), and `docs/tech-design-doc.md`.

- F-6.03's acceptance criteria (product-features-planning.md v1.1) are the contract for this change — trigger point, balanced thresholds (≥ 7 days installed, ≥ 3 distinct logging days, ≥ 10 lifetime expenses, non-deficit triggering log, once-per-version guard), platform-managed cooldown, and the two analytics events.
- **Conflict with docs (minor, resolved by doc update):** analytics-spec.md v0.14 §12 and product-features-planning.md F-6.03 currently tag `rating_prompt_eligible` / `rating_prompt_requested` as **Phase 2 (F-8.03)**. This change pulls those two events forward into F-6.03 (precedent: the Phase-1-promoted people properties in analytics-spec §10.3). A task updates both docs to note the two rating events ship with the `rating-prompt` change (F-6.03), not F-8.03.
- tech-design-doc.md §4.5 (KV-key table) gains the new rating-prompt keys; §7/§9 unaffected beyond a cross-reference. Doc updates are listed in tasks.md.
