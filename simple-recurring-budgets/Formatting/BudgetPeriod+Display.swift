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
    }
  }

  /// Inline/sentence form of the period name for use inside localized sentences.
  /// Uses dedicated per-locale keys rather than `.lowercased()` so translators control
  /// casing for their language (German capitalises nouns; Turkish has dotless-i rules).
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
    }
  }
}
