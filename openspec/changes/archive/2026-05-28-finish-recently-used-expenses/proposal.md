## Why

F-7.04 (Recently used expenses) is functionally complete for English users with no accessibility needs — the algorithm, UI, data-layer wiring, and bidirectional `CurrencyAmountField` fix are in place and manually verified — but it has not yet satisfied the four cross-cutting ongoing concerns in main-prd.md §6.8 (accessibility, source-string keying, translations queue, Mixpanel analytics) that gate every UI-touching change. It also lacks Swift Testing coverage for the new algorithm and the field-sync sentinel pattern. Closing those gaps is what finishes the feature.

## What Changes

- **Key all user-facing strings** in the Recents section (`"Recents"`, `"No matches"`, plus VoiceOver labels and hints added by the a11y task) into `Localizable.xcstrings` under the existing `addEditExpense.recents.*` namespace, with translator-friendly `comment:` text.
- **Run the `translate-new-strings` pipeline** to ship translations for all 38 App Store storefront locales (extract → translate → merge → validate; the pipeline ends on a clean `check_translations.py`).
- **Add accessibility coverage** to the Recents surface: composed `accessibilityLabel`/`accessibilityHint` on each tappable tile that announces both the name and amount; a labeled placeholder for the "No matches" state; explicit `accessibilityHidden(true)` on the phantom-content sizing anchor and the trailing swipe-affordance icon (its meaning is announced via VoiceOver text instead); Dynamic Type review of the tile geometry (the hard-coded 180pt cap and 14×11pt padding may need `@ScaledMetric` treatment so larger type sizes still render legibly).
- **Add a Mixpanel analytics event** for the recents tile tap (working name: `expense_recent_reused`), with no-PII categorical properties only (e.g., budget period, number of recents currently visible, position of the tapped suggestion). The event should answer the Phase 1 "do users actually reuse recents?" product question; final property list lives in analytics-spec.md alongside the existing `expense_logged` and `expense_edited` events.
- **Add Swift Testing coverage** for: the static `computeRecentCandidates(for:limit:)` helper (sort order, dedup-by-name-most-recent-wins, exclusion of Add Funds entries, exclusion of unnamed entries, respect for the cap, empty / nil-budget edge cases); the `AddEditExpenseViewModel` recents API surface (`hasRecentSources`, `filteredRecentSuggestions`, `shouldShowRecentsSection`, `applyRecent(_:)`); and the `CurrencyAmountField` bidirectional sentinel (external value writes re-seed the display; user keystrokes don't trigger re-seed cascades; mid-keystroke `"1."` is preserved across an external write of an equal value).
- **Update product-features-planning.md F-7.04 status** from `Open` to `Implemented` (with the implementing change name) as part of the same code change.

## Capabilities

### New Capabilities
<!-- None — all behavior lives inside the existing add/edit expense screen capability. -->

### Modified Capabilities
- `add-edit-expense-screen`: add the F-7.04 recents surface as new requirements (Add-mode-only render, recents algorithm, tap behavior, filter-as-you-type, empty / no-match presentation, accessibility, source-string keying, analytics).

## Impact

- **Code affected:**
  - `simple-recurring-budgets/Views/AddEditExpenseView+RecentsSection.swift` — replace bare-literal `Text` calls with `String(localized:defaultValue:comment:)`; add `accessibilityLabel`/`accessibilityHint` on tiles and the no-matches placeholder; add `accessibilityHidden(true)` on the swipe icon; replace hard-coded geometry constants with `@ScaledMetric` where appropriate; wire the recents-tap analytics event from `applyRecent(_:)` or a thin view-layer wrapper.
  - `simple-recurring-budgets/Resources/Localizable.xcstrings` — new `addEditExpense.recents.*` keys + translations for 38 locales (driven by the translate-new-strings skill).
  - `simple-recurring-budgets/Logging/AnalyticsEvent.swift` (and adjacent) — register `expense_recent_reused` with its property keys.
  - `docs/analytics-spec.md` — append the new event + its property surface to the canonical event list and the Phase 1 dashboard reference.
  - `docs/product-features-planning.md` — F-7.04 status update.
  - `simple-recurring-budgetsTests/` — new `RecentsAlgorithmTests`, `AddEditExpenseViewModelRecentsTests`, and `CurrencyAmountFieldSentinelTests` suites.
- **APIs / dependencies:** No new external dependencies. Internal additions only: a new `AnalyticsEvent` case, new property keys, new localization keys.
- **Behavior unchanged for users at sheet-open time:** the visible UI does not change in this change; the only user-observable additions are VoiceOver behavior under the screen reader and (eventually) the surface working in non-English locales.

### Doc alignment

- `docs/main-prd.md` — no changes (cross-cutting concerns §6.8 already governs this work; we're satisfying it, not amending it).
- `docs/product-features-planning.md` — F-7.04 status flip from `Open` to `Implemented` (this change name). No acceptance-criteria changes; prior workshop already resolved the open edge cases via vaguer wording.
- `docs/tech-design-doc.md` — no changes (the bidirectional `CurrencyAmountField` contract shipped with the workshop work and is internal to the field; no architectural shift).
- `docs/analytics-spec.md` — append the new `expense_recent_reused` event and its property surface; reference the Phase 1 product question it answers.
