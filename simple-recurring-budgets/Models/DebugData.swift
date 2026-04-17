//
//  DebugData.swift
//  simple-recurring-budgets
//

#if DEBUG
import Foundation
import SwiftData

/// Canonical source of truth for `Budget` / `ExpenseItem` fixtures used by `#Preview`
/// blocks and ad-hoc debugging.
///
/// Every accessor is a **function** (not a computed property) because each invocation
/// must mint fresh SwiftData model instances — a single `@Model` instance is bound to
/// the first `ModelContext` it is inserted into and cannot be shared across containers.
///
/// Every function takes `now: Date = Date()` so callers can pin a deterministic anchor
/// (for snapshot testing or stable previews). All relative expense dates are derived
/// from `now` via `Calendar.current`.
///
/// Budget names are intentionally self-describing ("Daily – Default", "Weekly –
/// Carry-Over Disabled", etc.) so you can tell at a glance which edge case a row is
/// exercising when the fixtures are rendered in the UI.
enum DebugData {

    // MARK: - Shared date helpers

    /// Returns `now` shifted by `days` days (negative = earlier).
    private static func daysAgo(_ days: Int, from now: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
    }

    // MARK: - Special ExpenseItem factories
    //
    // Each factory below exercises a distinct UI edge case. They are declared once here
    // and composed into budgets below, so a tweak to e.g. "longNameExpense" updates every
    // budget that uses it.

    /// Very long `name` that should wrap to 2+ lines on a phone-width row.
    static func longNameExpense(now: Date = Date()) -> ExpenseItem {
        ExpenseItem(
            amount: 12.34,
            name: "Dinner with out-of-town friends at that new ramen place downtown including tip and parking",
            date: daysAgo(0, from: now)
        )
    }

    /// Negative `amount` — represents adding funds (F-6.01); stresses the
    /// `isAddFunds` / sign display path.
    static func addFundsExpense(now: Date = Date()) -> ExpenseItem {
        ExpenseItem(
            amount: -50,
            name: "Added funds from reimbursement",
            date: daysAgo(1, from: now)
        )
    }

    /// 6+ digit display amount (≥ `1000.00`) to stress numeric column widths.
    static func largeAmountExpense(now: Date = Date()) -> ExpenseItem {
        ExpenseItem(
            amount: 12_345.67,
            name: "Annual membership renewal",
            date: daysAgo(2, from: now)
        )
    }

    /// Smallest meaningful positive amount (`0.01`) — stresses rounding and
    /// fractional display.
    static func tinyAmountExpense(now: Date = Date()) -> ExpenseItem {
        ExpenseItem(
            amount: 0.01,
            name: "Penny candy",
            date: daysAgo(0, from: now)
        )
    }

    /// `name == nil` — exercises the nil-name fallback in list / detail rendering.
    static func unnamedExpense(now: Date = Date()) -> ExpenseItem {
        ExpenseItem(
            amount: 4.75,
            name: nil,
            date: daysAgo(0, from: now)
        )
    }

    /// Populates `expenseType` (F-6.02) so the UI can exercise its expense-type
    /// badge / label path.
    static func expenseWithExpenseType(now: Date = Date()) -> ExpenseItem {
        ExpenseItem(
            amount: 18.50,
            name: "Coffee",
            date: daysAgo(1, from: now),
            expenseType: "Credit Card"
        )
    }

    // MARK: - Budget factories
    //
    // Each factory returns a detached `Budget` (no `ModelContext`) with its
    // `expenseItems` pre-populated. Insert via `seed(into:now:)` or manually via
    // `context.insert(budget)` + `context.insert(expense)` for each expense.

    /// Daily period, default weekly reset cadence, carry-over enabled.
    /// 3 expenses within the current daily period.
    static func dailyDefault(now: Date = Date()) -> Budget {
        let budget = Budget(
            name: "Daily – Default",
            allocation: 25,
            currencyCode: "USD",
            period: .daily
        )
        let expenses = [
            ExpenseItem(amount: 4.50, name: "Morning coffee", date: now),
            ExpenseItem(amount: 9.25, name: "Lunch", date: now),
            ExpenseItem(amount: 3.00, name: "Snack", date: now)
        ]
        attach(expenses, to: budget)
        return budget
    }

