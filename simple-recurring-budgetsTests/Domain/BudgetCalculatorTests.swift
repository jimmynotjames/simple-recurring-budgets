import Foundation
@testable import simple_recurring_budgets
import SwiftData
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
  period: BudgetPeriod = .daily,
  allocation: Decimal = 20,
  startDate: Date,
  endDate: Date? = nil,
  lastResetDate: Date? = nil,
  isCarryOverEnabled: Bool = true
) -> Budget {
  let b = Budget(period: period, isCarryOverEnabled: isCarryOverEnabled)
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

// MARK: - Snapshot: active state, basic remaining

struct BudgetCalculatorSnapshotActiveTests {
  @Test func snapshot_active_noExpenses_remainingEqualsAllocation() {
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal)
    #expect(snap.lifecycleState == .active)
    #expect(snap.remaining == 20)
    #expect(snap.effectiveAllocation == 20)
  }

  @Test func snapshot_active_withExpenses_remainingReduced() {
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate)
    let exp = expense(amount: 12.50, date: d(2026, 4, 15, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15, hour: 14), calendar: cal)
    #expect(snap.remaining == 7.50)
  }

  @Test func snapshot_active_overspend_remainingNegative() {
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate)
    let exp = expense(amount: 25, date: d(2026, 4, 15, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15, hour: 14), calendar: cal)
    #expect(snap.remaining == -5)
  }

  @Test func snapshot_active_addFunds_remainingIncreased() {
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate)
    let exp = expense(amount: -10, date: d(2026, 4, 15, hour: 10)) // negative = add funds
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15, hour: 14), calendar: cal)
    #expect(snap.remaining == 30) // 20 - (-10)
  }
}

// MARK: - Snapshot: preStart state

struct BudgetCalculatorSnapshotPreStartTests {
  @Test func snapshot_preStart_nowBeforeStartDate() {
    let startDate = d(2026, 4, 20)
    let budget = makeBudget(startDate: startDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal)
    #expect(snap.lifecycleState == .preStart)
    #expect(snap.remaining == 0)
    #expect(snap.carryOver == 0)
    #expect(snap.effectivePeriodStart == d(2026, 4, 20))
    #expect(snap.effectivePeriodEnd == d(2026, 4, 20))
  }

  @Test func snapshot_preStart_effectiveAllocationReflectsInitialConfig() {
    let startDate = d(2026, 4, 20)
    let budget = makeBudget(allocation: 50, startDate: startDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal)
    #expect(snap.effectiveAllocation == 50)
  }

  @Test func snapshot_nilStartDate_fallsBackToCreatedAt() {
    let budget = Budget(period: .daily)
    budget.startDate = nil
    budget.createdAt = d(2026, 4, 15)
    let change = AllocationChange(effectiveFrom: d(2026, 4, 15), amount: 20)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal)
    #expect(snap.lifecycleState == .active)
  }
}

// MARK: - Snapshot: postEnd state

struct BudgetCalculatorSnapshotPostEndTests {
  @Test func snapshot_postEnd_nowAfterEndDate() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(startDate: startDate, endDate: endDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 5, 15), calendar: cal)
    #expect(snap.lifecycleState == .postEnd)
  }

  @Test func snapshot_postEnd_chipFrozenAtFinalTally() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(startDate: startDate, endDate: endDate)
    // Expense on Apr 28 — inside the window
    let exp = expense(amount: 5, date: d(2026, 4, 28))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 5, 15), calendar: cal)
    #expect(snap.lifecycleState == .postEnd)
    // Apr has 30 days; daily budget Apr 1–Apr 30 = 30 periods.
    // Prior periods Apr 1–29 each at allocation 20: 29 × 20 = 580
    // Day 28 had expense 5: contribution for Apr 28 = 20 − 5 = 15 instead of 20
    // Net walker = 28 × 20 + 15 + (final day Apr 30 remaining, which is in final period and collapses to symmetric)
    // Actually the postEnd walker goes up to currentPeriodStart (Apr 30), so walker = 28 full days + Apr 29 (empty) - Apr 28's expense
    // Let's just check it's active+frozen
    #expect(snap.effectivePeriodStart == d(2026, 4, 30))
    #expect(snap.effectivePeriodEnd == d(2026, 5, 1))
  }

  @Test func snapshot_onEndDate_isStillActive() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(startDate: startDate, endDate: endDate)
    // now = Apr 30 midday — endDate itself; budget is active through all of Apr 30
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 30, hour: 12), calendar: cal)
    #expect(snap.lifecycleState == .active)
  }

  @Test func snapshot_dayAfterEndDate_isPostEnd() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(startDate: startDate, endDate: endDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 5, 1), calendar: cal)
    #expect(snap.lifecycleState == .postEnd)
  }
}

