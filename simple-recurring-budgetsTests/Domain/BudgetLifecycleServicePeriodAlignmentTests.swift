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
  allocation: Decimal = 100,
  startDate: Date,
  endDate: Date? = nil,
  in context: ModelContext
) -> Budget {
  let b = Budget(period: period)
  b.startDate = startDate
  b.endDate = endDate
  let change = AllocationChange(effectiveFrom: startDate, amount: allocation)
  change.budget = b
  context.insert(b)
  context.insert(change)
  return b
}

// MARK: - Write-path period alignment

struct BudgetLifecyclePeriodAlignmentTests {
  @Test func applyAllocationEdit_weekly_rowLandsOnGlobalGrid() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    // Weekly budget started Wed 2026-04-01; the grid is the global Sunday week (#240).
    let budget = makeBudget(period: .weekly, startDate: d(2026, 4, 1), in: ctx)
    try ctx.save()

    // Edit on Mon Apr 13 → current Sunday-grid period starts Sun Apr 12, and the
    // edit key max(Apr 12, Apr 1) = Apr 12 → a fresh row on the global grid (the
    // budget's Wednesday startDate no longer defines a private Wed→Tue grid).
    try BudgetLifecycleService.applyAllocationEdit(
      budget, newAmount: 150, context: ctx, now: d(2026, 4, 13, hour: 10), calendar: cal, weekStart: .sunday
    )

