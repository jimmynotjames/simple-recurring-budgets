import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Shared test helpers (7.1)

/// Fixed-UTC Gregorian calendar for deterministic results in all BudgetCalculator tests.
private let cal: Calendar = {
  var c = Calendar(identifier: .gregorian)
  c.timeZone = TimeZone(identifier: "UTC")!
  return c
}()

/// Build a `Date` at midnight UTC.
private func d(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
  var comps = DateComponents()
  comps.year = year; comps.month = month; comps.day = day
  comps.hour = hour; comps.minute = 0; comps.second = 0
  comps.timeZone = TimeZone(identifier: "UTC")
  return Calendar(identifier: .gregorian).date(from: comps)!
}

/// Create an `ExpenseItem` with a given amount and date, inserted into `context`.
@discardableResult
private func expense(amount: Decimal, date: Date, in context: ModelContext) -> ExpenseItem {
  let item = ExpenseItem(amount: amount, date: date)
  context.insert(item)
  return item
}

// MARK: - BudgetCalculator.remaining (7.2)

struct BudgetCalculatorRemainingTests {
  @Test func remaining_underBudget() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let e = expense(amount: 12.50, date: d(2026, 4, 15, hour: 10), in: ctx)
    let result = BudgetCalculator.remaining(
      allocation: 20,
      expenses: [e],
      periodStart: d(2026, 4, 15),
      periodEnd: d(2026, 4, 16)
    )
    #expect(result == 7.50)
  }

  @Test func remaining_overBudget() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let e = expense(amount: 25, date: d(2026, 4, 15, hour: 10), in: ctx)
    let result = BudgetCalculator.remaining(
      allocation: 20,
      expenses: [e],
      periodStart: d(2026, 4, 15),
      periodEnd: d(2026, 4, 16)
    )
    #expect(result == -5)
  }

  @Test func remaining_noExpenses() {
    let result = BudgetCalculator.remaining(
      allocation: 20,
      expenses: [],
      periodStart: d(2026, 4, 15),
      periodEnd: d(2026, 4, 16)
    )
    #expect(result == 20)
  }

  /// Expense from a prior period (Saturday, before a Sunday weekly period start) is excluded.
  @Test func remaining_expensesFromOtherPeriodsExcluded() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    // Weekly period: Sun 2026-04-12 to Sat 2026-04-18 (end = Sun 2026-04-19)
    let inPeriod = expense(amount: 30, date: d(2026, 4, 13), in: ctx) // Monday — included
    let outOfPeriod = expense(amount: 50, date: d(2026, 4, 11), in: ctx) // Saturday prior — excluded
    let result = BudgetCalculator.remaining(
      allocation: 100,
      expenses: [inPeriod, outOfPeriod],
      periodStart: d(2026, 4, 12),
      periodEnd: d(2026, 4, 19)
    )
    #expect(result == 70) // 100 - 30 = 70
  }

  /// Add-funds transaction (negative amount) reduces net expenses and increases remaining.
  @Test func remaining_addFundsReducesExpenseTotal() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let exp = expense(amount: 15, date: d(2026, 4, 15, hour: 9), in: ctx)
    let add = expense(amount: -5, date: d(2026, 4, 15, hour: 10), in: ctx)
    let result = BudgetCalculator.remaining(
      allocation: 20,
      expenses: [exp, add],
      periodStart: d(2026, 4, 15),
      periodEnd: d(2026, 4, 16)
    )
    #expect(result == 10) // 20 - (15 + (-5)) = 10
  }
}

// MARK: - BudgetCalculator.rollCarryOver (7.3 & 7.4)

struct BudgetCalculatorRollCarryOverTests {
  /// biweekly anchor for tests that use daily/weekly periods (value unused by those periods)
  private let anchor = d(2026, 3, 29)

  // MARK: 7.3 — Daily-period roll scenarios

