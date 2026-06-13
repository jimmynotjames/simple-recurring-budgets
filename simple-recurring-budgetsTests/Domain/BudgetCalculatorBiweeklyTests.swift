import Foundation
@testable import simple_recurring_budgets
import Testing

// MARK: - Shared test helpers

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
  period: BudgetPeriod = .biweekly,
  allocation: Decimal = 100,
  startDate: Date,
  endDate: Date? = nil,
  lastResetDate: Date? = nil
) -> Budget {
  let b = Budget(period: period)
  b.startDate = startDate
  b.endDate = endDate
  b.lastResetDate = lastResetDate
  let change = AllocationChange(effectiveFrom: startDate, amount: allocation)
  change.budget = b
  b.allocationChangesStorage = [change]
  return b
}

private func expense(amount: Decimal, date: Date) -> ExpenseItem {
  ExpenseItem(amount: amount, date: date)
}

// MARK: - Snapshot: biweekly cycles (pre-#240 safety net, Group A)

/// Biweekly anchoring is inherently per-budget — a 14-day cycle's phase cannot be
/// derived from a global weekday setting — so every expectation here MUST survive
/// the #240 "Option 1" change (weekly → global AppSettings.weekStartDay grid).
/// Default fixture: biweekly, $100/cycle, startDate Wed 2026-04-01.
/// Cycle grid: [Apr 1–15), [Apr 15–29), [Apr 29–May 13), [May 13–27), [May 27–Jun 10).
struct BudgetCalculatorBiweeklySnapshotTests {
  @Test func multiCycleCarryOverWalk_sumsCompletedCycles() {
    let budget = makeBudget(startDate: d(2026, 4, 1))
    let expenses = [
      expense(amount: 30, date: d(2026, 4, 5, hour: 10)), // cycle 1
      expense(amount: 120, date: d(2026, 4, 20, hour: 10)), // cycle 2 (overspend)
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 5, 1), calendar: cal, weekStart: .sunday)
    // Walker: cycle 1 = 100 − 30 = 70; cycle 2 = 100 − 120 = −20; sum = 50.
    // Current cycle [Apr 29–May 13) empty → spillover 0.
    #expect(snap.carryOver == 50)
    #expect(snap.remaining == 100)
    #expect(snap.effectivePeriodStart == d(2026, 4, 29))
    #expect(snap.effectivePeriodEnd == d(2026, 5, 13))
  }

  @Test func allocationChangeAtCycleBoundary_appliesPerCycle() {
    let budget = Budget(period: .biweekly)
    budget.startDate = d(2026, 4, 1)
    let change1 = AllocationChange(effectiveFrom: d(2026, 4, 1), amount: 100)
    let change2 = AllocationChange(effectiveFrom: d(2026, 4, 15), amount: 150)
    change1.budget = budget; change2.budget = budget
    budget.allocationChangesStorage = [change1, change2]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 29), calendar: cal, weekStart: .sunday)
    // Walker: cycle 1 at 100 + cycle 2 at 150 = 250. Current cycle 3 allocation = 150.
    #expect(snap.carryOver == 250)
    #expect(snap.effectiveAllocation == 150)
  }

  @Test func pauseResumeAcrossCycles_pausedCycleContributesZero() {
    let budget = makeBudget(startDate: d(2026, 4, 1))
    // Pause mid cycle 2 (pause-action period stays active per the whole-period rule);
    // resume mid cycle [May 13–27) (resume-action period active). The cycle fully
    // covered by the pause, [Apr 29–May 13), contributes 0.
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 18, hour: 10))
    let resumeEvent = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 5, 20, hour: 10))
    pauseEvent.budget = budget; resumeEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent, resumeEvent]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 5, 30), calendar: cal, weekStart: .sunday)
    // Walker: 100 (cycle 1) + 100 (pause-action cycle 2) + 0 (paused) + 100 (resume-action) = 300.
    #expect(snap.carryOver == 300)
    #expect(snap.lifecycleState == .active)
    #expect(snap.remaining == 100)
  }

  @Test func midCycleReset_excludesPreResetExpenses_awardsFullAllocation() {
    let budget = makeBudget(startDate: d(2026, 4, 1), lastResetDate: d(2026, 4, 20))
    let expenses = [
      expense(amount: 40, date: d(2026, 4, 17, hour: 10)), // pre-reset (cycle 2) — excluded
      expense(amount: 25, date: d(2026, 4, 22, hour: 10)), // post-reset (cycle 2)
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 5, 1), calendar: cal, weekStart: .sunday)
    // Walk window starts at the reset (Apr 20); the containing cycle [Apr 15–29) is
    // walked with expense lower bound Apr 20 and the full allocation (no proration):
    // contribution = 100 − 25 = 75.
    #expect(snap.carryOver == 75)
    #expect(snap.remaining == 100)
  }

  @Test func endDateMidCycle_postEndClampsAndFoldsFinalRemaining() {
    let budget = makeBudget(startDate: d(2026, 4, 1), endDate: d(2026, 4, 20))
    let exp = expense(amount: 10, date: d(2026, 4, 16, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 5, 15), calendar: cal, weekStart: .sunday)
    // effectiveNow clamps to Apr 20 → final period is cycle 2, [Apr 15, Apr 21) after
    // the endDate clamp. Walker: cycle 1 = 100. remaining = 100 − 10 = 90; postEnd
    // folds the entire final remaining → carryOver = 100 + 90 = 190.
    #expect(snap.lifecycleState == .postEnd)
    #expect(snap.remaining == 90)
    #expect(snap.carryOver == 190)
    #expect(snap.effectivePeriodStart == d(2026, 4, 15))
    #expect(snap.effectivePeriodEnd == d(2026, 4, 21))
  }

  @Test func backDatedStartDate_shiftsAnchor_andFallbackAllocationCovers() {
    // Built with startDate Apr 15 (AllocationChange row lands there), then the user
    // back-dates to Apr 1 — the VM's recurring path mutates Budget.startDate only.
    let budget = makeBudget(startDate: d(2026, 4, 15))
    budget.startDate = d(2026, 4, 1)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 29), calendar: cal, weekStart: .sunday)
    // New anchor Apr 1 → cycles [Apr 1–15), [Apr 15–29). The Apr 1 boundary has no
    // row with effectiveFrom <= Apr 1, so allocationInEffect falls back to the
    // earliest row (100). Walker = 100 + 100 = 200.
    #expect(snap.carryOver == 200)
    #expect(snap.effectivePeriodStart == d(2026, 4, 29))
  }

  @Test func nilStartDate_fallsBackToCreatedAt_asBiweeklyAnchor() {
    let budget = Budget(period: .biweekly)
    budget.startDate = nil
    budget.createdAt = d(2026, 4, 1, hour: 10)
    let change = AllocationChange(effectiveFrom: d(2026, 4, 1), amount: 100)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 20), calendar: cal, weekStart: .sunday)
    // effectiveStartDate = startOfDay(createdAt) = Apr 1 → cycle grid anchors there.
    #expect(snap.effectivePeriodStart == d(2026, 4, 15))
    #expect(snap.effectivePeriodEnd == d(2026, 4, 29))
    #expect(snap.carryOver == 100) // cycle 1 closed, no expenses
  }

  @Test func currentCycleOverspend_spillsLive() {
    let budget = makeBudget(startDate: d(2026, 4, 1))
    let exp = expense(amount: 130, date: d(2026, 4, 18, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 20), calendar: cal, weekStart: .sunday)
    // Walker: cycle 1 = 100. Current cycle remaining = 100 − 130 = −30 → committed
    // overspend spills live: carryOver = 100 + (−30) = 70.
    #expect(snap.remaining == -30)
    #expect(snap.carryOver == 70)
  }

  @Test func biweekly_anchorIndependentOfWeekStartSetting() {
    // Hard #240 guarantee: the Week Starts On setting never touches biweekly cycles —
    // the 14-day phase comes from startDate alone. Identical snapshots under any grid.
    let budget = makeBudget(startDate: d(2026, 4, 1))
    let expenses = [
      expense(amount: 30, date: d(2026, 4, 5, hour: 10)),
      expense(amount: 20, date: d(2026, 4, 18, hour: 10)),
    ]
    let sunday = BudgetCalculator.snapshot(
      budget: budget, expenses: expenses, now: d(2026, 4, 20), calendar: cal, weekStart: .sunday
    )
    let friday = BudgetCalculator.snapshot(
      budget: budget, expenses: expenses, now: d(2026, 4, 20), calendar: cal, weekStart: .friday
    )
    #expect(sunday.effectivePeriodStart == friday.effectivePeriodStart)
    #expect(sunday.effectivePeriodEnd == friday.effectivePeriodEnd)
    #expect(sunday.remaining == friday.remaining)
    #expect(sunday.carryOver == friday.carryOver)
    #expect(sunday.effectivePeriodStart == d(2026, 4, 15)) // cycle 2, anchored to Apr 1
  }

  @Test func endDateBeforeFirstCycleCompletes_singleTruncatedWindow() {
    let budget = makeBudget(startDate: d(2026, 4, 1), endDate: d(2026, 4, 7))
    let exp = expense(amount: 20, date: d(2026, 4, 3, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 25), calendar: cal, weekStart: .sunday)
    // effectiveNow clamps to Apr 7 → the budget never left cycle 1. Walker window
    // [Apr 1, Apr 1) is empty → 0. remaining = 100 − 20 = 80; postEnd folds it all.
    #expect(snap.lifecycleState == .postEnd)
    #expect(snap.remaining == 80)
    #expect(snap.carryOver == 80)
    #expect(snap.effectivePeriodEnd == d(2026, 4, 8))
  }
}