    #expect(budget.allocationChanges.count == 2)
    let newRow = budget.allocationChanges.first { $0.amount == 150 }
    #expect(newRow?.effectiveFrom == d(2026, 4, 12))

    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 13, hour: 10), calendar: cal, weekStart: .sunday
    )
    // Current period [Apr 12–19) uses the edited 150; the closed partial week
    // [Apr 1–5) and full week [Apr 5–12) walked at the original 100 → carryOver 200.
    #expect(snap.effectiveAllocation == 150)
    #expect(snap.carryOver == 200)
  }

  @Test func applyAllocationEdit_weekly_firstPartialPeriod_mutatesStartRow_consistentReads() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    // Weekly budget started Wed 2026-04-01 on a Sunday grid: the first period is the
    // clipped [Apr 1, Apr 5). An edit during it keys on max(Mar 29, Apr 1) = Apr 1 and
    // mutates the initial startDate row — the weekly variant of the #247 class.
    let budget = makeBudget(period: .weekly, startDate: d(2026, 4, 1), in: ctx)
    try ctx.save()

    try BudgetLifecycleService.applyAllocationEdit(
      budget, newAmount: 150, context: ctx, now: d(2026, 4, 3, hour: 10), calendar: cal, weekStart: .sunday
    )

    #expect(budget.allocationChanges.count == 1)
    #expect(budget.allocationChanges.first?.amount == 150)

    // Live: lookup at max(Mar 29, Apr 1) = Apr 1 → the mutated row → 150.
    let live = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 3, hour: 10), calendar: cal, weekStart: .sunday
    )
    #expect(live.effectiveAllocation == 150)

    // Closed: the partial week's walker lookup (boundary Mar 29 → earliest-row
    // fallback) sees the same mutated row → carry-over credits it at 150.
    let closed = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 6), calendar: cal, weekStart: .sunday
    )
    #expect(closed.carryOver == 150)
  }

  @Test func applyAllocationEdit_biweekly_rowLandsOnCycleStart() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    // Biweekly anchored Apr 1 → cycles [Apr 1–15), [Apr 15–29).
    let budget = makeBudget(period: .biweekly, startDate: d(2026, 4, 1), in: ctx)
    try ctx.save()

    try BudgetLifecycleService.applyAllocationEdit(
      budget, newAmount: 150, context: ctx, now: d(2026, 4, 20, hour: 10), calendar: cal, weekStart: .sunday
    )

    #expect(budget.allocationChanges.count == 2)
    let newRow = budget.allocationChanges.first { $0.amount == 150 }
    #expect(newRow?.effectiveFrom == d(2026, 4, 15))

    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 20, hour: 10), calendar: cal, weekStart: .sunday
    )
    // Cycle 2 uses 150 live; closed cycle 1 walked at 100.
    #expect(snap.effectiveAllocation == 150)
    #expect(snap.carryOver == 100)
  }

  @Test func applyAllocationEdit_monthly_firstMonthMutates_laterMonthInserts() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(period: .monthly, allocation: 500, startDate: d(2026, 2, 1), in: ctx)
    try ctx.save()

    // Edit within the first month: currentPeriodStart (Feb 1) equals the existing
    // row's effectiveFrom → in-place mutation, no new row, and the mutated amount
    // applies retroactively to the whole first period.
    try BudgetLifecycleService.applyAllocationEdit(
      budget, newAmount: 600, context: ctx, now: d(2026, 2, 28, hour: 10), calendar: cal, weekStart: .sunday
    )
    #expect(budget.allocationChanges.count == 1)
    #expect(budget.allocationChanges.first?.amount == 600)

    // Edit in a later month inserts a fresh row at that month's start.
    try BudgetLifecycleService.applyAllocationEdit(
      budget, newAmount: 650, context: ctx, now: d(2026, 3, 31, hour: 10), calendar: cal, weekStart: .sunday
    )
    #expect(budget.allocationChanges.count == 2)
    let marchRow = budget.allocationChanges.first { $0.amount == 650 }
    #expect(marchRow?.effectiveFrom == d(2026, 3, 1))

    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 3, 31, hour: 10), calendar: cal, weekStart: .sunday
    )
    // Closed February walks at the mutated 600 (retroactive within the first period).
    #expect(snap.effectiveAllocation == 650)
    #expect(snap.carryOver == 600)
  }

  /// The #247 fix: a monthly budget created mid-month keys its first-period edit on
  /// `max(currentPeriodStart, effectiveStartDate)` = the startDate row, mutating it in
  /// place — so the live read (lookup at Jan 15) and the walker's closed-month lookup
  /// (boundary Jan 1 → earliest-row fallback) both observe the edit. Before the fix
  /// the edit inserted a shadowed row at Jan 1: live showed 500 while the walker
  /// credited 600.
  @Test func applyAllocationEdit_monthly_midMonthStart_mutatesStartRow_liveAndWalkerAgree() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(period: .monthly, allocation: 500, startDate: d(2026, 1, 15), in: ctx)
    try ctx.save()

    try BudgetLifecycleService.applyAllocationEdit(
      budget, newAmount: 600, context: ctx, now: d(2026, 1, 31, hour: 10), calendar: cal, weekStart: .sunday
    )
    // The governing startDate row is mutated in place — no shadowed second row.
    #expect(budget.allocationChanges.count == 1)
    let row = budget.allocationChanges.first
    #expect(row?.effectiveFrom == d(2026, 1, 15))
    #expect(row?.amount == 600)

    // Live snapshot in January sees the edit immediately.
    let live = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 1, 31, hour: 12), calendar: cal, weekStart: .sunday
    )
    #expect(live.effectiveAllocation == 600)

    // After January closes, the walker credits the month at the same 600.
    let closed = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 2, 10), calendar: cal, weekStart: .sunday
    )
    #expect(closed.carryOver == 600)
  }

  @Test func pauseBudget_clampsEffectiveDateToEndDate() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(startDate: d(2026, 4, 1), endDate: d(2026, 4, 30), in: ctx)
    try ctx.save()

    // Apr 30 12:00 is still inside the budget's last day (postEnd begins May 1),
    // so the pause succeeds — but the event's effectiveDate clamps to the stored
    // endDate (midnight Apr 30), not the tap moment.
    let didPause = try BudgetLifecycleService.pauseBudget(
      budget, context: ctx, now: d(2026, 4, 30, hour: 12), calendar: cal, weekStart: .sunday
    )

    #expect(didPause)
    #expect(budget.lifecycleEvents.count == 1)
    #expect(budget.lifecycleEvents.first?.effectiveDate == d(2026, 4, 30))
  }

  @Test func resetBudget_pausedWeekly_resumesAndZeroesCarryOver() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    // Sunday-start weekly (survives Option 1 under the default global week start).
    let budget = makeBudget(period: .weekly, startDate: d(2026, 4, 5), in: ctx)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 14))
    pauseEvent.budget = budget; ctx.insert(pauseEvent)
    for (amount, date) in [(Decimal(50), d(2026, 4, 8, hour: 10)), (Decimal(20), d(2026, 4, 13, hour: 10))] {
      let exp = ExpenseItem(amount: amount, date: date)
      exp.budget = budget; ctx.insert(exp)
    }
    try ctx.save()

    try BudgetLifecycleService.resetBudget(
      budget, context: ctx, now: d(2026, 4, 21, hour: 10), weekStart: .sunday
    )

    #expect(budget.expenseItems.isEmpty)
    #expect(budget.lastResetDate == d(2026, 4, 21, hour: 10))
    // The paused budget gains a balancing .resume at the reset moment.
    #expect(budget.lifecycleEvents.count == 2)
    #expect(budget.lifecycleEvents.contains { $0.kind == .resume && $0.effectiveDate == d(2026, 4, 21, hour: 10) })

    // Next day: walker window [Apr 21, Apr 19) is empty → 0; the current week
    // [Apr 19–26) contains the resume → active; no expenses survive the reset.
    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 22), calendar: cal, weekStart: .sunday)
    #expect(result.lifecycleState == .active)
    #expect(result.remaining == 100)
    #expect(result.carryOverAmount == 0)
  }

  @Test func resetCarryOver_biweekly_midCycle_zeroesWalkerKeepsRemaining() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(period: .biweekly, startDate: d(2026, 4, 1), in: ctx)
    for (amount, date) in [(Decimal(60), d(2026, 4, 5, hour: 10)), (Decimal(40), d(2026, 4, 16, hour: 10))] {
      let exp = ExpenseItem(amount: amount, date: date)
      exp.budget = budget; ctx.insert(exp)
    }
    try ctx.save()

    try BudgetLifecycleService.resetCarryOver(budget, context: ctx, now: d(2026, 4, 18, hour: 10))

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 25), calendar: cal, weekStart: .sunday)
    // Walker window [Apr 18, Apr 15) empty → 0. Spillover input = 100 − (post-reset
    // expenses: none) = 100 → ordinary slack → 0. carryOver = 0.
    // remaining keeps ALL current-cycle expenses (post-reset rebound, §A.6.4): 100 − 40.
    #expect(result.carryOverAmount == 0)
    #expect(result.remaining == 60)
  }
}
