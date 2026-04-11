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
        let schema = Schema(SchemaV1.models)
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: BudgetMigrationPlan.self,
                configurations: modelConfiguration
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
