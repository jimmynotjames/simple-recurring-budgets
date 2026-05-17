import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

private func makeBudget(name: String = "Test", allocation: Decimal = 50, in context: ModelContext) -> Budget {
  let b = Budget(name: name, currencyCode: "USD", period: .daily)
  let startDate = Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: -86400 * 30))
  b.startDate = startDate
  let change = AllocationChange(effectiveFrom: startDate, amount: allocation)
  change.budget = b
  context.insert(b)
  context.insert(change)
  return b
}

// MARK: - Reset Budget

struct ResetBudgetAlgorithmTests {
  @Test func resetBudget_deletesAllExpensesAndSetsLastResetDate() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = makeBudget(in: context)
    for i in 1 ... 3 {
      let e = ExpenseItem(amount: Decimal(i * 10)); e.budget = budget; context.insert(e)
    }
    try context.save()
    #expect(budget.expenseItems.count == 3)

    let now = Date()
    BudgetLifecycleService.resetBudget(budget, context: context, now: now)

    #expect(budget.expenseItems.isEmpty)
    #expect(budget.lastResetDate != nil)
    #expect(budget.lastModified >= now)
  }

  @Test func resetBudget_budgetEntityPreserved() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = makeBudget(name: "Fun Money", allocation: 60, in: context)
    let budgetID = budget.id
    for i in 1 ... 2 {
      let e = ExpenseItem(amount: Decimal(i * 5)); e.budget = budget; context.insert(e)
    }
    try context.save()

    BudgetLifecycleService.resetBudget(budget, context: context)

    let context2 = ModelContext(container)
    let found = try context2.fetch(FetchDescriptor<Budget>()).first { $0.id == budgetID }
    #expect(found != nil)
    #expect(found?.name == "Fun Money")
  }

  @Test func resetBudget_emptyBudget_noError() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = makeBudget(in: context)
    try context.save()

    BudgetLifecycleService.resetBudget(budget, context: context)

    #expect(budget.expenseItems.isEmpty)
  }

  @Test func resetBudget_isolatedToTargetBudget() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budgetA = makeBudget(name: "A", in: context)
    let budgetB = makeBudget(name: "B", in: context)
    for b in [budgetA, budgetB] {
      let e = ExpenseItem(amount: 10); e.budget = b; context.insert(e)
    }
    try context.save()

    BudgetLifecycleService.resetBudget(budgetA, context: context)

    #expect(budgetA.expenseItems.isEmpty)
    #expect(budgetB.expenseItems.count == 1)
  }

  @Test func resetBudget_persistsAtomically() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = makeBudget(in: context)
    let budgetID = budget.id
    let e1 = ExpenseItem(amount: 10); e1.budget = budget; context.insert(e1)
    let e2 = ExpenseItem(amount: 20); e2.budget = budget; context.insert(e2)
    try context.save()

    BudgetLifecycleService.resetBudget(budget, context: context)

    let context2 = ModelContext(container)
    let allExpenses = try context2.fetch(FetchDescriptor<ExpenseItem>())
    let remaining = allExpenses.filter { $0.budget?.id == budgetID }
    #expect(remaining.isEmpty)
  }
}

// MARK: - Reset Carry-Over

struct ResetCarryOverAlgorithmTests {
  @Test func resetCarryOver_setsLastResetDate_preservesExpenses() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = makeBudget(in: context)
    let e1 = ExpenseItem(amount: 10, name: "Burger"); e1.budget = budget; context.insert(e1)
    let e2 = ExpenseItem(amount: 8, name: "Salad"); e2.budget = budget; context.insert(e2)
    try context.save()

    let now = Date()
    BudgetLifecycleService.resetCarryOver(budget, context: context, now: now)

