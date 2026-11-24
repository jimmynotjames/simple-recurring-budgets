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
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .active)
    #expect(snap.remaining == 20)
    #expect(snap.effectiveAllocation == 20)
  }

  @Test func snapshot_active_withExpenses_remainingReduced() {
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate)
    let exp = expense(amount: 12.50, date: d(2026, 4, 15, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15, hour: 14), calendar: cal, weekStart: .sunday)
    #expect(snap.remaining == 7.50)
  }

  @Test func snapshot_active_overspend_remainingNegative() {
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate)
    let exp = expense(amount: 25, date: d(2026, 4, 15, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15, hour: 14), calendar: cal, weekStart: .sunday)
    #expect(snap.remaining == -5)
  }

  @Test func snapshot_active_addFunds_remainingIncreased() {
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate)
    let exp = expense(amount: -10, date: d(2026, 4, 15, hour: 10)) // negative = add funds
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15, hour: 14), calendar: cal, weekStart: .sunday)
    #expect(snap.remaining == 30) // 20 - (-10)
  }
}

// MARK: - Snapshot: preStart state

struct BudgetCalculatorSnapshotPreStartTests {
  @Test func snapshot_preStart_nowBeforeStartDate() {
    let startDate = d(2026, 4, 20)
    let budget = makeBudget(startDate: startDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .preStart)
    #expect(snap.remaining == 0)
    #expect(snap.carryOver == 0)
    #expect(snap.effectivePeriodStart == d(2026, 4, 20))
    #expect(snap.effectivePeriodEnd == d(2026, 4, 20))
  }

  @Test func snapshot_preStart_effectiveAllocationReflectsInitialConfig() {
    let startDate = d(2026, 4, 20)
    let budget = makeBudget(allocation: 50, startDate: startDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    #expect(snap.effectiveAllocation == 50)
  }

  @Test func snapshot_nilStartDate_fallsBackToCreatedAt() {
    let budget = Budget(period: .daily)
    budget.startDate = nil
    budget.createdAt = d(2026, 4, 15)
    let change = AllocationChange(effectiveFrom: d(2026, 4, 15), amount: 20)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .active)
  }
}

// MARK: - Snapshot: postEnd state

struct BudgetCalculatorSnapshotPostEndTests {
  @Test func snapshot_postEnd_nowAfterEndDate() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(startDate: startDate, endDate: endDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 5, 15), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .postEnd)
  }

  @Test func snapshot_postEnd_chipFrozenAtFinalTally() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(startDate: startDate, endDate: endDate)
    let exp = expense(amount: 5, date: d(2026, 4, 28))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 5, 15), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .postEnd)
    // The frozen period is the final day (Apr 30).
    #expect(snap.effectivePeriodStart == d(2026, 4, 30))
    #expect(snap.effectivePeriodEnd == d(2026, 5, 1))
  }

  @Test func snapshot_onEndDate_isStillActive() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(startDate: startDate, endDate: endDate)
    // endDate is inclusive: still active at midday Apr 30.
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 30, hour: 12), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .active)
  }

  @Test func snapshot_dayAfterEndDate_isPostEnd() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(startDate: startDate, endDate: endDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 5, 1), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .postEnd)
  }
}

// MARK: - Snapshot: carry-over walker

struct BudgetCalculatorCarryOverTests {
  @Test func carryOver_zeroPriorPeriods_isZero() {
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    #expect(snap.carryOver == 0)
  }

