# Proposal: recents-rework-spec-sync

## Why

The F-7.04 Recents UX was reworked on branch `recents-ux-workshop` (PR #244) through a workshop process: code, copy, translations, and unit tests are finalized and green, but the main spec (`add-edit-expense-screen`) and docs still describe the pre-rework behavior — section above the Amount card, name-only dedup, single 15-tile cap, unconditional fill-on-tap. This change formalizes the shipped behavior so specs and docs stop drifting from code.

## What Changes

All behavior below is already implemented; this change writes the delta specs and syncs docs. One small code touch rides along (analytics bucket relabel, see Impact).

- **Placement**: the Recents section renders **below the Description card** (card order Amount → Description → Recents → When), turning the description-as-filter into an input-above/suggestions-below autocomplete idiom. Previously specified as "above the Amount card".
- **Algorithm**: per-name base tile (most recent amount) is unchanged, but a name can now surface **extra amount-variant tiles** when an exact (name, amount) pair recurred ≥ `variantRecurrenceThreshold` (3) times, capped at `maxVariantsPerName` (2) extras, clustered after their base tile. One-off price jitter still collapses to a single tile.
- **Caps decoupled**: the memoized candidate set is now a **search corpus** (cap 200) distinct from the **display cap** (30, applied to both the unfiltered row and filtered results). Typing filters the corpus, so names beyond the visible row surface on search. Previously corpus == display == 15.
- **Smart-apply provenance rule**: a tile tap always fills the description and resets Add Funds, but fills the **amount only when the draft amount is empty or tile-seeded** — a user-typed amount survives the tap (and survives suggestion-switching). Previously the tap wrote the amount unconditionally.
- **Double-tap full replace**: a double-tap on a tile (sighted) or the "Replace amount and description" VoiceOver custom action overrides provenance and writes both fields. The double-tap's first tap runs the normal smart apply (delay-free single taps via `simultaneousGesture`); no second analytics event fires.
- **Description clear button**: the Description field shows a trailing ✕ (mirroring `CurrencyAmountField`) whenever non-empty; clearing resets the Recents filter.
- **Analytics bucket relabel**: `recents_visible_count`'s top bucket label `"8-15"` is wrong under the 30-tile display cap; relabel to `"8+"` (app is unreleased, so no data-continuity concern).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `add-edit-expense-screen`: requirement-level changes to the F-7.04 Recents requirements — section placement (below Description), candidate algorithm (recurrence-gated amount variants; corpus vs display caps), tap semantics (amount-provenance smart apply; double-tap/VoiceOver full replace), accessibility (full-replace custom action), localization key inventory (two new keys), analytics emission note (no second event on full replace, top bucket `"8+"`), and the Description field's trailing clear button under the form-fields requirement.

## Impact

- **Specs**: `openspec/specs/add-edit-expense-screen/spec.md` (via delta in this change).
- **Docs**: `docs/product-features-planning.md` F-7.04 (ranking/edge-cases notes describe name-only collapse; needs variants, caps, provenance, double-tap, and status pointer to this change); `docs/analytics-spec.md` §3 `recents_visible_count` bucket row (`8-15` → `8+`); `docs/tech-design-doc.md` mentions Recents — verify and update if it pins the old placement/algorithm.
- **Code**: already merged into PR #244 (`AddEditExpenseView.swift`, `AddEditExpenseViewModel.swift`, `AddEditExpenseView+RecentsSection.swift`, `Localizable.xcstrings`, two test files). The only new code in this change: `recentsVisibleCountBucket` top-bucket relabel in `Logging/Analytics+DomainExtensions.swift` plus its `RecentsBucketingTests` expectation.
- **Out of scope** (future candidates, not requirements): `expense_recent_reused` properties for preserved-vs-filled amount and full-replace taps; keyboard-accessory suggestion strip.

## Doc alignment

- `docs/main-prd.md`: no conflicts — the rework strengthens Guiding Principles #2/#3 (minimal input; clarity) and §6.8 concerns are satisfied (a11y labels/action, 49-locale translations shipped, analytics reviewed). No PRD edits needed.
- `docs/product-features-planning.md` F-7.04: **drifts** — Edge Cases "Ranking" note ("duplicates by description collapse to the most recent occurrence") predates variants; acceptance criteria "Reuse name + amount … populates both" predates the provenance rule. Update tasked in this change. The AC's own "Subject to revision once usage data accrues" anticipated this.
- `docs/analytics-spec.md`: **drifts** on the `recents_visible_count` bucket boundaries. Update tasked in this change.
- `docs/tech-design-doc.md`: verify-and-update task included.
