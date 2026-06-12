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
  allocation: Decimal = 100,
  startDate: Date,
  endDate: Date? = nil,
  lastResetDate: Date? = nil
) -> Budget {
  let b = Budget(period: .weekly)
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

// MARK: - Snapshot: weekly, Sunday-start (pre-#240 safety net, Group A)

/// All budgets here start on a SUNDAY deliberately: under the #240 "Option 1"
/// change (weekly → global AppSettings.weekStartDay grid) these expectations
/// survive as long as the test threads Sunday as the effective week start —
/// only the parameter plumbing should need to change, never the arithmetic.
struct BudgetCalculatorWeeklySundayStartTests {
  @Test func pauseResume_acrossWeeks_pausedWeekContributesZero() {
    // Start Sun Apr 5 2026. Weeks: [Apr 5–12), [Apr 12–19), [Apr 19–26), [Apr 26–May 3).
    let budget = makeBudget(startDate: d(2026, 4, 5))
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 14, hour: 10))
    let resumeEvent = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 28, hour: 10))
    pauseEvent.budget = budget; resumeEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent, resumeEvent]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 5, 4), calendar: cal)
    // Walker: 100 (wk 1) + 100 (pause-action wk 2) + 0 (paused wk 3) + 100 (resume-action wk 4) = 300.
    #expect(snap.carryOver == 300)
    #expect(snap.lifecycleState == .active)
  }

  @Test func endDateMidWeek_postEndClampsFinalWeek() {
    // endDate Wed Apr 22, inside week [Apr 19–26).
    let budget = makeBudget(startDate: d(2026, 4, 5), endDate: d(2026, 4, 22))
    let exp = expense(amount: 60, date: d(2026, 4, 20, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 5, 10), calendar: cal)
    // effectiveNow clamps to Apr 22 → final period [Apr 19, Apr 23). Walker:
    // weeks Apr 5 + Apr 12 = 200. remaining = 100 − 60 = 40; postEnd folds it → 240.
    #expect(snap.lifecycleState == .postEnd)
    #expect(snap.remaining == 40)
    #expect(snap.carryOver == 240)
    #expect(snap.effectivePeriodEnd == d(2026, 4, 23))
  }

  @Test func allocationEditThenReset_walkerUsesNewAllocAndPostResetExpensesOnly() {
    let budget = Budget(period: .weekly)
    budget.startDate = d(2026, 4, 5)
    budget.lastResetDate = d(2026, 4, 21)
    let change1 = AllocationChange(effectiveFrom: d(2026, 4, 5), amount: 100)
    let change2 = AllocationChange(effectiveFrom: d(2026, 4, 19), amount: 150)
    change1.budget = budget; change2.budget = budget
    budget.allocationChangesStorage = [change1, change2]
    let expenses = [
      expense(amount: 50, date: d(2026, 4, 8, hour: 10)), // wk 1 — pre-reset, excluded
      expense(amount: 30, date: d(2026, 4, 20, hour: 10)), // wk 3, pre-reset — excluded
      expense(amount: 20, date: d(2026, 4, 22, hour: 10)), // wk 3, post-reset
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 28), calendar: cal)
    // Walk window starts at the reset (Apr 21) → only week [Apr 19–26) is walked,
    // at the edited allocation 150, with expenses >= Apr 21: 150 − 20 = 130.
    #expect(snap.carryOver == 130)
    #expect(snap.effectiveAllocation == 150)
    #expect(snap.remaining == 150)
  }
}

// ============================================================================
// GROUP B — PINS CURRENT PER-BUDGET WEEKLY ANCHORING (issue #240 / "Option 1")
// These tests intentionally pin the CURRENT behavior where the weekly grid is
// derived from Budget.startDate's weekday. Option 1 will switch weekly budgets
// to a global grid from AppSettings.weekStartDay; when that lands, UPDATE the
// expectations in this suite deliberately — do not "fix" them to pass.
// ============================================================================

struct BudgetCalculatorWeeklyAnchorPinTests {
  @Test func fridayStart_weekRunsFriToThu() {
    // Start Fri Apr 3 2026 → weeks run Fri→Thu regardless of locale or settings.
    let budget = makeBudget(startDate: d(2026, 4, 3))
    let lateThursday = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 9, hour: 23), calendar: cal
    )
    #expect(lateThursday.effectivePeriodStart == d(2026, 4, 3))
    #expect(lateThursday.effectivePeriodEnd == d(2026, 4, 10))

    let fridayRollover = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 10), calendar: cal
    )
    #expect(fridayRollover.effectivePeriodStart == d(2026, 4, 10))
    #expect(fridayRollover.carryOver == 100) // week 1 closed untouched
  }

  @Test func saturdayStart_yearBoundaryWeek() {
    // Start Sat Dec 26 2026 → the first week spans the year boundary, [Dec 26, Jan 2).
    let budget = makeBudget(startDate: d(2026, 12, 26))
    let newYearsDay = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2027, 1, 1), calendar: cal
    )
    #expect(newYearsDay.effectivePeriodStart == d(2026, 12, 26))
    #expect(newYearsDay.effectivePeriodEnd == d(2027, 1, 2))
    #expect(newYearsDay.carryOver == 0) // still inside week 1

    let secondWeek = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2027, 1, 3), calendar: cal
    )
    #expect(secondWeek.effectivePeriodStart == d(2027, 1, 2))
    #expect(secondWeek.carryOver == 100) // week 1 closed across the year boundary
  }

  @Test func thursdayStart_multiWeekWalk_negativeCarry() {
    // Start Thu Apr 2 2026 → weeks [Apr 2–9), [Apr 9–16), [Apr 16–23).
    let budget = makeBudget(startDate: d(2026, 4, 2))
    let expenses = [
      expense(amount: 80, date: d(2026, 4, 5, hour: 10)), // wk 1: +20
      expense(amount: 130, date: d(2026, 4, 10, hour: 10)), // wk 2: −30
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 18), calendar: cal)
    // Walker: (100 − 80) + (100 − 130) = −10. Current week empty → spillover 0.
    #expect(snap.carryOver == -10)
    #expect(snap.remaining == 100)
    #expect(snap.effectivePeriodStart == d(2026, 4, 16))
  }

  @Test func nilStartDate_weekAnchoredOnCreatedAtWeekday() {
    let budget = Budget(period: .weekly)
    budget.startDate = nil
    budget.createdAt = d(2026, 4, 7, hour: 14) // Tuesday
    let change = AllocationChange(effectiveFrom: d(2026, 4, 7), amount: 100)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 16), calendar: cal)
    // effectiveStartDate = startOfDay(createdAt) = Tue Apr 7 → weeks run Tue→Mon.
    #expect(snap.effectivePeriodStart == d(2026, 4, 14))
    #expect(snap.carryOver == 100) // week [Apr 7–14) closed untouched
  }
}