  @Test func carryOver_singleCompletedPeriod_foldsIn() {
    let startDate = d(2026, 4, 14)
    let budget = makeBudget(startDate: startDate)
    let exp = expense(amount: 18, date: d(2026, 4, 14, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    // Apr 14: 20 − 18 = 2; current period empty → spillover 0.
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
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    // −5 + 5 + 0 = 0; current period empty.
    #expect(snap.carryOver == 0)
  }

  @Test func carryOver_overspendCurrentPeriod_absorbedsLive() {
    let startDate = d(2026, 4, 14)
    let budget = makeBudget(startDate: startDate)
    let expenses = [
      expense(amount: 18, date: d(2026, 4, 14, hour: 10)), // prior: +2 carry
      expense(amount: 21, date: d(2026, 4, 15, hour: 10)), // current: overspend by 1
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 15, hour: 12), calendar: cal, weekStart: .sunday)
    // Walker 2 + spillover (20 − 21 = −1) = 1.
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
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 15, hour: 12), calendar: cal, weekStart: .sunday)
    // Remaining 10 is inside [0, 20] → spillover 0; carry-over stays at walker 2.
    #expect(snap.remaining == 10)
    #expect(snap.carryOver == 2)
  }

  @Test func carryOver_addFundsExcess_absorbedsLive() {
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate)
    // Remaining 20 − (−30) = 50 exceeds the allocation by 30.
    let exp = expense(amount: -30, date: d(2026, 4, 15, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15, hour: 12), calendar: cal, weekStart: .sunday)
    #expect(snap.remaining == 50)
    #expect(snap.carryOver == 30) // 0 walker + 30 spillover
  }

  @Test func carryOver_lastResetDate_trimmsWalkWindow() {
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate)
    budget.lastResetDate = d(2026, 4, 13) // reset happened on Apr 13
    // Pre-reset expenses (Apr 1–12) are excluded from the walker.
    let oldExpenses = (1 ... 12).map { day in expense(amount: 5, date: d(2026, 4, day, hour: 10)) }
    let newExpense = expense(amount: 8, date: d(2026, 4, 14, hour: 10))
    let snap = BudgetCalculator.snapshot(
      budget: budget,
      expenses: oldExpenses + [newExpense],
      now: d(2026, 4, 15),
      calendar: cal, weekStart: .sunday
    )
    // Walk starts at Apr 13: Apr 13 = 20, Apr 14 = 20 − 8 = 12 → 32; current period empty.
    #expect(snap.carryOver == 32)
  }

  @Test func carryOver_weeklyMidPeriodReset_excludesPreResetExpensesFromContainingPeriod() {
    // Wednesday-grid weekly budget; week 1 = Apr 1–7. Reset on Fri Apr 3 (mid-week).
    // The walker drops pre-reset expenses from week 1 but still awards the full allocation.
    let startDate = d(2026, 4, 1) // Wednesday — aligned with the Wednesday grid
    let budget = makeBudget(period: .weekly, allocation: 100, startDate: startDate)
    budget.lastResetDate = d(2026, 4, 3) // Fri, mid week 1
    let expenses = [
      expense(amount: 20, date: d(2026, 4, 1, hour: 10)), // pre-reset (week 1)
      expense(amount: 15, date: d(2026, 4, 2, hour: 10)), // pre-reset (week 1)
      expense(amount: 30, date: d(2026, 4, 5, hour: 10)), // post-reset (week 1)
    ]
    let now = d(2026, 4, 8) // Wed — start of week 2
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: now, calendar: cal, weekStart: .wednesday)
    // Week 1: 100 − 30 post-reset = 70 (pre-reset 20 + 15 excluded by the walkWindowStart clamp).
    #expect(snap.carryOver == 70)
  }
}

// MARK: - Snapshot: reset-aware spillover

