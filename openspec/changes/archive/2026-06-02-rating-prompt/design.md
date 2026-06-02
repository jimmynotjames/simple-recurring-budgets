## Context

F-6.03 (product-features-planning.md v1.1) adds automatic, eligibility-gated App Store review prompting. The manual **Rate the App** button already exists in `SettingsView` (`@Environment(\.requestReview)`, line ~382). This change adds the *automatic* path.

Constraints that shape the design:
- **No backend, no custom dialog.** Apple's native `requestReview` is the only mechanism; review-gating ("do you like the app?" pre-prompts) is banned by the no-engagement-pressure constraint (main-prd.md §3, analytics-spec.md §2.1.7).
- **The native API is opaque.** `requestReview` reports neither whether StoreKit presented the dialog nor the user's choice. Re-prompt prevention therefore cannot depend on an outcome — only on Apple's automatic throttle (≤ 3/year, per acted-on version) plus our own once-per-version guard.
- **Eligibility must work without analytics consent.** Counters live in the iCloud KV store via the existing `KeyValueStore` abstraction, not behind `AppSettings.analyticsOptIn` and not reusing `AppSettings.analyticsFirstOpenAt` (which is analytics-semantics state).
- Cross-cutting concerns (main-prd.md §6.8): no new user-facing strings (system dialog), so no Dynamic Type / VoiceOver / localization surface; analytics is in scope.

## Goals / Non-Goals

**Goals:**
- Ask happy, established users for a review at a positive moment with the balanced threshold profile from F-6.03.
- Keep the decision logic a pure, unit-testable core decoupled from SwiftUI and from StoreKit.
- Ship the two learning-loop analytics events (`rating_prompt_eligible`, `rating_prompt_requested`).

**Non-Goals:**
- No custom rating UI, no in-app "rate" sheet, no star capture.
- No attempt to observe whether the dialog showed or what the user chose (impossible with the native API).
- No change to the manual Settings button (it stays as-is).
- No SwiftData/CloudKit schema change; no new third-party dependency.
- No A/B testing of thresholds now (left as a future F-8.03 feature-flag seam).

## Decisions

### D1. Native `requestReview` only, presented from the root view via a deferred "pending" signal
The coordinator never calls `requestReview` directly. On an eligible log it sets a transient `isRequestPending = true`. A root-level presenter modifier (`.ratingPromptPresenter()` applied in `RootView`) reads `@Environment(\.requestReview)` and, when `isRequestPending` is true **and** `scenePhase == .active`, calls `requestReview()`, records the asked version, fires `rating_prompt_requested`, and clears the flag.

*Why:* the trigger fires inside the Add Expense sheet's save path, but presenting a system dialog mid-sheet-dismissal is racy and often silently dropped. Deferring to the root after the sheet dismisses guarantees a stable presentation context regardless of whether the user lands on the Budgets list or a Budget detail.
*Alternatives rejected:* (a) calling `requestReview()` in the save handler then `dismiss()` — dismissal race; (b) `Task.sleep` delay after dismiss — fragile timing, still racy.

### D2. Decision core is a `@MainActor @Observable RatingPromptCoordinator` over a KV-backed `RatingPromptState`
`RatingPromptState` holds the persisted counters via the existing `KeyValueStore` protocol (default `NSUbiquitousKeyValueStore.default`), mirroring `AppSettings`'s read/write/observe pattern. The coordinator exposes:
- `recordExpenseLogged(isActiveBudget:remainingIsNonNegative:now:appVersion:)` → updates counters, evaluates eligibility, sets `isRequestPending` and fires `rating_prompt_eligible` (one-shot) when newly eligible.
- `consumePendingRequest(appVersion:)` → called by the presenter after `requestReview()`; records `lastRequestedVersion`, refreshes the `rating_prompt_last_requested_at` people property.

Persisted keys (added to tech-design-doc.md §4.5):
- `ratingPromptInstalledAt` (Double, ref-date) — first launch; set once, never updated.
- `ratingPromptLoggedExpenseCount` (Int64) — lifetime successful Add-mode logs.
- `ratingPromptDistinctLogDayCount` (Int64) + `ratingPromptLastLogDayStart` (Double) — distinct calendar days a log occurred (incremented when a log lands on a new `Calendar.current.startOfDay`).
- `ratingPromptFirstEligibleAt` (Double, optional) — one-shot gate for `rating_prompt_eligible`.
- `ratingPromptLastRequestedVersion` (String, optional) — once-per-version guard.

