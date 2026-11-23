import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Shared helpers

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
  in context: ModelContext
) -> Budget {
  let b = Budget(period: period)
  b.startDate = startDate
  let change = AllocationChange(effectiveFrom: startDate, amount: allocation)
  change.budget = b
  context.insert(b)
  context.insert(change)
  return b
}

// MARK: - result(for:): pure read, no mutations

struct BudgetLifecycleResultTests {
  @Test func result_idempotent_includesNewFields() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10))
    pauseEvent.budget = budget; ctx.insert(pauseEvent)
    try ctx.save()

    let r1 = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    let r2 = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(r1 == r2)
    #expect(r1.lifecycleState == .paused)
    #expect(r1.pausedSince == d(2026, 4, 10))
  }

  /// One minute after a mid-period pause (same period), `lifecycleState` is already `.paused`.
  /// Snapshot-level tests cover the math; this checks the adapter passes it through.
  @Test func result_lifecycleState_flipsPaused_immediately_onMidPeriodPause() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    let pauseMoment = d(2026, 5, 16, hour: 10)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: pauseMoment)
    pauseEvent.budget = budget; ctx.insert(pauseEvent)
    try ctx.save()

    let oneMinuteAfter = pauseMoment.addingTimeInterval(60)
    let result = BudgetLifecycleService.result(for: budget, now: oneMinuteAfter, calendar: cal, weekStart: .sunday)

    #expect(result.lifecycleState == .paused)
    #expect(result.pausedSince == pauseMoment)
  }

  @Test func result_doesNotMutateBudget() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate, in: ctx)
    let originalLastModified = budget.lastModified

    _ = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(budget.lastModified == originalLastModified)
    #expect(budget.lastResetDate == nil)
  }

  @Test func result_mapsSnapshotToResult() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 14)
    let budget = makeBudget(allocation: 20, startDate: startDate, in: ctx)
    let exp = ExpenseItem(amount: 18, date: d(2026, 4, 14, hour: 10))
    exp.budget = budget; ctx.insert(exp)

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result.remaining == 20) // current period Apr 15, no expenses
    #expect(result.carryOverAmount == 2) // walker: 20 − 18 = 2
    #expect(result.periodStart == d(2026, 4, 15))
    #expect(result.periodEnd == d(2026, 4, 16))
  }

  @Test func result_remainingIsIndependentOfCarryOver() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    // Many prior periods build surplus carry-over; the current period spends 5.
    let currentExpense = ExpenseItem(amount: 5, date: d(2026, 4, 15, hour: 9))
    currentExpense.budget = budget; ctx.insert(currentExpense)

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result.remaining == 15) // 20 − 5, regardless of carry-over
  }

  @Test func result_remainingMayBeNegative() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(allocation: 10, startDate: startDate, in: ctx)
    let exp = ExpenseItem(amount: 15, date: d(2026, 4, 15, hour: 9))
    exp.budget = budget; ctx.insert(exp)

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result.remaining == -5)
  }

  @Test func result_weeklyBudget_periodBoundaries() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 5) // Sunday
    let budget = makeBudget(period: .weekly, allocation: 100, startDate: startDate, in: ctx)
    let now = d(2026, 4, 12, hour: 1) // just after Sun Apr 12

    let result = BudgetLifecycleService.result(for: budget, now: now, calendar: cal, weekStart: .sunday)

    #expect(result.periodStart == d(2026, 4, 12))
    #expect(result.periodEnd == d(2026, 4, 19))
  }
}

// MARK: - applyAllocationEdit write path

struct BudgetLifecycleApplyAllocationEditTests {
  @Test func applyAllocationEdit_insertsNewRowForCurrentPeriod() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    let now = d(2026, 4, 15, hour: 10)
    try BudgetLifecycleService.applyAllocationEdit(budget, newAmount: 30, context: ctx, now: now, calendar: cal, weekStart: .sunday)

