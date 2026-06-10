import Foundation

/// Destinations for modal sheet presentation.
///
/// Conforms to `Identifiable` so it binds directly to `.sheet(item:)`.
/// Cases carry the model's stable `id` (UUID), never a live model reference — see
/// `AppRoute` for the rationale; `RootView` resolves at the presentation site.
/// Add a case here for each screen that is presented as a sheet.
/// Note: existing-expense editing is a push destination (`AppRoute.expenseDetail`) not a sheet.
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
