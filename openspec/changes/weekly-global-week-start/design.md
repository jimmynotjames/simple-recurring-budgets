## Context

Weekly is the only recurring period type with a per-budget grid: `BudgetCalculator.recurringBranch` derives `weekStart` from `Budget.startDate`'s weekday (BudgetCalculator.swift:115-116), as does `BudgetLifecycleService.applyAllocationEdit` (BudgetLifecycleService.swift:141-142). Daily and monthly budgets share universal grids; biweekly is inherently per-budget (its 14-day phase comes from a date, not a weekday — `PeriodCalculator`'s biweekly branch consumes only `biweeklyAnchor`). `AppSettings.weekStartDay` today only seeds the pre-filled start date for new weekly/biweekly budgets.

Two bugs anchor this change: #240 (the setting doesn't cascade; the Settings alert claims it does) and #247 (allocation edits in a mid-grid first period are shadowed: the write keys on `currentPeriodStart` while the read keys on `max(currentPeriodStart, effectiveStartDate)`).

PR #248's first commit added 34 characterization tests specifically structured for this change: Group A pins behavior that must survive; Group B suites carry banners saying they pin the old weekly anchoring and must be flipped deliberately.

## Goals / Non-Goals

**Goals:**
- The Week Starts On setting is the single source of truth for every weekly budget's grid — past and future periods, all devices (KVS-synced), immediately on change.
- Settings copy, math, and spec agree.
- Allocation edits read back consistently in mid-grid first periods (#247), for monthly today and weekly under the new grid.
- Compile-time enforcement that every math call site chooses a week start (no silent defaults).

**Non-Goals:**
- Biweekly anchoring changes of any kind (hard guarantee; pinned by a new test).
- Per-budget week-start overrides (a possible future feature; would be an explicit field, not the old implicit startDate coupling).
- Migration/normalization of legacy `AllocationChange` rows written on old per-budget grids (pre-launch: no real data).
- Displaying the week span in budget UI (deferred separately by the owner).

## Decisions

1. **Explicit `weekStart: Weekday` parameter with no default** on `snapshot` and the five lifecycle-service entry points (`resetCarryOver` excluded — it writes `lastResetDate` only). A default would let a call site silently compute on the wrong grid; omission is a compile error instead. Tests pass the simulated user setting explicitly, which also lets non-Sunday-arithmetic tests keep their values by passing their anchor weekday.
   *Alternative rejected:* reading `AppSettings` inside the calculator — breaks the documented pure-function design and testability.
2. **Pass the global value unconditionally; only `.weekly` consumes it.** Verified `PeriodCalculator.periodStart` uses `weekStart` solely in the `.weekly` case; `.biweekly` uses `biweeklyAnchor` + day-diff `floorDiv`; daily/monthly use neither. So the derivation lines are deleted outright with no per-type branching.
3. **#247: governing-row mutate rule.** Key = `max(currentPeriodStart, calendar.startOfDay(for: budget.effectiveStartDate))` — exactly the read path's lookup instant. The edit mutates the latest row with `effectiveFrom <= key` **iff** that row's `effectiveFrom >= currentPeriodStart` (it governs only the current period); otherwise inserts at the key.
   - Grid-aligned budgets: key == `currentPeriodStart`; governing row either sits at it (mutate — same as today) or is older (insert — same as today). **Zero behavior change.**
   - Mid-grid first period (monthly started Jan 15, edit Jan 31): key = Jan 15 → mutates the initial row → live read (lookup at Jan 15) and the walker's closed-period lookup (boundary Jan 1 → earliest-row fallback → same row) both see the new amount.
   - Forward-dated startDate + allocation edit in one save (the stranded-row corner): key moves with `effectiveStartDate`, but the governing row (old startDate row, still `>= currentPeriodStart`) is mutated rather than stranded behind a new insert — earliest-row fallback can never resurrect a stale amount.
   *Alternative rejected:* exact-match on the key only — simpler to state, but leaves the stranded-row corner open.
4. **`AddEditExpenseViewModel` captures the `Weekday` value, not `AppSettings`** (both inits gain the param), preserving the add-edit-expense-screen rule that the VM doesn't store settings. The captured value joins the existing captured-snapshot design; a mid-sheet setting change doesn't refresh validation bounds — same staleness class as the already-documented cached snapshot. `RatingPromptCoordinator.expenseLogSignals` similarly takes the value as a parameter (stays a pure static helper).
5. **Reactivity via `onChange(of: settings.weekStartDay)`** on `BudgetRowView` and `BudgetDetailView`, joining their existing trigger lists (`.task(id:)`, `recomputeToken`, scenePhase). The KVS external-change observer already mutates the `@Observable` property on the main actor, so remote-device setting changes drive the same triggers.
6. **Copy states the consequence, not the mechanism**: "Changing to %@ will immediately regroup all weekly budgets — including past weeks — onto the new week. Biweekly budgets keep their own cycle." Key names unchanged; the en value change marks all translations stale for the pipeline.

## Risks / Trade-offs

- **[Historical carry-over values change when the setting changes]** → Inherent to the feature (regrouping is the point); every expense still counts exactly once. The confirmation alert now warns about exactly this. Pre-launch: no installed base.
- **[Legacy old-grid `AllocationChange` rows]** → Rows written at old per-budget week starts become mid-grid; worse, a legacy row dated later than a new grid-aligned edit row wins `allocationInEffect` precedence from its date onward. Deterministic, crash-free, display-only — and pre-launch there is no legacy data. A one-shot normalization (snap weekly rows to `periodStart(effectiveFrom)`) is explicitly out of scope; revisit only if pre-launch TestFlight data matters.
- **[Mixed-version devices]** → Old builds compute on the old grid until updated; math is pure-read so nothing corrupts. Only `applyAllocationEdit` writes grid-dependent rows (folds into the legacy-row risk). Accepted pre-launch.
- **[Mechanical test churn (~100 call sites gain a param)]** → The hardening commit's Group A suites guarantee arithmetic survives: any value change outside the banner-marked Group B suites and the enumerated flips is a regression, not plumbing.

## Migration Plan

No schema change; nothing stored derives from the weekday. Ship = flip. Rollback = revert the commits. Existing budgets re-grid on next snapshot after update.

## Open Questions

None — direction, biweekly carve-out, copy approach, and #247 inclusion confirmed with the owner.
