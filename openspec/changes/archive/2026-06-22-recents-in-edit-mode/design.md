## Context

The Recents surface (F-7.04) shipped as an Add-only affordance. `AddEditExpenseViewModel.shouldShowRecentsSection` is `!isEditing && hasRecentSources`, and the `add-edit-expense-screen` spec pins "Edit mode never shows the Recents section." The corpus (`cachedRecentCandidates`) is, however, **already computed in Edit mode** at sheet open — the section is simply gated off — so the algorithm, filtering, tap apply, double-tap full replace, and VoiceOver action all already exist and are mode-agnostic.

This change reuses that machinery and only changes (a) when the section is visible in Edit mode and (b) the provenance of the edited amount so a single tap can't silently overwrite real data.

## Goals / Non-Goals

**Goals:**
- Show Recents in Edit mode when the Description is (or becomes) blank, then keep it shown for the rest of the sheet's lifetime.
- Reuse Add mode's affordances/UI/filtering verbatim once revealed.
- Make a single tile tap in Edit mode overwrite the Description only; reserve amount overwrite for the explicit double-tap / VoiceOver full replace (or clearing the amount first).

**Non-Goals:**
- No change to the Recents algorithm, caps, recurrence-gated variants, or filter (the de-dup behavior is explicitly left as-is).
- No exclusion of the edited row from its own corpus (the "self-tile quirk" is intentionally left in).
- No focus-based trigger, no `@FocusState`, no `CurrencyAmountField` / `DecimalInputField` changes.
- No change to Add-mode behavior.
- No new user-facing strings.

## Decisions

1. **Blank-Description gate with a one-way reveal latch (vs always-on, vs focus-triggered).**
   A new observed `recentsRevealedInEdit` flag drives visibility in Edit mode. It is set `true` when the trimmed Description is empty — at `init(editing:)` time and whenever `name`'s `didSet` observes an empty trimmed value — and is never reset to `false`. Visibility becomes `hasRecentSources && (!isEditing || recentsRevealedInEdit)`.
   - *Always-on in Edit* was rejected because it clutters the common edit (amount/date tweaks where the description is fine), shows the row pre-filtered to the current name, and surfaces the edited row as its own suggestion on open.
   - *Focus-triggered reveal* was rejected: it requires plumbing focus out of the UIViewRepresentable amount field (no resign hook exists on `DecimalInputField`), and a tile tap resigns focus, collapsing the section the instant it is used.
   - The latch is essential: without it, tapping a tile fills the Description (now non-empty) and the row would vanish mid-use. "Empty description unlocks suggestions for the rest of the session" is the user-facing model.

2. **Protect the edited amount via `amountProvenance = .userTyped` seed.**
   In Edit mode the seeded `amount` is real user data. The existing smart-apply rule (`applyRecent` writes `amount` only when provenance is `.empty` or `.tileSeeded`) already does the right thing if the edited amount is treated as user-typed. Because `init(editing:)`'s `amount = expense.displayAmount` is an initializer assignment that skips the `didSet`, provenance defaults to `.empty` today — which would let a single tap silently overwrite the amount. Setting `amountProvenance = .userTyped` after the seed in `init(editing:)` fixes this with no new branching in `applyRecent`. Single tap → Description only; double-tap full replace and the VoiceOver "Replace amount and description" action still overwrite both; clearing the amount (✕) re-arms single-tap fill. This keeps Add and Edit semantics identical except for the protected starting amount.

3. **Reuse the rendered section unchanged.** `recentsSection` / `RecentsSectionView` already key off `shouldShowRecentsSection` and the VM's filter; no view restructuring is needed beyond the visibility predicate. The filter still uses the Description as the query, so a revealed Edit-mode row filters as the user types, identical to Add.

4. **Self-tile quirk left as-is (explicit product decision).** The corpus stays sourced from all `budget.expenseItems` including the edited row. In the blank-on-open case the edited row has no name and is already excluded (unnamed entries are filtered); in the typo-clear case a tile derived from the edited row may appear and re-applying it restores the stored value — harmless and accepted.

5. **Analytics: extend `expense_recent_reused` to Edit context.** The event already fires from `applyRecent`, so it will now also fire in Edit mode. Update the `docs/analytics-spec.md` catalog description accordingly. Recommended (low-cost) parity: add a `from_screen` property (`add_sheet` / `budget_detail`) matching the other `expense_*` events, so add-vs-edit reuse is distinguishable; this is a new categorical property and requires a Revision-History entry. If the property is added, `applyRecent` must pass it from the call site's mode.

## Risks / Trade-offs

- **Diverges from "identical to Add mode" visibility** → Accepted: Edit is blank-gated + latched, Add is always-on. The trade buys less clutter and intent-gating in Edit; to a user it reads as "suggestions show when the field is empty," which is self-explanatory.
- **Single tap overwrites a visible Description without confirmation** → Mitigated: the Description is the lower-stakes field (amount is protected), the tap is reversible in place before Save, and it is exactly the requested typo/blank-fix action.
- **Self-tile re-apply in the typo path** → Accepted per decision 4; visible and reversible.
- **Pinned tests + preview encode the old Add-only behavior** → Updated in this change (`shouldShowRecentsSection_falseInEditModeEvenWithSources`, the "Recents — Edit mode (no section)" preview). UI screen objects updated if Edit-mode Recents becomes reachable in a journey.

## Migration Plan

Pure UI/VM behavior change; no schema, model, or CloudKit impact and no data migration. Rollback is reverting the visibility predicate and the provenance seed.

## Open Questions

- Whether to add the `from_screen` property to `expense_recent_reused` now (recommended) or defer it and only update the event's prose. Defaulting to adding it for analytic clarity; can be dropped to keep the change minimal.
