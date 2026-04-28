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

// MARK: - ModelContainer creation (task 6.3)

struct ModelContainerTests {

    @Test func inMemoryContainerCreatesSuccessfully() throws {
        _ = try TestModelContainer.make()
    }
}

// MARK: - Budget defaults (task 6.2)

struct BudgetModelTests {

    @Test func budget_defaultsAreCorrect() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let budget = Budget()
        budget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(budget)

        #expect(budget.name == "Budget")
        #expect(budget.allocation == 10)
        #expect(budget.period == BudgetPeriod.daily.rawValue)
        #expect(budget.resetCadence == ResetCadence.never.rawValue) // PAUSED (Reset Cadences)
        #expect(budget.carryOverAmount == 0)
        #expect(budget.isCarryOverEnabled == true)
        #expect(budget.expenseItems.isEmpty)
        #expect(budget.sortOrder == 0)
    }

    @Test func budget_customValuesStored() throws {
        let container = try TestModelContainer.make()
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

    // PAUSED (Reset Cadences): while paused, Budget.init always defaults to .never regardless
    // of period. The type-level defaultResetCadence mapping is still tested in EnumTests.swift.
    @Test func budget_defaultResetCadence_isNeverWhilePaused() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        for period in BudgetPeriod.allCases {
            let budget = Budget(period: period)
            budget.sortOrder = try Budget.nextSortOrder(for: context)
            context.insert(budget)
            #expect(
                budget.resetCadence == ResetCadence.never.rawValue,
                "Expected .never for period \(period.rawValue) while Reset Cadences are paused"
            )
        }
    }

    @Test func budget_sortOrder_firstBudgetIsZero() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let budget = Budget()
        budget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(budget)
        #expect(budget.sortOrder == 0)
    }

    @Test func budget_sortOrder_incrementsAfterEachInsert() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        for expected in 0..<3 {
            let budget = Budget()
            budget.sortOrder = try Budget.nextSortOrder(for: context)
            context.insert(budget)
            #expect(budget.sortOrder == expected)
        }
    }

    @Test func budget_cascadeDeletesExpenses() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let budget = Budget()
        budget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(budget)

        let expense = ExpenseItem(amount: 10)
        expense.budget = budget
        context.insert(expense)
        budget.expenseItems.append(expense)

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
        let container = try TestModelContainer.make()
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
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let budget = Budget()
        budget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(budget)

        let item = ExpenseItem(amount: 15)
        item.budget = budget
        context.insert(item)
        budget.expenseItems.append(item)

        #expect(budget.expenseItems.count == 1)
        #expect(budget.expenseItems.first?.amount == 15)
    }
}
