import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// F-6.01 Add Funds toggle — wiring tests for `AddEditExpenseViewModel`.
///
/// Co-located with `AddEditExpenseViewModelTests` but in its own file to stay under the
/// project's 600-line per-file lint cap.
@MainActor
struct AddEditExpenseViewModelAddFundsTests {
  // MARK: - Helpers

  private func makeBudget(in context: ModelContext) -> Budget {
    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    return budget
  }

  private func expenseLoggedProperties(_ spy: SpyAnalyticsClient) -> [String: String]? {
    spy.trackCalls.first(where: { $0.event == AnalyticsEvent.expenseLogged })?.properties
  }

  private func expenseEditedCalls(_ spy: SpyAnalyticsClient) -> [SpyAnalyticsClient.TrackCall] {
    spy.trackCalls.filter { $0.event == AnalyticsEvent.expenseEdited }
  }

  // MARK: - 1. Add-mode sign on save (task 6.1)

  @Test func addMode_save_isAddFundsFalse_insertsPositiveAmount() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = makeBudget(in: context)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    vm.amount = 5
    vm.name = "Coffee"
    // isAddFunds defaults to false
    vm.save(context: context, analytics: spy)

    let expense = try #require(budget.expenseItems.first)
    #expect(expense.amount == 5)
    #expect(expense.isAddFunds == false)

    let props = try #require(expenseLoggedProperties(spy))
    #expect(props[AnalyticsProperty.isAddFunds] == "false")
  }

  @Test func addMode_save_isAddFundsTrue_insertsNegativeAmount() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = makeBudget(in: context)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    vm.amount = 25
    vm.name = "Refund"
    vm.isAddFunds = true
    vm.save(context: context, analytics: spy)

    let expense = try #require(budget.expenseItems.first)
    #expect(expense.amount == -25)
    #expect(expense.isAddFunds == true)

    let props = try #require(expenseLoggedProperties(spy))
    #expect(props[AnalyticsProperty.isAddFunds] == "true")
  }

  // MARK: - 2. Edit-mode init seeds isAddFunds from the existing row (task 6.2)

  @Test func editMode_init_seedsIsAddFundsFromNegativeExpense() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = makeBudget(in: context)
    let expense = ExpenseItem(amount: -10, name: "Reimbursement")
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense)

    #expect(vm.isAddFunds == true)
    #expect(vm.amount == 10) // displayAmount, not signed
  }

  @Test func editMode_init_seedsIsAddFundsFromPositiveExpense() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = makeBudget(in: context)
    let expense = ExpenseItem(amount: 4.50, name: "Coffee")
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense)

    #expect(vm.isAddFunds == false)
    #expect(vm.amount == 4.50)
  }

  // MARK: - 3. Edit-mode init does NOT fire the description seed (task 6.3)

  @Test func editMode_init_doesNotSeedDefaultDescription() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = makeBudget(in: context)
    // Negative-amount expense with nil name: if the didSet fired, vm.name would become
    // "Add funds". It must NOT fire on initializer-phase assignment.
    let expense = ExpenseItem(amount: -10, name: nil)
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense)

    #expect(vm.isAddFunds == true)
    #expect(vm.name == "") // empty, not "Add funds"
  }

  // MARK: - 4. Edit-mode standalone toggle flip (tasks 6.4, 6.5)

  @Test func editMode_save_toggleFlipFalseToTrue_flipsSign() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = makeBudget(in: context)
    let expense = ExpenseItem(amount: 5, name: "Snack")
    expense.budget = budget
    let originalLastModified = Date(timeIntervalSinceNow: -3600)
    expense.lastModified = originalLastModified
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense)
    #expect(vm.isAddFunds == false)
    #expect(vm.amount == 5)

    // Flip the toggle. Leave amount, name, date untouched.
    vm.isAddFunds = true
    vm.save(context: context, analytics: spy)

    #expect(expense.amount == -5)
    #expect(expense.isAddFunds == true)
    #expect(expense.lastModified > originalLastModified)

    let edited = expenseEditedCalls(spy)
    #expect(edited.count == 1)
    #expect(edited.first?.properties?[AnalyticsProperty.isAddFunds] == "true")
  }

  @Test func editMode_save_toggleFlipTrueToFalse_flipsSign() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = makeBudget(in: context)
    let expense = ExpenseItem(amount: -25, name: "Refund")
    expense.budget = budget
    let originalLastModified = Date(timeIntervalSinceNow: -3600)
    expense.lastModified = originalLastModified
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense)
    #expect(vm.isAddFunds == true)
    #expect(vm.amount == 25)

    vm.isAddFunds = false
    vm.save(context: context, analytics: spy)

    #expect(expense.amount == 25)
    #expect(expense.isAddFunds == false)
    #expect(expense.lastModified > originalLastModified)

    let edited = expenseEditedCalls(spy)
    #expect(edited.count == 1)
    #expect(edited.first?.properties?[AnalyticsProperty.isAddFunds] == "false")
  }

  // MARK: - 5. Combined flip + amount change (task 6.6)

  @Test func editMode_save_flipAndChangeAmount_persistsBothInOneWrite() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = makeBudget(in: context)
    let expense = ExpenseItem(amount: 5, name: "Snack")
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense)
    vm.isAddFunds = true
    vm.amount = 12
    vm.save(context: context, analytics: spy)

    #expect(expense.amount == -12)
    #expect(expense.isAddFunds == true)

    // Exactly one expense_edited event (not two — single coherent write)
    #expect(expenseEditedCalls(spy).count == 1)
  }

  // MARK: - 6. Description seed cases (task 6.7)

  @Test func descriptionSeed_emptyName_toggleOn_seedsDefault() {
    let budget = Budget()
    let vm = AddEditExpenseViewModel(adding: budget)
    #expect(vm.name == "")

    vm.isAddFunds = true

    #expect(vm.name == "Add funds")
  }

  @Test func descriptionSeed_nonEmptyName_toggleOn_doesNotOverwrite() {
    let budget = Budget()
    let vm = AddEditExpenseViewModel(adding: budget)
    vm.name = "Refund from Acme"

    vm.isAddFunds = true

    #expect(vm.name == "Refund from Acme")
  }

  @Test func descriptionSeed_whitespaceOnlyName_toggleOn_seedsDefault() {
    let budget = Budget()
    let vm = AddEditExpenseViewModel(adding: budget)
    vm.name = "   "

    vm.isAddFunds = true

    #expect(vm.name == "Add funds")
  }

  @Test func descriptionSeed_toggleOnThenOff_retainsSeededName() {
    let budget = Budget()
    let vm = AddEditExpenseViewModel(adding: budget)
    vm.isAddFunds = true
    #expect(vm.name == "Add funds")

    vm.isAddFunds = false

    #expect(vm.name == "Add funds") // retained on toggle-off (not cleared)
  }

  @Test func descriptionSeed_secondToggleOn_doesNotOverwriteNonEmpty() {
    let budget = Budget()
    let vm = AddEditExpenseViewModel(adding: budget)
    vm.isAddFunds = true
    #expect(vm.name == "Add funds")
    vm.isAddFunds = false
    // Now name is non-empty ("Add funds"); second toggle-on should NOT re-seed
    // anything different — it should leave the existing non-empty name alone.
    vm.isAddFunds = true

    #expect(vm.name == "Add funds")
  }
}
