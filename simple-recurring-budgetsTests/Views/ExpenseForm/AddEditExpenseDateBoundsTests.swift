import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Date bounds for paused budgets (F-7.06)

private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
  var comps = DateComponents()
  comps.year = year; comps.month = month; comps.day = day; comps.hour = hour
  comps.timeZone = TimeZone(identifier: "UTC")
  return Calendar(identifier: .gregorian).date(from: comps)!
}

@MainActor
struct AddEditExpenseDateBoundsTests {
  // MARK: - Specific Dates window bounds (F-2.08 / F-2.04)

  @Test func dateRange_clampedByEndDate_forSpecificDates() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let startDate = utcDate(2026, 5, 8)
    let endDate = utcDate(2026, 5, 25)
    let budget = Budget(name: "Italy Trip", currencyCode: "EUR", period: .specificDates, isCarryOverEnabled: false)
    budget.startDate = startDate
    budget.endDate = endDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 1500)
    change.budget = budget
    context.insert(budget); context.insert(change)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    #expect(vm.dateRange.lowerBound == startDate)
    // Per Budget.endDate convention (inclusive day), the upper bound is the last
    // moment of endDate's day — not startOfDay(endDate). Clamping at start-of-day
    // would reject all times after 00:00 on endDate.
    #expect(vm.dateRange.upperBound > endDate)
    #expect(vm.dateRange.upperBound < utcDate(2026, 5, 26))
    // A date inside the window passes.
    vm.amount = 50
    vm.date = utcDate(2026, 5, 15)
    #expect(vm.canSave)
    // A date at midnight on endDate is admitted.
    vm.date = endDate
    #expect(vm.canSave)
    // A mid-day expense on endDate is admitted (this would have failed before the
    // inclusive-day fix because upperBound was startOfDay(endDate) = midnight).
    vm.date = utcDate(2026, 5, 25, hour: 14)
    #expect(vm.canSave)
    // The last hour of endDate is still admitted.
    vm.date = utcDate(2026, 5, 25, hour: 23)
    #expect(vm.canSave)
  }

  @Test func dateRange_isUnbounded_forActiveDaily() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let startDate = utcDate(2026, 4, 1)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    budget.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 20)
    change.budget = budget
    context.insert(budget); context.insert(change)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    #expect(vm.dateRange.upperBound > utcDate(2100, 1, 1))
    // Active budget never surfaces a paused caption (proactive or violation).
    #expect(vm.dateContextCaption == nil)
  }

  @Test func canSave_isFalse_whenDateInPausedGap() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let startDate = utcDate(2026, 4, 1)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    budget.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 20)
    change.budget = budget
    // Pause Apr 10, resume Apr 15, pause Apr 20 — budget is currently paused
    let pause1 = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 10))
    let resume1 = LifecycleEvent(kind: .resume, effectiveDate: utcDate(2026, 4, 15))
    let pause2 = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 20))
    pause1.budget = budget; resume1.budget = budget; pause2.budget = budget
    context.insert(budget); context.insert(change)
    context.insert(pause1); context.insert(resume1); context.insert(pause2)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    vm.amount = 5
    vm.date = utcDate(2026, 4, 12, hour: 10) // In the paused gap between pause1 and resume1
    // Behavioral invariant: Save is blocked. Caption-text assertions live in
    // AddEditExpensePausedCaptionTests.
    #expect(vm.canSave == false)
  }

  @Test func canSave_isTrue_whenDateInActivePeriod_andBudgetPaused() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let startDate = utcDate(2026, 4, 1)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    budget.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 20)
    change.budget = budget
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 15))
    pauseEvent.budget = budget
    context.insert(budget); context.insert(change); context.insert(pauseEvent)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    vm.amount = 5
    vm.date = utcDate(2026, 4, 5, hour: 10) // In active period before pause
    #expect(vm.canSave == true)
  }

  @Test func dateRange_upperBound_isPauseEventDate_whenPaused() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let startDate = utcDate(2026, 4, 1)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    budget.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 20)
    change.budget = budget
    let pauseDate = utcDate(2026, 4, 10, hour: 14)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: pauseDate)
    pauseEvent.budget = budget
    context.insert(budget); context.insert(change); context.insert(pauseEvent)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    #expect(vm.dateRange.upperBound == pauseDate)
    #expect(vm.dateRange.lowerBound == startDate)
  }

  @Test func addMode_seedsDateToPauseEventDate_whenPaused() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let startDate = utcDate(2026, 4, 1)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    budget.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 20)
    change.budget = budget
    let pauseDate = utcDate(2026, 4, 10, hour: 14)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: pauseDate)
    pauseEvent.budget = budget
    context.insert(budget); context.insert(change); context.insert(pauseEvent)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    // Seed should land on the pause event date (the precise upper bound of the active
    // union under moment-granular UI), not Date() (which would be in a paused gap).
    #expect(vm.date == pauseDate)
    vm.amount = 5
    #expect(vm.canSave == true)
  }
}
