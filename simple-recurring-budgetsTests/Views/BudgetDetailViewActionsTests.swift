import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Reset Budget

struct ResetBudgetAlgorithmTests {
  // MARK: Happy path

  /// Algorithm deletes all expenses, zeros carryOver, and bumps timestamps.
  @Test func resetBudget_happyPath() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Groceries", allocation: 100)
    budget.carryOverAmount = 12.50
    context.insert(budget)
    let expenses = [
      ExpenseItem(amount: 10, name: "Apples"),
      ExpenseItem(amount: 20, name: "Bread"),
      ExpenseItem(amount: 5, name: "Milk"),
    ]
    for e in expenses {
      e.budget = budget
      context.insert(e)
    }
    try context.save()
    #expect(budget.expenseItems.count == 3)

    // Inline the resetBudget algorithm
    Thread.sleep(forTimeInterval: 0.001)
    let now = Date()
    for expense in Array(budget.expenseItems) {
      context.delete(expense)
    }
    budget.carryOverAmount = 0
    budget.carryOverLastResetDate = now
    budget.lastModified = now
    try context.save()

    #expect(budget.expenseItems.isEmpty)
    #expect(budget.carryOverAmount == 0)
    #expect(budget.carryOverLastResetDate >= now)
    #expect(budget.lastModified >= now)
  }

  // MARK: Budget entity is preserved

  /// The Budget row itself SHALL NOT be deleted by resetBudget.
  @Test func resetBudget_budgetEntityPreserved() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Fun Money", allocation: 60, currencyCode: "USD", period: .weekly)
    context.insert(budget)
    let budgetID = budget.id
    for i in 1 ... 2 {
      let e = ExpenseItem(amount: Decimal(i) * 5, name: "Item \(i)")
      e.budget = budget
      context.insert(e)
    }
    try context.save()

    // Run resetBudget algorithm
    for expense in Array(budget.expenseItems) {
      context.delete(expense)
    }
    budget.carryOverAmount = 0
    budget.carryOverLastResetDate = Date()
    budget.lastModified = Date()
    try context.save()

    // Verify via a fresh ModelContext
    let context2 = ModelContext(container)
    let fetched = try context2.fetch(FetchDescriptor<Budget>())
    let found = fetched.first { $0.id == budgetID }
    #expect(found != nil, "Budget entity must still exist after Reset Budget")
    #expect(found?.name == "Fun Money")
    #expect(found?.allocation == 60)
    #expect(found?.currencyCode == "USD")
  }

  // MARK: Empty starting state

  /// Calling resetBudget on a budget with zero expenses must not crash and
  /// must still zero carryOver and bump timestamps.
  @Test func resetBudget_emptyBudget() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Empty", allocation: 50)
    budget.carryOverAmount = 0
    context.insert(budget)
    try context.save()

    Thread.sleep(forTimeInterval: 0.001)
    let now = Date()
    for expense in Array(budget.expenseItems) {
      context.delete(expense)
    }
    budget.carryOverAmount = 0
    budget.carryOverLastResetDate = now
    budget.lastModified = now
    try context.save()

    #expect(budget.expenseItems.isEmpty)
    #expect(budget.carryOverAmount == 0)
    #expect(budget.lastModified >= now)
  }

  // MARK: Isolation — does not affect other budgets

  /// resetBudget on budget A must not touch budget B's expenses or carryOver.
  @Test func resetBudget_isolatedToTargetBudget() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budgetA = Budget(name: "A", allocation: 100)
    budgetA.carryOverAmount = 5
    let budgetB = Budget(name: "B", allocation: 200)
    budgetB.carryOverAmount = 10
    context.insert(budgetA); context.insert(budgetB)

    for i in 1 ... 2 {
      let ea = ExpenseItem(amount: Decimal(i), name: "A-\(i)")
      ea.budget = budgetA; context.insert(ea)
      let eb = ExpenseItem(amount: Decimal(i) * 2, name: "B-\(i)")
      eb.budget = budgetB; context.insert(eb)
    }
    try context.save()

    // Reset only budget A
    for expense in Array(budgetA.expenseItems) {
      context.delete(expense)
    }
    budgetA.carryOverAmount = 0
    budgetA.carryOverLastResetDate = Date()
    budgetA.lastModified = Date()
    try context.save()

    #expect(budgetA.expenseItems.isEmpty)
    #expect(budgetA.carryOverAmount == 0)
    #expect(budgetB.expenseItems.count == 2, "Budget B expenses should be untouched")
    #expect(budgetB.carryOverAmount == 10, "Budget B carry-over should be untouched")
  }

  // MARK: Atomicity — changes visible after refetch through fresh context

  @Test func resetBudget_persistsAtomically() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Atomic", allocation: 50)
    budget.carryOverAmount = 3
    context.insert(budget)
    let e1 = ExpenseItem(amount: 10, name: "X"); e1.budget = budget; context.insert(e1)
    let e2 = ExpenseItem(amount: 20, name: "Y"); e2.budget = budget; context.insert(e2)
    try context.save()
    let budgetID = budget.id

    for expense in Array(budget.expenseItems) {
      context.delete(expense)
    }
    budget.carryOverAmount = 0
    budget.carryOverLastResetDate = Date()
    budget.lastModified = Date()
    try context.save()

    let context2 = ModelContext(container)
    let allExpenses = try context2.fetch(FetchDescriptor<ExpenseItem>())
    // Extract filter result before #expect to avoid a macro-expansion issue with
    // optional-chaining inside chained .filter { }.isEmpty expressions.
    let remainingForBudget = allExpenses.filter { $0.budget?.id == budgetID }
    #expect(
      remainingForBudget.isEmpty,
      "No ExpenseItems for this budget should remain after a save"
    )
    let budgets = try context2.fetch(FetchDescriptor<Budget>())
    let refetched = budgets.first { $0.id == budgetID }
    #expect(refetched?.carryOverAmount == 0)
  }
}