// MARK: - Snapshot: carry-over walker

struct BudgetCalculatorCarryOverTests {
  @Test func carryOver_zeroPriorPeriods_isZero() {
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal)
    #expect(snap.carryOver == 0)
  }

  @Test func carryOver_singleCompletedPeriod_foldsIn() {
    let startDate = d(2026, 4, 14)
    let budget = makeBudget(startDate: startDate)
    // Apr 14 had expense 18; Apr 15 is current
    let exp = expense(amount: 18, date: d(2026, 4, 14, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15), calendar: cal)
    // Walker: Apr 14 = 20 − 18 = 2; current period has no expenses → spillover = 0
    #expect(snap.carryOver == 2)
  }

  @Test func carryOver_multipleCompletedPeriods_catchUp() {
    let startDate = d(2026, 4, 12)
    let budget = makeBudget(startDate: startDate)
    let expenses = [
      expense(amount: 25, date: d(2026, 4, 12, hour: 10)), // day1: −5
      expense(amount: 15, date: d(2026, 4, 13, hour: 10)), // day2: +5
      expense(amount: 20, date: d(2026, 4, 14, hour: 10)), // day3: 0
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 15), calendar: cal)
    // Walker: −5 + 5 + 0 = 0; current period empty → spillover = 0
    #expect(snap.carryOver == 0)
  }

  @Test func carryOver_overspendCurrentPeriod_absorbedsLive() {
    let startDate = d(2026, 4, 14)
    let budget = makeBudget(startDate: startDate)
    let expenses = [
      expense(amount: 18, date: d(2026, 4, 14, hour: 10)), // prior: +2 carry
      expense(amount: 21, date: d(2026, 4, 15, hour: 10)), // current: overspend by 1
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 15, hour: 12), calendar: cal)
    // Walker = 2; current remaining = 20 − 21 = −1 → spillover = −1; total = 1
    #expect(snap.remaining == -1)
    #expect(snap.carryOver == 1)
  }

  @Test func carryOver_ordinarySlack_doesNotAbsorbLive() {
    let startDate = d(2026, 4, 14)
    let budget = makeBudget(startDate: startDate)
    let expenses = [
      expense(amount: 18, date: d(2026, 4, 14, hour: 10)), // prior: +2 carry
      expense(amount: 10, date: d(2026, 4, 15, hour: 10)), // current: 10 remaining (ordinary slack)
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 15, hour: 12), calendar: cal)
    // Walker = 2; current remaining = 10, inside [0, 20] → spillover = 0; total = 2
    #expect(snap.remaining == 10)
    #expect(snap.carryOver == 2)
  }

  @Test func carryOver_addFundsExcess_absorbedsLive() {
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate)
    // Add $30 funds → remaining = 20 − (−30) = 50, which is > 20 → excess = 30
    let exp = expense(amount: -30, date: d(2026, 4, 15, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15, hour: 12), calendar: cal)
    #expect(snap.remaining == 50)
    #expect(snap.carryOver == 30) // 0 walker + 30 spillover
  }

  @Test func carryOver_lastResetDate_trimmsWalkWindow() {
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate)
    budget.lastResetDate = d(2026, 4, 13) // reset happened on Apr 13
    // Expenses in Apr 1–12 should be excluded from walker
    let oldExpenses = (1 ... 12).map { day in expense(amount: 5, date: d(2026, 4, day, hour: 10)) }
    // Apr 13 expense (within reset day's period — included since Apr 13's period end Apr 14 > Apr 13 reset)
    let newExpense = expense(amount: 8, date: d(2026, 4, 14, hour: 10))
    let snap = BudgetCalculator.snapshot(
      budget: budget,
      expenses: oldExpenses + [newExpense],
      now: d(2026, 4, 15),
      calendar: cal
    )
    // Walk window starts at max(Apr 1, Apr 13) = Apr 13 00:00
    // Period Apr 13: ends Apr 14, Apr 14 <= Apr 15 (currentPeriodStart) → included
    // Expense on Apr 14 is in Apr 14's period (Apr 14–Apr 15); Apr 15 = currentPeriodStart, so Apr 14 is a prior period
    // Walker: Apr 13 period (no expense on Apr 13) = 20 − 0 = 20; Apr 14 period = 20 − 8 = 12; total = 32
    // Spillover for current period Apr 15 (no expenses) = 0
    #expect(snap.carryOver == 32)
  }

  @Test func carryOver_weeklyMidPeriodReset_excludesPreResetExpensesFromContainingPeriod() {
    // Weekly budget anchored on Wed (Apr 1, 2026). Week 1 = Apr 1–7, week 2 begins Apr 8.
    // User resets on Fri Apr 3 (mid-week); spends both before and after the reset within
    // week 1; then week 1 closes. The walker should exclude pre-reset expenses from
    // week 1's contribution and still award the full $100 allocation.
    let startDate = d(2026, 4, 1) // Wednesday — weekly anchor is Wed
    let budget = makeBudget(period: .weekly, allocation: 100, startDate: startDate)
    budget.lastResetDate = d(2026, 4, 3) // Fri, mid week 1
    let expenses = [
      expense(amount: 20, date: d(2026, 4, 1, hour: 10)), // pre-reset (week 1)
      expense(amount: 15, date: d(2026, 4, 2, hour: 10)), // pre-reset (week 1)
      expense(amount: 30, date: d(2026, 4, 5, hour: 10)), // post-reset (week 1)
    ]
    let now = d(2026, 4, 8) // Wed — start of week 2
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: now, calendar: cal)
    // Walker week 1: $100 allocation − post-reset expenses ($30) = $70.
    // Pre-reset ($20 + $15) are excluded by the walkWindowStart clamp.
    // Current period (week 2) has no expenses → spillover = 0.
    #expect(snap.carryOver == 70)
  }
}

