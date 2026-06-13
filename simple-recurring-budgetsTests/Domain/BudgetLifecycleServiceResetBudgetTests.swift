import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Shared helpers

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

    try BudgetLifecycleService.resetBudget(budget, context: ctx, now: d(2026, 4, 15), weekStart: .sunday)

    #expect(budget.expenseItems.isEmpty)
  }

  @Test func resetBudget_setsLastResetDate_bumpsLastModified() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    let now = d(2026, 4, 15, hour: 10)
    try BudgetLifecycleService.resetBudget(budget, context: ctx, now: now, weekStart: .sunday)

    #expect(budget.lastResetDate == now)
    #expect(budget.lastModified == now)
  }

  @Test func resetBudget_preservesAllocationChanges() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    try BudgetLifecycleService.resetBudget(budget, context: ctx, weekStart: .sunday)

    #expect(!budget.allocationChanges.isEmpty)
  }

  @Test func resetBudget_preservesPriorLifecycleEvents_whenCurrentlyActive() throws {
    // Seed a pause+resume pair so the budget is currently active at `now`.
    // Reset on an active budget must preserve prior events and NOT insert any new event
    // (the auto-resume branch fires only when the current lifecycleState is .paused).
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 5))
    pauseEvent.budget = budget; ctx.insert(pauseEvent)
    let resumeEvent = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 10))
    resumeEvent.budget = budget; ctx.insert(resumeEvent)
    try ctx.save()

    try BudgetLifecycleService.resetBudget(budget, context: ctx, now: d(2026, 4, 15), weekStart: .sunday)

    #expect(budget.lifecycleEvents.count == 2)
    #expect(budget.lifecycleEvents.contains { $0.kind == .pause && $0.effectiveDate == d(2026, 4, 5) })
    #expect(budget.lifecycleEvents.contains { $0.kind == .resume && $0.effectiveDate == d(2026, 4, 10) })
  }

  @Test func resetBudget_active_withExpenses_doesNotInsertLifecycleEvent() throws {
    // Confirms a reset on a non-paused budget deletes every expense, sets
    // lastResetDate/lastModified, and inserts no LifecycleEvent.
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    for i in 1 ... 3 {
      let exp = ExpenseItem(amount: Decimal(i * 5), date: d(2026, 4, i, hour: 10))
      exp.budget = budget; ctx.insert(exp)
    }
    try ctx.save()

    let now = d(2026, 4, 15, hour: 10)
    try BudgetLifecycleService.resetBudget(budget, context: ctx, now: now, weekStart: .sunday)

    #expect(budget.expenseItems.isEmpty)
    #expect(budget.lastResetDate == now)
    #expect(budget.lastModified == now)
    #expect(budget.lifecycleEvents.isEmpty)
  }

  @Test func resetBudget_paused_insertsResumeEvent_andSnapshotResolvesActive() throws {
    // Confirms a reset on a paused budget folds in a .resume event and the
    // post-reset snapshot reports lifecycleState == .active.
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10))
    pauseEvent.budget = budget; ctx.insert(pauseEvent)
    let exp = ExpenseItem(amount: 5, date: d(2026, 4, 11, hour: 12))
    exp.budget = budget; ctx.insert(exp)
    try ctx.save()

    let now = d(2026, 4, 15, hour: 10)
    try BudgetLifecycleService.resetBudget(budget, context: ctx, now: now, weekStart: .sunday)

    #expect(budget.expenseItems.isEmpty)
    #expect(budget.lastResetDate == now)
    #expect(budget.lastModified == now)
    #expect(budget.lifecycleEvents.count == 2)
    #expect(budget.lifecycleEvents.contains { $0.kind == .pause && $0.effectiveDate == d(2026, 4, 10) })
    let resumeEvents = budget.lifecycleEvents.filter { $0.kind == .resume }
    #expect(resumeEvents.count == 1)
    #expect(resumeEvents.first?.effectiveDate == now)

    // The moment-granular pause classifier uses a strict `effectiveDate < now` comparison
    // (see LifecycleClassification.isPausedAtMoment). In real flow the snapshot's `Date()`
    // is strictly after the service's `now`; the test mirrors that with a 1s delta.
    let snapshotNow = now.addingTimeInterval(1)
    let result = BudgetLifecycleService.result(for: budget, now: snapshotNow, weekStart: .sunday)
    #expect(result.lifecycleState == .active)
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

    try BudgetLifecycleService.resetBudget(budgetA, context: ctx, weekStart: .sunday)

    #expect(budgetA.expenseItems.isEmpty)
    #expect(budgetB.expenseItems.count == 1)
  }
}