    // Original row (Apr 1 = 20) plus a new row (Apr 15 = 30).
    #expect(budget.allocationChanges.count == 2)
    #expect(budget.lastModified == now)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: now, calendar: cal, weekStart: .sunday)
    #expect(snap.effectiveAllocation == 30)
  }

  @Test func applyAllocationEdit_mutatesExistingRowForSamePeriod() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 15)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    let now = d(2026, 4, 15, hour: 10)
    try BudgetLifecycleService.applyAllocationEdit(budget, newAmount: 25, context: ctx, now: now, calendar: cal, weekStart: .sunday)
    let countAfterFirst = budget.allocationChanges.count

    // Second edit in the same period mutates the existing row.
    try BudgetLifecycleService.applyAllocationEdit(budget, newAmount: 35, context: ctx, now: now, calendar: cal, weekStart: .sunday)

    #expect(budget.allocationChanges.count == countAfterFirst)
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: now, calendar: cal, weekStart: .sunday)
    #expect(snap.effectiveAllocation == 35)
  }

  @Test func applyAllocationEdit_priorPeriodsUnaffected() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(allocation: 20, startDate: startDate, in: ctx)
    let exp = ExpenseItem(amount: 5, date: d(2026, 4, 10, hour: 10))
    exp.budget = budget; ctx.insert(exp)
    try ctx.save()

    try BudgetLifecycleService.applyAllocationEdit(budget, newAmount: 30, context: ctx, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [exp], now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)
    // Apr 1–14 still at 20: 9 × 20 + (20 − 5) + 4 × 20 = 275
    #expect(snap.carryOver == 275)
    #expect(snap.effectiveAllocation == 30)
  }

  // MARK: - Specific Dates: latest-wins overwrite

  @Test func applyAllocationEdit_specificDates_overwritesExistingRow() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let start = d(2026, 5, 8)
    let end = d(2026, 5, 25)
    let budget = Budget(period: .specificDates)
    budget.startDate = start
    budget.endDate = end
    let change = AllocationChange(effectiveFrom: start, amount: 1500, lastModified: d(2026, 5, 7))
    change.budget = budget
    ctx.insert(budget); ctx.insert(change)
    try ctx.save()

    let now = d(2026, 5, 15)
    try BudgetLifecycleService.applyAllocationEdit(budget, newAmount: 1800, context: ctx, now: now, calendar: cal, weekStart: .sunday)

    #expect(budget.allocationChanges.count == 1) // no new row inserted
    let only = try #require(budget.allocationChanges.first)
    #expect(only.amount == 1800)
    #expect(only.effectiveFrom == start)
    #expect(only.lastModified == now)
    #expect(budget.lastModified == now)
  }

  @Test func applyAllocationEdit_specificDates_noOpWhenAmountUnchanged() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let start = d(2026, 5, 8)
    let priorLastModified = d(2026, 5, 7)
    let priorBudgetLastModified = d(2026, 5, 7, hour: 1)
    let budget = Budget(period: .specificDates)
    budget.startDate = start
    budget.endDate = d(2026, 5, 25)
    budget.lastModified = priorBudgetLastModified
    let change = AllocationChange(effectiveFrom: start, amount: 1500, lastModified: priorLastModified)
    change.budget = budget
    ctx.insert(budget); ctx.insert(change)
    try ctx.save()

    try BudgetLifecycleService.applyAllocationEdit(
      budget, newAmount: 1500, context: ctx, now: d(2026, 5, 15), calendar: cal, weekStart: .sunday
    )

    #expect(budget.allocationChanges.count == 1)
    let only = try #require(budget.allocationChanges.first)
    #expect(only.amount == 1500)
    #expect(only.lastModified == priorLastModified) // unchanged — no-op
    #expect(budget.lastModified == priorBudgetLastModified) // unchanged
  }
}

// MARK: - resetCarryOver write path

struct BudgetLifecycleResetCarryOverTests {
  @Test func resetCarryOver_setsLastResetDate_bumpsLastModified() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    let now = d(2026, 4, 15, hour: 10)
    try BudgetLifecycleService.resetCarryOver(budget, context: ctx, now: now)

