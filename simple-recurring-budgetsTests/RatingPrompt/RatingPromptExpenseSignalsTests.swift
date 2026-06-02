import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Covers the Add-mode save hook's pure core, `RatingPromptCoordinator.expenseLogSignals`
/// (W2): edit-mode / nil-budget produce no signals; active vs paused and non-deficit vs
/// deficit budgets produce the correct flags the hook feeds to `recordExpenseLogged`.
@Suite("Rating prompt — expense-log signals (F-6.03, W2)")
@MainActor
struct RatingPromptExpenseSignalsTests {
  static var utcCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.minute = 0; comps.second = 0
    comps.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: comps)!
  }

  private func makeBudget(allocation: Decimal = 20, startDate: Date, in ctx: ModelContext) -> Budget {
    let b = Budget(period: .daily)
    b.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: allocation)
    change.budget = b
    ctx.insert(b)
    ctx.insert(change)
    return b
  }

  @Test("edit mode produces no signals (does not feed the prompt)")
  func editModeReturnsNil() throws {
    let ctx = try ModelContext(TestModelContainer.make())
    let budget = makeBudget(startDate: date(2026, 1, 1), in: ctx)
    let signals = RatingPromptCoordinator.expenseLogSignals(
      isAddMode: false, budget: budget, now: date(2026, 1, 10), calendar: Self.utcCalendar
    )
    #expect(signals == nil)
  }

  @Test("nil budget produces no signals")
  func nilBudgetReturnsNil() {
    #expect(RatingPromptCoordinator.expenseLogSignals(isAddMode: true, budget: nil) == nil)
  }

  @Test("add mode on an active, non-deficit budget → (active, non-negative)")
  func activeNonDeficit() throws {
    let ctx = try ModelContext(TestModelContainer.make())
    let budget = makeBudget(allocation: 20, startDate: date(2026, 1, 1), in: ctx)
    try ctx.save()
    let signals = RatingPromptCoordinator.expenseLogSignals(
      isAddMode: true, budget: budget, now: date(2026, 1, 10), calendar: Self.utcCalendar
    )
    #expect(signals?.isActiveBudget == true)
    #expect(signals?.remainingIsNonNegative == true)
  }

  @Test("add mode on an overspent active budget → (active, deficit)")
  func activeDeficit() throws {
    let ctx = try ModelContext(TestModelContainer.make())
    let now = date(2026, 1, 10)
    let budget = makeBudget(allocation: 20, startDate: date(2026, 1, 1), in: ctx)
    let overspend = ExpenseItem(amount: Decimal(50), date: now)
    overspend.budget = budget
    ctx.insert(overspend)
    try ctx.save()
    let signals = RatingPromptCoordinator.expenseLogSignals(
      isAddMode: true, budget: budget, now: now, calendar: Self.utcCalendar
    )
    #expect(signals?.isActiveBudget == true)
    #expect(signals?.remainingIsNonNegative == false)
  }

  @Test("add mode on a paused budget → not active (excluded from prompting)")
  func pausedNotActive() throws {
    let ctx = try ModelContext(TestModelContainer.make())
    let budget = makeBudget(allocation: 20, startDate: date(2026, 1, 1), in: ctx)
    let pause = LifecycleEvent(kind: .pause, effectiveDate: date(2026, 1, 5))
    pause.budget = budget
    ctx.insert(pause)
    try ctx.save()
    let signals = RatingPromptCoordinator.expenseLogSignals(
      isAddMode: true, budget: budget, now: date(2026, 1, 10), calendar: Self.utcCalendar
    )
    #expect(signals?.isActiveBudget == false)
  }
}