  /// Single period boundary crossed: yesterday is complete, carry-over picks up remainder.
  @Test func rollCarryOver_singleBoundaryCrossed() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    // yesterday: 2026-04-14; today: 2026-04-15
    let e = expense(amount: 18, date: d(2026, 4, 14, hour: 10), in: ctx)
    let result = BudgetCalculator.rollCarryOver(
      currentAmount: 0,
      allocation: 20,
      expenses: [e],
      lastProcessedDate: d(2026, 4, 14),
      now: d(2026, 4, 15, hour: 8),
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.amount == 2) // 0 + (20 - 18)
    #expect(result.lastProcessedDate == d(2026, 4, 15))
  }

  /// Multi-boundary catch-up: 3 completed days, each with different expenses.
  @Test func rollCarryOver_multiBoundaryCatchUp() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    // day1=Apr 12 (25), day2=Apr 13 (15), day3=Apr 14 (20). now=Apr 15.
    let e1 = expense(amount: 25, date: d(2026, 4, 12, hour: 10), in: ctx) // delta: -5
    let e2 = expense(amount: 15, date: d(2026, 4, 13, hour: 10), in: ctx) // delta: +5
    let e3 = expense(amount: 20, date: d(2026, 4, 14, hour: 10), in: ctx) // delta: 0
    let result = BudgetCalculator.rollCarryOver(
      currentAmount: 0,
      allocation: 20,
      expenses: [e1, e2, e3],
      lastProcessedDate: d(2026, 4, 12),
      now: d(2026, 4, 15, hour: 8),
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.amount == 0) // (-5) + 5 + 0
    #expect(result.lastProcessedDate == d(2026, 4, 15))
  }

  /// No boundary crossed: both lastProcessedDate and now are within the same day.
  @Test func rollCarryOver_noBoundaryCrossed() {
    let result = BudgetCalculator.rollCarryOver(
      currentAmount: 5,
      allocation: 20,
      expenses: [],
      lastProcessedDate: d(2026, 4, 15),
      now: d(2026, 4, 15, hour: 14),
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.amount == 5) // unchanged
    #expect(result.lastProcessedDate == d(2026, 4, 15)) // unchanged
  }

  /// Negative carry-over accumulates when expenses exceed allocation.
  @Test func rollCarryOver_negativeCarryOverAccumulates() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let e = expense(amount: 30, date: d(2026, 4, 14, hour: 10), in: ctx)
    let result = BudgetCalculator.rollCarryOver(
      currentAmount: -10,
      allocation: 20,
      expenses: [e],
      lastProcessedDate: d(2026, 4, 14),
      now: d(2026, 4, 15, hour: 8),
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.amount == -20) // -10 + (20 - 30)
    #expect(result.lastProcessedDate == d(2026, 4, 15))
  }

  // MARK: 7.4 — Weekly period roll

  /// Weekly roll: last Sunday processed, current Sunday boundary has been crossed.
  /// Expenses in last week total 80; allocation = 100.
  @Test func rollCarryOver_weeklyPeriod_correctExpenseBucketing() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    // Last week: Sun Apr 5 – Sat Apr 11. Expenses in that window = 80.
    let e1 = expense(amount: 50, date: d(2026, 4, 6, hour: 10), in: ctx) // Mon Apr 6 — in window
    let e2 = expense(amount: 30, date: d(2026, 4, 10, hour: 10), in: ctx) // Fri Apr 10 — in window
    let eOut = expense(amount: 20, date: d(2026, 4, 13, hour: 10), in: ctx) // Mon Apr 13 — out of window
    // now = Sun Apr 12, 01:00 (boundary just crossed)
    let result = BudgetCalculator.rollCarryOver(
      currentAmount: 0,
      allocation: 100,
      expenses: [e1, e2, eOut],
      lastProcessedDate: d(2026, 4, 5), // last Sunday
      now: d(2026, 4, 12, hour: 1),
      period: .weekly,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.amount == 20) // 100 - 80 = 20
    #expect(result.lastProcessedDate == d(2026, 4, 12))
  }
}

// MARK: - BudgetCalculator.checkScheduledReset (7.5)

struct BudgetCalculatorResetTests {
  private let anchor = d(2026, 3, 29)

  // MARK: Weekly reset cadence on a daily budget

  /// lastResetDate = Sunday Apr 5; now = Sunday Apr 12. Weekly cadence crosses the boundary.
  @Test func checkScheduledReset_weeklyCadence_dailyBudget_resetsOnSunday() {
    // 2026-04-05 is Sunday; 2026-04-12 is Sunday — both verified above.
    let result = BudgetCalculator.checkScheduledReset(
      lastResetDate: d(2026, 4, 5),
      resetCadence: .weekly,
      now: d(2026, 4, 12),
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.shouldReset == true)
    #expect(result.newResetDate == d(2026, 4, 12))
  }

  // MARK: Monthly reset cadence on a weekly budget

  /// lastResetDate = Mon Mar 2; monthly candidate = Mon Apr 6 (first Monday >= Apr 2).
  @Test func checkScheduledReset_monthlyCadence_weeklyBudget() {
    // 2026-03-02 is Monday (verified: (4+60)%7=1 → Monday).
    // 2026-04-02 is Thursday: candidate for first Monday after that = Apr 6.
    // 2026-04-06: (4+95)%7=1 → Monday ✓
    let result = BudgetCalculator.checkScheduledReset(
      lastResetDate: d(2026, 3, 2),
      resetCadence: .monthly,
      now: d(2026, 4, 6, hour: 12),
      period: .weekly,
      weekStart: .monday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.shouldReset == true)
    #expect(result.newResetDate == d(2026, 4, 6))
  }

  // MARK: Quarterly reset cadence on a monthly budget

  @Test func checkScheduledReset_quarterlyCadence_monthlyBudget() {
    let result = BudgetCalculator.checkScheduledReset(
      lastResetDate: d(2026, 1, 1),
      resetCadence: .quarterly,
      now: d(2026, 4, 1),
      period: .monthly,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.shouldReset == true)
    #expect(result.newResetDate == d(2026, 4, 1))
  }

  // MARK: Biweekly reset cadence on a daily budget

