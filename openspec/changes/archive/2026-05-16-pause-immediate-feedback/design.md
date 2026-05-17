## Context

The pause/resume feature shipped in change `pause-resume-budget` (archived 2026-05-16) classifies pause state at **whole-period granularity**. `LifecycleClassification.isActive(period:lifecycleEvents:)` returns `true` if any lifecycle event lands inside the period, which means the period containing a `.pause` action is treated as **active** for both:

1. **Math** — `BudgetCalculator.snapshot.remaining` continues normal accrual, and the carry-over walker contributes the period's leftover into carry-over at period close.
2. **UI** — `BudgetSnapshot.lifecycleState` returns `.active`, so every view site that reads it (Budgets list row, Detail header, Detail primary slot, Add Expense date picker) shows the active presentation.

This coupling is deliberate for the math (no proration; the period was in motion when the user paused), but it bleeds into UX as a confusing "I tapped Pause and nothing visibly changed" moment. A user who creates a daily budget at 10 AM and pauses it at 10:05 AM observes zero feedback until midnight.

The fix is to decouple the two: keep period-granular classification for the math, introduce a moment-granular classification for the UI. The carry-over algorithm — already well-tested and stable — is untouched.

**Constraints:**
- No data-model changes. `LifecycleEvent` rows remain the source of truth.
- No regression in the carry-over walker (the math the snapshot exposes via `remaining` and `carryOver`).
- The same-period-before-pause-moment expense affordance must remain available (a 9 AM coffee can still be logged after the user pauses at 11 AM the same day).
- F-2.04's date-picker constraints (paused budgets) must continue to constrain new entries to active periods.

## Goals / Non-Goals

**Goals:**
- `BudgetSnapshot.lifecycleState == .paused` immediately upon pause-tap, regardless of where `now` falls in the pause-action period.
- Carry-over math (walker, `remaining` zeroing for paused periods, `effectivePeriodEnd` clamps) bit-for-bit unchanged.
- Add Expense sheet shows a persistent paused note while bound to a paused budget; existing out-of-range caption retained as the violation state in the same slot.
- Detail-screen Resume CTA caption tweaked to quietly acknowledge backdated-entry availability via the list `+`.
- Tests continue to validate both the math (period-granular) and the UI state (moment-granular) without conflating the two.

**Non-Goals:**
- No proration of allocation across mid-period pause/resume actions. The pause-action period's full allocation continues to roll into carry-over at period close, exactly as today.
- No change to write-path eligibility for `BudgetLifecycleService.pauseBudget(...)` / `resumeBudget(...)` (the service already rejects `.specificDates`, `.paused`, `.postEnd`).
- No new disabled "Add Expense" affordance. The Detail screen continues to swap the primary slot to Resume Budget when paused; the list `+` continues to open the sheet with the paused-state date constraint already enforced via `dateRange`.
- No analytics-event changes. `budget_paused` and `budget_resumed` continue to fire on successful service return; their property shapes do not change.
- No change to F-2.08 (Specific Dates) behavior — pause/resume remain hidden and ignored for that period type.

## Decisions

### Decision 1: Two classifications inside `BudgetCalculator.snapshot`, not two fields on `BudgetSnapshot`

`BudgetCalculator.snapshot(...)` internally computes both:

- **`mathIsPaused: Bool`** — period-granular, via the existing `LifecycleClassification.isActive(periodStart:periodEnd:sortedLifecycleEvents:)`. Used for `remaining = 0` short-circuit and walker accrual. **Unchanged from today.**
- **`uiIsPaused: Bool`** — moment-granular, via a new free function `isPausedAtMoment(now:sortedLifecycleEvents:) -> Bool` that scans `sortedLifecycleEvents` and returns `true` iff the latest event with `effectiveDate ≤ now` is a `.pause`. Used to populate `BudgetSnapshot.lifecycleState`.

