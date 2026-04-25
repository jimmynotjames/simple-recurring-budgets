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
    @State private var settings: AppSettings
    @State private var router = Router()
    private let analytics: any AnalyticsClient
    var sharedModelContainer: ModelContainer

    init() {
        let client = ConsoleAnalyticsClient()
        self.analytics = client
        self.sharedModelContainer = Self.makeModelContainer(analytics: client)
        self._settings = State(initialValue: AppSettings())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(settings)
                .environment(\.analytics, analytics)
                .task {
                    analytics.track(AnalyticsEvent.appLaunched)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - Private

    /// Creates the SwiftData `ModelContainer`, preferring CloudKit-backed storage
    /// and falling back to local-only when CloudKit is unavailable. All outcomes
    /// are reported through `analytics` so every event travels the same code path.
    private static func makeModelContainer(analytics: any AnalyticsClient) -> ModelContainer {
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
            analytics.track(AnalyticsEvent.cloudKitContainerBacked, channel: .cloudKit)
            return container
        }

        analytics.track(AnalyticsEvent.cloudKitContainerLocalFallback, channel: .cloudKit, level: .notice)

        let localConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: BudgetMigrationPlan.self,
                configurations: localConfig
            )
            analytics.track(AnalyticsEvent.cloudKitContainerLocalSuccess, channel: .cloudKit)
            return container
        } catch {
            analytics.track(
                AnalyticsEvent.cloudKitContainerFailed,
                channel: .cloudKit,
                level: .error,
                properties: ["error": error.localizedDescription]
            )
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
