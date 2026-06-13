import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Shared test helpers (deliberately local — mirrors BudgetCalculatorTests.swift)

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

// MARK: - Moment-granular UI pause classification (F-7.06 two-clock model)

struct BudgetCalculatorMomentGranularPauseTests {
  @Test func midPeriodPause_flipsLifecycleStateImmediately() {
    let budget = makeBudget(startDate: d(2026, 4, 1))
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 14))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    // now is one minute after the pause moment, same period (the day Apr 10).
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
    // Expenses totaling 12 on Apr 10 (before the pause moment).
    let exp = ExpenseItem(amount: 12, date: d(2026, 4, 10, hour: 9))
    // The pause-action day contributes `allocation - in-period-expenses = 20 - 12 = 8` to the walker.
    // Apr 1–9 (9 active days) contribute 9 * 20 = 180. Apr 10 contributes 8. Walker = 188.
    // Apr 11 is paused (post-pause-action) → contributes 0; the current period (Apr 11)
    // also short-circuits to remaining = 0.
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
    // Budget starts May 1; pause clamped to startDate; now is before startDate.
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
    // Budget ends Apr 30; pause on Apr 25; now is after endDate.
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
    // Regression: a pause scheduled at 14:00 today must NOT flip the UI at 13:59.
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
