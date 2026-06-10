import OSLog
import SwiftData
import SwiftUI

// MARK: - Pause / Resume actions (F-7.06)

extension BudgetDetailView {
  func pauseBudgetTapped() {
    Logger.ui.debug(
      "ui.action: pauseBudget budget=\(String(describing: budget.persistentModelID), privacy: .private)"
    )
    let period = budget.periodEnum
    let succeeded: Bool
    do {
      succeeded = try BudgetLifecycleService.pauseBudget(
        budget,
        context: context,
        analytics: analytics
      )
    } catch let error as PersistenceError {
      saveError.setForFailure(error, retry: { [self] in pauseBudgetTapped() })
      return
    } catch {
      return
    }
    saveError.clear()
    // ⚠️ Boundary-adjacent (sibling pattern): Logger.ui.debug above (F-8.01) and
    // analytics.track below (F-8.02) are independent siblings. See design.md D6.
    // budget_paused fires only on a successful save (budget-lifecycle delta spec).
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
    let period = budget.periodEnum
    let succeeded: Bool
    do {
      succeeded = try BudgetLifecycleService.resumeBudget(
        budget,
        context: context,
        analytics: analytics
      )
    } catch let error as PersistenceError {
      saveError.setForFailure(error, retry: { [self] in resumeBudgetTapped() })
      return
    } catch {
      return
    }
    saveError.clear()
    // ⚠️ Boundary-adjacent (sibling pattern): Logger.ui.debug above (F-8.01) and
    // analytics.track below (F-8.02) are independent siblings. See design.md D6.
    // budget_resumed fires only on a successful save (budget-lifecycle delta spec).
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
