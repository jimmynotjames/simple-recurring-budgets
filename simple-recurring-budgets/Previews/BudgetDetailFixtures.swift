#if DEBUG
  import Foundation
  import SwiftData

  extension DebugData {
    // MARK: - Detail-screen budget factories

    static func detailDailyCurrentOnly(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Food & Coffee", currencyCode: "USD", period: .daily)
      let startDate = Calendar.current.startOfDay(for: now)
      budget.startDate = startDate
      let hoursAgo: (Double) -> Date = { now.addingTimeInterval(-$0 * 3600) }
      let expenses = [
        ExpenseItem(amount: 4.50, name: "Morning coffee", date: hoursAgo(2)),
        ExpenseItem(amount: 9.25, name: "Lunch", date: hoursAgo(5.5)),
        ExpenseItem(amount: 2.50, name: "Afternoon snack", date: hoursAgo(1)),
      ]
      attachToDetail(expenses, to: budget)
      addDetailChange(amount: 25, startDate: startDate, to: budget)
      return budget
    }

    static func detailMonthlyCurrentAndPast(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Monthly Discretionary", currencyCode: "USD", period: .monthly)
      let cal = Calendar.current
      let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
      let lastMonthStart = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
      let twoMonthsAgo = cal.date(byAdding: .month, value: -2, to: monthStart) ?? monthStart
      budget.startDate = twoMonthsAgo // show multiple past months

      // swiftlint:disable large_tuple
      let currentExpenses: [(Decimal, String?, TimeInterval)] = [
        (87.40, "Groceries", 86400 * 2),
        (55.20, "Gas station", 86400 * 5),
        (24.85, "Pharmacy", 86400 * 8),
        (68.00, "Restaurant", 86400 * 12),
        (42.10, "Online order", 86400 * 16),
      ]
      let pastExpenses: [(Decimal, String?, Date)] = [
        (112.34, "Dinner with friends at that new ramen place including tip and parking", lastMonthStart.addingTimeInterval(86400 * 20)),
        (67.71, "Hardware store", lastMonthStart.addingTimeInterval(86400 * 15)),
        (31.00, nil, lastMonthStart.addingTimeInterval(86400 * 10)),
        (49.50, "Clothing", lastMonthStart.addingTimeInterval(86400 * 5)),
        (18.90, "Coffee shop", lastMonthStart.addingTimeInterval(86400 * 2)),
        (88.00, "Groceries", twoMonthsAgo.addingTimeInterval(86400 * 22)),
        (34.20, "Gas station", twoMonthsAgo.addingTimeInterval(86400 * 14)),
        (72.00, "Electronics", twoMonthsAgo.addingTimeInterval(86400 * 7)),
      ]
      // swiftlint:enable large_tuple

      var expenses: [ExpenseItem] = []
      for (amount, name, offset) in currentExpenses {
        expenses.append(ExpenseItem(amount: amount, name: name, date: monthStart.addingTimeInterval(offset)))
      }
      for (amount, name, date) in pastExpenses {
        expenses.append(ExpenseItem(amount: amount, name: name, date: date))
      }
      attachToDetail(expenses, to: budget)
      addDetailChange(amount: 800, startDate: twoMonthsAgo, to: budget)
      return budget
    }

    static func detailWeeklyPastOnly(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Fun Money", currencyCode: "USD", period: .weekly)
      let cal = Calendar.current
      let startDate = cal.date(byAdding: .day, value: -21, to: cal.startOfDay(for: now))!
      budget.startDate = startDate
      let daysAgo: (Int) -> Date = { cal.date(byAdding: .day, value: -$0, to: now) ?? now }
      let expenses = [
        ExpenseItem(amount: 12.00, name: "Coffee & snacks", date: daysAgo(10)),
        ExpenseItem(amount: 45.00, name: "Concert tickets", date: daysAgo(12)),
        ExpenseItem(amount: 8.50, name: "Parking", date: daysAgo(14)),
        ExpenseItem(amount: 22.00, name: "Dinner out", date: daysAgo(18)),
      ]
      attachToDetail(expenses, to: budget)
      addDetailChange(amount: 60, startDate: startDate, to: budget)
      return budget
    }

    static func detailWeeklyEmpty(now _: Date = Date()) -> Budget {
      let budget = Budget(name: "Beauty & Fashion", currencyCode: "USD", period: .weekly)
      let startDate = Calendar.current.startOfDay(for: Date())
      budget.startDate = startDate
      addDetailChange(amount: 100, startDate: startDate, to: budget)
      return budget
    }

    static func detailMonthlyCarryOverDisabled(now: Date = Date()) -> Budget {
      let budget = Budget(
        name: "Household Supplies",
        currencyCode: "USD",
        period: .monthly,
        isCarryOverEnabled: false
      )
      let cal = Calendar.current
      let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
      budget.startDate = monthStart
      let expenses = [
        ExpenseItem(amount: 28.40, name: "Cleaning products", date: monthStart.addingTimeInterval(86400 * 2)),
        ExpenseItem(amount: 18.50, name: "Paper goods", date: monthStart.addingTimeInterval(86400 * 8)),
      ]
      attachToDetail(expenses, to: budget)
      addDetailChange(amount: 200, startDate: monthStart, to: budget)
      return budget
    }

    static func detailDailyPaused(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Entertainment", currencyCode: "USD", period: .daily)
      let cal = Calendar.current
      let startDate = cal.date(byAdding: .day, value: -5, to: cal.startOfDay(for: now))!
      budget.startDate = startDate
      let expenses = [
        ExpenseItem(amount: 8.00, name: "Streaming", date: startDate.addingTimeInterval(86400)),
        ExpenseItem(amount: 12.50, name: "App purchase", date: startDate.addingTimeInterval(86400 * 2)),
      ]
      let pauseDate = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: now))!
      let pauseEvent = LifecycleEvent(kind: .pause, effectiveDate: pauseDate)
      pauseEvent.budget = budget
      for expense in expenses {
        expense.budget = budget
      }
      budget.expenseItems = expenses
      budget.lifecycleEventsStorage = [pauseEvent]
      addDetailChange(amount: 25, startDate: startDate, to: budget)
      return budget
    }

    static func detailWeeklyOverBudget(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Fun Money", currencyCode: "USD", period: .weekly)
      let cal = Calendar.current
      let dayStart = cal.startOfDay(for: now)
      let weekday = cal.component(.weekday, from: dayStart)
      let daysBack = (weekday - 1 + 7) % 7
      let startDate = cal.date(byAdding: .day, value: -daysBack, to: dayStart)!
      budget.startDate = startDate
      let daysAgo: (Int) -> Date = { cal.date(byAdding: .day, value: -$0, to: now) ?? now }
      let expenses = [
        ExpenseItem(amount: 48.00, name: "Concert tickets", date: daysAgo(1)),
        ExpenseItem(amount: 20.40, name: "Merch", date: daysAgo(1)),
      ]
      attachToDetail(expenses, to: budget)
      addDetailChange(amount: 60, startDate: startDate, to: budget)
      return budget
    }

    // MARK: - Specific Dates fixture

    /// The "Italy Trip" Specific Dates fixture used by BudgetDetail previews. Mirrors
    /// `DebugData.specificDatesDefault` (Budgets-list previews) — see that doc comment
    /// for why the two fixtures are intentionally separate. Keep the date offsets,
    /// allocation, and currency in sync when one changes.
    static func detailSpecificDates(now: Date = Date()) -> Budget {
      let cal = Calendar.current
      let startDate = cal.date(byAdding: .day, value: -10, to: cal.startOfDay(for: now))!
      let endDate = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now))!
      let budget = Budget(name: "Italy Trip", currencyCode: "EUR", period: .specificDates, isCarryOverEnabled: false)
      budget.startDate = startDate
      budget.endDate = endDate
      let expenses = [
        ExpenseItem(amount: 450, name: "Hotel deposit", date: startDate.addingTimeInterval(3600)),
        ExpenseItem(amount: 85, name: "Dinner", date: cal.date(byAdding: .day, value: -3, to: now)!),
        ExpenseItem(amount: 24, name: "Museum tickets", date: cal.date(byAdding: .day, value: -1, to: now)!),
      ]
      attachToDetail(expenses, to: budget)
      addDetailChange(amount: 1500, startDate: startDate, to: budget)
      return budget
    }

    // MARK: - Inactive-state fixtures (preStart / postEnd)

    /// Daily budget whose `startDate` is in the future — exercises the `.preStart`
    /// inactive presentation (allocation displayed, full-width secondary bar,
    /// "Starts {date}" chip).
    static func detailDailyPreStart(now: Date = Date()) -> Budget {
      let cal = Calendar.current
      let startDate = cal.date(byAdding: .day, value: 14, to: cal.startOfDay(for: now))!
      let budget = Budget(name: "Daily Coffee", currencyCode: "USD", period: .daily)
      budget.startDate = startDate
      addDetailChange(amount: 8, startDate: startDate, to: budget)
      return budget
    }

    /// Monthly budget whose `endDate` has passed — exercises the `.postEnd`
    /// inactive presentation (allocation displayed, full-width secondary bar,
    /// "Ended {date}" chip).
    static func detailMonthlyPostEnd(now: Date = Date()) -> Budget {
      let cal = Calendar.current
      let startDate = cal.date(byAdding: .month, value: -3, to: cal.startOfDay(for: now))!
      let endDate = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!
      let budget = Budget(name: "Vacation Fund", currencyCode: "USD", period: .monthly)
      budget.startDate = startDate
      budget.endDate = endDate
      let expenses = [
        ExpenseItem(amount: 145.00, name: "Flights", date: cal.date(byAdding: .day, value: -45, to: now)!),
        ExpenseItem(amount: 80.00, name: "Hotel", date: cal.date(byAdding: .day, value: -20, to: now)!),
      ]
      attachToDetail(expenses, to: budget)
      addDetailChange(amount: 400, startDate: startDate, to: budget)
      return budget
    }

    /// Specific Dates budget whose window is in the future — exercises `.preStart`
    /// for a non-recurring budget (no `CarryOverChip`).
    static func detailSpecificDatesPreStart(now: Date = Date()) -> Budget {
      let cal = Calendar.current
      let startDate = cal.date(byAdding: .day, value: 30, to: cal.startOfDay(for: now))!
      let endDate = cal.date(byAdding: .day, value: 60, to: cal.startOfDay(for: now))!
      let budget = Budget(name: "Wedding", currencyCode: "USD", period: .specificDates, isCarryOverEnabled: false)
      budget.startDate = startDate
      budget.endDate = endDate
      addDetailChange(amount: 5000, startDate: startDate, to: budget)
      return budget
    }

    /// Specific Dates budget whose window has already ended — exercises `.postEnd`
    /// for a non-recurring budget.
    static func detailSpecificDatesPostEnd(now: Date = Date()) -> Budget {
      let cal = Calendar.current
      let startDate = cal.date(byAdding: .day, value: -40, to: cal.startOfDay(for: now))!
      let endDate = cal.date(byAdding: .day, value: -10, to: cal.startOfDay(for: now))!
      let budget = Budget(name: "Holiday Gifts", currencyCode: "USD", period: .specificDates, isCarryOverEnabled: false)
      budget.startDate = startDate
      budget.endDate = endDate
      let expenses = [
        ExpenseItem(amount: 240, name: "Family gifts", date: cal.date(byAdding: .day, value: -25, to: now)!),
      ]
      attachToDetail(expenses, to: budget)
      addDetailChange(amount: 500, startDate: startDate, to: budget)
      return budget
    }

    // MARK: - Insert helper

    static func insertDetail(_ budget: Budget, into context: ModelContext) {
      context.insert(budget)
      for expense in budget.expenseItems {
        context.insert(expense)
      }
      for change in budget.allocationChanges {
        context.insert(change)
      }
      for event in budget.lifecycleEvents {
        context.insert(event)
      }
      try? context.save()
    }

    // MARK: - Private helpers

    private static func attachToDetail(_ expenses: [ExpenseItem], to budget: Budget) {
      for expense in expenses {
        expense.budget = budget
      }
      budget.expenseItems = expenses
    }

    private static func addDetailChange(amount: Decimal, startDate: Date, to budget: Budget) {
      let change = AllocationChange(effectiveFrom: startDate, amount: amount)
      change.budget = budget
      budget.allocationChangesStorage = [change]
    }
  }
#endif
