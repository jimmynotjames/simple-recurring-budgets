import Foundation

/// Asymmetric live-coupling spillover for the current in-progress period.
///
/// - `.active`: only *committed* overflow spills immediately. Ordinary slack
///   (`0 ≤ remaining ≤ effectiveAllocation`) stays in the envelope until the period closes and the walker
///   folds it in. Overspend (`remaining < 0`) and add-funds excess (`remaining > effectiveAllocation`) are
///   committed actions and land live.
/// - `.postEnd`: symmetric; the whole final-period remaining folds in (no future boundary to wait for).
/// - `.preStart`, `.paused`: 0.
///
/// **Reset interaction lives in the caller.** This is a pure 3-input classifier;
/// `BudgetCalculator.recurringBranch` passes a *reset-aware* `remaining` (full allocation minus
/// post-`lastResetDate` expenses; 0 spillover when the reset was stamped after the budget ended) so live
/// spillover matches the walker's eventual contribution.
func currentPeriodSpillover(
  remaining: Decimal,
  effectiveAllocation: Decimal,
  lifecycleState: BudgetLifecycleState
) -> Decimal {
  switch lifecycleState {
  case .active:
    if remaining < 0 {
      return remaining
    } // overspend
    if remaining > effectiveAllocation {
      return remaining - effectiveAllocation
    } // add-funds excess
    return 0 // ordinary slack
  case .postEnd:
    return remaining // symmetric: entire remaining folds in
  case .preStart, .paused:
    return 0
  }
}
