# budget-math delta — reset-aware-spillover

## MODIFIED Requirements

### Requirement: Asymmetric live coupling for the current period

The system SHALL implement `currentPeriodSpillover` to absorb the current in-progress period's committed overflow into the carry-over chip in real time (algorithm doc §A.5.6):

- If `remaining` is inside `[0, effectiveAllocation]` (ordinary mid-period state), spillover is 0 — the current period's slack stays in "today's envelope" until the period closes.
- If `remaining < 0` (overspend), spillover is `remaining` (negative). The carry-over decreases by the overshoot immediately.
- If `remaining > effectiveAllocation` (the user added negative-amount expenses per F-6.01 so net spend went below 0), spillover is `remaining − effectiveAllocation` (positive). The carry-over increases by the excess immediately.

The snapshot's `carryOver` (for recurring budgets) SHALL equal `walkCarryOver(...) + currentPeriodSpillover`.

In `.postEnd` state the rule collapses to symmetric: the entire final-period remaining (positive or negative) is added to the carry-over, since there is no future period close.

**Reset interaction.** The spillover SHALL honor `Budget.lastResetDate`:

- The spillover's input SHALL be computed from post-reset expenses only: `spilloverRemaining = effectiveAllocation − Σ expenses in [max(effectivePeriodStart, lastResetDate ?? .distantPast), effectivePeriodEnd)`, with the full allocation awarded (no proration) — mirroring the walker's §A.5.3 convention for the period containing a reset. The spillover input therefore equals the contribution the walker will compute for that period once it closes, so the carry-over does not jump at the period boundary when overflow was already committed (slack still waits for the close, per the asymmetric rule above). The snapshot's `remaining` is NOT affected — it still reflects all current-period expenses (post-reset rebound, §A.6.4).
- When `lastResetDate >= effectiveEndExclusive` (the reset was performed after the budget ended), spillover SHALL be 0, so a post-end Reset Carry-Over or Reset Budget zeroes the carry-over permanently. (This condition is only reachable in `.postEnd`; reset write-paths stamp `now`, and a live budget has `now < effectiveEndExclusive`.)

#### Scenario: Ordinary slack does not affect carry-over

- **WHEN** `effectiveAllocation = 20`, today's expenses total 10, prior walker sum = 5
- **THEN** `currentPeriodSpillover = 0` and the chip reads carry-over = 5

#### Scenario: Overspend lands live

- **WHEN** `effectiveAllocation = 20`, today's expenses total 21 (so remaining = −1), prior walker sum = 5
- **THEN** `currentPeriodSpillover = −1` and the chip reads carry-over = 4

#### Scenario: Add-funds excess lands live

- **WHEN** `effectiveAllocation = 20`, today has a −$30 add-funds row (so remaining = 50), prior walker sum = 5
- **THEN** `currentPeriodSpillover = 30` (50 − 20) and the chip reads carry-over = 35

#### Scenario: Reverting the committed action snaps carry-over back

- **WHEN** the user deletes the $21 expense from the overspend scenario above
- **THEN** the next snapshot returns `currentPeriodSpillover = 0` and the chip reads carry-over = 5

#### Scenario: PostEnd collapses to symmetric

- **WHEN** `lifecycleState = .postEnd`, the final period's remaining is +12, and the walker sum from earlier periods is 8
- **THEN** the snapshot's `carryOver` is 20 (8 + 12), independent of whether the final period's remaining is inside `[0, effectiveAllocation]`

#### Scenario: Mid-period reset zeroes a current-period deficit immediately

- **WHEN** a daily budget has `effectiveAllocation = 50`, today's expenses total 80 (remaining = −30), and the user invokes Reset Carry-Over at `now` (so `lastResetDate = now`, within the current period)
- **THEN** the next snapshot's spillover input is `50 − 0 = 50` (no post-reset expenses), `currentPeriodSpillover = 0`, `carryOver = 0`, and `remaining` is still −30

#### Scenario: Post-reset overspend spills again

- **WHEN** after the reset above the user logs a further $60 expense (post-reset expenses total 60 > allocation 50)
- **THEN** the spillover input is `50 − 60 = −10`, `currentPeriodSpillover = −10`, and `carryOver = −10`

#### Scenario: Committed post-reset overspend carries continuously across the period close

- **WHEN** a reset occurs mid-period and post-reset expenses exceed the allocation (committed overspend)
- **THEN** the live spillover equals the contribution `walkCarryOver(...)` computes for the same period after it completes (full allocation minus post-reset expenses), so the snapshot's `carryOver` is identical immediately before and immediately after the period boundary

#### Scenario: Reset on an ended budget zeroes carry-over permanently

- **WHEN** a weekly budget with `endDate` in the past is in `.postEnd` with carry-over 100, and the user invokes Reset Carry-Over (so `lastResetDate >= effectiveEndExclusive`)
- **THEN** the next snapshot's walker contribution is 0, `currentPeriodSpillover = 0`, and `carryOver = 0`

#### Scenario: Reset Budget on an ended budget does not resurrect the final allocation

- **WHEN** a `.postEnd` budget's expenses are deleted by Reset Budget (final-period `remaining` rebounds to `effectiveAllocation`) and `lastResetDate >= effectiveEndExclusive`
- **THEN** spillover is 0 (not the symmetric fold of the rebounded remaining) and `carryOver = 0`

#### Scenario: Reset during the final period of a budget that later ends

- **WHEN** the user resets mid-final-period (so `lastResetDate < effectiveEndExclusive`), logs post-reset expenses of 10 against `effectiveAllocation = 50`, and the budget then passes its `endDate`
- **THEN** the `.postEnd` spillover folds in `50 − 10 = 40` (post-reset expenses only, full allocation) and `carryOver = 40` given an empty walker window
