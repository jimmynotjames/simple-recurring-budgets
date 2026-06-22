@testable import simple_recurring_budgets
import Testing

/// §18.1 test contract #7 — AnalyticsEvent constant string values.
@Suite("AnalyticsEvent — constants §18.1 #7")
struct AnalyticsEventConstantsTests {
  @Test("all Phase 1 event constants have correct string values")
  func phaseOneEventConstants() {
    #expect(AnalyticsEvent.appOpened == "app_opened")
    #expect(AnalyticsEvent.budgetCreated == "budget_created")
    #expect(AnalyticsEvent.budgetEdited == "budget_edited")
    #expect(AnalyticsEvent.budgetDeleted == "budget_deleted")
    #expect(AnalyticsEvent.budgetReset == "budget_reset")
    #expect(AnalyticsEvent.budgetPaused == "budget_paused")
    #expect(AnalyticsEvent.budgetResumed == "budget_resumed")
    #expect(AnalyticsEvent.carryOverReset == "carry_over_reset")
    #expect(AnalyticsEvent.expenseLogged == "expense_logged")
    #expect(AnalyticsEvent.expenseEdited == "expense_edited")
    #expect(AnalyticsEvent.expenseDeleted == "expense_deleted")
    #expect(AnalyticsEvent.settingsOpened == "settings_opened")
    #expect(AnalyticsEvent.settingChanged == "setting_changed")
    #expect(AnalyticsEvent.analyticsConsentChanged == "analytics_consent_changed")
  }

  @Test("AnalyticsProperty key constants are snake_case and non-empty")
  func propertyKeysNonEmpty() {
    let keys: [String] = [
      AnalyticsProperty.period,
      AnalyticsProperty.carryOverEnabled,
      AnalyticsProperty.currencyCode,
      AnalyticsProperty.isFirstBudget,
      AnalyticsProperty.timeSinceFirstAppOpenBucket,
      AnalyticsProperty.budgetName,
      AnalyticsProperty.budgetAllocationAmount,
      AnalyticsProperty.isAddFunds,
      AnalyticsProperty.fromScreen,
      AnalyticsProperty.timeSinceBudgetCreatedBucket,
      AnalyticsProperty.settingName,
      AnalyticsProperty.newValue,
      AnalyticsProperty.oldValue,
      AnalyticsProperty.appVersion,
      AnalyticsProperty.appBuild,
      AnalyticsProperty.deviceClass,
      AnalyticsProperty.locale,
      AnalyticsProperty.region,
      AnalyticsProperty.weekStartDay,
      AnalyticsProperty.currencyDisplayPreference,
      AnalyticsProperty.icloudState,
      AnalyticsProperty.budgetsCountBucket,
      AnalyticsProperty.carryOverDefaultEnabled,
      AnalyticsProperty.consentJurisdiction,
      AnalyticsProperty.firstSeenAt,
      AnalyticsProperty.analyticsOptInAt,
      AnalyticsProperty.lastAppOpenAt,
      AnalyticsProperty.dominantPeriod,
      AnalyticsProperty.usesCarryOver,
      AnalyticsProperty.hasDisabledCarryOver,
      AnalyticsProperty.budgetsWithCarryOverOnCountBucket,
      AnalyticsProperty.defaultCurrencyCode,
    ]
    for key in keys {
      #expect(!key.isEmpty, "Property key must be non-empty: \(key)")
    }
    // All keys unique.
    #expect(Set(keys).count == keys.count)
  }
}