struct BudgetCalculatorResetAwareSpilloverTests {
  @Test func midPeriodReset_zeroesCurrentDeficit_remainingUnchanged() {
    // Deficit of 30 today, then Reset Carry-Over mid-period.
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(allocation: 50, startDate: startDate)
    budget.lastResetDate = d(2026, 4, 15, hour: 12)
    let exp = expense(amount: 80, date: d(2026, 4, 15, hour: 10)) // pre-reset
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15, hour: 14), calendar: cal, weekStart: .sunday)
    // Spillover input 50 − 0 post-reset = 50 → no overflow.
    #expect(snap.carryOver == 0)
    // `remaining` still reflects all of today's expenses.
    #expect(snap.remaining == -30)
  }

  @Test func postResetOverspend_spillsAgain() {
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(allocation: 50, startDate: startDate)
    budget.lastResetDate = d(2026, 4, 15, hour: 12)
    let expenses = [
      expense(amount: 80, date: d(2026, 4, 15, hour: 10)), // pre-reset — excluded from spillover
      expense(amount: 60, date: d(2026, 4, 15, hour: 13)), // post-reset — overspends the fresh 50
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 15, hour: 14), calendar: cal, weekStart: .sunday)
    // Spillover input 50 − 60 = −10 lands live.
    #expect(snap.carryOver == -10)
    #expect(snap.remaining == -90) // 50 − 140, all expenses
  }

  @Test func liveSpilloverMatchesWalkerContributionAfterPeriodCloses() {
    // Live spillover in the reset period equals the walker's contribution once it closes,
    // so carry-over doesn't jump at the boundary.
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(allocation: 50, startDate: startDate)
    budget.lastResetDate = d(2026, 4, 15, hour: 12)
    let expenses = [
      expense(amount: 80, date: d(2026, 4, 15, hour: 10)), // pre-reset
      expense(amount: 60, date: d(2026, 4, 15, hour: 13)), // post-reset overspend
    ]
    let live = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 15, hour: 14), calendar: cal, weekStart: .sunday)
    let closed = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 16), calendar: cal, weekStart: .sunday)
    // Both: 50 − 60 = −10.
    #expect(live.carryOver == -10)
    #expect(closed.carryOver == live.carryOver)
  }

  @Test func postEndResetCarryOver_zeroesPermanently() {
    // Weekly budget ended Apr 30 with surplus carry-over; reset after the end zeroes it.
    let startDate = d(2026, 4, 1) // Wednesday — aligned with the Wednesday grid below
    let budget = makeBudget(period: .weekly, allocation: 100, startDate: startDate, endDate: d(2026, 4, 30))
    let exp = expense(amount: 60, date: d(2026, 4, 2, hour: 10)) // week 1: +40 surplus
    // Before the reset the post-end carry-over is nonzero.
    let before = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 5, 15), calendar: cal, weekStart: .wednesday)
    #expect(before.lifecycleState == .postEnd)
    #expect(before.carryOver != 0)

    budget.lastResetDate = d(2026, 5, 10) // after effectiveEndExclusive (May 1)
    let after = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 5, 15), calendar: cal, weekStart: .wednesday)
    #expect(after.carryOver == 0)
  }

  @Test func postEndResetBudget_doesNotResurrectFinalAllocation() {
    // Reset Budget on an ended budget deletes expenses, so the final period rebounds to the
    // full allocation. Without the post-end carve-out the symmetric .postEnd fold would
    // put that rebound straight back into carry-over.
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(period: .weekly, allocation: 100, startDate: startDate, endDate: d(2026, 4, 30))
    budget.lastResetDate = d(2026, 5, 10)
    // No expenses: resetBudget already deleted them.
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 5, 15), calendar: cal, weekStart: .wednesday)
    #expect(snap.lifecycleState == .postEnd)
    #expect(snap.carryOver == 0)
  }

  @Test func resetDuringFinalPeriod_postEndFoldsPostResetExpensesOnly() {
    // Reset mid-final-period, then the budget ends: .postEnd folds allocation − post-reset spend.
    let startDate = d(2026, 4, 1) // Wednesday grid; final period Apr 29 – May 1 (clamped)
    let budget = makeBudget(period: .weekly, allocation: 50, startDate: startDate, endDate: d(2026, 4, 30))
    budget.lastResetDate = d(2026, 4, 30, hour: 10) // inside the final period, before end
    let expenses = [
      expense(amount: 80, date: d(2026, 4, 29, hour: 9)), // pre-reset — excluded from spillover
      expense(amount: 10, date: d(2026, 4, 30, hour: 12)), // post-reset
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 5, 15), calendar: cal, weekStart: .wednesday)
    #expect(snap.lifecycleState == .postEnd)
    // Walker window [Apr 30 10:00, Apr 29) is empty; spillover = 50 − 10 = 40.
    #expect(snap.carryOver == 40)
    // `remaining` counts all final-period expenses: 50 − 90.
    #expect(snap.remaining == -40)
  }
}

