import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - ModelContainer creation

struct ModelContainerTests {
  @Test func inMemoryContainerCreatesSuccessfully() throws {
    _ = try TestModelContainer.make()
  }
}

// MARK: - Budget defaults

struct BudgetModelTests {
  @Test func budget_defaultsAreCorrect() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget()
    budget.sortOrder = try Budget.nextSortOrder(for: context)
    context.insert(budget)

    #expect(budget.name == "Budget")
    #expect(budget.period == BudgetPeriod.daily.rawValue)
    #expect(budget.startDate == nil)
    #expect(budget.endDate == nil)
    #expect(budget.lastResetDate == nil)
    #expect(budget.isCarryOverEnabled == true)
    #expect(budget.expenseItems.isEmpty)
    #expect(budget.allocationChanges.isEmpty)
    #expect(budget.lifecycleEvents.isEmpty)
    #expect(budget.sortOrder == 0)
    #expect(budget.currentAllocation == 0)
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
    for expected in 0 ..< 3 {
      let budget = Budget()
      budget.sortOrder = try Budget.nextSortOrder(for: context)
      context.insert(budget)
      #expect(budget.sortOrder == expected)
    }
  }

  @Test func budget_cascadeDeletesExpensesAllocationChangesAndLifecycleEvents() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget()
    budget.sortOrder = try Budget.nextSortOrder(for: context)
    context.insert(budget)

    let expense = ExpenseItem(amount: 10)
    expense.budget = budget
    context.insert(expense)

    let change = AllocationChange(effectiveFrom: Date(), amount: 20)
    change.budget = budget
    context.insert(change)

    let event = LifecycleEvent(kind: .pause, effectiveDate: Date())
    event.budget = budget
    context.insert(event)

    context.delete(budget)
    try context.save()

    #expect(try context.fetch(FetchDescriptor<ExpenseItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<AllocationChange>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<LifecycleEvent>()).isEmpty)
  }
}

// MARK: - AllocationChange round-trip

struct AllocationChangeModelTests {
  @Test func allocationChange_insertsAndFetches() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(); context.insert(budget)
    let change = AllocationChange(effectiveFrom: Date(), amount: 25)
    change.budget = budget; context.insert(change)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<AllocationChange>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.amount == 25)
  }

  @Test func allocationChange_budgetComputedAccessor_nonOptional() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(); context.insert(budget)
    let change = AllocationChange(effectiveFrom: Date(), amount: 30)
    change.budget = budget; context.insert(change)

    // allocationChanges accessor returns non-optional
    let allocs: [AllocationChange] = budget.allocationChanges
    #expect(allocs.count == 1)
    #expect(allocs.first?.amount == 30)
  }

  @Test func allocationChange_currentAllocation_returnsLatest() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    var comps = DateComponents()
    comps.year = 2026; comps.month = 4; comps.day = 1
    comps.timeZone = TimeZone(identifier: "UTC")
    let startDate = try #require(Calendar(identifier: .gregorian).date(from: comps))
    comps.day = 10
    let laterDate = try #require(Calendar(identifier: .gregorian).date(from: comps))

    let budget = Budget(); context.insert(budget)
    let c1 = AllocationChange(effectiveFrom: startDate, amount: 20)
    let c2 = AllocationChange(effectiveFrom: laterDate, amount: 30)
    c1.budget = budget; c2.budget = budget
    context.insert(c1); context.insert(c2)

    #expect(budget.currentAllocation == 30)
  }
}

// MARK: - LifecycleEvent round-trip

struct LifecycleEventModelTests {
  @Test func lifecycleEvent_kindRoundTrips() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(); context.insert(budget)
    let ev = LifecycleEvent(kind: .pause, effectiveDate: Date())
    ev.budget = budget; context.insert(ev)
    try context.save()

    let context2 = ModelContext(container)
    let fetched = try context2.fetch(FetchDescriptor<LifecycleEvent>())
    #expect(fetched.first?.kind == .pause)
  }

  @Test func lifecycleEvents_computedAccessor_nonOptional() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(); context.insert(budget)
    let ev = LifecycleEvent(kind: .resume, effectiveDate: Date())
    ev.budget = budget; context.insert(ev)

    let events: [LifecycleEvent] = budget.lifecycleEvents
    #expect(events.count == 1)
    #expect(events.first?.kind == .resume)
  }
}

// MARK: - ExpenseItem defaults and signed amount

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
