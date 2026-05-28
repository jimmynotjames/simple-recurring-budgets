## Context

The F-7.04 Recents surface is functionally complete: the hash-then-sort algorithm, the memoized candidate cache on `AddEditExpenseViewModel`, the horizontal tile row, the empty-state policy (true-empty hides, filter-empty shows "No matches" placeholder), and the bidirectional `CurrencyAmountField` sentinel pattern all shipped during the workshop and have been manually verified by the user. The four main-prd.md §6.8 cross-cutting concerns — accessibility, source-string keying, translations queue, and Mixpanel analytics — were intentionally deferred until UX direction stabilized. They are now the only thing standing between F-7.04 and "implemented."

The shipping `AddEditExpenseView` already has well-established conventions for each of these concerns (existing `String(localized:defaultValue:comment:)` keys under the `addEditExpense.*` namespace; `accessibilityLabel`/`accessibilityHint` on the destructive `Delete Expense` button and existing form controls; the `expense_logged` / `expense_edited` analytics events with their categorical properties), so this change leans on those patterns rather than inventing new ones.

## Goals / Non-Goals

**Goals:**

- Satisfy all four cross-cutting concerns for the Recents surface to the same bar as the surrounding form.
- Add Swift Testing coverage for the new algorithm and VM API surface so regressions surface in CI before they reach users.
- Flip F-7.04 from `Open` to `Implemented` in `docs/product-features-planning.md` as part of the same change, so the spec and code don't drift.
- Land the new `expense_recent_reused` analytics event with the property surface defined alongside `expense_logged` / `expense_edited` in `docs/analytics-spec.md`.

**Non-Goals:**

- Re-opening UX decisions made during the workshop (tile width cap, "No matches" copy, dedup-by-name-most-recent rule, cap of 15, horizontal-scroll choice). Those are locked.
- Adding a Phase 1 dashboard for `expense_recent_reused`. The event lands now; the dashboard work belongs in the broader F-8.02 dashboard build.
- Refactoring `CurrencyAmountField` further. The sentinel pattern shipped during workshop and is correct; this change only adds tests around it.
- Adding a "clear recents" or "manage recents" affordance. F-7.04 acceptance criteria explicitly say the feature is not user-configurable (per UX Simplicity and the "Minimal" Settings directive).
- Frequency-weighted ranking, cross-budget recents, or any of the OPEN spec items the workshop closed as "subject to revision once usage data accrues."

## Decisions

### D1 — Extend `add-edit-expense-screen`, do not introduce a new capability

The Recents surface lives entirely inside the Add/Edit Expense screen and shares its data, state container, and presentation rules. Introducing a separate capability would duplicate the screen-level context (Add-mode-only, ties to the budget the VM is bound to, etc.) for one cohesive feature. The new requirements slot cleanly into the existing screen capability.

*Alternative considered:* a new `recently-used-expenses` capability scoped to "the suggestion-and-reuse subsystem." Rejected because the subsystem has no independent presentation surface — there is no recents screen, no recents settings, no recents-only API. It is a section of one form.

### D2 — Analytics event fires from the ViewModel, not the view-layer button action

The existing `expense_logged` and `expense_edited` events are emitted from `AddEditExpenseViewModel.save(context:analytics:)`, where the view passes the `AnalyticsClient` at call time. The recents-tap event follows the same shape: a new VM method (`applyRecent(_:analytics:)` or analogous overload) emits the event. This keeps the action's single source of truth in the VM and means tests can verify event emission without spinning up a SwiftUI view.

*Alternative considered:* emitting from the button's `action` closure in `AddEditExpenseView+RecentsSection.swift`. Rejected — this would split where actions emit events between the VM (save/edit) and the view (recents tap), making it easy to forget the convention next time. Single source of truth wins.

### D3 — Event name `expense_recent_reused`, properties strictly categorical

The event represents "a recent suggestion was applied to the draft." Properties:

- `period` — the budget's `BudgetPeriod` enum, analytics-mapped (matches `expense_logged`).
- `recents_visible_count` — bucketed count of how many tiles were visible when the tap happened (`1`, `2-3`, `4-7`, `8-15`). Answers "do users tap into a dense or sparse recents row?" without enabling N-of-1 reidentification.
- `recents_tap_position` — 0-indexed position of the tapped tile (`0`, `1`, `2-4`, `5+`). Answers the canonical "do users overwhelmingly tap the first one?" question for ranking validation.
- `name_query_length` — bucketed length of the typed name query at tap time (`0`, `1-2`, `3+`). Answers "is filter-then-tap a real flow vs. open-and-tap?"

No PII rule (analytics-spec.md §2.1): never the expense name string, never the amount value, never the position-as-amount-tier. All categorical.

*Alternative considered:* a richer event with raw counts and the typed query length verbatim. Rejected because §2.1 requires bucketing or categoricals; the bucket boundaries above are deliberately coarse to avoid pseudo-identifying signatures (e.g., "typed 7 chars on a daily budget" is too specific).

### D4 — Localization keys land under the existing `addEditExpense.*` namespace

The shipping form uses keys like `addEditExpense.section.amount`, `addEditExpense.field.amount.placeholder`, `addEditExpense.action.delete`. The Recents surface adds:

