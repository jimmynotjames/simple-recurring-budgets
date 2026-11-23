import Foundation

/// Destinations for push navigation within the main `NavigationStack`.
///
/// Routes carry the model's stable `id`, never a live model reference, so they stay serializable (deep
/// links, widgets, App Intents). `RootView` resolves the UUID at the destination via
/// `ModelContext.budget(id:)` / `.expenseItem(id:)` and silently pops the route if the model is gone
/// (e.g. deleted on another device).
///
/// Stack: Budgets list (root) → Budget detail → Expense detail.
enum AppRoute: Hashable {
  /// Drill into the expense list for a specific budget.
  case budgetDetail(UUID)
  /// Push into the Add/Edit/View Expense screen for an existing expense.
  case expenseDetail(UUID)
}
