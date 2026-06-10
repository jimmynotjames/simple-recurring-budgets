import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Covers the UUID route-resolution lookups (`ModelContext.budget(id:)` /
/// `.expenseItem(id:)`) that back `AppRoute` / `SheetRoute` destination
/// resolution in `RootView` (architecture-audit-2026-06-10.md §4.2).
@MainActor
struct ModelContextLookupTests {
  @Test func budgetLookup_findsSavedBudget() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .weekly)
    context.insert(budget)
    try context.save()

    let found = context.budget(id: budget.id)
    #expect(found?.name == "Groceries")
  }

  @Test func budgetLookup_returnsNilForUnknownID() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Groceries")
    context.insert(budget)
    try context.save()

    #expect(context.budget(id: UUID()) == nil)
  }

  @Test func budgetLookup_returnsNilAfterDelete() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Groceries")
    context.insert(budget)
    try context.save()
    let id = budget.id

    context.delete(budget)
    try context.save()

    #expect(context.budget(id: id) == nil)
  }

  @Test func expenseLookup_findsSavedExpense() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let expense = ExpenseItem(amount: 5, name: "Coffee")
    context.insert(expense)
    try context.save()

    let found = context.expenseItem(id: expense.id)
    #expect(found?.name == "Coffee")
  }

  @Test func expenseLookup_returnsNilForUnknownID() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    #expect(context.expenseItem(id: UUID()) == nil)
  }
}
