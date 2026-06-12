import Foundation

// MARK: - Period partitioning

/// Result of `[ExpenseItem].partitioned(byPeriodStart:periodEnd:)` — the three
/// date buckets the Budget detail expense list renders. A struct rather than a
/// tuple (SwiftLint `large_tuple`); see the method doc for bucket semantics.
struct PartitionedExpenses {
  let future: [ExpenseItem]
  let current: [ExpenseItem]
  let past: [ExpenseItem]

  static let empty = PartitionedExpenses(future: [], current: [], past: [])
}

extension [ExpenseItem] {
  /// Splits expenses into future, current-period, and past-period arrays, each
  /// sorted most-recent first.
  ///
  /// The future bucket is deliberately a **single bucket for all future periods**
  /// (audit L2): future-dated expenses don't count toward Remaining until their
  /// date arrives (`BudgetCalculator` filters on `date < effectivePeriodEnd`), so
  /// folding them into the current section made the section total disagree with
  /// the Remaining headline.
  ///
  /// - Parameters:
  ///   - start: Inclusive start of the current Budget Period, as returned by
  ///     `BudgetLifecycleResult.periodStart`.
  ///   - end: Exclusive end of the current Budget Period, as returned by
  ///     `BudgetLifecycleResult.periodEnd`. When either bound is `nil`
  ///     (lifecycle not yet resolved), all arrays are empty.
  /// - Returns: A `PartitionedExpenses` whose `future` array contains items with
  ///   `date >= end`, `current` array contains items with `start <= date < end`,
  ///   and `past` array contains items with `date < start`.
  func partitioned(
    byPeriodStart start: Date?,
    periodEnd end: Date?
  ) -> PartitionedExpenses {
    guard let start, let end else { return .empty }
    return PartitionedExpenses(
      future: filter { $0.date >= end }.sorted { $0.date > $1.date },
      current: filter { $0.date >= start && $0.date < end }.sorted { $0.date > $1.date },
      past: filter { $0.date < start }.sorted { $0.date > $1.date }
    )
  }
}
