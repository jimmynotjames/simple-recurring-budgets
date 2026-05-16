import Foundation

/// Returns the allocation in effect at `date` by finding the latest `AllocationChange`
/// whose `effectiveFrom <= date`. Ties on `effectiveFrom` are broken by `lastModified`
/// (later wins) to handle CloudKit cross-device convergence for concurrent edits.
///
/// **Contract:** `sortedHistory` must be sorted ascending by `(effectiveFrom, lastModified)`.
/// The walker hot path calls this once per completed period; pre-sorting at the snapshot
/// entry point keeps that loop O(P × A) without an extra log factor per call. The single-
/// shot callers (`BudgetCalculator.snapshot` pre-start branch, current-period lookup)
/// pre-sort inline.
///
/// Falls back to the earliest row's amount when no row satisfies the predicate.
/// This fallback is load-bearing: the walker may query at a `boundaryStart` that
/// precedes the budget's `startDate` (e.g., a weekly budget created mid-week — the
/// first week's `boundaryStart` is the weekday-aligned date *before* `startDate`).
/// Returning the earliest row's amount awards the full period's allocation in that
/// case, matching the no-proration design (F-2.03 allocation-edit semantics).
func allocationInEffect(at date: Date, sortedHistory: [AllocationChange]) -> Decimal {
  guard !sortedHistory.isEmpty else { return 0 }
  // sortedHistory is ascending; last entry with effectiveFrom <= date is the winner.
  if let best = sortedHistory.last(where: { $0.effectiveFrom <= date }) {
    return best.amount
  }
  // Defensive fallback: no eligible row → earliest row's amount (index 0 since sorted ASC).
  return sortedHistory[0].amount
}
