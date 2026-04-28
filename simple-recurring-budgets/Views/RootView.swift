//
//  RootView.swift
//  simple-recurring-budgets
//

import SwiftUI
import SwiftData

/// Root navigation host. Owns the `NavigationStack` path and the active sheet
/// via the environment-injected `Router`.
///
/// Replace placeholder `Text` bodies here as real screens are implemented:
/// - `.budgetDetail` destination → `BudgetView` (F-2.02)
/// - Sheet destinations → their respective screens (F-2.03, F-2.04, F-2.05)
struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            BudgetsView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .budgetDetail(let budget):
                        Text("Budget detail: \(budget.name)")
                    }
                }
        }
        .sheet(item: $router.sheet) { route in
            switch route {
            case .addBudget:
                Text("Add Budget")
            case .editBudget:
                Text("Edit Budget")
            case .addExpense:
                Text("Add Expense")
            case .viewExpense:
                Text("View Expense")
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
