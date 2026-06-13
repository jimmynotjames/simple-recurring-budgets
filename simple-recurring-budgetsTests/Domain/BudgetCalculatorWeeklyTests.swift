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

// MARK: - Snapshot: weekly, Sunday grid

/// All budgets here start on a Sunday with `weekStart: .sunday`, so startDate
/// sits exactly on the grid boundary. (These began as the pre-#240 "Group A"
/// safety net; the #240 switch to the global grid changed only the parameter
/// plumbing here, never the arithmetic — exactly as designed.)
struct BudgetCalculatorWeeklySundayStartTests {
  @Test func pauseResume_acrossWeeks_pausedWeekContributesZero() {
    // Start Sun Apr 5 2026. Weeks: [Apr 5–12), [Apr 12–19), [Apr 19–26), [Apr 26–May 3).
    let budget = makeBudget(startDate: d(2026, 4, 5))
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 14, hour: 10))
    let resumeEvent = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 28, hour: 10))
    pauseEvent.budget = budget; resumeEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent, resumeEvent]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 5, 4), calendar: cal, weekStart: .sunday)
    // Walker: 100 (wk 1) + 100 (pause-action wk 2) + 0 (paused wk 3) + 100 (resume-action wk 4) = 300.
    #expect(snap.carryOver == 300)
    #expect(snap.lifecycleState == .active)
  }

  @Test func endDateMidWeek_postEndClampsFinalWeek() {
    // endDate Wed Apr 22, inside week [Apr 19–26).
    let budget = makeBudget(startDate: d(2026, 4, 5), endDate: d(2026, 4, 22))
    let exp = expense(amount: 60, date: d(2026, 4, 20, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 5, 10), calendar: cal, weekStart: .sunday)
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
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 28), calendar: cal, weekStart: .sunday)
    // Walk window starts at the reset (Apr 21) → only week [Apr 19–26) is walked,
    // at the edited allocation 150, with expenses >= Apr 21: 150 − 20 = 130.
    #expect(snap.carryOver == 130)
    #expect(snap.effectiveAllocation == 150)
    #expect(snap.remaining == 150)
  }
}

// MARK: - The global week grid is independent of startDate's weekday (#240)

