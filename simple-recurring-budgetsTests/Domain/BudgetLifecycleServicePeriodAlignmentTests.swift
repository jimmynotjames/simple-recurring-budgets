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

// ============================================================================
// GROUP B — PINS CURRENT PER-BUDGET WEEKLY ANCHORING (issue #240 / "Option 1")
// These tests intentionally pin the CURRENT behavior where the weekly grid is
// derived from Budget.startDate's weekday. Option 1 will switch weekly budgets
// to a global grid from AppSettings.weekStartDay; when that lands, UPDATE the
// expectations in this suite deliberately — do not "fix" them to pass.
// ============================================================================

struct BudgetLifecycleWeeklyAnchorPinTests {
  @Test func applyAllocationEdit_weekly_rowLandsOnBudgetWeekdayGrid() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    // Weekly budget anchored Wed 2026-04-01 → weeks run Wed→Tue.
    let budget = makeBudget(period: .weekly, startDate: d(2026, 4, 1), in: ctx)
    try ctx.save()

    // Edit on Mon Apr 13. Current behavior derives weekStart from startDate
    // (Wednesday), so the containing period starts Wed Apr 8 — NOT a global-grid
    // week start. daysBack = (Mon 2 − Wed 4 + 7) % 7 = 5 → Apr 8.
    try BudgetLifecycleService.applyAllocationEdit(
      budget, newAmount: 150, context: ctx, now: d(2026, 4, 13, hour: 10), calendar: cal
    )

    #expect(budget.allocationChanges.count == 2)
    let newRow = budget.allocationChanges.first { $0.amount == 150 }
    #expect(newRow?.effectiveFrom == d(2026, 4, 8))

    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 13, hour: 10), calendar: cal
    )
    // Current period [Apr 8–15) uses the edited 150; closed week [Apr 1–8) walked
    // at the original 100 → carryOver = 100.
    #expect(snap.effectiveAllocation == 150)
    #expect(snap.carryOver == 100)
  }
}

// MARK: - Write-path period alignment (Group A — survives #240 / Option 1)

struct BudgetLifecyclePeriodAlignmentTests {
  @Test func applyAllocationEdit_biweekly_rowLandsOnCycleStart() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    // Biweekly anchored Apr 1 → cycles [Apr 1–15), [Apr 15–29).
    let budget = makeBudget(period: .biweekly, startDate: d(2026, 4, 1), in: ctx)
    try ctx.save()

    try BudgetLifecycleService.applyAllocationEdit(
      budget, newAmount: 150, context: ctx, now: d(2026, 4, 20, hour: 10), calendar: cal
    )

    #expect(budget.allocationChanges.count == 2)
    let newRow = budget.allocationChanges.first { $0.amount == 150 }
    #expect(newRow?.effectiveFrom == d(2026, 4, 15))

    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 20, hour: 10), calendar: cal
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
      budget, newAmount: 600, context: ctx, now: d(2026, 2, 28, hour: 10), calendar: cal
    )
    #expect(budget.allocationChanges.count == 1)
    #expect(budget.allocationChanges.first?.amount == 600)

    // Edit in a later month inserts a fresh row at that month's start.
    try BudgetLifecycleService.applyAllocationEdit(
      budget, newAmount: 650, context: ctx, now: d(2026, 3, 31, hour: 10), calendar: cal
    )
    #expect(budget.allocationChanges.count == 2)
    let marchRow = budget.allocationChanges.first { $0.amount == 650 }
    #expect(marchRow?.effectiveFrom == d(2026, 3, 1))

    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 3, 31, hour: 10), calendar: cal
    )
    // Closed February walks at the mutated 600 (retroactive within the first period).
    #expect(snap.effectiveAllocation == 650)
    #expect(snap.carryOver == 600)
  }

  /// ⚠️ Pins a suspected production bug — DO NOT "fix" the expectations here without
  /// reading this comment. A monthly budget created mid-month stores its initial
  /// AllocationChange at `startDate` (Jan 15), but `applyAllocationEdit` inserts the
  /// edited row at `currentPeriodStart` (Jan 1, the calendar-month grid start). The
  /// live read then looks up `allocationInEffect(at: max(currentPeriodStart,
  /// effectiveStartDate)) = Jan 15`, which still resolves to the ORIGINAL row — the
  /// user's edit has no visible effect on the current allocation — while the walker,
  /// looking up the closed January at boundary Jan 1, uses the EDITED amount. The two
  /// reads disagree about the same month. Tracked in issue #247; characterized here
  /// so the inconsistency is visible the day it changes.
  @Test func applyAllocationEdit_monthly_midMonthStart_insertedRowShadowedByStartRow() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(period: .monthly, allocation: 500, startDate: d(2026, 1, 15), in: ctx)
    try ctx.save()

    try BudgetLifecycleService.applyAllocationEdit(
      budget, newAmount: 600, context: ctx, now: d(2026, 1, 31, hour: 10), calendar: cal
    )
    // The edit inserts at the month-grid start (Jan 1), not at startDate (Jan 15).
    #expect(budget.allocationChanges.count == 2)
    let editedRow = budget.allocationChanges.first { $0.amount == 600 }
    #expect(editedRow?.effectiveFrom == d(2026, 1, 1))

    // Live snapshot in January: lookup at max(Jan 1, Jan 15) = Jan 15 → the original
    // 500 row wins (latest effectiveFrom ≤ Jan 15). The edit is invisible live.
    let live = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 1, 31, hour: 12), calendar: cal
    )
    #expect(live.effectiveAllocation == 500)

    // After January closes: the walker credits the closed month at boundary Jan 1,
    // where the edited 600 row wins — disagreeing with what the live chip showed.
    let closed = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 2, 10), calendar: cal
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
      budget, context: ctx, now: d(2026, 4, 30, hour: 12), calendar: cal
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

    try BudgetLifecycleService.resetBudget(budget, context: ctx, now: d(2026, 4, 21, hour: 10))

    #expect(budget.expenseItems.isEmpty)
    #expect(budget.lastResetDate == d(2026, 4, 21, hour: 10))
    // The paused budget gains a balancing .resume at the reset moment.
    #expect(budget.lifecycleEvents.count == 2)
    #expect(budget.lifecycleEvents.contains { $0.kind == .resume && $0.effectiveDate == d(2026, 4, 21, hour: 10) })

    // Next day: walker window [Apr 21, Apr 19) is empty → 0; the current week
    // [Apr 19–26) contains the resume → active; no expenses survive the reset.
    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 22), calendar: cal)
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

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 25), calendar: cal)
    // Walker window [Apr 18, Apr 15) empty → 0. Spillover input = 100 − (post-reset
    // expenses: none) = 100 → ordinary slack → 0. carryOver = 0.
    // remaining keeps ALL current-cycle expenses (post-reset rebound, §A.6.4): 100 − 40.
    #expect(result.carryOverAmount == 0)
    #expect(result.remaining == 60)
  }
}