// MARK: - Snapshot: weekly period grid follows the global week-start setting

struct BudgetCalculatorWeeklyAnchorTests {
  @Test func snapshot_weeklyBudget_followsGlobalWeekStart() {
    // The weekly grid comes from the caller's weekStart, not startDate's weekday.
    let startDate = d(2026, 4, 1) // Wednesday
    let budget = makeBudget(period: .weekly, allocation: 100, startDate: startDate)
    let now = d(2026, 4, 5) // Sunday Apr 5 — start of a new Sunday-grid week
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: now, calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .active)
    #expect(snap.effectivePeriodStart == d(2026, 4, 5))
    #expect(snap.effectivePeriodEnd == d(2026, 4, 12))
    // The partial first week [Apr 1, Apr 5) closes at the full allocation (no proration).
    #expect(snap.carryOver == 100)
  }
}

// MARK: - Snapshot: startDate edit semantics (back-dating + forward-dating)

//
// Pins `allocationInEffect`'s earliest-row fallback (see `AllocationInEffectTests.
// noEligibleRow_fallsBackToEarliest`). `AddEditBudgetViewModel.applyDateEdits` deliberately
// does NOT realign `AllocationChange` history when a recurring budget's startDate is
// back-dated; the calculator extends the earliest row's amount backward at read time.
// Refactoring that fallback breaks the expectations below.

struct BudgetCalculatorStartDateEditTests {
  @Test func snapshot_backDatedStartDate_extendsEarliestAllocationToNewWindow() {
    // Weekly budget started Mon Apr 13 (one AllocationChange at Apr 13, 100); startDate is
    // back-dated to Mon Apr 6 and only Budget.startDate changes, as the VM's recurring path does.
    let originalStart = d(2026, 4, 13)
    let budget = makeBudget(period: .weekly, allocation: 100, startDate: originalStart)
    budget.startDate = d(2026, 4, 6)

    // On Mon Apr 20 the walker covers Apr 6–12 and Apr 13–19.
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 20), calendar: cal, weekStart: .monday)

    #expect(snap.effectivePeriodStart == d(2026, 4, 20))
    // Apr 6 precedes every row's effectiveFrom, so the fallback uses the earliest row (100): 2 × 100.
    #expect(snap.carryOver == 200)
  }

  @Test func snapshot_forwardDatedStartDate_walkerStartsAtNewStart() {
    // Same setup, but startDate moves forward to Mon Apr 20: the walker ignores the orphaned
    // Apr 13–19 period (no phantom credit) while the Apr 13 row still supplies the amount.
    let originalStart = d(2026, 4, 13)
    let budget = makeBudget(period: .weekly, allocation: 100, startDate: originalStart)
    budget.startDate = d(2026, 4, 20)

    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 27), calendar: cal, weekStart: .monday)

    #expect(snap.effectivePeriodStart == d(2026, 4, 27))
    // Only Apr 20–26 is credited.
    #expect(snap.carryOver == 100)
  }
}

// MARK: - Snapshot: allocation history (allocationInEffect)

struct BudgetCalculatorAllocationHistoryTests {
  @Test func snapshot_multipleAllocationChanges_usesCorrectHistoricalAllocation() {
    let startDate = d(2026, 4, 1)
    let budget = Budget(period: .daily)
    budget.startDate = startDate
    let change1 = AllocationChange(effectiveFrom: d(2026, 4, 1), amount: 20)
    let change2 = AllocationChange(effectiveFrom: d(2026, 4, 10), amount: 25)
    change1.budget = budget; change2.budget = budget
    budget.allocationChangesStorage = [change1, change2]

    // Walker covers Apr 1–14: 9 × 20 + 5 × 25 = 305; current period empty.
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    #expect(snap.effectiveAllocation == 25)
    #expect(snap.carryOver == 305)
  }

