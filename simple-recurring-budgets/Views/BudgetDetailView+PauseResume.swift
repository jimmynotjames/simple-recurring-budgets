import OSLog
import SwiftData
import SwiftUI

// MARK: - Pause / Resume actions (F-7.06)

extension BudgetDetailView {
  func pauseBudgetTapped() {
    Logger.ui.debug(
      "ui.action: pauseBudget budget=\(String(describing: budget.persistentModelID), privacy: .private)"
    )
    let period = BudgetPeriod(rawValue: budget.period) ?? .daily
    let succeeded = BudgetLifecycleService.pauseBudget(budget, context: context)
    // ⚠️ Boundary-adjacent (sibling pattern): Logger.ui.debug above (F-8.01) and
    // analytics.track below (F-8.02) are independent siblings. See design.md D6.
    if succeeded {
      analytics.track(
        AnalyticsEvent.budgetPaused,
        properties: [
          AnalyticsProperty.period: period.analyticsValue,
          AnalyticsProperty.carryOverEnabled: budget.isCarryOverEnabled,
          AnalyticsProperty.currencyCode: budget.currencyCode,
          AnalyticsProperty.budgetName: budget.name,
          AnalyticsProperty.budgetAllocationAmount: (budget.currentAllocation as NSDecimalNumber).doubleValue,
        ]
      )
    }
    refreshLifecycle()
  }

  func resumeBudgetTapped() {
    Logger.ui.debug(
      "ui.action: resumeBudget budget=\(String(describing: budget.persistentModelID), privacy: .private)"
    )
    let period = BudgetPeriod(rawValue: budget.period) ?? .daily
    let succeeded = BudgetLifecycleService.resumeBudget(budget, context: context)
    // ⚠️ Boundary-adjacent (sibling pattern): Logger.ui.debug above (F-8.01) and
    // analytics.track below (F-8.02) are independent siblings. See design.md D6.
    if succeeded {
      analytics.track(
        AnalyticsEvent.budgetResumed,
        properties: [
          AnalyticsProperty.period: period.analyticsValue,
          AnalyticsProperty.carryOverEnabled: budget.isCarryOverEnabled,
          AnalyticsProperty.currencyCode: budget.currencyCode,
          AnalyticsProperty.budgetName: budget.name,
          AnalyticsProperty.budgetAllocationAmount: (budget.currentAllocation as NSDecimalNumber).doubleValue,
        ]
      )
    }
    refreshLifecycle()
  }
}
