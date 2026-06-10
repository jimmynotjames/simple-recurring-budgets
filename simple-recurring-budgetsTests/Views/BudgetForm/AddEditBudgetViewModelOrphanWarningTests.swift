import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Tests for the orphan-expense warning on Edit Budget Save: the
/// `AddEditBudgetViewModel.orphanedExpenseCount` computed property and the
/// `orphaned_expense_count` property emitted on `budget_edited`.
@MainActor
struct AddEditBudgetViewModelOrphanWarningTests {
  // MARK: - Helpers

  private func makeRecurringBudgetWithExpenses(
    in context: ModelContext,
    startDate: Date,
    expenseDates: [Date]
  ) throws -> Budget {
    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .weekly, isCarryOverEnabled: true)
    budget.startDate = startDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 50)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    context.insert(budget)
    for date in expenseDates {
      let expense = ExpenseItem(amount: 5, date: date)
      expense.budget = budget
      context.insert(expense)
    }
    return budget
  }

  private func makeSpecificDatesBudgetWithExpenses(
    in context: ModelContext,
    startDate: Date,
    endDate: Date,
    expenseDates: [Date]
  ) throws -> Budget {
    let budget = Budget(name: "Trip", currencyCode: "EUR", period: .specificDates, isCarryOverEnabled: false)
    budget.startDate = startDate
    budget.endDate = endDate
    let change = AllocationChange(effectiveFrom: startDate, amount: 1500)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    context.insert(budget)
    for date in expenseDates {
      let expense = ExpenseItem(amount: 5, date: date)
      expense.budget = budget
      context.insert(expense)
    }
    return budget
  }

  private func budgetEditedProperties(_ spy: SpyAnalyticsClient) -> [String: String]? {
    spy.trackCalls.first(where: { $0.event == AnalyticsEvent.budgetEdited })?.properties
  }

  private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
    let cal = Calendar.autoupdatingCurrent
    return try #require(cal.date(from: DateComponents(year: year, month: month, day: day)))
  }

  // MARK: - orphanedExpenseCount

  @Test func addMode_orphanedExpenseCount_isZero() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    #expect(vm.orphanedExpenseCount == 0)
  }

  @Test func editMode_noExpenses_orphanedExpenseCountIsZero() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = try makeRecurringBudgetWithExpenses(
      in: context,
      startDate: date(2026, 4, 1),
      expenseDates: []
    )
    let vm = AddEditBudgetViewModel(editing: budget)
    vm.startDate = try date(2026, 5, 1)
    #expect(vm.orphanedExpenseCount == 0)
  }

  @Test func editMode_allExpensesAtOrAfterStartDate_orphanedExpenseCountIsZero() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = try makeRecurringBudgetWithExpenses(
      in: context,
      startDate: date(2026, 4, 1),
      expenseDates: [date(2026, 4, 1), date(2026, 4, 15), date(2026, 5, 1)]
    )
    let vm = AddEditBudgetViewModel(editing: budget)
    // Drafted startDate equal to the earliest expense date — boundary equality
    // case; filter is `$0.date < startDate` (strict), so equal is NOT orphaned.
    vm.startDate = try date(2026, 4, 1)
    #expect(vm.orphanedExpenseCount == 0)
  }

  @Test func editMode_expensesBeforeStartDate_orphanedExpenseCountReflectsCount() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = try makeRecurringBudgetWithExpenses(
      in: context,
      startDate: date(2026, 4, 1),
      expenseDates: [
        date(2026, 3, 20), // before
        date(2026, 3, 25), // before
        date(2026, 4, 1), // on the boundary, not orphaned
        date(2026, 4, 15), // after
      ]
    )
    let vm = AddEditBudgetViewModel(editing: budget)
    vm.startDate = try date(2026, 4, 1)
    #expect(vm.orphanedExpenseCount == 2)
  }

  @Test func editMode_orphanedExpenseCountRecomputesOnStartDateChange() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = try makeRecurringBudgetWithExpenses(
      in: context,
      startDate: date(2026, 4, 1),
      expenseDates: [date(2026, 3, 20), date(2026, 3, 25), date(2026, 4, 10)]
    )
    let vm = AddEditBudgetViewModel(editing: budget)
    vm.startDate = try date(2026, 4, 1)
    #expect(vm.orphanedExpenseCount == 2)
    vm.startDate = try date(2026, 3, 19)
    #expect(vm.orphanedExpenseCount == 0)
    vm.startDate = try date(2026, 5, 1)
    #expect(vm.orphanedExpenseCount == 3)
  }

  // MARK: - orphaned_expense_count on budget_edited

  @Test func confirmedOrphanSave_emitsOrphanedExpenseCount() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = try makeRecurringBudgetWithExpenses(
      in: context,
      startDate: date(2026, 4, 1),
      expenseDates: [date(2026, 3, 20), date(2026, 3, 25), date(2026, 4, 15)]
    )

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.startDate = try date(2026, 4, 10) // moves past the two March expenses
    try vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    let props = try #require(budgetEditedProperties(spy))
    #expect(props[AnalyticsProperty.startDateChanged] == "true")
    #expect(props[AnalyticsProperty.orphanedExpenseCount] == "2")
  }

  @Test func nonOrphanSave_omitsOrphanedExpenseCount() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = try makeRecurringBudgetWithExpenses(
      in: context,
      startDate: date(2026, 4, 1),
      expenseDates: [date(2026, 4, 10)]
    )

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.name = "Coffee + tea"
    try vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    let props = try #require(budgetEditedProperties(spy))
    #expect(props[AnalyticsProperty.orphanedExpenseCount] == nil)
  }

  @Test func addModeSave_omitsOrphanedExpenseCount() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "New"
    vm.allocation = 10
    try vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    let createdCall = spy.trackCalls.first(where: { $0.event == AnalyticsEvent.budgetCreated })
    let props = try #require(createdCall?.properties)
    #expect(props[AnalyticsProperty.orphanedExpenseCount] == nil)
  }

  // MARK: - Period-type uniformity

  /// The orphan-warning behavior is intentionally uniform across every period type:
  /// the condition (`expenseItems.date < startDate`) is well-defined regardless of
  /// recurrence, and the user-facing consequence (orphaned expenses stay in the list
  /// but don't affect totals) is the same. Specific Dates therefore participates in
  /// the same `orphanedExpenseCount` + `orphaned_expense_count` emission path as
  /// recurring budgets. (The inline Schedule-disclosure warning is recurring-only
  /// by structural necessity — Specific Dates uses the Dates card — but that's a
  /// view-layer concern not visible from the viewModel.)
  @Test func specificDatesEditMode_orphanedExpenseCountAndAnalyticsBehaveLikeRecurring() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let spy = SpyAnalyticsClient()
    let budget = try makeSpecificDatesBudgetWithExpenses(
      in: context,
      startDate: date(2026, 5, 8),
      endDate: date(2026, 5, 25),
      expenseDates: [date(2026, 5, 8), date(2026, 5, 10), date(2026, 5, 12)]
    )

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.startDate = try date(2026, 5, 11) // orphans the May 8 and May 10 expenses
    #expect(vm.orphanedExpenseCount == 2)

    try vm.save(context: context, analytics: spy, settings: AppSettings(), router: Router())

    let props = try #require(budgetEditedProperties(spy))
    #expect(props[AnalyticsProperty.startDateChanged] == "true")
    #expect(props[AnalyticsProperty.orphanedExpenseCount] == "2")
  }
}
