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
    @State private var settings = AppSettings()

    var sharedModelContainer: ModelContainer = {
        let schema = SchemaV1.swiftDataSchema

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
                .environment(settings)
                .task {
                    try? await FirstRunSeeder.seedIfNeeded(
                        context: sharedModelContainer.mainContext,
                        store: NSUbiquitousKeyValueStore.default,
                        isCarryOverEnabled: settings.defaultCarryOverEnabled
                    )
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
