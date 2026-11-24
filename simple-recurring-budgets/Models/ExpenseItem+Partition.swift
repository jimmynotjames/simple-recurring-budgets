import Foundation

// MARK: - Period partitioning

/// Result of `[ExpenseItem].partitioned(byPeriodStart:periodEnd:)`: the three date buckets the Budget detail
/// expense list renders. A struct rather than a tuple (SwiftLint `large_tuple`).
struct PartitionedExpenses {
  let future: [ExpenseItem]
  let current: [ExpenseItem]
  let past: [ExpenseItem]

  static let empty = PartitionedExpenses(future: [], current: [], past: [])
}

extension [ExpenseItem] {
  /// Splits expenses into future, current-period, and past-period arrays, each sorted most-recent first.
  ///
  /// The future bucket is deliberately a **single bucket for all future periods**: future-dated expenses don't
  /// count toward Remaining until their date arrives (`BudgetCalculator` filters on `date < effectivePeriodEnd`),
  /// so folding them into the current section made its total disagree with the Remaining headline.
  ///
  /// - Parameters:
  ///   - start: Inclusive start of the current period (`BudgetLifecycleResult.periodStart`).
  ///   - end: Exclusive end of the current period (`BudgetLifecycleResult.periodEnd`). If either bound is
  ///     `nil` (lifecycle not yet resolved), all arrays are empty.
  /// - Returns: `future` has `date >= end`, `current` has `start <= date < end`, `past` has `date < start`.
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