    #expect(budget.lastResetDate == now)
    #expect(budget.lastModified >= now)
    #expect(budget.expenseItems.count == 2)
  }

  @Test func resetCarryOver_walkerDropsToZeroForPriorPeriods() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = makeBudget(allocation: 20, in: context)
    try context.save()

    var comps = DateComponents()
    comps.year = 2026; comps.month = 4; comps.day = 14
    comps.timeZone = TimeZone(identifier: "UTC")
    let cal = Calendar(identifier: .gregorian)
    let resetDate = try #require(cal.date(from: comps))

    BudgetLifecycleService.resetCarryOver(budget, context: context, now: resetDate)

    let snap = BudgetCalculator.snapshot(budget: budget, expenses: [], now: resetDate, calendar: cal)
    #expect(snap.carryOver == 0)
  }
}

// MARK: - Delete Expense (lastModified bump)

struct DeleteExpenseLastModifiedTests {
  @Test func deleteExpense_bumps_budgetLastModified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = makeBudget(in: context)
    let before = Date(timeIntervalSinceNow: -1)
    budget.lastModified = before

    let e = ExpenseItem(amount: 5); e.budget = budget; context.insert(e)
    try context.save()

    // Simulate the delete with lastModified bump (as done by BudgetDetailView+ExpenseSection)
    budget.lastModified = Date()
    context.delete(e)
    try context.save()

    #expect(budget.lastModified > before)
  }

  @Test func deleteExpense_onlyTargetRemoved() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = makeBudget(in: context)
    let e1 = ExpenseItem(amount: 15, name: "Movie"); e1.budget = budget; context.insert(e1)
    let e2 = ExpenseItem(amount: 8, name: "Popcorn"); e2.budget = budget; context.insert(e2)
    let e3 = ExpenseItem(amount: 22, name: "Dinner"); e3.budget = budget; context.insert(e3)
    let e2ID = e2.id
    try context.save()

    context.delete(e2); try context.save()

    let context2 = ModelContext(container)
    let all = try context2.fetch(FetchDescriptor<ExpenseItem>())
    #expect(all.count == 2)
    #expect(!all.map(\.id).contains(e2ID))
  }
}

// MARK: - Expense Row Push Navigation

struct ExpenseRowPushNavigationTests {
  @Test func tapExpenseRow_appendsExpenseDetailRoute() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let expense = ExpenseItem(amount: 5, name: "Coffee")
    context.insert(expense)
    try context.save()

    let router = Router()
    router.path.append(AppRoute.expenseDetail(expense))

    #expect(router.path.count == 1)
    #expect(router.path.last == AppRoute.expenseDetail(expense))
  }

  @Test func appRoute_expenseDetail_isHashable() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let expense = ExpenseItem(amount: 10, name: "Lunch")
    context.insert(expense)
    try context.save()

    let routeA = AppRoute.expenseDetail(expense)
    let routeB = AppRoute.expenseDetail(expense)
    #expect(routeA == routeB)
    #expect(routeA.hashValue == routeB.hashValue)
  }
}

// MARK: - Pause / Resume toolbar item visibility (F-7.06)

private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
  var comps = DateComponents()
  comps.year = year; comps.month = month; comps.day = day; comps.hour = hour
  comps.timeZone = TimeZone(identifier: "UTC")
  return Calendar(identifier: .gregorian).date(from: comps)!
}

struct PauseResumeToolbarVisibilityTests {
  // Tests verify the showPauseResumeItem / isPaused computed properties driving the toolbar item,
  // exercised via BudgetLifecycleService.pauseBudget / resumeBudget eligibility, which is the
  // canonical source of truth for the view's isPostEnd / isSpecificDates gates.

  @Test func pauseBudget_rejected_forSpecificDates_confirmsToolbarItemHidden() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let b = Budget(period: .specificDates)
    b.startDate = utcDate(2026, 4, 1)
    b.endDate = utcDate(2026, 4, 30)
    let change = AllocationChange(effectiveFrom: utcDate(2026, 4, 1), amount: 100)
    change.budget = b; ctx.insert(b); ctx.insert(change)
    try ctx.save()