  @Test func snapshot_allocationEditMidPeriod_priorPeriodsUnchanged() {
    let startDate = d(2026, 4, 1)
    let budget = Budget(period: .daily)
    budget.startDate = startDate
    let change1 = AllocationChange(effectiveFrom: d(2026, 4, 1), amount: 20)
    let change2 = AllocationChange(effectiveFrom: d(2026, 4, 10), amount: 25)
    change1.budget = budget; change2.budget = budget
    budget.allocationChangesStorage = [change1, change2]

    // now = the change day: the current period uses 25, Apr 1–9 stay at 20.
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 10), calendar: cal, weekStart: .sunday)
    #expect(snap.effectiveAllocation == 25)
    // 9 × 20
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
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .active)
    #expect(snap.remaining == 230)
    #expect(snap.carryOver == nil)
  }

  @Test func snapshot_specificDates_pastEndDate_postEnd() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(period: .specificDates, allocation: 350, startDate: startDate, endDate: endDate)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 5, 15), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .postEnd)
    #expect(snap.carryOver == nil)
  }

  @Test func snapshot_specificDates_ignorePauseEvents() {
    let startDate = d(2026, 4, 1)
    let endDate = d(2026, 4, 30)
    let budget = makeBudget(period: .specificDates, allocation: 350, startDate: startDate, endDate: endDate)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .active) // pause is ignored for specificDates
  }

  @Test func snapshot_specificDates_singleDayWindow_endEqualsStart() {
    // endDate is the inclusive last *day*, so start == end is a valid 1-day window.
    let day = d(2026, 4, 15)
    let budget = makeBudget(period: .specificDates, allocation: 100, startDate: day, endDate: day)
    let exp = expense(amount: 30, date: d(2026, 4, 15, hour: 10))

    let during = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15, hour: 12), calendar: cal, weekStart: .sunday)
    #expect(during.lifecycleState == .active)
    #expect(during.remaining == 70)
    #expect(during.carryOver == nil)
    #expect(during.effectivePeriodStart == d(2026, 4, 15))
    #expect(during.effectivePeriodEnd == d(2026, 4, 16))

    let after = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 16), calendar: cal, weekStart: .sunday)
    #expect(after.lifecycleState == .postEnd)
    #expect(after.remaining == 70) // frozen final tally
  }

  @Test func snapshot_specificDates_multiRowDrift_latestRowWinsRegardlessOfNow() {
    // specificDates should have exactly one AllocationChange row (F-2.08). If drift (CloudKit
    // divergence, UI bug) adds rows, the latest by (effectiveFrom, lastModified) wins with NO
    // `<= now` filter; pinned so this degradation stays deliberate.
    let budget = makeBudget(period: .specificDates, allocation: 300, startDate: d(2026, 4, 1), endDate: d(2026, 4, 30))
    let driftRow = AllocationChange(effectiveFrom: d(2026, 4, 20), amount: 250)
    driftRow.budget = budget
    budget.allocationChangesStorage = (budget.allocationChangesStorage ?? []) + [driftRow]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 10), calendar: cal, weekStart: .sunday)
    // now (Apr 10) precedes the drift row's effectiveFrom (Apr 20); it wins anyway.
    #expect(snap.effectiveAllocation == 250)
    #expect(snap.remaining == 250)
  }
}

// MARK: - Snapshot: window edges

