import OSLog
import SwiftData
import SwiftUI

// MARK: - Pause / Resume actions

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
        analytics: analytics,
        weekStart: settings.weekStartDay
      )
    } catch let error as PersistenceError {
      saveError.setForFailure(error, retry: { [self] in pauseBudgetTapped() })
      return
    } catch {
      return
    }
    saveError.clear()
    // budget_paused fires only after a successful save; the debug log above is
    // independent of it.
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
        analytics: analytics,
        weekStart: settings.weekStartDay
      )
    } catch let error as PersistenceError {
      saveError.setForFailure(error, retry: { [self] in resumeBudgetTapped() })
      return
    } catch {
      return
    }
    saveError.clear()
    // budget_resumed fires only after a successful save; the debug log above is
    // independent of it.
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