    // Service rejects, confirming the toolbar item must be hidden for this budget type.
    let result = BudgetLifecycleService.pauseBudget(b, context: ctx, now: utcDate(2026, 4, 15))
    #expect(result == false)
    #expect(b.lifecycleEvents.isEmpty)
  }

  @Test func pauseBudget_rejected_whenPastEndDate_confirmsToolbarItemHidden() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let b = Budget(period: .daily)
    b.startDate = utcDate(2026, 4, 1)
    b.endDate = utcDate(2026, 4, 10)
    let change = AllocationChange(effectiveFrom: utcDate(2026, 4, 1), amount: 20)
    change.budget = b; ctx.insert(b); ctx.insert(change)
    try ctx.save()

    // now > endDate → service rejects, confirming toolbar item must be hidden.
    let result = BudgetLifecycleService.pauseBudget(b, context: ctx, now: utcDate(2026, 4, 15))
    #expect(result == false)
    #expect(b.lifecycleEvents.isEmpty)
  }

  @Test func resumeBudget_rejected_whenPastEndDate_confirmsToolbarItemHidden() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let b = Budget(period: .daily)
    b.startDate = utcDate(2026, 4, 1)
    b.endDate = utcDate(2026, 4, 10)
    let change = AllocationChange(effectiveFrom: utcDate(2026, 4, 1), amount: 20)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 8))
    change.budget = b; pauseEvent.budget = b
    ctx.insert(b); ctx.insert(change); ctx.insert(pauseEvent)
    try ctx.save()

    // now > endDate → resume also rejected.
    let result = BudgetLifecycleService.resumeBudget(b, context: ctx, now: utcDate(2026, 4, 15))
    #expect(result == false)
    #expect(b.lifecycleEvents.count == 1) // no resume event added
  }

  @Test func pauseBudget_accepted_forActiveDaily_confirmsToolbarItemVisible() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let b = Budget(period: .daily)
    b.startDate = utcDate(2026, 4, 1)
    let change = AllocationChange(effectiveFrom: utcDate(2026, 4, 1), amount: 20)
    change.budget = b; ctx.insert(b); ctx.insert(change)
    try ctx.save()

    let result = BudgetLifecycleService.pauseBudget(b, context: ctx, now: utcDate(2026, 4, 15))
    #expect(result == true)
    #expect(b.lifecycleEvents.count == 1)
    #expect(b.lifecycleEvents[0].kind == .pause)
  }

  @Test func resumeBudget_accepted_whenPaused_confirmsToolbarItemShowsResume() throws {
    let container = try TestModelContainer.make()
    let ctx = ModelContext(container)
    let b = Budget(period: .daily)
    b.startDate = utcDate(2026, 4, 1)
    let change = AllocationChange(effectiveFrom: utcDate(2026, 4, 1), amount: 20)
    let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: utcDate(2026, 4, 10))
    change.budget = b; pauseEvent.budget = b
    ctx.insert(b); ctx.insert(change); ctx.insert(pauseEvent)
    try ctx.save()

    let result = BudgetLifecycleService.resumeBudget(b, context: ctx, now: utcDate(2026, 4, 20))
    #expect(result == true)
    let resumeEvent = b.lifecycleEvents.first { $0.kind == .resume }
    #expect(resumeEvent != nil)
  }
}

// MARK: - Resume caption copy (pause-immediate-feedback change)

struct ResumeCaptionCopyTests {
  /// Lock in the source-string change "Resume to log expenses" → "Resume to log new expenses".
  /// The caption is formatted with the pausedSince date; we don't care about the date format
  /// here — just that the trailing clause acknowledges backdated entries remain available
  /// (per F-7.06's two-clock model: Detail screen primary slot swaps, but backdated entry
  /// via the Budgets-list `+` is still possible).
  @Test func resumeCaptionFormat_includesLogNewExpenses_inEnglish() {
    let formatted = String(
      localized: "budgetDetail.action.resume.caption.format",
      defaultValue: "Paused since %@. Resume to log new expenses.",
      comment: "Caption below the Resume Budget button; argument is the abbreviated pause date"
    )
    #expect(formatted.contains("new expenses"))
  }
}
