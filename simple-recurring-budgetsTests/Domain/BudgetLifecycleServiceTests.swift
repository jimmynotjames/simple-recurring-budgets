import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Shared helpers

private let cal: Calendar = {
  var c = Calendar(identifier: .gregorian)
  c.timeZone = TimeZone(identifier: "UTC")!
  return c
}()

private func d(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
  var comps = DateComponents()
  comps.year = year; comps.month = month; comps.day = day
  comps.hour = hour; comps.minute = 0; comps.second = 0
  comps.timeZone = TimeZone(identifier: "UTC")
  return Calendar(identifier: .gregorian).date(from: comps)!
}

private func makeBudget(
  period: BudgetPeriod = .daily,
  allocation: Decimal = 20,
  startDate: Date,
  in context: ModelContext
) -> Budget {
  let b = Budget(period: period)
  b.startDate = startDate
  let change = AllocationChange(effectiveFrom: startDate, amount: allocation)
  change.budget = b
  context.insert(b)
  context.insert(change)
  return b
}

// MARK: - result(for:): pure read, no mutations

struct BudgetLifecycleResultTests {
  @Test func result_doesNotMutateBudget() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate, in: ctx)
    let originalLastModified = budget.lastModified

    _ = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal)

    #expect(budget.lastModified == originalLastModified)
    #expect(budget.lastResetDate == nil)
  }

  @Test func result_mapsSnapshotToResult() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 14)
    let budget = makeBudget(allocation: 20, startDate: startDate, in: ctx)
    // Prior period Apr 14: expense 18 → carry-over = 2
    let exp = ExpenseItem(amount: 18, date: d(2026, 4, 14, hour: 10))
    exp.budget = budget; ctx.insert(exp)

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal)

    #expect(result.remaining == 20) // current period Apr 15, no expenses
    #expect(result.carryOverAmount == 2) // walker: 20 − 18 = 2
    #expect(result.periodStart == d(2026, 4, 15))
    #expect(result.periodEnd == d(2026, 4, 16))
  }

  @Test func result_remainingIsIndependentOfCarryOver() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    // Many prior periods with surplus carry-over, current period has expense 5
    let currentExpense = ExpenseItem(amount: 5, date: d(2026, 4, 15, hour: 9))
    currentExpense.budget = budget; ctx.insert(currentExpense)

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal)

    #expect(result.remaining == 15) // 20 − 5, regardless of carry-over
  }

  @Test func result_remainingMayBeNegative() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(allocation: 10, startDate: startDate, in: ctx)
    let exp = ExpenseItem(amount: 15, date: d(2026, 4, 15, hour: 9))
    exp.budget = budget; ctx.insert(exp)

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal)

    #expect(result.remaining == -5)
  }

  @Test func result_weeklyBudget_periodBoundaries() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    // Budget with Sunday start date → week runs Sun–Sat
    let startDate = d(2026, 4, 5) // Sunday
    let budget = makeBudget(period: .weekly, allocation: 100, startDate: startDate, in: ctx)
    let now = d(2026, 4, 12, hour: 1) // just after Sun Apr 12

    let result = BudgetLifecycleService.result(for: budget, now: now, calendar: cal)

    #expect(result.periodStart == d(2026, 4, 12))
    #expect(result.periodEnd == d(2026, 4, 19))
  }
}

// MARK: - applyAllocationEdit write path

struct BudgetLifecycleApplyAllocationEditTests {
  @Test func applyAllocationEdit_insertsNewRowForCurrentPeriod() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    let now = d(2026, 4, 15, hour: 10)
    BudgetLifecycleService.applyAllocationEdit(budget, newAmount: 30, context: ctx, now: now, calendar: cal)

    // Should have original row (Apr 1 = 20) and a new row (Apr 15 = 30)
    #expect(budget.allocationChanges.count == 2)
    #expect(budget.lastModified == now)
    // Snapshot should now use 30 for Apr 15
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: now, calendar: cal)
    #expect(snap.effectiveAllocation == 30)
  }

  @Test func applyAllocationEdit_mutatesExistingRowForSamePeriod() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    let now = d(2026, 4, 15, hour: 10)
    // First edit
    BudgetLifecycleService.applyAllocationEdit(budget, newAmount: 25, context: ctx, now: now, calendar: cal)
    let countAfterFirst = budget.allocationChanges.count

    // Second edit in same period
    BudgetLifecycleService.applyAllocationEdit(budget, newAmount: 35, context: ctx, now: now, calendar: cal)

    // Should not have added a second row — mutated the existing one
    #expect(budget.allocationChanges.count == countAfterFirst)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: now, calendar: cal)
    #expect(snap.effectiveAllocation == 35)
  }

  @Test func applyAllocationEdit_priorPeriodsUnaffected() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(allocation: 20, startDate: startDate, in: ctx)
    // Some prior period expenses
    let exp = ExpenseItem(amount: 5, date: d(2026, 4, 10, hour: 10))
    exp.budget = budget; ctx.insert(exp)
    try ctx.save()

    // Edit on Apr 15
    BudgetLifecycleService.applyAllocationEdit(budget, newAmount: 30, context: ctx, now: d(2026, 4, 15), calendar: cal)

    // Apr 10's contribution should still use alloc 20
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15), calendar: cal)
    // Walker: Apr 1–14 with alloc 20; Apr 10 had expense 5 → +15; rest +20 each
    // Apr 1–9 = 9 × 20 = 180; Apr 10 = 15; Apr 11–14 = 4 × 20 = 80; total = 275
    #expect(snap.carryOver == 275)
    #expect(snap.effectiveAllocation == 30)
  }
}

