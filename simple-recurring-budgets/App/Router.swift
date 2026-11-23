import Foundation

/// Centralised navigation state, owned by `simple_recurring_budgetsApp` as `@State` and injected into the
/// environment so any screen can push a destination or present a sheet.
/// Usage in a leaf screen:
/// ```swift
/// @Environment(Router.self) private var router
/// // …
/// router.sheet = .addBudget
/// router.path.append(.budgetDetail(budget.id))
/// ```
@Observable
@MainActor
final class Router {
  var path: [AppRoute] = []
  var sheet: SheetRoute?
}
