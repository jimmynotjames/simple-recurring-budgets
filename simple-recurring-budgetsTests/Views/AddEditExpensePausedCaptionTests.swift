import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Proactive paused caption in Add/Edit Expense (F-7.06 moment-granular UI)

private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
  var comps = DateComponents()
  comps.year = year; comps.month = month; comps.day = day; comps.hour = hour
  comps.timeZone = TimeZone(identifier: "UTC")
  return Calendar(identifier: .gregorian).date(from: comps)!
}

private func violationCopy() -> String {
  String(
    localized: "addEditExpense.date.outOfRange.caption",
    defaultValue: "Pick a date within an active period of this budget.",
    comment: "Inline caption below the date picker when the selected date falls inside a paused period"
  )
}

@MainActor
struct AddEditExpensePausedCaptionTests {
  @Test func sheetOpen_showsProactiveCaption_whenBudgetIsPaused() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let startDate = utcDate(2026, 4, 1)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    budget.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 20)
    change.budget = budget
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 10, hour: 14))
    pauseEvent.budget = budget
    context.insert(budget); context.insert(change); context.insert(pauseEvent)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    let caption = vm.pausedCaption
    #expect(caption != nil)
    #expect(caption != violationCopy()) // Sheet opens on a valid date → proactive, not violation.
    #expect(caption?.contains("You can still add expenses") == true)
  }

  @Test func editingDateWithinValidRange_keepsProactiveCaption() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let startDate = utcDate(2026, 4, 1)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    budget.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 20)
    change.budget = budget
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 10, hour: 14))
    pauseEvent.budget = budget
    context.insert(budget); context.insert(change); context.insert(pauseEvent)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    vm.date = utcDate(2026, 4, 5, hour: 9) // Earlier valid date inside the active interval.
    let caption = vm.pausedCaption
    #expect(caption != nil)
    #expect(caption != violationCopy())
  }

  @Test func datePickedInPausedGap_swapsToViolationCaption_andDisablesSave() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let startDate = utcDate(2026, 4, 1)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    budget.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 20)
    change.budget = budget
    // Pause Apr 10, resume Apr 15, pause Apr 20 — currently paused.
    let pause1 = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 10))
    let resume1 = LifecycleEvent(kind: .resume, effectiveDate: utcDate(2026, 4, 15))
    let pause2 = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 20))
    pause1.budget = budget; resume1.budget = budget; pause2.budget = budget
    context.insert(budget); context.insert(change)
    context.insert(pause1); context.insert(resume1); context.insert(pause2)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    vm.amount = 5
    vm.date = utcDate(2026, 4, 12, hour: 10) // Inside the paused gap [Apr 10, Apr 15).
    #expect(vm.pausedCaption == violationCopy())
    #expect(vm.canSave == false)
  }

  @Test func revertingToValidDate_restoresProactiveCaption_andReEnablesSave() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let startDate = utcDate(2026, 4, 1)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    budget.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 20)
    change.budget = budget
    let pause1 = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 10))
    let resume1 = LifecycleEvent(kind: .resume, effectiveDate: utcDate(2026, 4, 15))
    let pause2 = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 20))
    pause1.budget = budget; resume1.budget = budget; pause2.budget = budget
    context.insert(budget); context.insert(change)
    context.insert(pause1); context.insert(resume1); context.insert(pause2)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget)
    vm.amount = 5
    vm.date = utcDate(2026, 4, 12, hour: 10) // Paused gap
    #expect(vm.pausedCaption == violationCopy())
    #expect(vm.canSave == false)
    // User reverts to a valid date inside the second active interval (Apr 15 – Apr 20).
    vm.date = utcDate(2026, 4, 17, hour: 10)
    #expect(vm.pausedCaption != nil)
    #expect(vm.pausedCaption != violationCopy()) // Now proactive again.
    #expect(vm.canSave == true)
  }

  @Test func activeBudget_doesNotShowProactiveCaption() throws {
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
    #expect(vm.pausedCaption == nil)
  }

  @Test func editMode_onPausedBudget_showsProactiveCaption() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let startDate = utcDate(2026, 4, 1)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    budget.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 20)
    change.budget = budget
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 10, hour: 14))
    pauseEvent.budget = budget
    // Existing expense dated inside a prior active period.
    let existing = ExpenseItem(amount: 5, name: "Coffee", date: utcDate(2026, 4, 5, hour: 9))
    existing.budget = budget
    context.insert(budget); context.insert(change); context.insert(pauseEvent); context.insert(existing)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: existing)
    let caption = vm.pausedCaption
    #expect(caption != nil)
    #expect(caption != violationCopy())
    #expect(vm.canSave == true)
  }
}