// MARK: - resetCarryOver write path

struct BudgetLifecycleResetCarryOverTests {
  @Test func resetCarryOver_setsLastResetDate_bumpsLastModified() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    let now = d(2026, 4, 15, hour: 10)
    BudgetLifecycleService.resetCarryOver(budget, context: ctx, now: now)

    #expect(budget.lastResetDate == now)
    #expect(budget.lastModified == now)
  }

  @Test func resetCarryOver_walkerDropsToCurrentPeriodOnly() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(allocation: 20, startDate: startDate, in: ctx)
    // Lots of prior period expenses
    for day in 1 ... 13 {
      let exp = ExpenseItem(amount: 18, date: d(2026, 4, day, hour: 10))
      exp.budget = budget; ctx.insert(exp)
    }
    try ctx.save()

    BudgetLifecycleService.resetCarryOver(budget, context: ctx, now: d(2026, 4, 14))

    // Snapshot now on Apr 14 (the reset day): walk window = max(Apr 1, Apr 14) = Apr 14 00:00
    // Apr 14 period is [Apr 14, Apr 15). It is the current period → walker goes up to Apr 14 start.
    // No completed period in the window since Apr 14 is the current period.
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 14), calendar: cal)
    #expect(snap.carryOver == 0)
  }

  @Test func resetCarryOver_doesNotDeleteExpenses() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    let exp = ExpenseItem(amount: 10, date: d(2026, 4, 1, hour: 10))
    exp.budget = budget; ctx.insert(exp)
    try ctx.save()

    BudgetLifecycleService.resetCarryOver(budget, context: ctx)

    #expect(budget.expenseItems.count == 1)
  }
}

// MARK: - resetBudget write path

struct BudgetLifecycleResetBudgetTests {
  @Test func resetBudget_deletesAllExpenses() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    for i in 1 ... 3 {
      let exp = ExpenseItem(amount: Decimal(i * 5), date: d(2026, 4, i, hour: 10))
      exp.budget = budget; ctx.insert(exp)
    }
    try ctx.save()
    #expect(budget.expenseItems.count == 3)

    BudgetLifecycleService.resetBudget(budget, context: ctx, now: d(2026, 4, 15))

    #expect(budget.expenseItems.isEmpty)
  }

  @Test func resetBudget_setsLastResetDate_bumpsLastModified() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    let now = d(2026, 4, 15, hour: 10)
    BudgetLifecycleService.resetBudget(budget, context: ctx, now: now)

    #expect(budget.lastResetDate == now)
    #expect(budget.lastModified == now)
  }

  @Test func resetBudget_preservesAllocationChanges() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    BudgetLifecycleService.resetBudget(budget, context: ctx)

    #expect(!budget.allocationChanges.isEmpty)
  }

  @Test func resetBudget_preservesLifecycleEvents() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    let ev = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 5))
    ev.budget = budget; ctx.insert(ev)
    try ctx.save()

    BudgetLifecycleService.resetBudget(budget, context: ctx)

    #expect(!budget.lifecycleEvents.isEmpty)
  }

  @Test func resetBudget_isolatedToTargetBudget() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)

    let budgetA = makeBudget(startDate: d(2026, 4, 1), in: ctx)
    let budgetB = makeBudget(startDate: d(2026, 4, 1), in: ctx)
    for b in [budgetA, budgetB] {
      let exp = ExpenseItem(amount: 10, date: d(2026, 4, 1, hour: 10))
      exp.budget = b; ctx.insert(exp)
    }
    try ctx.save()

    BudgetLifecycleService.resetBudget(budgetA, context: ctx)

    #expect(budgetA.expenseItems.isEmpty)
    #expect(budgetB.expenseItems.count == 1)
  }
}
