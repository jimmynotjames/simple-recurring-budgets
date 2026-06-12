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
  allocation: Decimal = 500,
  startDate: Date,
  endDate: Date? = nil,
  lastResetDate: Date? = nil
) -> Budget {
  let b = Budget(period: .monthly)
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

// MARK: - Snapshot: monthly grid (pre-#240 safety net, Group A)

/// Monthly budgets share the universal calendar-month grid, so every expectation
/// here survives the #240 "Option 1" change (which touches only weekly anchoring).
struct BudgetCalculatorMonthlySnapshotTests {
  @Test func startOnJan31_shortMonthTransition_fullAllocationsNoProration() {
    // Start on the last day of January — a 1-day stub before the Feb 1 boundary.
    let budget = makeBudget(startDate: d(2026, 1, 31))
    let exp = expense(amount: 100, date: d(2026, 1, 31, hour: 14))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 3, 10), calendar: cal)
    // Walker boundaries enumerate from periodStart(containing Jan 31) = Jan 1.
    // Jan period: no row has effectiveFrom <= Jan 1, so allocationInEffect falls
    // back to the earliest row (500); full award, no proration for the 1-day stub;
    // expenses >= max(Jan 1, Jan 31) → 100. Contribution = 400.
    // Feb (28 days, 2026 not a leap year): 500. Walker = 900.
    #expect(snap.carryOver == 900)
    #expect(snap.remaining == 500)
    #expect(snap.effectivePeriodStart == d(2026, 3, 1))
    #expect(snap.effectivePeriodEnd == d(2026, 4, 1))
  }

  @Test func multiMonthWalk_withAllocationChange_andOverspend() {
    let budget = Budget(period: .monthly)
    budget.startDate = d(2026, 1, 1)
    let change1 = AllocationChange(effectiveFrom: d(2026, 1, 1), amount: 500)
    let change2 = AllocationChange(effectiveFrom: d(2026, 3, 1), amount: 600)
    change1.budget = budget; change2.budget = budget
    budget.allocationChangesStorage = [change1, change2]
    let expenses = [
      expense(amount: 450, date: d(2026, 1, 10, hour: 10)),
      expense(amount: 700, date: d(2026, 2, 14, hour: 10)), // overspent month
      expense(amount: 100, date: d(2026, 3, 5, hour: 10)),
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 4, 10), calendar: cal)
    // Walker: Jan 500−450 = 50; Feb 500−700 = −200; Mar 600−100 = 500. Sum = 350.
    #expect(snap.carryOver == 350)
    #expect(snap.effectiveAllocation == 600)
    #expect(snap.remaining == 600)
  }

  @Test func endDateMidMonth_postEndFoldsFinalMonth() {
    let budget = makeBudget(startDate: d(2026, 2, 1), endDate: d(2026, 4, 15))
    let exp = expense(amount: 200, date: d(2026, 4, 10, hour: 10))
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 5, 20), calendar: cal)
    // effectiveNow clamps to Apr 15 → final period [Apr 1, Apr 16) after the endDate
    // clamp. Walker: Feb + Mar = 1000. remaining = 500 − 200 = 300; postEnd folds it
    // all → carryOver = 1300.
    #expect(snap.lifecycleState == .postEnd)
    #expect(snap.remaining == 300)
    #expect(snap.carryOver == 1300)
    #expect(snap.effectivePeriodEnd == d(2026, 4, 16))
  }

  @Test func midMonthReset_walkerExcludesPreResetExpenses() {
    let budget = makeBudget(startDate: d(2026, 1, 1), lastResetDate: d(2026, 2, 14))
    let expenses = [
      expense(amount: 300, date: d(2026, 2, 10, hour: 10)), // pre-reset — excluded
      expense(amount: 50, date: d(2026, 2, 20, hour: 10)), // post-reset
    ]
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: expenses, now: d(2026, 3, 10), calendar: cal)
    // Walk window starts at the reset (Feb 14) → boundaries enumerate [Feb 1] only;
    // January is implicitly excluded. February: full allocation (no proration) minus
    // post-reset expenses = 500 − 50 = 450.
    #expect(snap.carryOver == 450)
    #expect(snap.remaining == 500)
  }
}
