import Foundation

/// Destinations for push navigation within the main `NavigationStack`.
///
/// Add a case here for each screen that is reached by drilling down (not by sheet).
/// Current stack: Budgets list (root) → Budget detail.
enum AppRoute: Hashable {
  /// Drill into the expense list for a specific budget.
  case budgetDetail(Budget)
}