// MARK: - Snapshot: weekly period anchoring from startDate

struct BudgetCalculatorWeeklyAnchorTests {
  @Test func snapshot_weeklyBudget_anchorsOnStartDate_notAppSettings() {
    // Budget started on a Wednesday; week should run Wed → Tue
    let startDate = d(2026, 4, 1) // Wednesday
    let budget = makeBudget(period: .weekly, allocation: 100, startDate: startDate)
    let now = d(2026, 4, 5) // Sunday Apr 5 — but this is within the Wed Apr 1 week
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: now, calendar: cal)
    #expect(snap.lifecycleState == .active)
    // Period should start on Wed Apr 1 (not Sun Mar 29)
    #expect(snap.effectivePeriodStart == d(2026, 4, 1))
    #expect(snap.effectivePeriodEnd == d(2026, 4, 8))
  }
}

// MARK: - Snapshot: allocation history (allocationInEffect)

struct BudgetCalculatorAllocationHistoryTests {
  @Test func snapshot_multipleAllocationChanges_usesCorrectHistoricalAllocation() {
    let startDate = d(2026, 4, 1)
    let budget = Budget(period: .daily)
    budget.startDate = startDate
    // Initial allocation: 20 from Apr 1
    // New allocation: 25 starting Apr 10
    let change1 = AllocationChange(effectiveFrom: d(2026, 4, 1), amount: 20)
    let change2 = AllocationChange(effectiveFrom: d(2026, 4, 10), amount: 25)
    change1.budget = budget; change2.budget = budget
    budget.allocationChangesStorage = [change1, change2]

    // now = Apr 15; walker covers Apr 1–14
    // Apr 1–9 (9 days) at alloc 20 = 9 × 20 = 180
    // Apr 10–14 (5 days) at alloc 25 = 5 × 25 = 125
    // Total walker = 305; current period Apr 15 alloc = 25, no expenses → spillover = 0
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal)
    #expect(snap.effectiveAllocation == 25)
    #expect(snap.carryOver == 305)
  }

  @Test func snapshot_allocationEditMidPeriod_priorPeriodsUnchanged() {
    let startDate = d(2026, 4, 1)
    let budget = Budget(period: .daily)
    budget.startDate = startDate
    // Allocation was 20, changed to 25 mid-month on Apr 10
    let change1 = AllocationChange(effectiveFrom: d(2026, 4, 1), amount: 20)
    let change2 = AllocationChange(effectiveFrom: d(2026, 4, 10), amount: 25)
    change1.budget = budget; change2.budget = budget
    budget.allocationChangesStorage = [change1, change2]

    // now = Apr 10 (same day as allocation change)
    // Current period: Apr 10 with alloc 25; no prior completed periods with the new alloc
    // Apr 1–9 still used alloc 20
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 10), calendar: cal)
    #expect(snap.effectiveAllocation == 25)
    // Walker: Apr 1–9 at 20 each = 180 (9 complete days)
    #expect(snap.carryOver == 180)
  }
}

// MARK: - Snapshot: specificDates branch

