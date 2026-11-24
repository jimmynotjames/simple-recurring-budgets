import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Regression guard: the §10.2/§10.3 super/people-property refreshes must go through the
/// `AnalyticsClient` protocol, not an `as? MixpanelAnalyticsClient` downcast (which silently no-ops
/// under `SpyAnalyticsClient`, hiding regressions).
@MainActor
struct AddEditBudgetViewModelCohortRefreshTests {
  /// Creates a budget through the Add-mode VM with a plain (console) save,
  /// returning the persisted model for Edit/Delete-mode tests.
  private func makeSavedBudget(in context: ModelContext) throws -> Budget {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Transit"
    vm.allocation = 80
    vm.currencyCode = "CAD"
    vm.period = .weekly
    try vm.save(context: context)
    return try #require(try context.fetch(FetchDescriptor<Budget>()).first)
  }

  @Test func addModeSave_refreshesSuperAndCohortProperties() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Transit"
    vm.allocation = 80
    vm.currencyCode = "CAD"
    vm.period = .weekly
    try vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    #expect(spy.refreshSuperPropertiesCallCount == 1)
    #expect(spy.cohortRefreshCalls.count == 1)
    let cohort = try #require(spy.cohortRefreshCalls.first)
    #expect(cohort.count == 1)
    #expect(cohort.first?.currencyCode == "CAD")
    #expect(cohort.first?.periodRawValue == BudgetPeriod.weekly.rawValue)
  }

  @Test func editSave_refreshesCohortProperties() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = try makeSavedBudget(in: context)

    let spy = SpyAnalyticsClient()
    let vm = AddEditBudgetViewModel(editing: budget)
    vm.name = "Transit pass"
    try vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    #expect(spy.cohortRefreshCalls.count == 1)
    #expect(spy.cohortRefreshCalls.first?.first?.periodRawValue == BudgetPeriod.weekly.rawValue)
  }

  @Test func noOpEditSave_doesNotRefreshCohortProperties() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = try makeSavedBudget(in: context)

    let spy = SpyAnalyticsClient()
    let vm = AddEditBudgetViewModel(editing: budget)
    try vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    #expect(spy.cohortRefreshCalls.isEmpty)
    #expect(spy.refreshSuperPropertiesCallCount == 0)
  }

  @Test func delete_refreshesCohortProperties() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = try makeSavedBudget(in: context)

    let spy = SpyAnalyticsClient()
    let vm = AddEditBudgetViewModel(editing: budget)
    try vm.delete(context: context, analytics: spy)

    #expect(spy.cohortRefreshCalls.count == 1)
    // Deleted budget was the only one → cohort snapshot is empty.
    #expect(spy.cohortRefreshCalls.first?.isEmpty == true)
  }
}
