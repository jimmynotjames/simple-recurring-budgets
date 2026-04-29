import Foundation

// MARK: - Period partitioning

extension [ExpenseItem] {
  /// Splits expenses into current-period and past-period arrays, each sorted
  /// most-recent first.
  ///
  /// - Parameter start: The start date of the current Budget Period, as returned
  ///   by `BudgetLifecycleResult.periodStart`. When `nil` (lifecycle not yet
  ///   resolved), both arrays are empty.
  /// - Returns: A tuple whose `current` array contains items with `date >= start`
  ///   and `past` array contains items with `date < start`.
  func partitioned(byPeriodStart start: Date?) -> (current: [ExpenseItem], past: [ExpenseItem]) {
    guard let start else { return ([], []) }
    let current = filter { $0.date >= start }.sorted { $0.date > $1.date }
    let past = filter { $0.date < start }.sorted { $0.date > $1.date }
    return (current, past)
  }
}