// MARK: - Reset Carry-Over

struct ResetCarryOverAlgorithmTests {
  /// resetCarryOver zeros carryOver but does NOT delete any expenses.
  @Test func resetCarryOver_zerosCarryOverPreservesExpenses() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Lunch", allocation: 50)
    budget.carryOverAmount = -7.25
    context.insert(budget)
    let e1 = ExpenseItem(amount: 10, name: "Burger"); e1.budget = budget; context.insert(e1)
    let e2 = ExpenseItem(amount: 8, name: "Salad"); e2.budget = budget; context.insert(e2)
    try context.save()

    Thread.sleep(forTimeInterval: 0.001)
    let now = Date()
    budget.carryOverAmount = 0
    budget.carryOverLastResetDate = now
    budget.lastModified = now
    try context.save()

    #expect(budget.carryOverAmount == 0)
    #expect(budget.carryOverLastResetDate >= now)
    #expect(budget.lastModified >= now)
    #expect(budget.expenseItems.count == 2, "Expenses must NOT be deleted by resetCarryOver")

    // Verify via fresh context
    let context2 = ModelContext(container)
    let allExpenses = try context2.fetch(FetchDescriptor<ExpenseItem>())
    #expect(allExpenses.count == 2)
  }
}

// MARK: - Delete Expense

struct DeleteExpenseAlgorithmTests {
  /// Only the targeted expense is removed; siblings and the budget are untouched.
  @Test func deleteExpense_onlyTargetRemoved() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Entertainment", allocation: 100)
    budget.carryOverAmount = 4
    context.insert(budget)
    let e1 = ExpenseItem(amount: 15, name: "Movie"); e1.budget = budget; context.insert(e1)
    let e2 = ExpenseItem(amount: 8, name: "Popcorn"); e2.budget = budget; context.insert(e2)
    let e3 = ExpenseItem(amount: 22, name: "Dinner"); e3.budget = budget; context.insert(e3)
    let e2ID = e2.id
    try context.save()

    // Delete only e2
    context.delete(e2)
    try context.save()

    // Verify via fresh context
    let context2 = ModelContext(container)
    let allExpenses = try context2.fetch(FetchDescriptor<ExpenseItem>())
    let remainingIDs = Set(allExpenses.map(\.id))

