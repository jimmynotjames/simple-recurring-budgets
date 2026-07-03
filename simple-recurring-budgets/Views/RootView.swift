import SwiftData
import SwiftUI

/// Root navigation host. Owns the `NavigationStack` path and the active sheet
/// via the environment-injected `Router`.
///
/// Routes carry stable `UUID`s (see `AppRoute` / `SheetRoute`); this view resolves
/// them through `ModelContext.budget(id:)` / `.expenseItem(id:)`. When a UUID no
/// longer resolves — the model was deleted (e.g., on another device) after the
/// route was set — the route is silently popped/dismissed instead of rendering.
struct RootView: View {
  @Environment(Router.self) private var router
  @Environment(AppSettings.self) private var settings
  @Environment(\.modelContext) private var context

  var body: some View {
    @Bindable var router = router
    NavigationStack(path: $router.path) {
      BudgetsView()
        .navigationDestination(for: AppRoute.self) { route in
          switch route {
          case let .budgetDetail(id):
            if let budget = context.budget(id: id) {
              BudgetDetailView(budget: budget)
            } else {
              unresolvedPushDestination
            }
          case let .expenseDetail(id):
            if let expense = context.expenseItem(id: id) {
              AddEditExpenseView(
                viewModel: AddEditExpenseViewModel(editing: expense, weekStart: settings.weekStartDay)
              )
            } else {
              unresolvedPushDestination
            }
          }
        }
    }
    .sheet(item: $router.sheet) { route in
      Group {
        switch route {
        case .addBudget:
          AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: settings))
        case let .editBudget(id):
          if let budget = context.budget(id: id) {
            AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))
          } else {
            unresolvedSheetDestination
          }
        case let .addExpense(id):
          if let budget = context.budget(id: id) {
            NavigationStack {
              AddEditExpenseView(
                viewModel: AddEditExpenseViewModel(adding: budget, weekStart: settings.weekStartDay)
              )
            }
          } else {
            unresolvedSheetDestination
          }
        case .settings:
          SettingsView()
        case .analyticsConsent:
          AnalyticsConsentSheet()
        }
      }
      // Test-only Dynamic Type override (DEBUG-only — compiled out of Release; inert unless
      // IS_TESTING + FORCE_DYNAMIC_TYPE are set). Sheet content does NOT inherit the root-level
      // override applied in the App body, so the ad-hoc localized-layout screenshot check
      // (scripts/translation-accessibility-size-check/) re-applies it here to reach Settings /
      // Add Expense / Add Budget at the forced size too.
      #if DEBUG
      .modifier(TestDynamicTypeOverride())
      #endif
    }
  }

  /// Rendered when a pushed route's UUID no longer resolves: pop it on appear.
  /// Intentionally blank (no copy) — the model vanished out from under the route,
  /// and returning to the previous screen mirrors what SwiftData-backed lists do.
  private var unresolvedPushDestination: some View {
    Color.clear
      .onAppear {
        if !router.path.isEmpty {
          router.path.removeLast()
        }
      }
  }

  /// Rendered when a sheet route's UUID no longer resolves: dismiss on appear.
  private var unresolvedSheetDestination: some View {
    Color.clear
      .onAppear {
        router.sheet = nil
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
