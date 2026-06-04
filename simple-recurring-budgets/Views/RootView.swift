import SwiftData
import SwiftUI

/// Root navigation host. Owns the `NavigationStack` path and the active sheet
/// via the environment-injected `Router`.
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
            BudgetDetailView(budget: budget)
          case let .expenseDetail(expense):
            AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))
          }
        }
    }
    .sheet(item: $router.sheet) { route in
      Group {
        switch route {
        case .addBudget:
          AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: settings))
        case let .editBudget(budget):
          AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))
        case let .addExpense(budget):
          NavigationStack {
            AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget))
          }
        case .settings:
          SettingsView()
        case .analyticsConsent:
          AnalyticsConsentSheet()
        }
      }
      // Test-only Dynamic Type override (inert unless IS_TESTING + FORCE_DYNAMIC_TYPE are set).
      // Sheet content does NOT inherit the root-level override applied in the App body, so the
      // ad-hoc localized-layout screenshot check (scripts/translation-accessibility-size-check/)
      // re-applies it here to reach Settings / Add Expense / Add Budget at the forced size too.
      .modifier(TestDynamicTypeOverride())
    }
  }
}

#if DEBUG
  #Preview {
    RootView()
      .modelContainer(PreviewContainer.make())
      .environment(Router())
      .environment(AppSettings())
      .environment(SyncStatus(containerBacking: .cloudKit, accountStatus: .available))
  }
#endif