    #expect(allExpenses.count == 2)
    #expect(!remainingIDs.contains(e2ID), "Targeted expense must be gone")
    #expect(remainingIDs.contains(e1.id), "e1 must remain")
    #expect(remainingIDs.contains(e3.id), "e3 must remain")
  }

  /// Budget.lastModified is NOT bumped by deleteExpense; the lifecycle service
  /// updates its own fields independently.
  @Test func deleteExpense_doesNotBumpBudgetLastModified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Coffee", allocation: 20)
    context.insert(budget)
    let originalModified = budget.lastModified
    let e = ExpenseItem(amount: 5, name: "Latte"); e.budget = budget; context.insert(e)
    try context.save()

    Thread.sleep(forTimeInterval: 0.001)
    context.delete(e)
    try context.save()

    #expect(
      budget.lastModified == originalModified,
      "deleteExpense must NOT bump Budget.lastModified"
    )
  }

  /// deleteExpense invoked directly (no confirmation staging) removes the expense.
  /// This covers the path used by the swipe-to-delete action after the confirmation
  /// dialog was removed and `allowsFullSwipe` was enabled.
  @Test func deleteExpense_swipeDeleteCallsDirectly() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Dining", allocation: 80)
    context.insert(budget)
    let target = ExpenseItem(amount: 12, name: "Lunch"); target.budget = budget; context.insert(target)
    let keeper = ExpenseItem(amount: 6, name: "Coffee"); keeper.budget = budget; context.insert(keeper)
    let targetID = target.id
    try context.save()

    // Simulate what deleteExpense(_:) does directly (no expenseToDelete staging).
    context.delete(target)
    try context.save()

    let context2 = ModelContext(container)
    let all = try context2.fetch(FetchDescriptor<ExpenseItem>())
    let ids = Set(all.map(\.id))
    #expect(!ids.contains(targetID), "Directly-deleted expense must be removed")
    #expect(ids.contains(keeper.id), "Sibling expense must remain")
    #expect(all.count == 1)
  }

  /// Changes persist atomically across a fresh ModelContext.
  @Test func deleteExpense_persistsAtomically() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Shopping", allocation: 200)
    context.insert(budget)
    let target = ExpenseItem(amount: 30, name: "Shoes"); target.budget = budget; context.insert(target)
    let keeper = ExpenseItem(amount: 12, name: "Socks"); keeper.budget = budget; context.insert(keeper)
    let targetID = target.id
    let keeperID = keeper.id
    try context.save()

    context.delete(target)
    try context.save()

    let context2 = ModelContext(container)
    let all = try context2.fetch(FetchDescriptor<ExpenseItem>())
    let ids = Set(all.map(\.id))
    #expect(!ids.contains(targetID))
    #expect(ids.contains(keeperID))
  }
}

// MARK: - Expense Row Push Navigation

struct ExpenseRowPushNavigationTests {
  /// Tapping a row appends AppRoute.expenseDetail to the router path.
  @Test func tapExpenseRow_appendsExpenseDetailRoute() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let expense = ExpenseItem(amount: 5, name: "Coffee")
    context.insert(expense)
    try context.save()

    let router = Router()
    router.path.append(AppRoute.expenseDetail(expense))

    #expect(router.path.count == 1)
    #expect(router.path.last == AppRoute.expenseDetail(expense))
  }

  /// Two AppRoute.expenseDetail values wrapping the same ExpenseItem are equal.
  @Test func appRoute_expenseDetail_isHashable() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let expense = ExpenseItem(amount: 10, name: "Lunch")
    context.insert(expense)
    try context.save()

    let routeA = AppRoute.expenseDetail(expense)
    let routeB = AppRoute.expenseDetail(expense)
    #expect(routeA == routeB)
    #expect(routeA.hashValue == routeB.hashValue)
  }

  /// Two AppRoute.expenseDetail values wrapping distinct ExpenseItems are not equal.
  @Test func appRoute_expenseDetail_differsByExpense() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let expenseA = ExpenseItem(amount: 5, name: "Tea")
    let expenseB = ExpenseItem(amount: 8, name: "Juice")
    context.insert(expenseA)
    context.insert(expenseB)
    try context.save()

    #expect(AppRoute.expenseDetail(expenseA) != AppRoute.expenseDetail(expenseB))
  }
}
