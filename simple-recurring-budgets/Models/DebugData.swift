#if DEBUG
  import Foundation
  import SwiftData

  /// Canonical source of truth for `Budget` / `ExpenseItem` fixtures used by `#Preview`
  /// blocks and ad-hoc debugging.
  ///
  /// Every accessor is a **function** (not a computed property) because each invocation
  /// must mint fresh SwiftData model instances. Every function takes `now: Date = Date()`
  /// so callers can pin a deterministic anchor.
  enum DebugData {
    // MARK: - Shared date helpers

    private static func daysAgo(_ days: Int, from now: Date) -> Date {
      Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
    }

    // MARK: - Special ExpenseItem factories

    static func longNameExpense(now: Date = Date()) -> ExpenseItem {
      ExpenseItem(
        amount: 12.34,
        name: "Dinner with out-of-town friends at that new ramen place downtown including tip and parking",
        date: daysAgo(0, from: now)
      )
    }

    static func addFundsExpense(now: Date = Date()) -> ExpenseItem {
      ExpenseItem(amount: -50, name: "Added funds from reimbursement", date: daysAgo(1, from: now))
    }

    static func largeAmountExpense(now: Date = Date()) -> ExpenseItem {
      ExpenseItem(amount: 12345.67, name: "Annual membership renewal", date: daysAgo(2, from: now))
    }

    static func tinyAmountExpense(now: Date = Date()) -> ExpenseItem {
      ExpenseItem(amount: 0.01, name: "Penny candy", date: daysAgo(0, from: now))
    }

    static func unnamedExpense(now: Date = Date()) -> ExpenseItem {
      ExpenseItem(amount: 4.75, name: nil, date: daysAgo(0, from: now))
    }

    static func expenseWithExpenseType(now: Date = Date()) -> ExpenseItem {
      ExpenseItem(amount: 18.50, name: "Coffee", date: daysAgo(1, from: now), expenseType: "Credit Card")
    }

    // MARK: - Budget factories

    static func dailyDefault(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Daily – Default", currencyCode: "USD", period: .daily)
      let startDate = Calendar.current.startOfDay(for: now)
      budget.startDate = startDate
      let expenses = [
        ExpenseItem(amount: 4.50, name: "Morning coffee", date: now),
        ExpenseItem(amount: 9.25, name: "Lunch", date: now),
        ExpenseItem(amount: 3.00, name: "Snack", date: now),
      ]
      attach(expenses, to: budget)
      addInitialChange(amount: 25, startDate: startDate, to: budget)
      return budget
    }

    static func weeklyDefault(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Weekly – Groceries (EUR)", currencyCode: "EUR", period: .weekly)
      let cal = Calendar.current
      let dayStart = cal.startOfDay(for: now)
      let weekday = cal.component(.weekday, from: dayStart)
      let daysBack = (weekday - 1 + 7) % 7 // anchor on Sunday
      let startDate = cal.date(byAdding: .day, value: -daysBack, to: dayStart)!
      budget.startDate = startDate
      let expenses = [
        ExpenseItem(amount: 32.10, name: "Farmers market", date: daysAgo(0, from: now)),
        ExpenseItem(amount: 48.75, name: "Weekly grocery run", date: daysAgo(7, from: now)),
        ExpenseItem(amount: 27.40, name: "Bakery", date: daysAgo(21, from: now)),
        ExpenseItem(amount: 55.90, name: "Grocery run (last month)", date: daysAgo(35, from: now)),
      ]
      attach(expenses, to: budget)
      addInitialChange(amount: 120, startDate: startDate, to: budget)
      return budget
    }

    static func biweeklyDefault(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Biweekly – Household Stipend", currencyCode: "USD", period: .biweekly)
      let cal = Calendar.current
      let dayStart = cal.startOfDay(for: now)
      let weekday = cal.component(.weekday, from: dayStart)
      let daysBack = (weekday - 1 + 7) % 7
      let startDate = cal.date(byAdding: .day, value: -daysBack, to: dayStart)!
      budget.startDate = startDate
      let expenses = [
        ExpenseItem(amount: 1250, name: "Rent share", date: daysAgo(0, from: now)),
        ExpenseItem(amount: 425.60, name: "Utilities", date: daysAgo(3, from: now)),
        ExpenseItem(amount: 89.99, name: "Home supplies", date: daysAgo(8, from: now)),
      ]
      attach(expenses, to: budget)
      addInitialChange(amount: Decimal(string: "543210.99")!, startDate: startDate, to: budget)
      return budget
    }

    static func monthlyDefault(now: Date = Date()) -> Budget {
      let budget = Budget(
        name: "Monthly – Long descriptive name for the family grocery, pantry, and sundries budget that should wrap to two lines on a phone",
        currencyCode: "USD",
        period: .monthly
      )
      let cal = Calendar.current
      var comps = cal.dateComponents([.year, .month], from: now)
      comps.day = 1; comps.hour = 0; comps.minute = 0; comps.second = 0
      let startDate = cal.date(from: comps)!
      budget.startDate = startDate
      let expenses = [
        ExpenseItem(amount: 62.30, name: "Groceries week 1", date: daysAgo(2, from: now)),
        ExpenseItem(amount: 78.15, name: "Groceries week 2", date: daysAgo(9, from: now)),
        ExpenseItem(amount: 41.00, name: "Pantry restock", date: daysAgo(16, from: now)),
        longNameExpense(now: now),
        largeAmountExpense(now: now),
      ]
      attach(expenses, to: budget)
      addInitialChange(amount: 800, startDate: startDate, to: budget)
      return budget
    }

    static func dailyNeverReset(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Daily – Never Resets (JPY)", currencyCode: "JPY", period: .daily)
      let startDate = Calendar.current.startOfDay(for: daysAgo(4, from: now))
      budget.startDate = startDate
      let expenses = [
        ExpenseItem(amount: 350, name: "Bento", date: daysAgo(0, from: now)),
        ExpenseItem(amount: 180, name: "Vending machine", date: daysAgo(1, from: now)),
        ExpenseItem(amount: 420, name: "Convenience store", date: daysAgo(2, from: now)),
        unnamedExpense(now: now),
        tinyAmountExpense(now: now),
      ]
      expenses[3].date = daysAgo(3, from: now)
      expenses[4].date = daysAgo(4, from: now)
      attach(expenses, to: budget)
      addInitialChange(amount: 1000, startDate: startDate, to: budget)
      return budget
    }

    static func weeklyCarryOverOff(now: Date = Date()) -> Budget {
      let budget = Budget(
        name: "Weekly – Carry-Over Disabled",
        currencyCode: "USD",
        period: .weekly,
        isCarryOverEnabled: false
      )
      let cal = Calendar.current
      let dayStart = cal.startOfDay(for: now)
      let weekday = cal.component(.weekday, from: dayStart)
      let daysBack = (weekday - 1 + 7) % 7
      let startDate = cal.date(byAdding: .day, value: -daysBack, to: dayStart)!
      budget.startDate = startDate
      attach([addFundsExpense(now: now)], to: budget)
      addInitialChange(amount: 60, startDate: startDate, to: budget)
      return budget
    }

    static func weeklyNeverReset(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Weekly – Never Resets", currencyCode: "USD", period: .weekly)
      let cal = Calendar.current
      let dayStart = cal.startOfDay(for: now)
      let weekday = cal.component(.weekday, from: dayStart)
      let daysBack = (weekday - 1 + 7) % 7
      let startDate = cal.date(byAdding: .day, value: -daysBack, to: dayStart)!
      budget.startDate = startDate
      let expenses = [
        ExpenseItem(amount: 12.00, name: "Bus pass top-up", date: daysAgo(0, from: now)),
        ExpenseItem(amount: 8.75, name: "Magazine", date: daysAgo(2, from: now)),
        ExpenseItem(amount: 22.40, name: "Hardware store", date: daysAgo(4, from: now)),
      ]
      attach(expenses, to: budget)
      addInitialChange(amount: 75, startDate: startDate, to: budget)
      return budget
    }

    static func dailyWithSurplusCarryOver(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Daily – Surplus Carry-Over", currencyCode: "USD", period: .daily)
      let startDate = Calendar.current.startOfDay(for: daysAgo(5, from: now))
      budget.startDate = startDate
      let expenses = [
        ExpenseItem(amount: 3.25, name: "Coffee", date: daysAgo(0, from: now)),
        ExpenseItem(amount: 11.00, name: "Lunch", date: daysAgo(0, from: now)),
        ExpenseItem(amount: 2.50, name: "Tip", date: daysAgo(0, from: now)),
      ]
      attach(expenses, to: budget)
      addInitialChange(amount: 20, startDate: startDate, to: budget)
      return budget
    }

    static func dailyPaused(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Daily – Paused", currencyCode: "USD", period: .daily)
      let startDate = Calendar.current.startOfDay(for: daysAgo(30, from: now))
      budget.startDate = startDate
      let expenses = [
        ExpenseItem(amount: 6.50, name: "Coffee", date: daysAgo(20, from: now)),
        ExpenseItem(amount: 11.75, name: "Lunch", date: daysAgo(19, from: now)),
      ]
      attach(expenses, to: budget)
      addInitialChange(amount: 25, startDate: startDate, to: budget)
      addPauseEvent(effectiveDate: daysAgo(14, from: now), to: budget)
      return budget
    }

    static func monthlyWithDeficitCarryOver(now: Date = Date()) -> Budget {
      let budget = Budget(name: "Monthly – Deficit Carry-Over", currencyCode: "USD", period: .monthly)
      let cal = Calendar.current
      var comps = cal.dateComponents([.year, .month], from: now)
      comps.day = 1; comps.hour = 0; comps.minute = 0; comps.second = 0
      let startDate = cal.date(from: comps)!
      budget.startDate = startDate
      let expenses = [
        ExpenseItem(amount: 145.00, name: "Gym membership", date: daysAgo(3, from: now)),
        ExpenseItem(amount: 72.25, name: "Streaming services", date: daysAgo(10, from: now)),
        ExpenseItem(amount: 38.90, name: "Dry cleaning", date: daysAgo(15, from: now)),
        expenseWithExpenseType(now: now),
      ]
      attach(expenses, to: budget)
      addInitialChange(amount: 400, startDate: startDate, to: budget)
      return budget
    }

    static func specificDatesDefault(now: Date = Date()) -> Budget {
      let cal = Calendar.current
      let startDate = cal.date(byAdding: .day, value: -10, to: cal.startOfDay(for: now))!
      let endDate = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now))!
      let budget = Budget(name: "Italy Trip", currencyCode: "EUR", period: .specificDates, isCarryOverEnabled: false)
      budget.startDate = startDate
      budget.endDate = endDate
      addInitialChange(amount: 1500, startDate: startDate, to: budget)
      attach([
        ExpenseItem(amount: 450, name: "Hotel", date: cal.date(byAdding: .day, value: -9, to: now)!),
        ExpenseItem(amount: 85, name: "Dinner", date: cal.date(byAdding: .day, value: -3, to: now)!),
        ExpenseItem(amount: 24, name: "Museum", date: cal.date(byAdding: .day, value: -1, to: now)!),
      ], to: budget)
      return budget
    }

    // MARK: - Top-level accessors

    static func allBudgets(now: Date = Date()) -> [Budget] {
      [
        dailyWithSurplusCarryOver(now: now),
        monthlyWithDeficitCarryOver(now: now),
        specificDatesDefault(now: now),
        dailyPaused(now: now),
        dailyDefault(now: now),
        weeklyDefault(now: now),
        biweeklyDefault(now: now),
        monthlyDefault(now: now),
        dailyNeverReset(now: now),
        weeklyCarryOverOff(now: now),
        weeklyNeverReset(now: now),
      ]
    }

    static func seed(into context: ModelContext, now: Date = Date()) {
      for budget in allBudgets(now: now) {
        budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0
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
      }
      try? context.save()
    }

    // MARK: - Private helpers

    private static func attach(_ expenses: [ExpenseItem], to budget: Budget) {
      for expense in expenses {
        expense.budget = budget
      }
      budget.expenseItems = expenses
    }

    private static func addInitialChange(amount: Decimal, startDate: Date, to budget: Budget) {
      let change = AllocationChange(effectiveFrom: startDate, amount: amount)
      change.budget = budget
      budget.allocationChangesStorage = [change]
    }

    private static func addPauseEvent(effectiveDate: Date, to budget: Budget) {
      let event = LifecycleEvent(kind: .pause, effectiveDate: effectiveDate)
      event.budget = budget
      budget.lifecycleEventsStorage = (budget.lifecycleEventsStorage ?? []) + [event]
    }
  }
#endif