`BudgetSnapshot.lifecycleState` exposes only the UI-facing value (today's only consumer is the view layer). The math values inside `BudgetCalculator` reach `BudgetSnapshot.remaining`, `effectiveAllocation`, and `carryOver` directly without going through `lifecycleState`.

**Rationale:**
- Keeps `BudgetSnapshot`'s public surface unchanged for view sites. No call-site sweep needed.
- Localizes the asymmetry to one file (`BudgetCalculator.swift`) plus one new sibling helper.
- Walker code reads `LifecycleClassification.isActive(...)` directly — already correct, unchanged.

**Alternatives considered:**
- *Add a separate `displayState` field to `BudgetSnapshot`*: explicit but bloats the type and forces every consumer to choose. Rejected.
- *Move all classification into a new `LifecycleClassifier` type*: more refactor than the change needs. Rejected — the existing `isActive(...)` free function is fine as-is.
- *Change `LifecycleClassification.isActive(...)` to be moment-granular*: would silently change walker accrual — exactly the math regression we want to avoid. Rejected.

### Decision 2: `remaining` value during the pause-action period

During the pause-action period, `BudgetSnapshot.remaining` continues to compute as `allocation - in-period-expenses` (the existing "active" branch). The UI displays it dimmed (via the existing `dimmedStyle(_:when:)` helper, gated on `lifecycleState == .paused`), but the value is honest about what would roll into carry-over at period close.

**Rationale:**
- Option (a) from the explore — *show live remaining* — is the only option that stays internally consistent. The user paused with $10 left; carry-over will receive $10. Showing $10 here is truthful.
- Snapping to $0 would be punitive and confusing once the carry-over chip refreshes at period close ("Why did $10 appear in carry-over?").
- Showing the allocation would be misleading once any expense is logged.

This is the existing implementation. The only thing that changes is that the value is now rendered with paused styling (dimmed) during the pause-action period, because `lifecycleState == .paused` flips the view code's `isPaused` flag.

### Decision 3: Always-on paused caption in Add Expense, single-slot replacement on violation

The Add Expense sheet's `whenCard` already has a caption slot beneath the `DatePicker` for `dateOutOfRangeCaption`. The new always-on paused note shares this slot:

- **Default (always-on while `lifecycleState == .paused`):** `addEditExpense.paused.caption.format` → *"Paused since %@. You can still add expenses dated before then."* (key A2)
- **Violation (date picked inside a paused gap from multi-cycle history):** `addEditExpense.date.outOfRange.caption` → *"Pick a date within an active period of this budget."* (existing key B3)

The ViewModel exposes a single computed `pausedCaption: String?` that returns the violation copy when the date is invalid, the always-on copy when the bound budget is paused and the date is valid, and `nil` otherwise. The view renders zero or one caption — no stacking.

**Rationale:**
- One slot keeps the layout calm at small Dynamic Type sizes and avoids contradictory stacked messages.
- A computed property keeps view body evaluation cheap (no new snapshot calls; `cachedBudgetSnapshot` already at hand).
- The pre-start / post-end "clamped default" caption from F-2.04 is mutually exclusive with the paused caption (a pre-start budget cannot be in the `.paused` UI state — pre-start wins until `startDate`); the ViewModel returns the pre-start caption first, the violation second, then the always-on paused caption.

### Decision 4: Date-picker upper bound stays `cachedPauseEffectiveDate`

`AddEditExpenseViewModel.dateRange.upperBound` already resolves to `cachedPauseEffectiveDate` when the snapshot reports `.paused` (from the cached snapshot captured at init). Under the new moment-granular rule, this is exactly what we want: the picker allows any time in `[budget.effectiveStartDate, pauseEffectiveDate]`, which includes "same period, before pause moment" entries.

**Rationale:**
- Already implemented during `pause-resume-budget`. No change needed.
- The pause moment is the precise upper bound the user wants (per the explore conclusion).
- Save-time validation against the active-period union still catches the multi-cycle gap case via `dateOutOfRangeCaption`.

### Decision 5: Pre-start and post-end take precedence in `lifecycleState`

The classification order in `BudgetSnapshot.lifecycleState` stays:

```
if postEnd  → .postEnd
else if preStart → .preStart   (pre-existing semantics)
else if uiIsPaused → .paused   (NEW: moment-granular)
else → .active
```

**Rationale:**
- F-7.06 already specifies: "Pause before `startDate`: the pre-start chip presentation is preserved until `startDate`; from `startDate` onward the budget is in a paused state until the user resumes." This precedence implements that rule cleanly.
- `.postEnd` remains terminal per F-7.07; a paused budget that reaches `endDate` flips to `.postEnd` and stays there.

### Decision 6: Allocation edits during the pause-action period defer to resume

F-2.03 says: *"Allocation edits made while a budget is paused take effect at the resume point."* Today, "while a budget is paused" was interpreted as `lifecycleState == .paused`, which was period-granular and didn't activate until the next period. Under the new moment-granular rule, this same interpretation now correctly defers any allocation edit made after the pause-tap to the resume point.

**Rationale:**
- The rule's wording doesn't change; only the underlying classification it's gated on shifts to be more truthful. This is the intended behavior — a user who paused at 10 AM and edits allocation at 11 AM is "editing while paused" by any natural reading.
- The Add/Edit Budget sheet's existing allocation-edit code path already keys off `lifecycleState`; no view-side change is needed beyond confirming the behavior.

## Risks / Trade-offs

**[Risk] Hidden math-state assertions in tests.** Some existing tests (e.g., `BudgetCalculatorPauseResumeTests`, `BudgetLifecycleServiceTests`) assert `lifecycleState == .active` during the pause-action period to encode the period-granular semantic. → **Mitigation:** Update those assertions to check `mathIsPaused` (via the new internal helper if exposed `internal` for tests, or via the walker's behavior — `remaining` and `carryOver` values — which is the more important contract).

**[Risk] User confusion when carry-over jumps at next-period rollover.** A user pauses mid-period with $10 unspent, sees the budget as paused immediately, then sees carry-over rise by $10 at midnight. → **Mitigation:** This is not a new behavior — today's carry-over rollover does the same thing, just less visibly because no paused state preceded it. The truthfulness of seeing "paused" *and* watching money flow forward at period close is actually a wash: the chip refresh is the evidence the math is alive. We can revisit if user feedback flags this; no code action in this change.

**[Risk] CloudKit convergence with concurrent pause/resume.** Two devices race a `.pause` on device A and a `.resume` on device B with overlapping `effectiveDate` values. → **Mitigation:** The moment-granular check is `latest event with effectiveDate ≤ now wins`, which is deterministic given a merged event log. The walker is unchanged. No new convergence concern; the existing CloudKit conflict-resolution path covers this.

**[Risk] Snapshot caching in `AddEditExpenseViewModel`.** The ViewModel caches `cachedBudgetSnapshot` at init. If the user pauses the budget from another screen and the sheet is somehow still open, the cache goes stale. → **Mitigation:** Add Expense is presented as a sheet; in practice the only way to reach it is via the list `+` (paused budget) or the Detail primary slot (active budget). The user cannot pause while the sheet is open without dismissing it first. The cached value is correct for the sheet's lifetime. Existing F-7.06 implementation already relies on this assumption; no change needed.

**[Trade-off] Visual paused styling during pause-action period dims a chip whose value is still "live" until period close.** A purist might argue this is contradictory ("dimmed but the value is still being computed"). → **Acceptance:** The dimming signals "no new interaction," not "value frozen." The chip can still change due to backdated edits even when paused per the existing F-2.01 / F-2.02 rules — dimmed-but-live is already an accepted state. No copy or styling work needed to clarify.

## Migration Plan

This is a behavioral refinement, not a data migration. Steps:

1. Implement Decision 1 inside `BudgetCalculator.swift` (add `isPausedAtMoment(...)` helper; update `lifecycleState` derivation to use it).
2. Update tests that conflate UI state with math state — split assertions into "math: period-granular" and "UI: moment-granular" forms.
3. Wire Decision 3 in `AddEditExpenseViewModel` (new computed caption property) and `AddEditExpenseView` (single caption render below the `whenCard`).
4. Update one localized string (resume-CTA caption); add one new key (always-on paused caption). Queue translations.
5. Update `docs/product-features-planning.md` F-7.06 "Semantics" bullet and F-2.04 date-bounds bullet; update `docs/tech-design-doc.md` `BudgetCalculator` section to mention the split classification.
6. Run `make format → make lint-fix → make build → make test`.

**Rollback strategy:** A single-revert of the `BudgetCalculator.swift` change restores period-granular UI behavior without affecting math (which was never modified). The new caption render in the Add Expense sheet falls back to `nil` automatically when `lifecycleState != .paused`, so a partial revert is safe.

## Open Questions

None outstanding. The explore session converged on copy choices (A2 / B3 / C2) and on the same-period-before-pause-moment affordance being preserved.
