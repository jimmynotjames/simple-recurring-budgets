import Foundation

/// Destinations for push navigation within the main `NavigationStack`.
///
/// Routes carry the model's stable `id` (`Budget.id` / `ExpenseItem.id`), never a live
/// model reference, so they stay serializable for deep links, widgets, and App Intents
/// (architecture-audit-2026-06-10.md §4.2). `RootView` resolves the UUID at the
/// destination via `ModelContext.budget(id:)` / `.expenseItem(id:)` and silently pops
/// the route when the model no longer exists (e.g., deleted on another device).
///
/// Add a case here for each screen that is reached by drilling down (not by sheet).
/// Current stack: Budgets list (root) → Budget detail → Expense detail.
enum AppRoute: Hashable {
  /// Drill into the expense list for a specific budget.
  case budgetDetail(UUID)
  /// Push into the Add/Edit/View Expense screen for an existing expense (F-2.04).
  case expenseDetail(UUID)
}
