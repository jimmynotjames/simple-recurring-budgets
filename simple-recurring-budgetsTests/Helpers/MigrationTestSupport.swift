import Foundation
@testable import simple_recurring_budgets
import SwiftData

/// Fixture harness for SwiftData schema-migration tests: write a store with the *source*
/// schema at a temp URL, release the container, re-open the URL through `BudgetMigrationPlan`
/// with the *current* schema, and assert the rows survived. While `stages` is empty this is
/// a round-trip sanity check; a SchemaV2 test copies this shape with `writeSchemaV1Fixture`
/// as the old-store writer.
enum MigrationTestSupport {
  /// Runs `body` with a store URL in a fresh temp directory, removed afterwards (with -wal/-shm).
  static func withTemporaryStoreURL<T>(_ body: (URL) throws -> T) throws -> T {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("migration-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir.appendingPathComponent("store.sqlite"))
  }

  /// Writes a SchemaV1 store at `url` (one budget with one expense, allocation change, and
  /// lifecycle event), then releases the container so the file can be re-opened.
  static func writeSchemaV1Fixture(at url: URL, now: Date = Date()) throws {
    let container = try makeContainer(at: url)
    let context = ModelContext(container)

    let budget = Budget(name: "Migrated", period: .monthly)
    budget.startDate = now
    context.insert(budget)

    let expense = ExpenseItem(amount: 12.50, name: "Fixture expense", date: now)
    expense.budget = budget
    context.insert(expense)

    let change = AllocationChange(effectiveFrom: now, amount: 100)
    change.budget = budget
    context.insert(change)

    let event = LifecycleEvent(kind: .pause, effectiveDate: now)
    event.budget = budget
    context.insert(event)

    try context.save()
    // `container` goes out of scope here, releasing the file handles.
  }

  /// Opens the store at `url` through `BudgetMigrationPlan` with the current schema, as
  /// `ProductionContainerFactory` does minus CloudKit.
  static func openThroughMigrationPlan(at url: URL) throws -> ModelContainer {
    try makeContainer(at: url)
  }

  private static func makeContainer(at url: URL) throws -> ModelContainer {
    let schema = SchemaV1.swiftDataSchema
    let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    return try ModelContainer(
      for: schema,
      migrationPlan: BudgetMigrationPlan.self,
      configurations: config
    )
  }
}
