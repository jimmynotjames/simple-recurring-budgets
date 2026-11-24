@testable import simple_recurring_budgets
import SwiftData

/// Shared in-memory `ModelContainer` factory for SwiftData tests: each `make()` returns a
/// fresh, empty container with CloudKit disabled. Use it instead of per-file configurations.
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
