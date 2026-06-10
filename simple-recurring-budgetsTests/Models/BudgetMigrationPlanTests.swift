import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Sanity check for the migration harness (test-coverage-audit-2026-06-10 B2):
/// a SchemaV1 store written to disk re-opens through `BudgetMigrationPlan` with
/// every row and relationship intact. With `stages` empty this pins the
/// identity round-trip; the first real SchemaV2 migration test should copy
/// this shape via `MigrationTestSupport`.
@Suite("BudgetMigrationPlan — SchemaV1 store round-trip")
@MainActor
struct BudgetMigrationPlanTests {
  @Test func schemaV1Store_reopensThroughMigrationPlan_withRowsIntact() throws {
    try MigrationTestSupport.withTemporaryStoreURL { url in
      let now = Date()
      try MigrationTestSupport.writeSchemaV1Fixture(at: url, now: now)

      let container = try MigrationTestSupport.openThroughMigrationPlan(at: url)
      let context = ModelContext(container)

      let budgets = try context.fetch(FetchDescriptor<Budget>())
      let budget = try #require(budgets.first)
      #expect(budgets.count == 1)
      #expect(budget.name == "Migrated")

      let expenses = try context.fetch(FetchDescriptor<ExpenseItem>())
      #expect(expenses.count == 1)
      #expect(expenses.first?.amount == 12.50)
      #expect(expenses.first?.budget?.name == "Migrated")

      let changes = try context.fetch(FetchDescriptor<AllocationChange>())
      #expect(changes.count == 1)
      #expect(changes.first?.amount == 100)

      let events = try context.fetch(FetchDescriptor<LifecycleEvent>())
      #expect(events.count == 1)
      #expect(events.first?.kind == .pause)
    }
  }
}
