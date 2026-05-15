import Foundation

/// Returns the allocation in effect at `date` by finding the latest `AllocationChange`
/// whose `effectiveFrom <= date`. Ties on `effectiveFrom` are broken by `lastModified`
/// (later wins) to handle CloudKit cross-device convergence for concurrent edits.
///
/// Falls back to the earliest row's amount when no row satisfies the predicate
/// (defensive: not reachable in normal flow because every saved budget has an initial
/// row at `startDate`).
func allocationInEffect(at date: Date, history: [AllocationChange]) -> Decimal {
  let eligible = history.filter { $0.effectiveFrom <= date }
  if let best = eligible.max(by: { lhs, rhs in
    if lhs.effectiveFrom != rhs.effectiveFrom { return lhs.effectiveFrom < rhs.effectiveFrom }
    return lhs.lastModified < rhs.lastModified
  }) {
    return best.amount
  }
  // Defensive fallback: no eligible row → use the earliest row's amount.
  let earliest = history.min { $0.effectiveFrom < $1.effectiveFrom }
  return earliest?.amount ?? 0
}