    /// Weekly period in EUR, default monthly reset cadence, carry-over enabled.
    /// Expenses **span multiple weekly periods AND cross the monthly reset boundary**.
    static func weeklyDefault(now: Date = Date()) -> Budget {
        let budget = Budget(
            name: "Weekly – Groceries (EUR)",
            allocation: 120,
            currencyCode: "EUR",
            period: .weekly
        )
        // Offsets chosen so that at a typical `now`, at least one expense falls before
        // the start of the current month (monthly reset boundary) and at least one
        // falls after. Spanning 35 days > 30 guarantees crossing a month boundary
        // regardless of which day of the month `now` lands on.
        let expenses = [
            ExpenseItem(amount: 32.10, name: "Farmers market", date: daysAgo(0, from: now)),
            ExpenseItem(amount: 48.75, name: "Weekly grocery run", date: daysAgo(7, from: now)),
            ExpenseItem(amount: 27.40, name: "Bakery", date: daysAgo(21, from: now)),
            ExpenseItem(amount: 55.90, name: "Grocery run (last month)", date: daysAgo(35, from: now))
        ]
        attach(expenses, to: budget)
        return budget
    }

    /// Biweekly period, default quarterly reset cadence, carry-over enabled.
    /// Extra-large 6-digit allocation to stress numeric display.
    static func biweeklyDefault(now: Date = Date()) -> Budget {
        let budget = Budget(
            name: "Biweekly – Household Stipend",
            allocation: Decimal(string: "543210.99")!,
            currencyCode: "USD",
            period: .biweekly
        )
        let expenses = [
            ExpenseItem(amount: 1_250, name: "Rent share", date: daysAgo(0, from: now)),
            ExpenseItem(amount: 425.60, name: "Utilities", date: daysAgo(3, from: now)),
            ExpenseItem(amount: 89.99, name: "Home supplies", date: daysAgo(8, from: now))
        ]
        attach(expenses, to: budget)
        return budget
    }

    /// Monthly period, default quarterly reset cadence, carry-over enabled.
    /// **Long name** that should wrap to 2+ lines on a phone-width row.
    /// 5 expenses including `longNameExpense` and `largeAmountExpense`.
    static func monthlyDefault(now: Date = Date()) -> Budget {
        let budget = Budget(
            name: "Monthly – Long descriptive name for the family grocery, pantry, and sundries budget that should wrap to two lines on a phone",
            allocation: 800,
            currencyCode: "USD",
            period: .monthly
        )
        let expenses = [
            ExpenseItem(amount: 62.30, name: "Groceries week 1", date: daysAgo(2, from: now)),
            ExpenseItem(amount: 78.15, name: "Groceries week 2", date: daysAgo(9, from: now)),
            ExpenseItem(amount: 41.00, name: "Pantry restock", date: daysAgo(16, from: now)),
            longNameExpense(now: now),
            largeAmountExpense(now: now)
        ]
        attach(expenses, to: budget)
        return budget
    }

    /// Daily period with `resetCadence = .never` (no automatic reset), carry-over
    /// enabled. Uses JPY (0 fraction digits) to exercise no-decimal currency
    /// formatting. 5 expenses **spanning multiple daily periods within a single
    /// (implicit) reset window**.
    static func dailyNeverReset(now: Date = Date()) -> Budget {
        let budget = Budget(
            name: "Daily – Never Resets (JPY)",
            allocation: 1_000,
            currencyCode: "JPY",
            period: .daily,
            resetCadence: .never
        )
        let expenses = [
            ExpenseItem(amount: 350, name: "Bento", date: daysAgo(0, from: now)),
            ExpenseItem(amount: 180, name: "Vending machine", date: daysAgo(1, from: now)),
            ExpenseItem(amount: 420, name: "Convenience store", date: daysAgo(2, from: now)),
            unnamedExpense(now: now),
            tinyAmountExpense(now: now)
        ]
        // unnamedExpense + tinyAmountExpense default to `daysAgo(0, ...)`; override
        // their dates so they actually span multiple daily periods with the rest.
        expenses[3].date = daysAgo(3, from: now)
        expenses[4].date = daysAgo(4, from: now)
        attach(expenses, to: budget)
        return budget
    }

    /// Weekly period, default reset cadence, **`isCarryOverEnabled = false`**.
    /// The only budget with exactly **1 expense** (using `addFundsExpense` so that
    /// single row exercises the add-funds display path).
    static func weeklyCarryOverOff(now: Date = Date()) -> Budget {
        let budget = Budget(
            name: "Weekly – Carry-Over Disabled",
            allocation: 60,
            currencyCode: "USD",
            period: .weekly,
            isCarryOverEnabled: false
        )
        attach([addFundsExpense(now: now)], to: budget)
        return budget
    }

