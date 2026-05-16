import Foundation

// MARK: - BudgetPeriod display

extension BudgetPeriod {
  var listLabel: String {
    switch self {
    case .daily:
      String(
        localized: "period.daily",
        defaultValue: "Daily",
        comment: "Budget period label for daily budgets in the list"
      )
    case .weekly:
      String(
        localized: "period.weekly",
        defaultValue: "Weekly",
        comment: "Budget period label for weekly budgets in the list"
      )
    case .biweekly:
      String(
        localized: "period.biweekly",
        defaultValue: "Biweekly",
        comment: "Budget period label for biweekly budgets in the list"
      )
    case .monthly:
      String(
        localized: "period.monthly",
        defaultValue: "Monthly",
        comment: "Budget period label for monthly budgets in the list"
      )
    case .specificDates:
      String(
        localized: "period.specificDates",
        defaultValue: "Specific Dates",
        comment: "Budget period label for specific-dates budgets in the list"
      )
    }
  }

  /// Inline/sentence form of the period name for use inside localized sentences.
  var inlineLabel: String {
    switch self {
    case .daily:
      String(
        localized: "period.daily.inline",
        defaultValue: "daily",
        comment: "Period name used inline in an accessibility sentence, e.g. 'remaining this daily period'"
      )
    case .weekly:
      String(
        localized: "period.weekly.inline",
        defaultValue: "weekly",
        comment: "Period name used inline in an accessibility sentence, e.g. 'remaining this weekly period'"
      )
    case .biweekly:
      String(
        localized: "period.biweekly.inline",
        defaultValue: "biweekly",
        comment: "Period name used inline in an accessibility sentence, e.g. 'remaining this biweekly period'"
      )
    case .monthly:
      String(
        localized: "period.monthly.inline",
        defaultValue: "monthly",
        comment: "Period name used inline in an accessibility sentence, e.g. 'remaining this monthly period'"
      )
    case .specificDates:
      String(
        localized: "period.specificDates.inline",
        defaultValue: "specific dates",
        comment: "Period name used inline in an accessibility sentence for a specific-dates budget"
      )
    }
  }
}
