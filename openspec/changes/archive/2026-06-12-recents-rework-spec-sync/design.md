# Design: recents-rework-spec-sync

## Context

The Recents rework shipped on branch `recents-ux-workshop` (PR #244) via an explicit UX-workshop process: design decisions were made conversationally, implemented, manually verified in the simulator, and then pinned by rewritten unit tests — deliberately ahead of spec/doc formalization. This change is the formalization pass. The code in PR #244 is the reference implementation; the delta spec describes it, not a future plan. The only code this change itself introduces is a one-line analytics bucket relabel.

Implementation reference (all on PR #244):
- `simple-recurring-budgets/Views/ExpenseForm/AddEditExpenseView.swift` — card order; Description clear button.
- `simple-recurring-budgets/Views/ExpenseForm/AddEditExpenseView+RecentsSection.swift` — algorithm (`computeRecentCandidates`), caps, filter, `applyRecent`, `applyRecentFullReplace`, double-tap gesture, VoiceOver custom action, previews.
- `simple-recurring-budgets/Views/ExpenseForm/AddEditExpenseViewModel.swift` — `AmountProvenance` enum and the `amount` property observer.
- Tests: `RecentsAlgorithmTests.swift`, `AddEditExpenseViewModelRecentsTests.swift`.

## Goals / Non-Goals

**Goals:**
- Delta-spec the shipped Recents behavior in `add-edit-expense-screen` so the main spec merges clean at archive.
- Sync `docs/product-features-planning.md` F-7.04, `docs/analytics-spec.md` bucket row, and verify `docs/tech-design-doc.md`.
- Relabel `recentsVisibleCountBucket`'s top bucket `"8-15"` → `"8+"` (code + test + analytics-spec row), removing the mislabel introduced by the 30-tile display cap.

**Non-Goals:**
- No UX, copy, or behavior changes beyond the bucket label. The provenance rule, caps, variants, and gestures are settled.
- No new analytics properties (preserved-vs-filled, full-replace tap) — recorded as future candidates in the proposal, not specced.
- No keyboard-accessory suggestion strip.

## Decisions

Decisions below were made during the workshop and are recorded here with rationale; the delta spec encodes them as requirements.

1. **Placement below Description, not above Amount.** The cache job (browse-and-tap) tolerates any visible slot; the autocomplete job (type-to-filter) requires adjacency to its input. Asymmetric needs → the autocomplete position wins, and the Amount card reclaims the top slot, strengthening amount-first quick logging. Alternative (suggestions both at top and near the field via a keyboard accessory) rejected as a second surface to maintain without evidence of need.
2. **Recurrence gate ≥ 3, max 2 extra variants per name.** The base most-recent amount per name always shows, so the gate only delays *extra* tiles. ≥ 2 lets coincidental round-number repeats mint permanent tiles; ≥ 3 filters coincidence while true fixtures qualify within weeks. Naive `(name, amount)` dedup rejected: price jitter would flood the row.
3. **Corpus (200) decoupled from display (30).** Filtering the displayed row made search shallow by construction. The corpus is memoized once at sheet-open (O(N) scan already paid); per-keystroke filter is O(200) folded substring matches. Caps are pinned in `capConstants_pinWorkshopDecisions` as deliberate product numbers.
4. **Amount provenance (`.empty` / `.userTyped` / `.tileSeeded`) decides fill-vs-preserve.** Fresher user input beats staler suggestion data; the silent-overwrite failure (wrong amount saved unnoticed) is costlier than the visible not-applied failure. Echo writes from `CurrencyAmountField`'s re-seed cycle are excluded by an equality guard; tile seeds by a suppression flag. Alternative (always overwrite, rely on user noticing) rejected for the silent-error asymmetry.
5. **Double-tap full replace via `simultaneousGesture`, not counted `onTapGesture`.** A counted gesture delays every single tap ~300 ms waiting for a second tap — unacceptable for the speed-first flow. Consequence (accepted): the double-tap's first tap runs the normal smart apply before the second upgrades it; end state converges. VoiceOver gets a custom action because VO's double-tap is its activation gesture.
6. **No second analytics event on full replace.** The pair's first tap already emitted `expense_recent_reused`; a second emission would double-count reuse.
7. **Bucket relabel `"8-15"` → `"8+"` rather than adding `"16-30"`.** The product question is dense-vs-sparse row; coarse buckets are deliberate (anti-fingerprinting note in analytics-spec). The app is unreleased, so no historical-data continuity concern.

## Risks / Trade-offs

- [Delta merges against a long existing spec file] → MODIFIED entries copy entire requirement blocks verbatim-then-edited; requirements whose names became inaccurate are REMOVED + ADDED pairs rather than renames, so the sync has no header-matching ambiguity.
- [Bucket relabel touches code in a "specs-only" change] → scoped to one switch-case label and one test expectation; called out in the proposal so it can be struck if the user prefers a pure doc sync.
- [Docs edits could drift from the delta spec wording] → tasks sequence spec first, then docs derived from it.

## Open Questions

(none — behavior is shipped and pinned by tests)
