@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Top-level smoke test for the test target (replaces the Xcode template placeholder).
struct simple_recurring_budgetsTests {
  /// The SchemaV1 schema loads into a container and accepts a trivial fetch.
  @Test func schemaLoads() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budgets = try context.fetch(FetchDescriptor<Budget>())
    #expect(budgets.isEmpty)
  }
}
