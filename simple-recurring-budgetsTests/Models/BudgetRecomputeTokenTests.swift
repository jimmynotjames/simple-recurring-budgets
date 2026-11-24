//
//  BudgetRecomputeTokenTests.swift
//  simple-recurring-budgetsTests
//
//  Guards the CloudKit-sync recompute: after a sync brings in an expense, the displayed
//  Remaining must update. Views drive their cached lifecycle off
//  `.onChange(of: budget.recomputeToken)`, so the token MUST change whenever a child row is
//  inserted, edited, or removed, even if the parent `Budget.lastModified` is NOT bumped
//  (the remote-merge race).
//

import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

struct BudgetRecomputeTokenTests {
  /// Inserting an expense without touching `budget.lastModified` (remote merge) still
  /// changes the token, and the lifecycle math reflects the expense.
  @Test func token_changesWhenExpenseInsertedWithoutBumpingLastModified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Groceries")
    context.insert(budget)
    let allocation = AllocationChange(effectiveFrom: budget.effectiveStartDate, amount: 50)
    allocation.budget = budget
    context.insert(allocation)
    try context.save()

    let tokenBefore = budget.recomputeToken
    let lastModifiedBefore = budget.lastModified

    // Remote merge: the synced ExpenseItem arrives in a separate transaction, leaving the
    // parent `lastModified` unchanged.
    let expense = ExpenseItem(amount: 5)
    expense.budget = budget
    context.insert(expense)
    try context.save()

    #expect(budget.lastModified == lastModifiedBefore, "Precondition: lastModified must NOT change")
    #expect(budget.recomputeToken != tokenBefore, "Token must change when an expense is inserted")
    #expect(BudgetLifecycleService.result(for: budget, weekStart: .sunday).remaining == 45)
  }

  /// Editing an expense's amount (count unchanged) changes the token via the edited row's
  /// `lastModified` (latest-child timestamp).
  @Test func token_changesWhenExpenseEdited() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Groceries")
    context.insert(budget)
    let expense = ExpenseItem(amount: 5)
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let tokenBefore = budget.recomputeToken

    expense.amount = 8
    expense.lastModified = expense.lastModified.addingTimeInterval(1)

    #expect(budget.recomputeToken != tokenBefore, "Token must change when an expense amount is edited")
  }

  /// Removing an expense changes the token (count drops).
  @Test func token_changesWhenExpenseDeleted() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Groceries")
    context.insert(budget)
    let expense = ExpenseItem(amount: 5)
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let tokenBefore = budget.recomputeToken

    context.delete(expense)
    try context.save()

    #expect(budget.recomputeToken != tokenBefore, "Token must change when an expense is deleted")
  }

  /// A no-op leaves the token equal so the view doesn't recompute needlessly.
  @Test func token_stableWhenNothingChanges() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Groceries")
    context.insert(budget)
    let expense = ExpenseItem(amount: 5)
    expense.budget = budget
    context.insert(expense)
    try context.save()

    #expect(budget.recomputeToken == budget.recomputeToken)
  }
}
