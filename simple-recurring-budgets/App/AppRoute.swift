import Foundation

/// Destinations for push navigation within the main `NavigationStack`.
///
/// Add a case here for each screen that is reached by drilling down (not by sheet).
/// Current stack: Budgets list (root) → Budget detail → Expense detail.
enum AppRoute: Hashable {
  /// Drill into the expense list for a specific budget.
  case budgetDetail(Budget)
  /// Push into the Add/Edit/View Expense screen for an existing expense (F-2.04).
  case expenseDetail(ExpenseItem)
}
