//
//  simple_recurring_budgetsApp.swift
//  simple-recurring-budgets
//
//  Created by Jimmy Ho on 4/10/26.
//

import SwiftUI
import SwiftData

@main
struct simple_recurring_budgetsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Budget.self, ExpenseItem.self])

        // Try CloudKit-backed storage first. CloudKit requires an active iCloud account;
        // fall back to local-only storage when unavailable (e.g., Simulator without a
        // signed-in account, or offline first launch).
        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        if let container = try? ModelContainer(
            for: schema,
            migrationPlan: BudgetMigrationPlan.self,
            configurations: cloudConfig
        ) {
            return container
        }

        let localConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: BudgetMigrationPlan.self,
                configurations: localConfig
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