- `addEditExpense.recents.section.title` → "Recents"
- `addEditExpense.recents.empty.noMatches` → "No matches"
- `addEditExpense.recents.tile.accessibilityLabel` → composed label with name + amount (parameterized; the existing `paused.caption.format` key precedents the parameterized pattern)
- `addEditExpense.recents.tile.accessibilityHint` → "Fills the amount and description for review."
- `addEditExpense.recents.empty.accessibilityLabel` → "No matching recent expenses"
- `addEditExpense.recents.scrollAffordance.accessibilityLabel` → "More recents — swipe to scroll" (only used if the arrow icon is exposed to VoiceOver; see D6 below for the alternative of hiding it)

Each `comment:` will be translator-friendly: explain the surface, parameter meaning, and any relevant context (e.g., "F-7.04 Recents row; argument 1 is the expense name, argument 2 is the formatted amount").

### D5 — Run the translate-new-strings pipeline autonomously, per AGENTS.md

Adding keys to `Localizable.xcstrings` invalidates 38 storefront locales' translation state. The plan SHALL include a task that runs the project's `translate-new-strings` skill (extract → translate → merge → validate) via the temp-file invocations defined in `scripts/translate_catalog/`. The skill ends on a clean `check_translations.py`. Per the global memory `feedback_localization_autonomous`, this runs without prompting.

### D6 — Dynamic Type strategy: `@ScaledMetric` for tile width and padding; hide the swipe icon from VoiceOver

The current tile geometry uses hard-coded constants (`tileMaxWidth = 180`, `padding(.horizontal, 14)`, `padding(.vertical, 11)`). At larger Dynamic Type sizes, the two-line subheadline content grows but the frame doesn't, causing truncation that the workshop never intended. The fix: wrap each constant with `@ScaledMetric(relativeTo: .subheadline)` so the geometry scales with type.

The trailing `arrow.right` icon is decorative (its "more in this direction" meaning is reproduced by VoiceOver's natural scroll-container behavior when the user reaches the row's end). Hide it with `.accessibilityHidden(true)` rather than introducing a VoiceOver label that announces "right arrow" — the announcement adds noise without information.

The section header `Text("Recents")` already participates in the GroupBox's labeling semantics, so no additional VoiceOver treatment is needed for the title itself.

### D7 — Tests target the algorithm and the VM API; not the SwiftUI view, not the field's sentinel

The two layers worth exercising in unit tests:

1. **`AddEditExpenseViewModel.computeRecentCandidates(for:limit:)`** — pure, static, easy to drive with constructed in-memory `Budget` + `ExpenseItem` graphs. Covers sort, dedup, exclusions, cap, edge cases (nil budget, empty budget, all-excluded budget).
2. **`AddEditExpenseViewModel`'s recents API** (`hasRecentSources`, `filteredRecentSuggestions`, `shouldShowRecentsSection`, `applyRecent(_:)`) — driven by constructing VMs in Add and Edit modes and asserting return values / mutation effects.

The `CurrencyAmountField` sentinel logic is a SwiftUI-lifecycle property, not a pure function. Asserting "an external write triggers a re-seed; an internal write does not" requires either driving the view's `body` or extracting the rule into a pure helper. The latter is invasive for marginal coverage. *Decision:* skip unit tests for the sentinel; rely on the workshop's manual verification and the algorithmic property's obvious correctness. If a future regression suggests we got this wrong, factor a pure helper out.

The view itself is exercised by the existing `#Preview` set (5 previews covering Light/Dark/Empty/Filtering/Filled and the new long-name truncation case). Snapshot tests are not currently in the project's testing repertoire and aren't being added here.

## Risks / Trade-offs

- **Bucket boundaries for `recents_tap_position` may obscure the "do users tap the first one?" signal if the first-position bucket is too wide.** → Mitigation: bucket `0` and `1` as separate values (not `0-1`); coarser only at higher positions.
- **`@ScaledMetric` interactions with `LazyVGrid` were dropped from the design, but the horizontal scroll row uses no grid — single-row `HStack` — so this risk is low.** → No mitigation needed; flagged for awareness if the layout ever shifts back to a grid.
- **The `translate-new-strings` skill occasionally produces awkward translations for short fragments like "Recents" or "No matches" in languages without close cognates.** → Mitigation: the `comment:` field on each key includes enough surface context that the per-locale subagent can pick a natural-sounding equivalent; the pipeline's `check_translations.py` will catch placeholder mismatches even if it can't catch quality.
- **Adding `analytics: any AnalyticsClient` as a parameter to `applyRecent(_:)` changes the VM's public surface.** → The existing `save(context:analytics:)` already takes the same parameter, so the pattern is established; no consumer code outside the view uses `applyRecent` yet (the VM was introduced in the workshop). No risk of breaking other call sites.
- **`@ScaledMetric` values for very large accessibility type sizes (`accessibility1` through `accessibility5`) could push a single tile beyond the visible row width, leaving only one tile visible on screen.** → Acceptable trade-off: at those sizes, the user has explicitly traded density for legibility; horizontal scroll still works.

## Migration Plan

This is additive UI + analytics + tests; no schema migration, no data migration, no rollback considerations beyond standard "revert the PR." The new analytics event is opt-in for users in consent-required jurisdictions (per F-8.02) — same gating as every other event. The new localization keys are backward compatible (older app builds simply don't reference them).

The four-step build/test discipline from AGENTS.md applies during apply: `make format` → `make lint-fix` → `make build` → `make test`. The translations pipeline runs as its own task within apply, autonomously.