    /// Weekly period with `resetCadence = .never`, carry-over enabled.
    /// 3 expenses within the current weekly period.
    static func weeklyNeverReset(now: Date = Date()) -> Budget {
        let budget = Budget(
            name: "Weekly – Never Resets",
            allocation: 75,
            currencyCode: "USD",
            period: .weekly,
            resetCadence: .never
        )
        let expenses = [
            ExpenseItem(amount: 12.00, name: "Bus pass top-up", date: daysAgo(0, from: now)),
            ExpenseItem(amount: 8.75, name: "Magazine", date: daysAgo(2, from: now)),
            ExpenseItem(amount: 22.40, name: "Hardware store", date: daysAgo(4, from: now))
        ]
        attach(expenses, to: budget)
        return budget
    }

    /// Daily period with a **pre-seeded positive carry-over amount** (surplus) to
    /// exercise the surplus display path.
    static func dailyWithSurplusCarryOver(now: Date = Date()) -> Budget {
        let budget = Budget(
            name: "Daily – Surplus Carry-Over",
            allocation: 20,
            currencyCode: "USD",
            period: .daily
        )
        budget.carryOverAmount = Decimal(string: "87.50")!
        let expenses = [
            ExpenseItem(amount: 3.25, name: "Coffee", date: daysAgo(0, from: now)),
            ExpenseItem(amount: 11.00, name: "Lunch", date: daysAgo(0, from: now)),
            ExpenseItem(amount: 2.50, name: "Tip", date: daysAgo(0, from: now))
        ]
        attach(expenses, to: budget)
        return budget
    }

    /// Monthly period with a **pre-seeded negative carry-over amount** (deficit) to
    /// exercise the deficit display path. Includes `expenseWithExpenseType` so the
    /// expense-type label renders at least once in the preview set.
    static func monthlyWithDeficitCarryOver(now: Date = Date()) -> Budget {
        let budget = Budget(
            name: "Monthly – Deficit Carry-Over",
            allocation: 400,
            currencyCode: "USD",
            period: .monthly
        )
        budget.carryOverAmount = Decimal(string: "-123.45")!
        let expenses = [
            ExpenseItem(amount: 145.00, name: "Gym membership", date: daysAgo(3, from: now)),
            ExpenseItem(amount: 72.25, name: "Streaming services", date: daysAgo(10, from: now)),
            ExpenseItem(amount: 38.90, name: "Dry cleaning", date: daysAgo(15, from: now)),
            expenseWithExpenseType(now: now)
        ]
        attach(expenses, to: budget)
        return budget
    }

    // MARK: - Top-level accessors

    /// Every fixture budget, in sidebar display order.
    ///
    /// Order is chosen to front-load the "common" cases (each period's default) so a
    /// preview that crops to the first few rows still shows a diverse set; edge-case
    /// budgets follow.
    static func allBudgets(now: Date = Date()) -> [Budget] {
        [
            dailyDefault(now: now),
            weeklyDefault(now: now),
            biweeklyDefault(now: now),
            monthlyDefault(now: now),
            dailyNeverReset(now: now),
            weeklyCarryOverOff(now: now),
            weeklyNeverReset(now: now),
            dailyWithSurplusCarryOver(now: now),
            monthlyWithDeficitCarryOver(now: now)
        ]
    }

    /// Inserts every fixture budget (and its expenses) into `context` and saves.
    ///
    /// Errors from `nextSortOrder(for:)` and `context.save()` are swallowed because
    /// previews must never `fatalError`; a failed save at preview time will manifest
    /// as missing rows rather than a crashed canvas.
    static func seed(into context: ModelContext, now: Date = Date()) {
        for budget in allBudgets(now: now) {
            budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0
            context.insert(budget)
            for expense in budget.expenseItems {
                context.insert(expense)
            }
        }
        try? context.save()
    }

    // MARK: - Private helpers

    /// Wires `expenses` to `budget` on both sides of the relationship. SwiftData
    /// requires setting `expense.budget` *and* appending to the parent's collection
    /// for the relationship to be fully populated before insert.
    private static func attach(_ expenses: [ExpenseItem], to budget: Budget) {
        for expense in expenses {
            expense.budget = budget
        }
        budget.expenseItems = expenses
    }
}
#endif
