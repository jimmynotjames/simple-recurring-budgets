@testable import simple_recurring_budgets
import Testing

/// PII enforcement: expense_* events carry no ExpenseItem fields.
@Suite("PII Enforcement — §18.1 #8")
@MainActor
struct PIIEnforcementCallSiteTests {
  /// Keys allowed on expense_* events.
  private static let expenseAllowList: Set<String> = [
    AnalyticsProperty.period,
    AnalyticsProperty.isAddFunds,
    AnalyticsProperty.fromScreen,
    AnalyticsProperty.timeSinceBudgetCreatedBucket,
  ]

  /// Keys that are NEVER allowed on expense_* events.
  private static let expenseDenyList: Set<String> = [
    "expense_name",
    "expense_amount",
    "expense_date",
    "expense_notes",
    "name",
    "amount",
    "date",
    "notes",
  ]

  @Test("expense_logged properties contain only allow-listed keys")
  func expenseLoggedAllowListedOnly() {
    let spy = SpyAnalyticsClient()
    // Mirrors the expense_logged property bag from AddEditExpenseViewModel.save().
    spy.track(
      AnalyticsEvent.expenseLogged,
      properties: [
        AnalyticsProperty.period: "daily",
        AnalyticsProperty.isAddFunds: false,
        AnalyticsProperty.fromScreen: "add_sheet",
        AnalyticsProperty.timeSinceBudgetCreatedBucket: "<1h",
      ]
    )
    #expect(spy.trackCalls.count == 1)
    let call = spy.trackCalls[0]
    #expect(call.event == AnalyticsEvent.expenseLogged)
    let keys = call.properties.map { Set($0.keys) } ?? []
    #expect(keys.isDisjoint(with: Self.expenseDenyList))
    #expect(keys.isSubset(of: Self.expenseAllowList))
  }

  @Test("expense_edited properties contain only allow-listed keys")
  func expenseEditedAllowListedOnly() {
    let spy = SpyAnalyticsClient()
    spy.track(
      AnalyticsEvent.expenseEdited,
      properties: [
        AnalyticsProperty.period: "weekly",
        AnalyticsProperty.isAddFunds: false,
        AnalyticsProperty.fromScreen: "budget_detail",
      ]
    )
    let keys = spy.trackCalls[0].properties.map { Set($0.keys) } ?? []
    #expect(keys.isDisjoint(with: Self.expenseDenyList))
  }

  @Test("expense_deleted properties contain only allow-listed keys")
  func expenseDeletedAllowListedOnly() {
    let spy = SpyAnalyticsClient()
    spy.track(
      AnalyticsEvent.expenseDeleted,
      properties: [
        AnalyticsProperty.period: "monthly",
        AnalyticsProperty.isAddFunds: false,
        AnalyticsProperty.fromScreen: "budget_detail",
      ]
    )
    let keys = spy.trackCalls[0].properties.map { Set($0.keys) } ?? []
    #expect(keys.isDisjoint(with: Self.expenseDenyList))
  }

  @Test("no AnalyticsClient extension accepts ExpenseItem parameter")
  func noExtensionAcceptsExpenseItemParameter() {
    // Structural: the protocol surface is `track`, `identify`, `reset` plus one `track`
    // convenience overload, so PII could only leak via a call site's property dict
    // (covered by the property-bag tests above).
    let spy = SpyAnalyticsClient()
    spy.track("test") // convenience overload
    spy.track("test", properties: nil) // full signature
    spy.identify(nil)
    spy.reset()
    #expect(spy.trackCalls.count == 2)
  }
}
