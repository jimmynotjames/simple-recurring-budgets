import Foundation

/// Destinations for modal sheet presentation. `Identifiable`, so it binds to `.sheet(item:)`.
///
/// Cases carry the model's stable `id`, never a live model (see `AppRoute`); `RootView` resolves it at the
/// presentation site. Existing-expense editing is a push (`AppRoute.expenseDetail`), not a sheet.
enum SheetRoute: Hashable, Identifiable {
  case addBudget
  case editBudget(UUID)
  case addExpense(UUID)
  case settings
  case analyticsConsent

  var id: Self {
    self
  }
}
