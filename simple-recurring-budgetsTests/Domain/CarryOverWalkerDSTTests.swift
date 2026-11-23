import Foundation
@testable import simple_recurring_budgets
import Testing

// MARK: - Carry-over walk across a DST transition

/// `walkCarryOver` re-derives every boundary on every read, so a DST-shifted boundary must
/// not re-bucket expenses or change the total. Walks a daily budget across the US 2026-03-08
/// spring-forward (a 23-hour day) in America/Los_Angeles.
struct CarryOverWalkerDSTTests {
  @Test func dailyWalk_acrossSpringForward_awardsFullAllocationsAndKeepsExpenseBuckets() {
    let cal = TestCalendars.gregorian(in: "America/Los_Angeles")
    let windowStart = TestCalendars.date(2026, 3, 6, in: cal)
    let currentPeriodStart = TestCalendars.date(2026, 3, 10, in: cal)

    let change = AllocationChange(effectiveFrom: windowStart, amount: 10)
    let expenses = [
      // Before the transition.
      ExpenseItem(amount: 5, date: TestCalendars.date(2026, 3, 7, hour: 12, in: cal)),
      // Midday on the 23-hour transition day.
      ExpenseItem(amount: 7, date: TestCalendars.date(2026, 3, 8, hour: 12, in: cal)),
      // Late evening on the transition day: still in the shortened period, not 03-09.
      ExpenseItem(amount: 3, date: TestCalendars.date(2026, 3, 8, hour: 23, minute: 30, in: cal)),
    ]

    let carryOver = walkCarryOver(
      from: windowStart,
      to: currentPeriodStart,
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: windowStart,
      sortedAllocationChanges: [change],
      sortedLifecycleEvents: [],
      expenses: expenses,
      calendar: cal
    )

    // 4 completed periods (03-06 … 03-09, including the 23-hour 03-08) × 10, minus 15 of
    // expenses. A shifted boundary would mis-count periods and change the total; re-bucketing
    // the 23:30 expense into 03-09 keeps the same total, so that is asserted in PeriodCalculatorDSTTests.
    #expect(carryOver == 25)
  }

  /// Fall-back (25-hour day, 2026-11-01): the repeated 1 AM hour must not
  /// double-count a period or an expense.
  @Test func dailyWalk_acrossFallBack_countsEachPeriodOnce() {
    let cal = TestCalendars.gregorian(in: "America/Los_Angeles")
    let windowStart = TestCalendars.date(2026, 10, 30, in: cal)
    let currentPeriodStart = TestCalendars.date(2026, 11, 3, in: cal)

    let change = AllocationChange(effectiveFrom: windowStart, amount: 10)
    let expenses = [
      // Noon on the 25-hour day.
      ExpenseItem(amount: 4, date: TestCalendars.date(2026, 11, 1, hour: 12, in: cal)),
    ]

    let carryOver = walkCarryOver(
      from: windowStart,
      to: currentPeriodStart,
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: windowStart,
      sortedAllocationChanges: [change],
      sortedLifecycleEvents: [],
      expenses: expenses,
      calendar: cal
    )

    // 4 completed periods (10-30, 10-31, 11-01 [25h], 11-02) × $10 − $4.
    #expect(carryOver == 36)
  }

  /// Biweekly cycle [03-01, 03-15) spans the US 2026-03-08 spring-forward (the only biweekly
  /// DST coverage); neither the cycle count nor expense bucketing may shift. The 03-14 23:30
  /// expense must stay inside the cycle.
  @Test func biweeklyWalk_acrossSpringForward_fullCycleAwarded() {
    let cal = TestCalendars.gregorian(in: "America/Los_Angeles")
    let windowStart = TestCalendars.date(2026, 3, 1, in: cal) // Sunday anchor
    let currentPeriodStart = TestCalendars.date(2026, 3, 15, in: cal)

    let change = AllocationChange(effectiveFrom: windowStart, amount: 200)
    let expenses = [
      // Midday on the 23-hour transition day, mid-cycle.
      ExpenseItem(amount: 50, date: TestCalendars.date(2026, 3, 8, hour: 12, in: cal)),
      // Last evening of the cycle, still inside [03-01, 03-15).
      ExpenseItem(amount: 25, date: TestCalendars.date(2026, 3, 14, hour: 23, minute: 30, in: cal)),
    ]

    let carryOver = walkCarryOver(
      from: windowStart,
      to: currentPeriodStart,
      period: .biweekly,
      weekStart: .sunday,
      biweeklyAnchor: windowStart,
      sortedAllocationChanges: [change],
      sortedLifecycleEvents: [],
      expenses: expenses,
      calendar: cal
    )

    // One completed 14-day cycle (335 absolute hours): $200 − $75.
    #expect(carryOver == 125)
  }
}
