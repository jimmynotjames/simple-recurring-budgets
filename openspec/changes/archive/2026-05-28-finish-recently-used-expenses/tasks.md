## 1. Source-string keying

- [x] 1.1 Register `addEditExpense.recents.section.title` ("Recents") in `Localizable.xcstrings` with a translator-friendly `comment:` explaining it labels the F-7.04 Recents card.
- [x] 1.2 Register `addEditExpense.recents.empty.noMatches` ("No matches") with a comment explaining it appears when the typed query filters the Recents row to zero results.
- [x] 1.3 Register `addEditExpense.recents.tile.accessibilityLabel` as a parameterized key (name + formatted amount) with a comment naming each argument and the surface (mirror the existing `addEditExpense.paused.caption.format` precedent for parameterized keys).
- [x] 1.4 Register `addEditExpense.recents.tile.accessibilityHint` ("Fills the amount and description for review.") with a comment.
- [x] 1.5 Register `addEditExpense.recents.empty.accessibilityLabel` ("No matching recent expenses") with a comment distinguishing it from the visible "No matches" copy.
- [x] 1.6 Replace every bare-literal `Text("…")` and inline string in `simple-recurring-budgets/Views/AddEditExpenseView+RecentsSection.swift` with the corresponding `String(localized:defaultValue:comment:)` call. Verify via grep that no bare literals remain on the user-visible Recents surface.

## 2. Accessibility

