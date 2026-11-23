import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Shared test helpers (local copy of BudgetCalculatorTests.swift's)

private let cal: Calendar = {
  var c = Calendar(identifier: .gregorian)
  c.timeZone = TimeZone(identifier: "UTC")!
  return c
}()

private func d(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
  var comps = DateComponents()
  comps.year = year; comps.month = month; comps.day = day
  comps.hour = hour; comps.minute = minute; comps.second = 0
  comps.timeZone = TimeZone(identifier: "UTC")
  return Calendar(identifier: .gregorian).date(from: comps)!
}

private func makeBudget(
  period: BudgetPeriod = .daily,
  allocation: Decimal = 20,
  startDate: Date,
  endDate: Date? = nil
) -> Budget {
  let b = Budget(period: period)
  b.startDate = startDate
  b.endDate = endDate
  let change = AllocationChange(effectiveFrom: startDate, amount: allocation)
  change.budget = b
  b.allocationChangesStorage = [change]
  return b
}

// MARK: - Moment-granular UI pause classification

struct BudgetCalculatorMomentGranularPauseTests {
  @Test func midPeriodPause_flipsLifecycleStateImmediately() {
    let budget = makeBudget(startDate: d(2026, 4, 1))
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 14))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    // One minute after the pause moment, same day.
    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [],
      now: d(2026, 4, 10, hour: 14, minute: 1), calendar: cal, weekStart: .sunday
    )
    #expect(snap.lifecycleState == .paused)
  }

  @Test func midPeriodPause_doesNotChangeCarryOverMathForPauseActionPeriod() {
    let budget = makeBudget(startDate: d(2026, 4, 1))
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 14))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    // Expense of 12 precedes the pause moment.
    let exp = ExpenseItem(amount: 12, date: d(2026, 4, 10, hour: 9))
    // Walker: Apr 1–9 = 9 × 20 = 180, pause-action day Apr 10 = 20 − 12 = 8 → 188.
    // Apr 11 is paused: contributes 0 and remaining short-circuits to 0.
    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [exp],
      now: d(2026, 4, 11, hour: 9), calendar: cal, weekStart: .sunday
    )
    #expect(snap.carryOver == 188)
    #expect(snap.remaining == 0)
    #expect(snap.lifecycleState == .paused)
  }

  @Test func samePeriodPauseThenResume_netsToActive() {
    let budget = makeBudget(startDate: d(2026, 4, 1))
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 9))
    let resumeEvent = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 10, hour: 11))
    pauseEvent.budget = budget; resumeEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent, resumeEvent]
    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [],
      now: d(2026, 4, 10, hour: 12), calendar: cal, weekStart: .sunday
    )
    #expect(snap.lifecycleState == .active)
  }

  @Test func preStartPrecedence_overridesPaused() {
    // Pause clamped to the May 1 startDate; now is before it.
    let budget = makeBudget(startDate: d(2026, 5, 1))
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 5, 1))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [],
      now: d(2026, 4, 20), calendar: cal, weekStart: .sunday
    )
    #expect(snap.lifecycleState == .preStart)
  }

  @Test func postEndPrecedence_overridesPaused() {
    // Pause on Apr 25; now is after the Apr 30 endDate.
    let budget = makeBudget(startDate: d(2026, 4, 1), endDate: d(2026, 4, 30))
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 25))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [],
      now: d(2026, 5, 5), calendar: cal, weekStart: .sunday
    )
    #expect(snap.lifecycleState == .postEnd)
  }

  @Test func emptyLifecycleHistory_staysActive() {
    let budget = makeBudget(startDate: d(2026, 4, 1))
    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [],
      now: d(2026, 4, 15), calendar: cal, weekStart: .sunday
    )
    #expect(snap.lifecycleState == .active)
  }

  @Test func beforePauseMoment_sameDay_isStillActive() {
    // A pause at 14:00 must NOT flip the UI at 13:59.
    let budget = makeBudget(startDate: d(2026, 4, 1))
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 14))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [],
      now: d(2026, 4, 10, hour: 13, minute: 59), calendar: cal, weekStart: .sunday
    )
    #expect(snap.lifecycleState == .active)
  }
}
