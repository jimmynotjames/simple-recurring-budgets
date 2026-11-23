import Foundation

/// Returns the allocation in effect at `date`: the latest `AllocationChange` with `effectiveFrom <= date`.
/// Ties on `effectiveFrom` break by `lastModified` (later wins) so concurrent CloudKit edits converge.
///
/// **Contract:** `sortedHistory` must be sorted ascending by `(effectiveFrom, lastModified)`. The walker
/// calls this once per completed period, so sorting once at the snapshot entry point keeps the loop
/// O(P × A); single-shot callers pre-sort inline.
///
/// Falls back to the earliest row's amount when no row matches. Load-bearing: the walker may query at a
/// `boundaryStart` before the budget's `startDate` (a weekly budget created mid-week has its first
/// `boundaryStart` on the weekday-aligned date before `startDate`); the earliest amount awards the full
/// period's allocation (no proration).
func allocationInEffect(at date: Date, sortedHistory: [AllocationChange]) -> Decimal {
  guard !sortedHistory.isEmpty else { return 0 }
  if let best = sortedHistory.last(where: { $0.effectiveFrom <= date }) {
    return best.amount
  }
  return sortedHistory[0].amount
}