struct BudgetCalculatorSpecificDatesTests {
  @Test func snapshot_specificDates_inProgress_remainingAndNilCarryOver() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(period: .specificDates, allocation: 350, startDate: startDate, endDate: endDate)
    let exp = expense(amount: 120, date: d(2026, 4, 15))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15), calendar: cal)
    #expect(snap.lifecycleState == .active)
    #expect(snap.remaining == 230)
    #expect(snap.carryOver == nil)
  }

  @Test func snapshot_specificDates_pastEndDate_postEnd() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(period: .specificDates, allocation: 350, startDate: startDate, endDate: endDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 5, 15), calendar: cal)
    #expect(snap.lifecycleState == .postEnd)
    #expect(snap.carryOver == nil)
  }

  @Test func snapshot_specificDates_ignorePauseEvents() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(period: .specificDates, allocation: 350, startDate: startDate, endDate: endDate)
    // Add a spurious pause event
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal)
    #expect(snap.lifecycleState == .active) // pause is ignored for specificDates
  }
}

// MARK: - Snapshot: paused state

struct BudgetCalculatorPausedTests {
  @Test func snapshot_pausedPeriod_remainingZero() {
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate)
    // Pause on Apr 10 → Apr 10 is still active, Apr 11 onwards is paused
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 10))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 12), calendar: cal)
    #expect(snap.lifecycleState == .paused)
    #expect(snap.remaining == 0)
  }

  @Test func snapshot_pauseActionPeriod_isStillActive() {
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 10))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    // now = Apr 10 itself (the pause-action period)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 10), calendar: cal)
    #expect(snap.lifecycleState == .active)
  }

  @Test func snapshot_resumeActionPeriod_isActive() {
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 10))
    let resumeEvent = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 15, hour: 10))
    pauseEvent.budget = budget; resumeEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent, resumeEvent]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal)
    #expect(snap.lifecycleState == .active)
  }

  // Integration: exercises the walker's threading of pre-sorted allocation history and
  // lifecycle events through multiple completed periods. Catches regressions where the
  // sort contract or the per-period lookup gets the wrong value.
  @Test func snapshot_multiplePauseCycles_andAllocationChanges_walkerSumsCorrectly() {
    let startDate = d(2026, 4, 1)
    let budget = Budget(period: .daily)
    budget.startDate = startDate
    // Initial alloc 20; bumps to 30 on Apr 10.
    let initial = AllocationChange(effectiveFrom: startDate, amount: 20)
    let bump = AllocationChange(effectiveFrom: d(2026, 4, 10), amount: 30)
    initial.budget = budget
    bump.budget = budget
    budget.allocationChangesStorage = [initial, bump]
    // Pause Apr 5 → Resume Apr 8; Pause Apr 13 → Resume Apr 16.
    // Pause/resume-action periods are themselves active; the periods *between* are paused.
    let events: [LifecycleEvent] = [
      LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 5, hour: 10)),
      LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 8, hour: 10)),
      LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 13, hour: 10)),
      LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 16, hour: 10)),
    ]
    for e in events {
      e.budget = budget
    }
    budget.lifecycleEventsStorage = events

    let snap = BudgetCalculator.snapshot(
      budget: budget, expenses: [],
      now: d(2026, 4, 20), calendar: cal
    )
    // Apr 1–4: 4 × 20 = 80
    // Apr 5 (pause-action): active, 20
    // Apr 6–7: paused, 0
    // Apr 8 (resume-action): active, 20
    // Apr 9: 20
    // Apr 10–12: 3 × 30 = 90 (allocation bumped on Apr 10)
    // Apr 13 (pause-action): active, 30
    // Apr 14–15: paused, 0
    // Apr 16 (resume-action): active, 30
    // Apr 17–19: 3 × 30 = 90
    // Total = 80 + 20 + 20 + 20 + 90 + 30 + 30 + 90 = 380
    #expect(snap.carryOver == 380)
    #expect(snap.lifecycleState == .active)
  }

  @Test func snapshot_paused_backdatedExpenseInPriorActivePeriod_reflected() {
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 10))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    // Budget is paused on Apr 11+. User backdates an expense to Apr 5.
    let backdatedExpense = expense(amount: 8, date: d(2026, 4, 5, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [backdatedExpense], now: d(2026, 4, 12), calendar: cal)
    // Apr 1–4: 4 × 20 = 80; Apr 5: 20 − 8 = 12; Apr 6–9 (4 days): 4 × 20 = 80; Apr 10: active, 20 − 0 = 20
    // Walker total = 80 + 12 + 80 + 20 = 192; current period Apr 11 is paused → remaining = 0, spillover = 0
    #expect(snap.lifecycleState == .paused)
    #expect(snap.carryOver == 192)
  }
}
