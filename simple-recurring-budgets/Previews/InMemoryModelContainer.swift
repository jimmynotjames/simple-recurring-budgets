//
//  InMemoryModelContainer.swift
//  simple-recurring-budgets
//

import Foundation
import SwiftData

/// In-memory `ModelContainer` (CloudKit off). Used for previews, optional **manual** app-launch
/// overrides, and dev-only `DebugData` fixtures.
enum InMemoryModelContainer {

    /// Isolated in-memory store with **no** inserted models — for testing the first-run / empty
    /// `Budgets` list without touching disk or iCloud.
    static func makeEmpty() -> ModelContainer {
        let schema = SchemaV1.swiftDataSchema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        // Force-try: in-memory init without CloudKit should only fail on schema/migration bugs.
        return try! ModelContainer(
            for: schema,
            migrationPlan: BudgetMigrationPlan.self,
            configurations: config
        )
    }

    #if DEBUG
    /// In-memory store seeded with every fixture from `DebugData` (previews, manual testing).
    static func makeSeeded(now: Date = Date()) -> ModelContainer {
        let container = makeEmpty()
        DebugData.seed(into: container.mainContext, now: now)
        return container
    }
    #endif
}