    #expect(budget.lastResetDate == now)
    #expect(budget.lastModified == now)
  }

  @Test func resetCarryOver_walkerDropsToCurrentPeriodOnly() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(allocation: 20, startDate: startDate, in: ctx)
    for day in 1 ... 13 {
      let exp = ExpenseItem(amount: 18, date: d(2026, 4, day, hour: 10))
      exp.budget = budget; ctx.insert(exp)
    }
    try ctx.save()

    try BudgetLifecycleService.resetCarryOver(budget, context: ctx, now: d(2026, 4, 14))

    // On the reset day the walk window starts at Apr 14, the current period → no completed periods.
    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: d(2026, 4, 14), calendar: cal, weekStart: .sunday)
    #expect(snap.carryOver == 0)
  }

  @Test func resetCarryOver_doesNotDeleteExpenses() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    let exp = ExpenseItem(amount: 10, date: d(2026, 4, 1, hour: 10))
    exp.budget = budget; ctx.insert(exp)
    try ctx.save()

    try BudgetLifecycleService.resetCarryOver(budget, context: ctx)

    #expect(budget.expenseItems.count == 1)
  }
}

// MARK: - pauseBudget write path

struct BudgetLifecyclePauseTests {
  @Test func pauseBudget_returnsTrue_insertsEvent_bumpsLastModified() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 4, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    let now = d(2026, 4, 15, hour: 10)
    let result = try BudgetLifecycleService.pauseBudget(budget, context: ctx, now: now, calendar: cal, weekStart: .sunday)

    #expect(result == true)
    #expect(budget.lifecycleEvents.count == 1)
    #expect(budget.lifecycleEvents[0].kind == .pause)
    #expect(budget.lifecycleEvents[0].effectiveDate == now)
    #expect(budget.lastModified == now)
  }

  @Test func pauseBudget_clampsToStartDate_whenNowBeforeStart() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let startDate = d(2026, 5, 1)
    let budget = makeBudget(startDate: startDate, in: ctx)
    try ctx.save()

    let now = d(2026, 4, 10)
    let result = try BudgetLifecycleService.pauseBudget(budget, context: ctx, now: now, calendar: cal, weekStart: .sunday)

    #expect(result == true)
    #expect(budget.lifecycleEvents.count == 1)
    #expect(budget.lifecycleEvents[0].effectiveDate == startDate)
  }

  @Test func pauseBudget_returnsFalse_forSpecificDates() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let b = Budget(period: .specificDates)
    b.startDate = d(2026, 4, 1)
    let change = AllocationChange(effectiveFrom: d(2026, 4, 1), amount: 100)
    change.budget = b; ctx.insert(b); ctx.insert(change)
    try ctx.save()

    let result = try BudgetLifecycleService.pauseBudget(b, context: ctx, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result == false)
    #expect(b.lifecycleEvents.isEmpty)
  }

  @Test func pauseBudget_returnsFalse_whenAlreadyPaused() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(startDate: d(2026, 4, 1), in: ctx)
    let ev = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10))
    ev.budget = budget; ctx.insert(ev)
    try ctx.save()

    let result = try BudgetLifecycleService.pauseBudget(budget, context: ctx, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result == false)
    #expect(budget.lifecycleEvents.count == 1) // no new event inserted
  }

  @Test func pauseBudget_returnsFalse_whenPastEndDate() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(startDate: d(2026, 4, 1), in: ctx)
    budget.endDate = d(2026, 4, 10)
    try ctx.save()

    let result = try BudgetLifecycleService.pauseBudget(budget, context: ctx, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result == false)
    #expect(budget.lifecycleEvents.isEmpty)
  }
}

// MARK: - resumeBudget write path

