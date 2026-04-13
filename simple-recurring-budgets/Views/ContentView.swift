//
//  ContentView.swift
//  simple-recurring-budgets
//
//  Created by Jimmy Ho on 4/10/26.
//

import SwiftUI

/// Root navigation host. Owns the `NavigationStack` path and the active sheet.
///
/// Replace placeholder `Text` bodies here as real screens are implemented:
/// - Budgets list root → `BudgetsView` (F-2.01)
/// - `.budgetDetail` destination → `BudgetView` (F-2.02)
/// - Sheet destinations → their respective screens (F-2.03, F-2.04, F-2.05)
struct ContentView: View {
    @State private var path: [AppRoute] = []
    @State private var sheet: SheetRoute? = nil

    var body: some View {
        NavigationStack(path: $path) {
            Text("Budgets screen placeholder")
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .budgetDetail(let budget):
                        Text("Budget detail: \(budget.name)")
                    }
                }
        }
        .sheet(item: $sheet) { route in
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
                Text("Settings")
            }
        }
    }
}

#Preview {
    ContentView()
}
