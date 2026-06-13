import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - dateContextCaption pre-start / post-end branches (F-2.04) + date seeding

/// Tests for the `dateContextCaption` priority-ordered resolution in
/// `AddEditExpenseViewModel`: paused branches (existing, exercised by
/// `AddEditExpensePausedCaptionTests`) + the new F-2.04 Add-mode pre-start /
/// post-end branches plus the post-end date seed clamp.
///
/// Paused-state precedence is asserted defensively here even though
/// `BudgetSnapshot.lifecycleState` cannot report `.paused` simultaneously with
/// `.preStart` or `.postEnd` in practice — the priority ordering should hold
/// against any future overlapping-state change.
@MainActor
struct AddEditExpenseDateContextCaptionTests {
  // MARK: - Add-mode pre-start branch (task 4.1)

  @Test func addMode_preStartBudget_showsPreStartCaption() throws {
    let budget = DebugData.dailyPreStart()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    let caption = vm.dateContextCaption
    let formatted = try #require(budget.startDate?.formatted(date: .abbreviated, time: .omitted))
    let expected = String(
      localized: "addEditExpense.preStart.caption.format",
      defaultValue: "Budget starts on \(formatted).",
      comment: "Inline caption below the When card in Add Expense when the bound budget is pre-start (now < startDate); argument is the abbreviated start date. Explains why the date picker default isn't today."
    )
    #expect(caption == expected)
  }

  // MARK: - Add-mode post-end branch (task 4.1)

  @Test func addMode_postEndBudget_showsPostEndCaption() throws {
    let budget = DebugData.weeklyPostEnd()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    let caption = vm.dateContextCaption
    let formatted = try #require(budget.endDate?.formatted(date: .abbreviated, time: .omitted))
    let expected = String(
      localized: "addEditExpense.postEnd.caption.format",
      defaultValue: "Budget ended on \(formatted).",
      comment: "Inline caption below the When card in Add Expense when the bound budget is post-end (now > endDate); argument is the abbreviated end date. Explains why the date picker default isn't today."
    )
    #expect(caption == expected)
  }

  // MARK: - Active state — no caption (task 4.1)

  @Test func addMode_activeBudget_returnsNil() {
    // dailyDefault is an active budget — the caption should be nil.
    let budget = DebugData.dailyDefault()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(vm.dateContextCaption == nil)
  }

  // MARK: - Edit mode suppresses pre-start / post-end captions (task 4.1)

  @Test func editMode_preStartBudget_suppressesPreStartCaption() throws {
    // F-2.04 says the pre-start caption is Add-mode-only. An existing ExpenseItem
    // already carries its stored date, so the clamped-default rationale doesn't
    // apply.
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = DebugData.dailyPreStart()
    context.insert(budget)
    // Attach an expense dated INSIDE the future startDate window so Edit-mode
    // construction is well-formed.
    let startDate = try #require(budget.startDate)
    let expense = ExpenseItem(amount: 5, name: nil, date: startDate)
    expense.budget = budget
    context.insert(expense)

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    #expect(vm.dateContextCaption == nil)
  }

  @Test func editMode_postEndBudget_suppressesPostEndCaption() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = DebugData.weeklyPostEnd()
    context.insert(budget)
    let cal = Calendar.autoupdatingCurrent
    let inWindow = try #require(cal.date(byAdding: .day, value: -30, to: Date()))
    let expense = ExpenseItem(amount: 5, name: nil, date: inWindow)
    expense.budget = budget
    context.insert(expense)

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    #expect(vm.dateContextCaption == nil)
  }

  // MARK: - Post-end date seed clamps to endDate end-of-day (task 4.2)

  @Test func addMode_postEndBudget_dateSeededToEndOfEndDateDay() throws {
    let budget = DebugData.weeklyPostEnd()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    // The picker upper bound is the last moment of endDate's day; the seed
    // must land at the same moment so the picker opens inside dateRange.
    let cal = Calendar.autoupdatingCurrent
    let endDate = try #require(budget.endDate)
    let nextDayStart = try #require(cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endDate)))
    let expectedSeed = nextDayStart.addingTimeInterval(-1)
    #expect(vm.date == expectedSeed)
    // Sanity check: the seeded date lies inside the picker's allowed range.
    #expect(vm.dateRange.contains(vm.date))
  }

  // MARK: - Pre-start date seed lands at effectiveStartDate (task 4.3)

  @Test func addMode_preStartBudget_dateSeededToEffectiveStartDate() {
    let budget = DebugData.dailyPreStart()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    // For pre-start, `max(Date(), effectiveStartDate)` collapses to
    // effectiveStartDate because `Date()` < startDate.
    #expect(vm.date == budget.effectiveStartDate)
    #expect(vm.dateRange.contains(vm.date))
  }

  // MARK: - Defensive: pre-start budget with nil Budget.startDate returns nil caption

  @Test func addMode_preStartBudget_withNilStartDate_returnsNilCaption() throws {
    // Defensive scenario: a CloudKit-synced budget where the `startDate` field
    // hasn't arrived yet. `Budget.effectiveStartDate` falls back to `createdAt`,
    // so `lifecycleState == .preStart` is reachable while `Budget.startDate`
    // is still `nil`. The pre-start caption should be omitted (there is no
    // startDate value to surface), NOT crash. `cachedStartDateFormatted`
    // captures `budget.startDate?.formatted(...)` which is `nil` in this case,
    // and `dateContextCaption`'s `.preStart` branch guards on it.
    let budget = Budget(name: "Future", currencyCode: "USD", period: .daily, isCarryOverEnabled: true)
    budget.startDate = nil
    // createdAt 30 days in the future → effectiveStartDate is in the future
    // → lifecycleState is .preStart, but budget.startDate stays nil.
    let cal = Calendar.autoupdatingCurrent
    let futureCreatedAt = try #require(cal.date(byAdding: .day, value: 30, to: Date()))
    budget.createdAt = futureCreatedAt
    let change = AllocationChange(effectiveFrom: futureCreatedAt, amount: 10)
    change.budget = budget
    budget.allocationChangesStorage = [change]

    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(vm.dateContextCaption == nil)
  }
}