struct BudgetLifecycleResumeTests {
  @Test func resumeBudget_returnsTrue_insertsEvent_bumpsLastModified() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(startDate: d(2026, 4, 1), in: ctx)
    let ev = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10))
    ev.budget = budget; ctx.insert(ev)
    try ctx.save()

    let now = d(2026, 4, 20, hour: 9)
    let result = try BudgetLifecycleService.resumeBudget(budget, context: ctx, now: now, calendar: cal, weekStart: .sunday)

    #expect(result == true)
    #expect(budget.lifecycleEvents.count == 2)
    let resumeEvent = budget.lifecycleEvents.first { $0.kind == .resume }
    #expect(resumeEvent?.effectiveDate == now)
    #expect(budget.lastModified == now)
  }

  @Test func resumeBudget_returnsFalse_forSpecificDates() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let b = Budget(period: .specificDates)
    b.startDate = d(2026, 4, 1)
    let change = AllocationChange(effectiveFrom: d(2026, 4, 1), amount: 100)
    change.budget = b; ctx.insert(b); ctx.insert(change)
    try ctx.save()

    let result = try BudgetLifecycleService.resumeBudget(b, context: ctx, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result == false)
    #expect(b.lifecycleEvents.isEmpty)
  }

  @Test func resumeBudget_returnsFalse_whenAlreadyActive() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(startDate: d(2026, 4, 1), in: ctx)
    try ctx.save()

    let result = try BudgetLifecycleService.resumeBudget(budget, context: ctx, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result == false)
    #expect(budget.lifecycleEvents.isEmpty)
  }

  @Test func resumeBudget_returnsFalse_whenPastEndDate() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(startDate: d(2026, 4, 1), in: ctx)
    budget.endDate = d(2026, 4, 10)
    // Paused, but past endDate, so the state is still postEnd.
    let ev = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 8))
    ev.budget = budget; ctx.insert(ev)
    try ctx.save()

    let result = try BudgetLifecycleService.resumeBudget(budget, context: ctx, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result == false)
    #expect(budget.lifecycleEvents.count == 1) // no resume event added
  }
}

// MARK: - pausedSince computation in result(for:)

struct BudgetLifecyclePausedSinceTests {
  @Test func result_pausedSince_isNil_whenActive() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(startDate: d(2026, 4, 1), in: ctx)
    try ctx.save()

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result.pausedSince == nil)
    #expect(result.lifecycleState == .active)
  }

  @Test func result_pausedSince_isMostRecentPauseDate_whenPaused() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(startDate: d(2026, 4, 1), in: ctx)
    let pause1 = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 5))
    let resume1 = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 10))
    let pause2 = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15))
    for ev in [pause1, resume1, pause2] {
      ev.budget = budget; ctx.insert(ev)
    }
    try ctx.save()

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 20), calendar: cal, weekStart: .sunday)

    #expect(result.lifecycleState == .paused)
    #expect(result.pausedSince == d(2026, 4, 15))
  }

  /// A future-dated `.resume` after an active `.pause` must not null `pausedSince`;
  /// it has to agree with `isPausedAtMoment(now)`.
  @Test func result_pausedSince_ignoresFutureResume() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(startDate: d(2026, 4, 1), in: ctx)
    let pauseNow = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10))
    let resumeFuture = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 5, 1))
    for ev in [pauseNow, resumeFuture] {
      ev.budget = budget; ctx.insert(ev)
    }
    try ctx.save()

    // `now` is strictly between the pause and the future resume.
    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 20), calendar: cal, weekStart: .sunday)

    #expect(result.lifecycleState == .paused)
    #expect(result.pausedSince == d(2026, 4, 10))
  }

  @Test func result_pausedSince_isNil_whenResumedAfterPause() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(startDate: d(2026, 4, 1), in: ctx)
    let pause1 = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 5))
    let resume1 = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 10))
    for ev in [pause1, resume1] {
      ev.budget = budget; ctx.insert(ev)
    }
    try ctx.save()

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result.lifecycleState == .active)
    #expect(result.pausedSince == nil)
  }

  @Test func result_lifecycleState_isExposed() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let budget = makeBudget(startDate: d(2026, 4, 15), in: ctx)
    try ctx.save()

    let result = BudgetLifecycleService.result(for: budget, now: d(2026, 4, 15), calendar: cal, weekStart: .sunday)

    #expect(result.lifecycleState == .active)
  }
}
