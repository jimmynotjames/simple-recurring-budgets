## 1. Persisted eligibility state

- [x] 1.1 Add a `RatingPromptState` type backed by the existing `KeyValueStore` abstraction (default `NSUbiquitousKeyValueStore.default`), mirroring `AppSettings`'s read/write/observe pattern, with keys: `ratingPromptInstalledAt`, `ratingPromptLoggedExpenseCount`, `ratingPromptDistinctLogDayCount`, `ratingPromptLastLogDayStart`, `ratingPromptFirstEligibleAt` (optional), `ratingPromptLastRequestedVersion` (optional).
- [x] 1.2 Stamp `ratingPromptInstalledAt` once on first access; never overwrite. Ensure none of these keys reuse or depend on `AppSettings.analyticsFirstOpenAt` or `analyticsOptIn`.

## 2. Decision core (coordinator) + unit tests

- [x] 2.1 Add `RatingPromptCoordinator` (`@MainActor @Observable`) holding `RatingPromptState`, a transient `isRequestPending: Bool`, and the balanced-profile threshold constants (install age ≥ 7d, distinct log days ≥ 3, lifetime logs ≥ 10).
- [x] 2.2 Implement `recordExpenseLogged(isActiveBudget:remainingIsNonNegative:now:appVersion:)`: advance counters (lifetime count; distinct-day count when the log lands on a new `Calendar.current.startOfDay`), evaluate eligibility, set `isRequestPending` when eligible + active + non-deficit + not-yet-asked-this-version, and fire the one-shot `rating_prompt_eligible` (set `ratingPromptFirstEligibleAt`).
- [x] 2.3 Implement `consumePendingRequest(appVersion:)`: record `ratingPromptLastRequestedVersion`, clear `isRequestPending`, fire `rating_prompt_requested`, refresh the `rating_prompt_last_requested_at` people property.
- [x] 2.4 Swift Testing unit suite over an in-memory `KeyValueStore`: covers every scenario in `specs/rating-prompt/spec.md` — thresholds (each boundary), deficit log not eligible, non-active log not eligible, once-per-version guard, install-date stamped-once, distinct-day increment logic, one-shot eligible event, version recorded even when outcome unobservable.

## 3. Expense-save hook

- [x] 3.1 In `AddEditExpenseView`'s Add-mode success path, after `viewModel.save(...)` succeeds, compute `isActiveBudget` and `remainingIsNonNegative` from the existing budget calculator and call `coordinator.recordExpenseLogged(...)`. Do not notify on Edit mode, delete, or save failure; leave existing `expense_logged`/dismissal/error behavior unchanged.

## 4. Root presenter + environment wiring

- [x] 4.1 Add a `.ratingPromptPresenter()` view modifier that reads `@Environment(\.requestReview)` and observes the coordinator; when `isRequestPending` and `scenePhase == .active`, call `requestReview()` then `coordinator.consumePendingRequest(appVersion:)`.
- [x] 4.2 Inject `RatingPromptCoordinator` into the environment in `simple_recurring_budgetsApp` and apply `.ratingPromptPresenter()` once at `RootView`.

## 5. Analytics events (pulled forward from Phase 2)

- [x] 5.1 Add `AnalyticsEvent.ratingPromptEligible = "rating_prompt_eligible"` and `ratingPromptRequested = "rating_prompt_requested"`; add property `timeSinceFirstEligibleBucket = "time_since_first_eligible_bucket"`.
- [x] 5.2 Add people-property refresh for `rating_prompt_first_eligible_at` and `rating_prompt_last_requested_at` via the existing `MixpanelAnalyticsClient` people-property path; confirm both events drop when opted out and carry no PII (§5 contract).

## 6. Cross-cutting concerns (main-prd.md §6.8)

- [x] 6.1 **Accessibility (Dynamic Type / VoiceOver):** N/A — no new in-app UI; the review dialog is the system-provided native sheet and the existing Settings button is unchanged.
- [x] 6.2 **Localized source strings:** N/A — no new user-facing strings (native dialog is system-localized).
- [x] 6.3 **Translations pipeline:** N/A — confirm `Localizable.xcstrings` is untouched; no `translate-new-strings` run needed (verify with `scripts/translate_catalog/check_translations.py` only if any key changed).
- [x] 6.4 **Mixpanel user-action analytics:** covered by §5 above (`rating_prompt_eligible`, `rating_prompt_requested`).
- [x] 6.5 **UI test screen objects (main-prd.md §6.8.5):** N/A — no navigation/label/toolbar/sheet-route change; the native dialog is not XCUITest-testable. No screen object update.

## 7. Documentation updates

- [x] 7.1 `docs/product-features-planning.md` — flip F-6.03 status to **Implemented** (record the implementing change `rating-prompt`); update the Analytics AC to state the two events ship with this change, not F-8.03.
- [x] 7.2 `docs/analytics-spec.md` — §12 / §4.4: note `rating_prompt_eligible` and `rating_prompt_requested` are shipped by F-6.03 (`rating-prompt`) rather than deferred to F-8.03; bump version + revision history.
- [x] 7.3 `docs/tech-design-doc.md` — §4.5 KV-key table: add the five `ratingPrompt*` keys (type + semantics, "not analytics-gated"); add a one-line F-6.03 cross-reference.

## 8. Build, test, verify

- [x] 8.1 Run the four-step procedure (AGENTS.md): `make format` → `make lint-fix` → `make build` → `make test`.
- [x] 8.2 Verify implementation and specs against the three `docs/*.md` files; fix any drift before archive. Manually note that the native dialog itself is validated only in a production/App Store build (not simulator/TestFlight).
