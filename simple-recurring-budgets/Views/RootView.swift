import SwiftData
import SwiftUI

/// Root navigation host. Owns the `NavigationStack` path and the active sheet
/// via the environment-injected `Router`.
///
/// Replace placeholder bodies as screens land:
/// - `.budgetDetail` destination → `BudgetView` (F-2.02)
/// - `.addExpense` / `.expense` → `AddEditExpenseView` (F-2.04)
struct RootView: View {
  @Environment(Router.self) private var router
  @Environment(AppSettings.self) private var settings

  var body: some View {
    @Bindable var router = router
    NavigationStack(path: $router.path) {
      BudgetsView()
        .navigationDestination(for: AppRoute.self) { route in
          switch route {
          case let .budgetDetail(budget):
            Text("Budget detail: \(budget.name)")
          }
        }
    }
    .sheet(item: $router.sheet) { route in
      switch route {
      case .addBudget:
        AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: settings))
      case let .editBudget(budget):
        AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))
      case let .addExpense(budget):
        AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget))
      case let .expense(expense):
        AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))
      case .settings:
        SettingsView()
      }
    }
  }
}

#Preview {
  RootView()
    .modelContainer(PreviewContainer.make())
    .environment(Router())
    .environment(AppSettings())
    .environment(SyncStatus(containerBacking: .cloudKit, accountStatus: .available))
}
