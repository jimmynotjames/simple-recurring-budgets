#if DEBUG
  import Foundation
  import SwiftData

  /// Fixtures specific to `BudgetDetailView` previews and ad-hoc debugging.
  ///
  /// Each factory exercises a distinct edge case of the detail screen
  /// (current-period only, mixed current/past, past-only, empty,
  /// carry-over disabled, over-budget). Like the rest of `DebugData`, every
  /// factory mints fresh `Budget` / `ExpenseItem` instances on each call so
  /// they can be safely inserted into a new `ModelContext`, and accepts a
  /// `now: Date` anchor for deterministic snapshots.
  extension DebugData {
    // MARK: - Detail-screen budget factories

    /// Daily budget with 3 expenses all logged within the current day —
    /// exercises the "Current Period" section in isolation.
    static func detailDailyCurrentOnly(now: Date = Date()) -> Budget {
      let budget = Budget(
        name: "Food & Coffee",
        allocation: 25,
        currencyCode: "USD",
        period: .daily
      )
      let hoursAgo: (Double) -> Date = { now.addingTimeInterval(-$0 * 3600) }
      let expenses = [
        ExpenseItem(amount: 4.50, name: "Morning coffee", date: hoursAgo(2)),
        ExpenseItem(amount: 9.25, name: "Lunch", date: hoursAgo(5.5)),
        ExpenseItem(amount: 2.50, name: "Afternoon snack", date: hoursAgo(1)),
      ]
      attachToDetail(expenses, to: budget)
      return budget
    }

    /// Monthly budget with both current-month and past-month expenses
    /// (spanning two prior months) — exercises both list sections plus a
    /// nil-name row and a multi-line wrapping row.
    static func detailMonthlyCurrentAndPast(now: Date = Date()) -> Budget {
      let budget = Budget(
        name: "Monthly Discretionary",
        allocation: 800,
        currencyCode: "USD",
        period: .monthly
      )
      let cal = Calendar.current
      let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
      let lastMonthStart = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
      let twoMonthsAgo = cal.date(byAdding: .month, value: -2, to: monthStart) ?? monthStart

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

      var expenses: [ExpenseItem] = []
      for (amount, name, offset) in currentExpenses {
        expenses.append(ExpenseItem(amount: amount, name: name, date: monthStart.addingTimeInterval(offset)))
      }
      for (amount, name, date) in pastExpenses {
        expenses.append(ExpenseItem(amount: amount, name: name, date: date))
      }
      // swiftlint:enable large_tuple
      attachToDetail(expenses, to: budget)
      return budget
    }

    /// Weekly budget whose only expenses fall before the current period —
    /// exercises the "Past" section when "Current" is empty.
    static func detailWeeklyPastOnly(now: Date = Date()) -> Budget {
      let budget = Budget(
        name: "Fun Money",
        allocation: 60,
        currencyCode: "USD",
        period: .weekly
      )
      let cal = Calendar.current
      let daysAgo: (Int) -> Date = { cal.date(byAdding: .day, value: -$0, to: now) ?? now }
      let expenses = [
        ExpenseItem(amount: 12.00, name: "Coffee & snacks", date: daysAgo(10)),
        ExpenseItem(amount: 45.00, name: "Concert tickets", date: daysAgo(12)),
        ExpenseItem(amount: 8.50, name: "Parking", date: daysAgo(14)),
        ExpenseItem(amount: 22.00, name: "Dinner out", date: daysAgo(18)),
      ]
      attachToDetail(expenses, to: budget)
      return budget
    }

    /// Weekly budget with no expenses — exercises the empty-state row.
    static func detailWeeklyEmpty(now _: Date = Date()) -> Budget {
      Budget(
        name: "Beauty & Fashion",
        allocation: 100,
        currencyCode: "USD",
        period: .weekly
      )
    }

    /// Monthly budget with `isCarryOverEnabled = false` — exercises the
    /// header layout when the carry-over chip is hidden.
    static func detailMonthlyCarryOverDisabled(now: Date = Date()) -> Budget {
      let budget = Budget(
        name: "Household Supplies",
        allocation: 200,
        currencyCode: "USD",
        period: .monthly,
        isCarryOverEnabled: false
      )
      let cal = Calendar.current
      let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
      let expenses = [
        ExpenseItem(amount: 28.40, name: "Cleaning products", date: monthStart.addingTimeInterval(86400 * 2)),
        ExpenseItem(amount: 18.50, name: "Paper goods", date: monthStart.addingTimeInterval(86400 * 8)),
      ]
      attachToDetail(expenses, to: budget)
      return budget
    }

    /// Weekly budget with current-period spending exceeding the allocation —
    /// exercises the over-budget header colour and accessibility wording.
    static func detailWeeklyOverBudget(now: Date = Date()) -> Budget {
      let budget = Budget(
        name: "Fun Money",
        allocation: 60,
        currencyCode: "USD",
        period: .weekly
      )
      let cal = Calendar.current
      let daysAgo: (Int) -> Date = { cal.date(byAdding: .day, value: -$0, to: now) ?? now }
      let expenses = [
        ExpenseItem(amount: 48.00, name: "Concert tickets", date: daysAgo(1)),
        ExpenseItem(amount: 20.40, name: "Merch", date: daysAgo(1)),
      ]
      attachToDetail(expenses, to: budget)
      return budget
    }

    // MARK: - Insert helper

    /// Inserts a detail-screen fixture budget and all its expenses into
    /// `context` and saves. Mirrors the per-budget loop inside
    /// `DebugData.seed(into:now:)` for single-budget previews.
    static func insertDetail(_ budget: Budget, into context: ModelContext) {
      context.insert(budget)
      for expense in budget.expenseItems {
        context.insert(expense)
      }
      try? context.save()
    }

    // MARK: - Private helpers

    /// Wires `expenses` to `budget` on both sides of the relationship.
    /// Duplicates `DebugData.attach(_:to:)` because that helper is
    /// file-private to `DebugData.swift`.
    private static func attachToDetail(_ expenses: [ExpenseItem], to budget: Budget) {
      for expense in expenses {
        expense.budget = budget
      }
      budget.expenseItems = expenses
    }
  }
#endif
