import Foundation

/// Destinations for modal sheet presentation.
///
/// Conforms to `Identifiable` so it binds directly to `.sheet(item:)`.
/// Add a case here for each screen that is presented as a sheet.
/// Note: existing-expense editing is a push destination (`AppRoute.expenseDetail`) not a sheet.
enum SheetRoute: Hashable, Identifiable {
  case addBudget
  case editBudget(Budget)
  case addExpense(Budget)
  case settings

  var id: Self {
    self
  }
}
