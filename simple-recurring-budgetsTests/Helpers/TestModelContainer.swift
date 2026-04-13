//
//  TestModelContainer.swift
//  simple-recurring-budgetsTests
//

import SwiftData
@testable import simple_recurring_budgets

/// Shared factory for in-memory `ModelContainer` instances used across all SwiftData tests.
///
/// Using an in-memory store ensures test isolation: each `make()` call returns a fresh,
/// empty container with CloudKit sync disabled. Prefer this over copy-pasting the
/// configuration in individual test files.
enum TestModelContainer {
    /// Creates an isolated in-memory `ModelContainer` with CloudKit disabled.
    static func make() throws -> ModelContainer {
        let schema = SchemaV1.swiftDataSchema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: BudgetMigrationPlan.self,
            configurations: config
        )
    }
}
