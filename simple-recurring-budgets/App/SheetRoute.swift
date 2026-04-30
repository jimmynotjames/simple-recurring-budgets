import Foundation

/// Destinations for modal sheet presentation.
///
/// Conforms to `Identifiable` so it binds directly to `.sheet(item:)`.
/// Add a case here for each screen that is presented as a sheet.
enum SheetRoute: Hashable, Identifiable {
  case addBudget
  case editBudget(Budget)
  case addExpense(Budget)
  /// Existing expense: F-2.04 single surface for viewing and in-place editing (no separate view vs edit mode).
  case expense(ExpenseItem)
  case settings

  var id: Self {
    self
  }
}
