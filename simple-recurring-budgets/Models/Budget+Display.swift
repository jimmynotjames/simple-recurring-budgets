import Foundation

extension Budget {
  /// The period label to show in list rows and screen headers.
  ///
  /// For `.specificDates` budgets, returns the formatted date range (e.g. "May 18 – Jun 3")
  /// using `Date.IntervalFormatStyle` for full locale and RTL support. For all other period
  /// types, falls back to `BudgetPeriod.listLabel`.
  @MainActor var periodDisplayLabel: String {
    let p = BudgetPeriod(rawValue: period) ?? .daily
    if p == .specificDates, let start = startDate, let end = endDate {
      return (start ..< end).formatted(
        Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)
      )
    }
    return p.listLabel
  }
}
