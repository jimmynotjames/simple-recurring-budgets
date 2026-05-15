import Foundation

/// Computes the asymmetric live-coupling spillover for the current in-progress period.
///
/// Rule (§A.5.6):
/// - `.active`: only *committed* overflow spills into carry-over immediately.
///   Ordinary mid-period slack (`0 ≤ remaining ≤ effectiveAllocation`) stays in the
///   current-period envelope and waits for the period close — where the walker folds it in.
///   Overspend (`remaining < 0`) and add-funds excess (`remaining > effectiveAllocation`)
///   are committed user actions that land live.
/// - `.postEnd`: symmetric — the entire final-period remaining folds in (the period will
///   never close normally, so there is no future boundary to wait for).
/// - `.preStart`, `.paused`: 0 (remaining is also 0 in both states).
func currentPeriodSpillover(
  remaining: Decimal,
  effectiveAllocation: Decimal,
  lifecycleState: BudgetLifecycleState
) -> Decimal {
  switch lifecycleState {
  case .active:
    if remaining < 0 { return remaining } // overspend
    if remaining > effectiveAllocation { return remaining - effectiveAllocation } // add-funds excess
    return 0 // ordinary slack
  case .postEnd:
    return remaining // symmetric: entire remaining folds in
  case .preStart, .paused:
    return 0
  }
}