*Why a separate type, not `AppSettings`:* these are non-user-facing eligibility counters, not settings; keeping them out of `AppSettings` keeps that type focused and the eligibility logic independently testable with an in-memory `KeyValueStore`.
*Alternative rejected:* deriving counts from the SwiftData `ExpenseItem` store. Rejected because "distinct **logging** days" needs the log *event* time, and backdated/edited expenses would pollute a `date`-based derivation; a log-time counter is both simpler and correct.

### D3. Trigger only on Add-mode log, active budget, non-deficit
The hook fires only from `AddEditExpenseViewModel.save` success in **Add** mode. The view computes `remainingIsNonNegative` from the existing budget calculator (the same value the detail header shows) and whether the budget is in the **active** lifecycle state, and passes both to `recordExpenseLogged`. Edits, deletes, add-funds-only flows, and logs on paused/pre-start/post-end budgets advance counters? — **No**: only successful Add-mode expense logs increment counters and can trigger, and the trigger additionally requires active + non-deficit. This keeps the ask anchored to a genuine "I just used the core feature and I'm in good shape" moment.

*Why count only Add-mode logs:* matches the F-6.03 "meaningful usage = logging" definition; avoids inflating eligibility via edits/deletes.

### D4. Eligibility thresholds as fixed constants (balanced profile)
`installAge ≥ 7 days` AND `distinctLogDayCount ≥ 3` AND `loggedExpenseCount ≥ 10` AND `remainingIsNonNegative` AND `isActiveBudget` AND `lastRequestedVersion != currentAppVersion`. Constants live in one place in the coordinator. Eligibility (the first five) and the version guard are evaluated together at request time; `rating_prompt_eligible` fires the first time the first-five become true (independent of the version guard) so the analytics "when do users become eligible" question is answerable even if we later choose not to ask.

### D5. Analytics events pulled forward from Phase 2
Add `rating_prompt_eligible` and `rating_prompt_requested` to `AnalyticsEvent`, the `time_since_first_eligible_bucket` property, and the `rating_prompt_first_eligible_at` / `rating_prompt_last_requested_at` people properties via the existing `MixpanelAnalyticsClient` people-property refresh path. Both events are consent-gated like all product events and carry only categorical/bucketed values (PII contract §5 unchanged). Docs (analytics-spec.md §12, product-features-planning.md F-6.03) get updated to note these two events ship with this change, not F-8.03.

## Risks / Trade-offs

- **KV-store eventual consistency** → two devices could each request for the same version before `ratingPromptLastRequestedVersion` syncs. Mitigation: Apple's own per-device/Apple-ID throttle still caps real presentations; user harm is negligible (at worst one extra silent request).
- **`requestReview` may no-op** (Apple decides not to show) yet we still record `lastRequestedVersion` → a user could be "spent" for a version without seeing a dialog. Accepted: within Apple's throttle a re-request wouldn't show anyway, and we cannot detect the no-op. Documented in F-6.03.
- **Counting only log-time means a brand-new install of an existing iCloud account starts counters fresh on that install for the day-count**, but `installedAt` and lifetime count sync. Acceptable; eligibility is forgiving, not exact.
- **Distinct-day counting across timezone travel / DST** uses `Calendar.current.startOfDay`; an edge user crossing date lines might get an extra "distinct day." Negligible and only ever makes a user eligible slightly sooner.
- **No simulator/TestFlight validation of the dialog itself.** Mitigation: the coordinator/eligibility math is fully unit-tested; the dialog is verified manually in production. Documented.

## Migration Plan

Additive only. New KV keys default to "absent" → `installedAt` is stamped on first launch post-update; existing users effectively start their 7-day / count windows at upgrade time (acceptable — they become eligible after genuine post-update usage). No rollback concerns; removing the feature would just stop reading the keys.

## Open Questions

None blocking. (Threshold tuning is intentionally deferred to post-launch analytics / the F-8.03 feature-flag seam.)