  /// lastResetDate = Sunday Apr 5; biweekly cadence; now = Sunday Apr 19 (14 days later).
  @Test func checkScheduledReset_biweeklyCadence_dailyBudget() {
    // Apr 5 + 14 days = Apr 19. Apr 19: (4+108)%7=0 → Sunday ✓
    let result = BudgetCalculator.checkScheduledReset(
      lastResetDate: d(2026, 4, 5),
      resetCadence: .biweekly,
      now: d(2026, 4, 19),
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.shouldReset == true)
    #expect(result.newResetDate == d(2026, 4, 19))
  }

  // MARK: Never cadence

  @Test func checkScheduledReset_neverCadence_noReset() {
    let result = BudgetCalculator.checkScheduledReset(
      lastResetDate: d(2026, 1, 1),
      resetCadence: .never,
      now: d(2026, 12, 31),
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.shouldReset == false)
    #expect(result.newResetDate == nil)
  }

  // MARK: Cadence interval not yet elapsed

  @Test func checkScheduledReset_cadenceNotElapsed_noReset() {
    // lastReset = Sun Apr 5; cadence = weekly; now = Thu Apr 9 (< Apr 12)
    // 2026-04-09: (4+98)%7=4 → Thursday ✓
    let result = BudgetCalculator.checkScheduledReset(
      lastResetDate: d(2026, 4, 5),
      resetCadence: .weekly,
      now: d(2026, 4, 9),
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.shouldReset == false)
    #expect(result.newResetDate == nil)
  }

  // MARK: Multiple resets skipped → most recent boundary returned

  /// lastReset = Sun Mar 1; cadence = weekly; now = Sun Apr 12 (6 weeks later).
  /// Should return the most recent applicable Sunday, which is Apr 12.
  @Test func checkScheduledReset_longGap_returnsMostRecentBoundary() {
    // 2026-03-01 is Sunday: (4+59)%7=0 → Sunday ✓
    let result = BudgetCalculator.checkScheduledReset(
      lastResetDate: d(2026, 3, 1),
      resetCadence: .weekly,
      now: d(2026, 4, 12),
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(result.shouldReset == true)
    #expect(result.newResetDate == d(2026, 4, 12))
  }
}

// MARK: - Roll-then-reset ordering (7.6)

struct BudgetCalculatorRollThenResetTests {
  /// Scenario: carry-over is 0, allocation 20/day, reset cadence weekly (Sunday start).
  ///
  /// lastProcessedDate is 6 days before this Sunday Apr 12 = Monday Apr 6.
  /// (The spec labels this "Saturday" but Monday Apr 6 is the correct date 6 days prior.)
  /// lastResetDate = last Sunday Apr 5. now = Sunday Apr 12 01:00 (reset boundary crossed).
  ///
  /// Expenses on Apr 6–11 total 100 (the 6 completed days between lastProcessedDate and now):
  ///   20 + 20 + 20 + 20 + 10 + 10 = 100
  ///
  /// Roll first: 6 × 20 − 100 = 20. Then reset zeroes carry-over to 0.
  @Test func rollThenReset_carryOverAccumulatesThenResets() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)

    // Expenses on the 6 completed days: Apr 6 (Mon) through Apr 11 (Sat)
    let e1 = expense(amount: 20, date: d(2026, 4, 6, hour: 10), in: ctx)
    let e2 = expense(amount: 20, date: d(2026, 4, 7, hour: 10), in: ctx)
    let e3 = expense(amount: 20, date: d(2026, 4, 8, hour: 10), in: ctx)
    let e4 = expense(amount: 20, date: d(2026, 4, 9, hour: 10), in: ctx)
    let e5 = expense(amount: 10, date: d(2026, 4, 10, hour: 10), in: ctx)
    let e6 = expense(amount: 10, date: d(2026, 4, 11, hour: 10), in: ctx)
    let allExpenses = [e1, e2, e3, e4, e5, e6]

    let anchor = d(2026, 3, 29)
    let now = d(2026, 4, 12, hour: 1) // just after Sunday Apr 12 midnight

    // Step 1: Roll carry-over.
    // periodBoundaries(from: Apr 6, to: Apr 12 01:00) yields [Apr 6 … Apr 12].
    // Apr 6–11 each complete (nextBoundary <= now); Apr 12's next = Apr 13 > now → skip.
    // Deltas: 0, 0, 0, 0, +10, +10 → amount = 20.
    let rollResult = BudgetCalculator.rollCarryOver(
      currentAmount: 0,
      allocation: 20,
      expenses: allExpenses,
      lastProcessedDate: d(2026, 4, 6), // 6 days before this Sunday
      now: now,
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(rollResult.amount == 20)
    #expect(rollResult.lastProcessedDate == d(2026, 4, 12))

    // Step 2: Check for scheduled reset.
    let resetResult = BudgetCalculator.checkScheduledReset(
      lastResetDate: d(2026, 4, 5), // last Sunday reset
      resetCadence: .weekly,
      now: now,
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: cal
    )
    #expect(resetResult.shouldReset == true)
    #expect(resetResult.newResetDate == d(2026, 4, 12))

    // Step 3: Caller applies reset — carry-over zeroes out.
    let finalAmount = resetResult.shouldReset ? Decimal(0) : rollResult.amount
    #expect(finalAmount == 0)
  }
}
