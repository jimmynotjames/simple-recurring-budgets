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
    #expect(vm.pausedCaption == nil)
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
