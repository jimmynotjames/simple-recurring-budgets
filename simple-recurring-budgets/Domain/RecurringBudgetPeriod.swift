import Foundation

/// Compile-time wrapper over the four recurring `BudgetPeriod` cases. `PeriodCalculator` accepts this type
/// so `.specificDates` can't reach period-boundary math; `init?` returns `nil` for it.
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
