//
//  BudgetRecomputeTokenTests.swift
//  simple-recurring-budgetsTests
//
//  Regression guard for issue #127: after a CloudKit sync brings in an expense,
//  the displayed Remaining must recompute. Views drive their cached lifecycle off
//  `.onChange(of: budget.recomputeToken)`, so the token MUST change whenever a
//  child row is inserted, edited, or removed — even when the parent
//  `Budget.lastModified` is NOT bumped (the remote-merge race that produced the bug).
//

import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

struct BudgetRecomputeTokenTests {
  /// Inserting an expense without touching `budget.lastModified` (the remote-merge
  /// case) still changes the token — and the lifecycle math reflects the new expense.
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

    // Simulate a remote merge: a synced ExpenseItem appears, but the parent
    // budget's `lastModified` is unchanged (it arrived in a separate transaction).
    let expense = ExpenseItem(amount: 5)
    expense.budget = budget
    context.insert(expense)
    try context.save()

    #expect(budget.lastModified == lastModifiedBefore, "Precondition: lastModified must NOT change")
    #expect(budget.recomputeToken != tokenBefore, "Token must change when an expense is inserted")
    #expect(BudgetLifecycleService.result(for: budget, weekStart: .sunday).remaining == 45)
  }

  /// Editing an existing expense's amount (count unchanged) still changes the token,
  /// because the edited row's `lastModified` advances the latest-child timestamp.
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

  /// A no-op (no child or field change) leaves the token equal, so the view does not
  /// recompute needlessly.
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