struct BudgetCalculatorWindowEdgeTests {
  @Test func expenseBeforeStartDate_neverCounted() {
    let budget = makeBudget(startDate: d(2026, 4, 10))
    let exp = expense(amount: 15, date: d(2026, 4, 5, hour: 10)) // before the window
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 12), calendar: cal, weekStart: .sunday)
    // Walker starts at Apr 10: Apr 10 + Apr 11 at 20 each; the Apr 5 expense is outside every bucket.
    #expect(snap.carryOver == 40)
    #expect(snap.remaining == 20)
  }

  @Test func expenseAfterEndDate_excludedFromFinalTally() {
    let budget = makeBudget(startDate: d(2026, 4, 1), endDate: d(2026, 4, 10))
    let exp = expense(amount: 5, date: d(2026, 4, 12, hour: 10)) // after the window
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 20), calendar: cal, weekStart: .sunday)
    // effectiveNow clamps to Apr 10 → final period [Apr 10, Apr 11); the Apr 12 expense is
    // past it and never counted. Walker Apr 1–9 = 180, postEnd folds the final day's 20 → 200.
    #expect(snap.lifecycleState == .postEnd)
    #expect(snap.remaining == 20)
    #expect(snap.carryOver == 200)
  }
}

// MARK: - Snapshot: paused state

struct BudgetCalculatorPausedTests {
  @Test func snapshot_pausedPeriod_remainingZero() {
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate)
    // Apr 10 (the pause-action day) is still active; Apr 11 onward is paused.
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 10))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 12), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .paused)
    #expect(snap.remaining == 0)
  }

  @Test func snapshot_pauseActionPeriod_isActiveBeforePauseMoment() {
    // The moment-granular UI classifier (F-7.06) shows the pause-action period as active only BEFORE
    // the pause moment (the walker treats the whole period as active for accrual).
    // After-pause sibling: BudgetCalculatorMomentGranularPauseTests.
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 10))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    // Midnight Apr 10: in the pause-action period, before the pause moment.
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 10), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .active)
  }

  @Test func snapshot_resumeActionPeriod_isActiveAfterResumeMoment() {
    // Under F-7.06, the resume-action period shows .active only AFTER the resume moment (paused before it);
    // the walker still treats the whole period as active for accrual.
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 10))
    let resumeEvent = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 15, hour: 10))
    pauseEvent.budget = budget; resumeEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent, resumeEvent]
    // 12:00 Apr 15 is strictly after the resume moment.
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 15, hour: 12), calendar: cal, weekStart: .sunday)
    #expect(snap.lifecycleState == .active)
  }

  // Integration: the walker threads pre-sorted allocation history and lifecycle events
  // through several periods; catches sort-contract or per-period lookup regressions.
  @Test func snapshot_multiplePauseCycles_andAllocationChanges_walkerSumsCorrectly() {
    let startDate = d(2026, 4, 1)
    let budget = Budget(period: .daily)
    budget.startDate = startDate
    let initial = AllocationChange(effectiveFrom: startDate, amount: 20)
    let bump = AllocationChange(effectiveFrom: d(2026, 4, 10), amount: 30)
    initial.budget = budget
    bump.budget = budget
    budget.allocationChangesStorage = [initial, bump]
    // Pause/resume-action periods are active; the periods between are paused.
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
      now: d(2026, 4, 20), calendar: cal, weekStart: .sunday
    )
    // Apr 1–4: 80; Apr 5: 20; Apr 6–7 paused: 0; Apr 8–9: 40; Apr 10–12 (alloc 30): 90;
    // Apr 13: 30; Apr 14–15 paused: 0; Apr 16: 30; Apr 17–19: 90 → 380.
    #expect(snap.carryOver == 380)
    #expect(snap.lifecycleState == .active)
  }

  @Test func snapshot_paused_backdatedExpenseInPriorActivePeriod_reflected() {
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 10))
    pauseEvent.budget = budget
    budget.lifecycleEventsStorage = [pauseEvent]
    // Paused from Apr 11; the expense is backdated into an earlier active period.
    let backdatedExpense = expense(amount: 8, date: d(2026, 4, 5, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [backdatedExpense], now: d(2026, 4, 12), calendar: cal, weekStart: .sunday)
    // Apr 1–4: 80; Apr 5: 20 − 8 = 12; Apr 6–9: 80; Apr 10: 20 → 192. Current period (Apr 11) is paused.
    #expect(snap.lifecycleState == .paused)
    #expect(snap.carryOver == 192)
  }
}