/// Until #240 these fixtures pinned the old per-budget anchoring (startDate's
/// weekday defined a private grid). They now demonstrate the inverse: the grid
/// comes solely from the caller-provided weekStart (the user's Week Starts On
/// setting); startDate only clips the window's first period.
struct BudgetCalculatorWeeklyGlobalGridTests {
  @Test func fridayStart_gridIsGlobal_notStartDateWeekday() {
    // Start Fri Apr 3 2026 on a Sunday grid → weeks [Mar 29–Apr 5), [Apr 5–12), …;
    // the budget's window is clipped at Apr 3, and there is NO Friday rollover.
    let budget = makeBudget(startDate: d(2026, 4, 3))
    let lateThursday = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 9, hour: 23), calendar: cal, weekStart: .sunday
    )
    #expect(lateThursday.effectivePeriodStart == d(2026, 4, 5))
    #expect(lateThursday.effectivePeriodEnd == d(2026, 4, 12))
    // The partial first week [Apr 3, Apr 5) already closed at the full allocation.
    #expect(lateThursday.carryOver == 100)

    // Friday Apr 10 is mid-week on the Sunday grid — same period, no rollover.
    let fridayMidWeek = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 10), calendar: cal, weekStart: .sunday
    )
    #expect(fridayMidWeek.effectivePeriodStart == d(2026, 4, 5))
    #expect(fridayMidWeek.carryOver == 100)

    // The rollover happens on Sunday: partial week + full week both closed.
    let sundayRollover = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 12), calendar: cal, weekStart: .sunday
    )
    #expect(sundayRollover.effectivePeriodStart == d(2026, 4, 12))
    #expect(sundayRollover.carryOver == 200)
  }

  @Test func saturdayStart_yearBoundary_onSundayGrid() {
    // Start Sat Dec 26 2026 on a Sunday grid → partial week [Dec 26, Dec 27), then
    // [Dec 27, Jan 3 2027), [Jan 3, Jan 10).
    let budget = makeBudget(startDate: d(2026, 12, 26))
    let newYearsDay = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2027, 1, 1), calendar: cal, weekStart: .sunday
    )
    #expect(newYearsDay.effectivePeriodStart == d(2026, 12, 27))
    #expect(newYearsDay.effectivePeriodEnd == d(2027, 1, 3))
    // The one-day partial week [Dec 26, Dec 27) closed at the full allocation.
    #expect(newYearsDay.carryOver == 100)

    let secondFullWeek = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2027, 1, 3), calendar: cal, weekStart: .sunday
    )
    #expect(secondFullWeek.effectivePeriodStart == d(2027, 1, 3))
    #expect(secondFullWeek.carryOver == 200) // partial week + the week spanning New Year
  }

  @Test func thursdayStart_multiWeekWalk_negativeCarry_onSundayGrid() {
    // Start Thu Apr 2 2026 on a Sunday grid → weeks [Mar 29–Apr 5), [Apr 5–12), [Apr 12–19).
    let budget = makeBudget(startDate: d(2026, 4, 2))
    let expenses = [
      expense(amount: 80, date: d(2026, 4, 5, hour: 10)), // Sunday-grid wk 2
      expense(amount: 130, date: d(2026, 4, 10, hour: 10)), // Sunday-grid wk 2
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 18), calendar: cal, weekStart: .sunday)
    // Walker: partial wk [Apr 2–5) = +100; wk [Apr 5–12) = 100 − 210 = −110. Sum = −10.
    // (Same cumulative deficit as under the old per-budget grid — expenses only re-bucket.)
    #expect(snap.carryOver == -10)
    #expect(snap.remaining == 100)
    #expect(snap.effectivePeriodStart == d(2026, 4, 12))
  }

  @Test func nilStartDate_fallbackDefinesWindowStart_notTheGrid() {
    let budget = Budget(period: .weekly)
    budget.startDate = nil
    budget.createdAt = d(2026, 4, 7, hour: 14) // Tuesday
    let change = AllocationChange(effectiveFrom: d(2026, 4, 7), amount: 100)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 16), calendar: cal, weekStart: .sunday)
    // createdAt's Tuesday only sets where the window begins; the grid stays Sunday:
    // partial week [Apr 7, Apr 12) closed at full allocation, current week [Apr 12–19).
    #expect(snap.effectivePeriodStart == d(2026, 4, 12))
    #expect(snap.carryOver == 100)
  }

  struct WeekGridCase {
    let weekStart: Weekday
    let periodStartDay: Int
    let carryOver: Decimal
  }

  @Test(arguments: [
    WeekGridCase(weekStart: .sunday, periodStartDay: 12, carryOver: 200),
    WeekGridCase(weekStart: .wednesday, periodStartDay: 8, carryOver: 100),
    WeekGridCase(weekStart: .monday, periodStartDay: 13, carryOver: 200),
  ])
  func weekStartSetting_controlsGrid(_ testCase: WeekGridCase) {
    // One budget, three settings: the Week Starts On value alone decides the grid.
    // Wed Apr 1 start, $100/week, no expenses, snapshot Mon Apr 13.
    // .sunday: weeks Mar 29 / Apr 5 / Apr 12 → two closed (partial + full) = 200.
    // .wednesday: weeks Apr 1 / Apr 8 → one closed full week = 100.
    // .monday: weeks Mar 30 / Apr 6 / Apr 13 → two closed (partial + full) = 200.
    let budget = makeBudget(startDate: d(2026, 4, 1))
    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: d(2026, 4, 13), calendar: cal, weekStart: testCase.weekStart
    )
    #expect(snap.effectivePeriodStart == d(2026, 4, testCase.periodStartDay))
    #expect(snap.carryOver == testCase.carryOver)
  }

  @Test func midGridStart_partialFirstPeriod_fullAllocation_preStartExpensesExcluded() {
    // Wed Apr 1 start on a Sunday grid: the first period is the clipped [Apr 1, Apr 5).
    // Full allocation, no proration — the same convention as a monthly budget created
    // mid-month. Expenses before startDate never count.
    let budget = makeBudget(startDate: d(2026, 4, 1))
    let expenses = [
      expense(amount: 15, date: d(2026, 3, 30, hour: 10)), // before startDate — excluded
      expense(amount: 30, date: d(2026, 4, 2, hour: 10)), // in the partial first week
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 5), calendar: cal, weekStart: .sunday)
    #expect(snap.effectivePeriodStart == d(2026, 4, 5))
    #expect(snap.carryOver == 70) // 100 − 30; the Mar 30 expense is outside the window
    #expect(snap.remaining == 100)
  }
}
