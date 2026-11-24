import Foundation

/// The repeating interval over which a Budget allocates funds. Ordered shortest to longest:
/// `daily < weekly < biweekly < monthly < specificDates`.
/// Use `RecurringBudgetPeriod` for period-boundary math: it excludes `.specificDates` at compile time so
/// that case can't reach `PeriodCalculator`.
enum BudgetPeriod: String, Codable, CaseIterable, Comparable {
  case daily
  case weekly
  case biweekly
  case monthly
  /// One-shot / trip-style envelope with a fixed `[startDate, endDate]` window. No recurrence.
  case specificDates

  private var sortOrder: Int {
    switch self {
    case .daily: 0
    case .weekly: 1
    case .biweekly: 2
    case .monthly: 3
    case .specificDates: 4
    }
  }

  static func < (lhs: BudgetPeriod, rhs: BudgetPeriod) -> Bool {
    lhs.sortOrder < rhs.sortOrder
  }
}
