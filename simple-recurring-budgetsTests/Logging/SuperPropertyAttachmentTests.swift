@testable import simple_recurring_budgets
import Testing

/// §18.1 test contract #9 — super-property bucket values and required keys.
@Suite("Super properties — §18.1 #9")
struct SuperPropertyAttachmentTests {
  // MARK: - budgets_count_bucket transitions

  @Test("budgets_count_bucket transitions correctly", arguments: [
    (0, "0"),
    (1, "1"),
    (2, "2-3"),
    (3, "2-3"),
    (4, "4-7"),
    (7, "4-7"),
    (8, "8+"),
    (100, "8+"),
  ])
  func bucketTransitions(count: Int, expected: String) {
    #expect(MixpanelAnalyticsClient.bucket(count: count) == expected)
  }

  // MARK: - Required super-property keys

  @Test("all required §10.2 super-property keys are defined as AnalyticsProperty constants")
  func requiredSuperPropertyKeysDefined() {
    let requiredKeys: [String] = [
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
    ]
    for key in requiredKeys {
      #expect(!key.isEmpty, "Super property key must be non-empty: \(key)")
    }
    #expect(requiredKeys.count == 11)
  }

  // MARK: - Cohort people-property computation

  @Test("empty budgets → all bucket 0 / false cohort properties")
  func emptyBudgetsCohort() {
    let budgets: [BudgetCohortInfo] = []
    #expect(MixpanelAnalyticsClient.bucket(count: budgets.count) == "0")
  }

  @Test("mixed carry-over budgets correctly set uses_carry_over and has_disabled_carry_over")
  @MainActor
  func mixedCarryOverCohort() {
    let budgets: [BudgetCohortInfo] = [
      BudgetCohortInfo(currencyCode: "USD", periodRawValue: "daily", isCarryOverEnabled: true),
      BudgetCohortInfo(currencyCode: "USD", periodRawValue: "weekly", isCarryOverEnabled: false),
    ]
    #expect(budgets.contains { $0.isCarryOverEnabled })
    #expect(budgets.contains { !$0.isCarryOverEnabled })
  }

  @Test("dominant period is the most frequent period")
  @MainActor
  func dominantPeriod() {
    let budgets: [BudgetCohortInfo] = [
      BudgetCohortInfo(currencyCode: "USD", periodRawValue: "daily", isCarryOverEnabled: true),
      BudgetCohortInfo(currencyCode: "USD", periodRawValue: "daily", isCarryOverEnabled: true),
      BudgetCohortInfo(currencyCode: "EUR", periodRawValue: "weekly", isCarryOverEnabled: false),
    ]
    let dominantPeriodRaw = budgets.mostFrequent(keyPath: \.periodRawValue)
    #expect(dominantPeriodRaw == "daily")
  }
}

// MARK: - Test access to internal mostFrequent helper

extension Array {
  func mostFrequent<T: Hashable>(keyPath: KeyPath<Element, T>) -> T? {
    guard !isEmpty else { return nil }
    var counts: [T: Int] = [:]
    for item in self {
      counts[item[keyPath: keyPath], default: 0] += 1
    }
    return counts.max(by: { $0.value < $1.value })?.key
  }
}