- [x] 2.1 Add a composed `accessibilityLabel` to the Recents tile Button that interpolates the localized parameterized key with the suggestion's name and its `Decimal.formatted(currencyCode:display:)` rendering.
- [x] 2.2 Add `accessibilityHint` to the Recents tile Button using the localized hint key.
- [x] 2.3 Add `.accessibilityElement(children: .ignore)` on the tile Button if needed to suppress VoiceOver from announcing each `Text` child separately, then rely on the composed label/hint.
- [x] 2.4 Add `.accessibilityHidden(true)` to the trailing `arrow.right` icon in `recentsHeader` (decorative — VoiceOver's scroll-container behavior reproduces the meaning).
- [x] 2.5 Add `accessibilityLabel` to the "No matches" `Text` in `recentsNoMatchesPlaceholder` using the localized empty-label key.
- [x] 2.6 Add `.accessibilityHidden(true)` to the phantom-content sizing `VStack` inside `recentsNoMatchesPlaceholder` (it is a layout anchor, not content).
- [x] 2.7 Replace the `private static var recentsTileMaxWidth: CGFloat { 180 }` constant with `@ScaledMetric(relativeTo: .subheadline) private var recentsTileMaxWidth: CGFloat = 180`. Update the call site accordingly (the property is no longer static).
- [x] 2.8 Wrap the tile inner padding constants (`.padding(.horizontal, 14)`, `.padding(.vertical, 11)`) with `@ScaledMetric(relativeTo: .subheadline)` properties.
- [x] 2.9 Spot-check the Recents previews at `.dynamicTypeSize(.xxxLarge)` in the Xcode canvas; confirm tile name + amount remain legible and the row still scrolls. Add a `Quick picks — xxxLarge type` preview to the existing preview block.

## 3. Mixpanel analytics — `expense_recent_reused` event (F-8.02)

- [x] 3.1 Add an `expenseRecentReused` case to `AnalyticsEvent` (mapping to the wire-format string `expense_recent_reused`).
- [x] 3.2 Add `recentsVisibleCount`, `recentsTapPosition`, and `nameQueryLength` cases to `AnalyticsProperty`.
- [x] 3.3 Add bucketing helpers (e.g., `recentsTapPositionBucket(position: Int) -> String`) following the same shape as the existing `timeSinceBudgetCreatedBucket`. Bucket boundaries per `design.md` D3: position {0, 1, 2-4, 5+}; visible count {1, 2-3, 4-7, 8-15}; query length {0, 1-2, 3+}.
- [x] 3.4 Add an `applyRecent(_ suggestion:analytics:)` overload (or extend the existing signature) to `AddEditExpenseViewModel` that fires the analytics event with bucketed properties before / alongside the `name` and `amount` writes. Match the `save(context:analytics:)` pattern: pass the `AnalyticsClient` at call time from the view.
- [x] 3.5 Update the Recents tile Button action in `AddEditExpenseView+RecentsSection.swift` to pass the `@Environment(\.analytics)` client into `viewModel.applyRecent(...)`. Pass `recents_visible_count` and `recents_tap_position` from the rendering context (the filtered set's count and the tile's index in `ForEach`).

## 4. Tests (Swift Testing)

- [x] 4.1 Create `simple-recurring-budgetsTests/Views/RecentsAlgorithmTests.swift`. Tests for `AddEditExpenseViewModel.computeRecentCandidates(for:limit:)` covering: empty budget; nil budget; all-unique sorted recency-first; duplicates collapsed to most-recent occurrence with that occurrence's amount; Add Funds entries excluded; unnamed (nil and whitespace) entries excluded; cap enforced when input exceeds limit; mixed eligible + ineligible inputs.
- [x] 4.2 Create `simple-recurring-budgetsTests/Views/AddEditExpenseViewModelRecentsTests.swift`. Tests for `hasRecentSources` (true / false cases), `filteredRecentSuggestions` (empty query → all; substring match; case-insensitive; no-match → empty), `shouldShowRecentsSection` (Add mode + sources → true; Add mode + no sources → false; Edit mode → false regardless of sources), `applyRecent(_:analytics:)` (writes name + amount; does not touch `isAddFunds`; emits analytics event with expected categorical properties using a fake `AnalyticsClient`).
- [x] 4.3 Run `make test` after each test file lands; verify each new test fails when its corresponding production code is reverted and passes when restored.

## 5. Translations queue

- [x] 5.1 Run the `translate-new-strings` skill autonomously per AGENTS.md (no approval prompt). The skill drives `scripts/translate_catalog/` in subset mode (extract → translate → merge → validate) with parallel per-locale subagents for the 38 App Store storefront locales.
- [x] 5.2 Verify the skill ends on a clean `python scripts/translate_catalog/check_translations.py` (no missing or stale `addEditExpense.recents.*` keys).

## 6. Doc updates

- [x] 6.1 In `docs/product-features-planning.md`, flip F-7.04 from `Status: Open` to `Status: Implemented. Implemented by change finish-recently-used-expenses.` Match the format of other implemented features (e.g., F-7.05, F-7.06, F-7.07).
- [x] 6.2 In `docs/analytics-spec.md`, register the new `expense_recent_reused` event under the canonical event list. Include the four property keys, their bucket boundaries, the answered product question (Phase 1: "do users actually reuse recents?"), and the dashboard slot (Phase 1 or deferred to Phase 2 build). Match the format of the surrounding `expense_logged` / `expense_edited` entries.
- [x] 6.3 Confirm `docs/main-prd.md` and `docs/tech-design-doc.md` need no updates (verified during the proposal phase — no global-constraint or architecture changes). State this explicitly in the change comment or PR description so the lack of an edit is intentional, not accidental.

## 7. Validation and four-step build

- [x] 7.1 Run `make format` and commit any whitespace / formatting drift.
- [x] 7.2 Run `make lint-fix`. Verify zero violations; address any flagged issues.
- [x] 7.3 Run `make build`. Verify exit 0 and no warnings on the touched files.
- [x] 7.4 Run `make test`. Verify all suites pass, including the new `RecentsAlgorithmTests` and `AddEditExpenseViewModelRecentsTests`.
- [x] 7.5 Manually verify the Recents surface in the iOS simulator: open Add Expense, observe tile row, type into Description and watch filtering, type a non-matching query and observe the stable "No matches" placeholder, tap a tile and confirm both Amount and Description fill (and the Amount field's bidirectional sentinel correctly updates the display).
- [x] 7.6 Manually verify VoiceOver behavior with the iOS simulator's accessibility inspector enabled: confirm each tile is announced as one combined element with the composed label and hint, the swipe icon is silent, and the "No matches" placeholder is announced with its accessibility label.
