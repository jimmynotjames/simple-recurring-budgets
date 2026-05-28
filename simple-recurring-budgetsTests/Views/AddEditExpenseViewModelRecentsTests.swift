import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Tests for `AddEditExpenseViewModel`'s F-7.04 Recents API surface — the cached
/// candidate set, the typed-query filter, the Add-mode-only visibility gate, and the
/// `applyRecent` method (including its analytics emission). The static algorithm itself
/// is covered separately by `RecentsAlgorithmTests`; here we exercise the VM-level wiring.
@MainActor
struct AddEditExpenseViewModelRecentsTests {
  // MARK: - Helpers

  /// Compact spec for table-style fixture construction. Avoids a 3-tuple (lint cap = 2).
  private struct ExpenseSpec {
    let name: String?
    let amount: Decimal
    let hoursAgo: Double
  }

  private func makeBudgetWithExpenses(_ specs: [ExpenseSpec]) throws -> Budget {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let now = Date()
    for spec in specs {
      let expense = ExpenseItem(
        amount: spec.amount,
        name: spec.name,
        date: now.addingTimeInterval(-spec.hoursAgo * 3600)
      )
      expense.budget = budget
      context.insert(expense)
    }
    try context.save()
    return budget
  }

  // MARK: - hasRecentSources

  @Test func hasRecentSources_trueWhenBudgetHasEligibleExpenses() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    #expect(vm.hasRecentSources == true)
  }

  @Test func hasRecentSources_falseWhenBudgetIsEmpty() throws {
    let budget = try makeBudgetWithExpenses([])
    let vm = AddEditExpenseViewModel(adding: budget)
    #expect(vm.hasRecentSources == false)
  }

  @Test func hasRecentSources_falseWhenAllExpensesAreIneligible() throws {
    // All Add Funds entries → all filtered out → no sources.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Refund A", amount: -10.00, hoursAgo: 1),
      ExpenseSpec(name: "Refund B", amount: -20.00, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    #expect(vm.hasRecentSources == false)
  }

  // MARK: - filteredRecentSuggestions

  @Test func filteredRecents_emptyQuery_returnsAllCandidates() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    #expect(vm.name == "") // Add-mode default
    #expect(vm.filteredRecentSuggestions.count == 2)
  }

  @Test func filteredRecents_substringMatch_narrowsResults() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
      ExpenseSpec(name: "Groceries", amount: 42.00, hoursAgo: 3),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    vm.name = "co"
    #expect(vm.filteredRecentSuggestions.map(\.name) == ["Coffee"])
  }

  @Test func filteredRecents_caseInsensitiveMatch() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    vm.name = "COFFEE"
    #expect(vm.filteredRecentSuggestions.count == 1)
  }

  @Test func filteredRecents_diacriticInsensitiveMatch() throws {
    // Typing "cafe" finds "Café"; typing "Café" finds "cafe". Same equivalence class
    // the dedup uses (see RecentsAlgorithmTests.dedupIsDiacriticInsensitive).
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Café", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Smoothie", amount: 8.75, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    vm.name = "cafe"
    #expect(vm.filteredRecentSuggestions.map(\.name) == ["Café"])
  }

  @Test func filteredRecents_noMatch_returnsEmpty() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    vm.name = "Pizza"
    #expect(vm.filteredRecentSuggestions.isEmpty)
  }

  @Test func filteredRecents_whitespaceOnlyQuery_treatedAsEmpty() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    vm.name = "   "
    #expect(vm.filteredRecentSuggestions.count == 2) // all candidates
  }

  // MARK: - shouldShowRecentsSection

  @Test func shouldShowRecentsSection_trueInAddModeWithSources() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    #expect(vm.shouldShowRecentsSection == true)
  }

  @Test func shouldShowRecentsSection_falseInAddModeWithoutSources() throws {
    let budget = try makeBudgetWithExpenses([])
    let vm = AddEditExpenseViewModel(adding: budget)
    #expect(vm.shouldShowRecentsSection == false)
  }

  @Test func shouldShowRecentsSection_falseInEditModeEvenWithSources() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let firstExpense = try #require(budget.expenseItems.first { $0.name == "Coffee" })
    let vm = AddEditExpenseViewModel(editing: firstExpense)
    #expect(vm.hasRecentSources == true) // candidates were computed
    #expect(vm.shouldShowRecentsSection == false) // but section is gated off in Edit
  }

  // MARK: - applyRecent

  @Test func applyRecent_writesNameAndAmount() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: SpyAnalyticsClient())
    #expect(vm.name == "Coffee")
    #expect(vm.amount == 5.50)
  }

  @Test func applyRecent_resetsIsAddFundsToFalse_whenWasOn() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    // Capture the pick first — toggling `isAddFunds` from false to true triggers the
    // didSet that seeds `name = "Add funds"`, which would filter our candidate set down
    // to zero before we could grab a suggestion. F-6.01 seeding behavior, not under test.
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.isAddFunds = true
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: SpyAnalyticsClient())
    #expect(vm.isAddFunds == false) // a Recents tile is a prior expense, not Add Funds
  }

  @Test func applyRecent_leavesIsAddFundsFalse_whenAlreadyOff() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    let pick = try #require(vm.filteredRecentSuggestions.first)
    #expect(vm.isAddFunds == false)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: SpyAnalyticsClient())
    #expect(vm.isAddFunds == false)
  }

  @Test func applyRecent_emitsAnalyticsEventWithCategoricalProperties() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    vm.name = "co" // a 2-char query
    let spy = SpyAnalyticsClient()
    let visible = vm.filteredRecentSuggestions
    let pick = try #require(visible.first)
    vm.applyRecent(pick, visibleCount: visible.count, tapPosition: 0, analytics: spy)
    #expect(spy.trackCalls.count == 1)
    let call = try #require(spy.trackCalls.first)
    #expect(call.event == AnalyticsEvent.expenseRecentReused)
    let props = call.properties ?? [:]
    #expect(props[AnalyticsProperty.period] == "daily")
    #expect(props[AnalyticsProperty.recentsTapPosition] == "0")
    // visibleCount = 1 (only "co" matched "Coffee") → bucket "1"
    #expect(props[AnalyticsProperty.recentsVisibleCount] == "1")
    // query "co" length 2 → bucket "1-2"
    #expect(props[AnalyticsProperty.nameQueryLength] == "1-2")
  }

  @Test func applyRecent_eventHasNoPII() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    let spy = SpyAnalyticsClient()
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: spy)
    let call = try #require(spy.trackCalls.first)
    let props = call.properties ?? [:]
    // Never the description or amount value.
    let allValues = props.values.joined(separator: " ")
    #expect(!allValues.contains("Coffee"))
    #expect(!allValues.contains("5.50"))
    #expect(!allValues.contains("5.5"))
    // Property keys are the categorical set only.
    let allowedKeys: Set<String> = [
      AnalyticsProperty.period,
      AnalyticsProperty.recentsVisibleCount,
      AnalyticsProperty.recentsTapPosition,
      AnalyticsProperty.nameQueryLength,
    ]
    #expect(Set(props.keys).isSubset(of: allowedKeys))
  }

  @Test func applyRecent_capturesQueryLengthBeforeOverwritingName() throws {
    // The query-length analytic must reflect what the user was typing AT THE MOMENT of
    // the tap, not the suggestion's name. So a tap on "Coffee" while the user has typed
    // "co" should yield bucket "1-2", not "3+" (the length of "Coffee").
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget)
    vm.name = "co"
    let spy = SpyAnalyticsClient()
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: spy)
    let props = spy.trackCalls.first?.properties ?? [:]
    #expect(props[AnalyticsProperty.nameQueryLength] == "1-2")
  }
}
