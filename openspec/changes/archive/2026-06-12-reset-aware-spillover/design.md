## Context

Carry-over for recurring budgets is `walkerSum + currentPeriodSpillover` (`BudgetCalculator.recurringBranch`):

- **Walker** (`walkCarryOver`) sums completed prior active periods. Its walk window starts at `max(effectiveStartDate, lastResetDate ?? .distantPast)`, and for the period containing the reset it filters expenses with `max(boundaryStart, walkWindowStart)` while still awarding the full allocation ("full period spending power, no proration" — documented in `CarryOverWalker.swift` and algorithm doc §A.5.3).
- **Spillover** (`currentPeriodSpillover`) folds the current period's *committed* overflow in live: overspend (`remaining < 0`), add-funds excess (`remaining > effectiveAllocation`), and — for `.postEnd` — the entire final-period remaining. Its input is the plain `remaining` computed from *all* current-period expenses; `lastResetDate` is never consulted.

That asymmetry produces issues #242 (mid-period reset leaves the current deficit in carry-over until the period closes) and #241 (post-end reset leaves a stale spillover forever, since the final period never closes).

## Goals / Non-Goals

**Goals:**
- After any manual reset, the next snapshot's carry-over reads 0 (absent post-reset committed overflow).
- The spillover's input is at all times an exact preview of what the walker will contribute for the current period once it closes, including in the reset period — so committed overflow carries continuously across the period boundary (ordinary slack still waits for the close, per the asymmetric rule).
- Post-end resets (`lastResetDate >= effectiveEndExclusive`) zero carry-over permanently for both Reset Carry-over and Reset Budget.
- Keep the change confined to the pure calculator; specify the rule in `budget-math` and the algorithm doc.

**Non-Goals:**
- No change to `remaining` — the documented post-reset rebound (the envelope still shows today's expenses) stays.
- No change to the walker, the reset write-paths (`BudgetLifecycleService`), the data model, UI, analytics, or localization.
- No change to `.specificDates` (its branch ignores `lastResetDate` by design, F-2.08).
- Issue #240 (week-start cascade) is explicitly out of scope.

## Decisions

1. **Adjust the spillover's input in `recurringBranch`, not the `currentPeriodSpillover` function.**
   The pure function's contract ("committed overflow of a remaining-vs-allocation pair") stays intact and its tests remain valid. `recurringBranch` computes a `spilloverRemaining` whose expense lower bound is `max(effectivePeriodStart, lastResetDate ?? .distantPast)` and passes that instead of `remaining`.
   *Alternative considered:* threading `lastResetDate` into `currentPeriodSpillover` — rejected; it would mix period-window concerns into a function that is deliberately a 3-input classifier.

2. **Full allocation, no proration, for the reset period — mirror the walker.**
   `spilloverRemaining = effectiveAllocation − Σ expenses in [max(effectivePeriodStart, lastResetDate), effectivePeriodEnd)`. This is exactly the contribution `walkCarryOver` computes for that period after it closes, so the live value and the close-time value can never diverge.
   *Alternative considered:* prorating the allocation after the reset — rejected; contradicts the documented §A.5.3 convention and would make live and close-time values diverge.

3. **Post-end reset suppresses spillover entirely.**
   When `lastResetDate >= effectiveEndExclusive`, spillover = 0. Rationale: the final period had already completed (in the "frozen final tally" sense) when the user reset; there is nothing left to spill — the reset's meaning is "zero everything up to now", and *everything* is before now. Without this rule, a post-end Reset Budget would show carry-over = full final allocation (expenses deleted, symmetric postEnd rule folds in the whole remaining).
   Note `lastResetDate >= effectiveEndExclusive` can only hold in `.postEnd` (the write paths use `now`, and a live budget has `now < effectiveEndExclusive`), so the rule cannot affect active budgets.

4. **Reset during the final period of a since-ended budget keeps the symmetric postEnd rule, applied to post-reset expenses.**
   If the user reset mid-final-period and the budget later ended, spillover = full allocation − post-reset expenses (decision 2), folded symmetrically. Consistent with both conventions; no special case needed.

5. **Paused short-circuit is preserved.**
   `spilloverRemaining` mirrors the existing `remaining` computation including the `isCurrentPaused → 0` short-circuit, and `currentPeriodSpillover` already returns 0 for `.paused`/`.preStart`.

## Risks / Trade-offs

- **[Behavioral surprise: carry-over rebounds to +allocation after the reset period closes]** → Pre-existing, documented walker behavior (no proration), not introduced here; the fix only makes the live chip agree with it earlier. Covered by a test pinning the live/close-time equivalence.
- **[Core-math regression risk]** → Change is additive gating in a pure function with an extensive suite (`BudgetCalculatorTests`, `CurrentPeriodSpilloverTests`, DST suites). New tests cover: mid-period reset with deficit (#242), post-reset overspend spills again, post-end Reset Carry-over (#241), post-end Reset Budget (#241), reset during final period of an ended budget, paused-period reset no-op.
- **[Spec/doc drift]** → Delta spec on `budget-math` plus algorithm-doc updates are tasks in this change; verify checks them before archive.

## Migration Plan

Pure read-path change — no stored data changes, nothing to migrate or roll back beyond reverting the commit. Existing `lastResetDate` values gain the new semantics on the next snapshot automatically (on all devices once the build ships; CloudKit payloads unchanged).

## Open Questions

None — semantics confirmed with the product owner (zero today's deficit immediately; fix both issues; defer #240).
