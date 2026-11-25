import SwiftData
import SwiftUI

/// Root navigation host: owns the `NavigationStack` path and active sheet via `Router`.
///
/// Routes carry stable `UUID`s (`AppRoute` / `SheetRoute`) resolved through
/// `ModelContext.budget(id:)` / `.expenseItem(id:)`. If one no longer resolves (model
/// deleted, e.g. on another device), the route is silently popped/dismissed.
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
    // Brand tint for the whole stack. It does NOT color the system back chevron: iOS 26
    // Liquid Glass renders it monochrome and no supported API (global accent,
    // UINavigationBar appearance, environment tint) changes it; don't retry (#297). The
    // concrete asset color, not the dynamic `.accentColor`, is deliberate: UIKit-hosted
    // surfaces resolve the dynamic accent to system blue. The bleed into the
    // budget-options menu is neutralized at that Menu (BudgetDetailView), not by
    // scoping the tint per screen.
    .tint(Color("AccentColor"))
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
      // Sheet content doesn't inherit the stack-level tint above (same isolation as
      // TestDynamicTypeOverride below), so re-apply it.
      .tint(Color("AccentColor"))
      // DEBUG-only test Dynamic Type override (inert unless IS_TESTING + FORCE_DYNAMIC_TYPE
      // are set). Sheets don't inherit the root-level override from the App body, so it's
      // re-applied here for scripts/translation-accessibility-size-check/ to reach Settings /
      // Add Expense / Add Budget at the forced size. The CI animations override is re-applied
      // for the same reason (inert unless UI_TESTS + FORCE_ANIMATIONS=off are set).
      #if DEBUG
        .modifier(TestDynamicTypeOverride())
        .modifier(TestAnimationsOverride.Modifier())
      #endif
    }
  }

  /// Pops on appear when a pushed route's UUID no longer resolves. Blank on purpose: the
  /// model vanished, and returning to the previous screen mirrors SwiftData-backed lists.
  private var unresolvedPushDestination: some View {
    Color.clear
      .onAppear {
        if !router.path.isEmpty {
          router.path.removeLast()
        }
      }
  }

  /// Dismisses on appear when a sheet route's UUID no longer resolves.
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
