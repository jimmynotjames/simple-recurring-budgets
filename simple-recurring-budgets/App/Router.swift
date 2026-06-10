import Foundation

/// Centralised navigation state for the app.
///
/// Owned by `RootView` as `@State` and injected into the environment so any
/// descendant screen can push a new destination or present a sheet without
/// needing a direct reference to the host.
///
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
