import Foundation

/// A compile-time wrapper over the four recurring `BudgetPeriod` cases.
///
/// `PeriodCalculator`'s public surface accepts this type so that `.specificDates` cannot
/// accidentally reach period-boundary math — the `init?` returns `nil` for that case.
enum RecurringBudgetPeriod {
  case daily
  case weekly
  case biweekly
  case monthly

  init?(_ period: BudgetPeriod) {
    switch period {
    case .daily: self = .daily
    case .weekly: self = .weekly
    case .biweekly: self = .biweekly
    case .monthly: self = .monthly
    case .specificDates: return nil
    }
  }
}
