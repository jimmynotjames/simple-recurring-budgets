//
//  ModelTests.swift
//  simple-recurring-budgetsTests
//
//  Created by Jimmy Ho on 4/11/26.
//

import Foundation
import SwiftData
import Testing
@testable import simple_recurring_budgets

// MARK: - Helpers

/// Creates an in-memory `ModelContainer` for testing. CloudKit is disabled in-memory.
private func makeInMemoryContainer() throws -> ModelContainer {
    let schema = Schema([Budget.self, ExpenseItem.self])
    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    return try ModelContainer(
        for: schema,
        migrationPlan: BudgetMigrationPlan.self,
        configurations: config
    )
}

// MARK: - ModelContainer creation (task 6.3)

struct ModelContainerTests {

    @Test func inMemoryContainerCreatesSuccessfully() throws {
        _ = try makeInMemoryContainer()
    }
}

// MARK: - Budget defaults (task 6.2)

struct BudgetModelTests {

    @Test func budget_defaultsAreCorrect() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let budget = Budget()
        budget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(budget)

        #expect(budget.name == "Budget")
        #expect(budget.allocation == 10)
        #expect(budget.period == BudgetPeriod.daily.rawValue)
        #expect(budget.resetCadence == ResetCadence.weekly.rawValue)
        #expect(budget.carryOverAmount == 0)
        #expect(budget.isCarryOverEnabled == true)
        #expect(budget.expenses.isEmpty)
        #expect(budget.sortOrder == 0)
    }

    @Test func budget_customValuesStored() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let budget = Budget(
            name: "Groceries",
            allocation: 500,
            currencyCode: "EUR",
            period: .monthly,
            resetCadence: .quarterly
        )
        budget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(budget)

        #expect(budget.name == "Groceries")
        #expect(budget.allocation == 500)
        #expect(budget.currencyCode == "EUR")
        #expect(budget.period == "monthly")
        #expect(budget.resetCadence == "quarterly")
    }

    @Test func budget_defaultResetCadence_followsPeriod() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let weeklyBudget = Budget(period: .weekly)
        weeklyBudget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(weeklyBudget)
        #expect(weeklyBudget.resetCadence == ResetCadence.monthly.rawValue)

        let biweeklyBudget = Budget(period: .biweekly)
        biweeklyBudget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(biweeklyBudget)
        #expect(biweeklyBudget.resetCadence == ResetCadence.quarterly.rawValue)
    }

    @Test func budget_sortOrder_firstBudgetIsZero() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let budget = Budget()
        budget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(budget)
        #expect(budget.sortOrder == 0)
    }

    @Test func budget_sortOrder_incrementsAfterEachInsert() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        for expected in 0..<3 {
            let budget = Budget()
            budget.sortOrder = try Budget.nextSortOrder(for: context)
            context.insert(budget)
            #expect(budget.sortOrder == expected)
        }
    }

    @Test func budget_cascadeDeletesExpenses() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let budget = Budget()
        budget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(budget)

        let expense = ExpenseItem(amount: 10)
        expense.budget = budget
        context.insert(expense)
        budget.expenses.append(expense)

        let budgetId = budget.id
        context.delete(budget)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<ExpenseItem>())
        #expect(remaining.isEmpty, "Cascade delete should remove all linked ExpenseItems")

        let budgets = try context.fetch(FetchDescriptor<Budget>())
        #expect(!budgets.contains(where: { $0.id == budgetId }))
    }
}

// MARK: - ExpenseItem defaults and signed amount (task 6.2)

struct ExpenseItemModelTests {

    @Test func expenseItem_defaultsAreCorrect() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let item = ExpenseItem(amount: 25)
        context.insert(item)

        #expect(item.amount == 25)
        #expect(item.name == nil)
        #expect(item.expenseType == nil)
        #expect(item.isAddFunds == false)
        #expect(item.displayAmount == 25)
    }

    @Test func expenseItem_positiveAmount_isExpense() {
        let item = ExpenseItem(amount: 50)
        #expect(item.isAddFunds == false)
        #expect(item.displayAmount == 50)
    }

    @Test func expenseItem_negativeAmount_isAddFunds() {
        let item = ExpenseItem(amount: -30)
        #expect(item.isAddFunds == true)
        #expect(item.displayAmount == 30)
    }

    @Test func expenseItem_linkedToBudget() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let budget = Budget()
        budget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(budget)

        let item = ExpenseItem(amount: 15)
        item.budget = budget
        context.insert(item)
        budget.expenses.append(item)

        #expect(budget.expenses.count == 1)
        #expect(budget.expenses.first?.amount == 15)
    }
}
