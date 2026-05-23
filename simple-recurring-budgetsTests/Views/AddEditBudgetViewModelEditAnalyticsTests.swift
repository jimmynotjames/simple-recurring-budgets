import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Tests for the F-8.02 per-field change flags emitted on `budget_edited` from
/// `AddEditBudgetViewModel.saveEdit`: `allocation_changed`, `start_date_changed`,
/// `end_date_changed`. The flags are emitted ONLY on `budgetEdited` — not on
/// `budgetCreated` or any other event.
@MainActor
struct AddEditBudgetViewModelEditAnalyticsTests {
  // MARK: - Helpers

  private func makeRecurringBudget(in context: ModelContext) throws -> Budget {
    let cal = Calendar.autoupdatingCurrent
    let start = try #require(cal.date(from: DateComponents(year: 2026, month: 4, day: 13)))
    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .weekly, isCarryOverEnabled: true)
    budget.startDate = start
    let change = AllocationChange(effectiveFrom: start, amount: 7)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    context.insert(budget)
    return budget
  }

  private func makeSpecificDatesBudget(in context: ModelContext) throws -> Budget {
    let cal = Calendar.autoupdatingCurrent
    let start = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let end = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 25)))
    let budget = Budget(name: "Trip", currencyCode: "EUR", period: .specificDates, isCarryOverEnabled: false)
    budget.startDate = start
    budget.endDate = end
    let change = AllocationChange(effectiveFrom: start, amount: 1500)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    context.insert(budget)
    return budget
  }

  private func budgetEditedProperties(_ spy: SpyAnalyticsClient) -> [String: String]? {
    spy.trackCalls.first(where: { $0.event == AnalyticsEvent.budgetEdited })?.properties
  }

  // MARK: - Tests

  @Test func onlyNameEdit_firesBudgetEdited_withAllDateAllocationFlagsFalse() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = try makeRecurringBudget(in: context)

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.name = "Coffee + tea"
    vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    let props = try #require(budgetEditedProperties(spy))
    #expect(props[AnalyticsProperty.allocationChanged] == "false")
    #expect(props[AnalyticsProperty.startDateChanged] == "false")
    #expect(props[AnalyticsProperty.endDateChanged] == "false")
  }

  @Test func recurringStartDateEdit_firesBudgetEdited_withStartFlagTrue() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = try makeRecurringBudget(in: context)

    let vm = AddEditBudgetViewModel(editing: budget)
    let cal = Calendar.autoupdatingCurrent
    let backDated = try #require(cal.date(from: DateComponents(year: 2026, month: 4, day: 6)))
    vm.startDate = backDated
    vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    let props = try #require(budgetEditedProperties(spy))
    #expect(props[AnalyticsProperty.startDateChanged] == "true")
    #expect(props[AnalyticsProperty.endDateChanged] == "false")
    #expect(props[AnalyticsProperty.allocationChanged] == "false")
  }

  @Test func clearingRecurringEndDate_firesBudgetEdited_withEndFlagTrue() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let cal = Calendar.autoupdatingCurrent
    let budget = try makeRecurringBudget(in: context)
    budget.endDate = try #require(cal.date(from: DateComponents(year: 2026, month: 12, day: 31)))
    try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.endDate = nil
    vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    let props = try #require(budgetEditedProperties(spy))
    #expect(props[AnalyticsProperty.endDateChanged] == "true")
    #expect(props[AnalyticsProperty.startDateChanged] == "false")
    #expect(props[AnalyticsProperty.allocationChanged] == "false")
  }

  @Test func specificDatesEndDateEdit_firesBudgetEdited_withEndFlagTrueOnly() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = try makeSpecificDatesBudget(in: context)

    let vm = AddEditBudgetViewModel(editing: budget)
    let cal = Calendar.autoupdatingCurrent
    let newEnd = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 30)))
    vm.endDate = newEnd
    vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    let props = try #require(budgetEditedProperties(spy))
    #expect(props[AnalyticsProperty.endDateChanged] == "true")
    #expect(props[AnalyticsProperty.startDateChanged] == "false")
    #expect(props[AnalyticsProperty.allocationChanged] == "false")
  }

  @Test func allocationEdit_firesBudgetEdited_withAllocationFlagTrue() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = try makeRecurringBudget(in: context)

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.allocation = 10
    vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    let props = try #require(budgetEditedProperties(spy))
    #expect(props[AnalyticsProperty.allocationChanged] == "true")
    #expect(props[AnalyticsProperty.startDateChanged] == "false")
    #expect(props[AnalyticsProperty.endDateChanged] == "false")
  }

  @Test func noOpSave_doesNotFireBudgetEdited() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = try makeRecurringBudget(in: context)

    let vm = AddEditBudgetViewModel(editing: budget)
    // No mutations to drafts.
    vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    #expect(!spy.trackedEvents.contains(AnalyticsEvent.budgetEdited))
  }

  @Test func budgetCreated_doesNotCarryPerFieldFlags() throws {
    // budget_created MUST NOT include the F-8.02 per-field change flags — they're
    // meaningless on creation (everything is "new" by definition).
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Groceries"
    vm.allocation = 100
    vm.period = .weekly
    vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    let createdProps = try #require(
      spy.trackCalls.first(where: { $0.event == AnalyticsEvent.budgetCreated })?.properties
    )
    #expect(createdProps[AnalyticsProperty.allocationChanged] == nil)
    #expect(createdProps[AnalyticsProperty.startDateChanged] == nil)
    #expect(createdProps[AnalyticsProperty.endDateChanged] == nil)
  }
}
