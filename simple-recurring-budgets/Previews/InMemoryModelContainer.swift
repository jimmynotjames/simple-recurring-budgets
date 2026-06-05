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
    // swiftlint:disable:next force_try
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

    /// In-memory store for UI test launches. Two seeding channels, checked in order:
    ///
    /// 1. `SEED_SCREENSHOTS_JSON` — a full per-locale screenshot demo-content catalog
    ///    JSON (set by the `AppStoreScreenshots` UI test). Decoded via `ScreenshotSeed`
    ///    and used to seed culturally-tuned budgets/expenses for App Store screenshots.
    /// 2. `SEED_BUDGETS` — a comma-separated list of budget names (set by
    ///    `makeApp(seedBudgets:)` in UITestHelpers) → one monthly $100 budget each, so
    ///    journey tests skip UI creation.
    ///
    /// Returns an empty store when neither is present, matching the behaviour of tests
    /// that set up their own state through the UI.
    static func makeForUITests(now: Date = Date()) -> ModelContainer {
      let env = ProcessInfo.processInfo.environment
      if let json = env["SEED_SCREENSHOTS_JSON"], !json.isEmpty, let seed = ScreenshotSeed.decode(from: json) {
        let container = makeEmpty()
        seed.seed(into: container.mainContext, now: now)
        return container
      }
      guard let seedList = env["SEED_BUDGETS"], !seedList.isEmpty else {
        return makeEmpty()
      }
      let names = seedList.split(separator: ",").map(String.init).filter { !$0.isEmpty }
      return makeSeeded(budgetNames: names, now: now)
    }

    /// In-memory store pre-populated with one monthly $100 budget per name.
    /// Used by `makeForUITests()` and available directly in test helpers that
    /// need a seeded container without going through the env-var channel.
    static func makeSeeded(budgetNames names: [String], now: Date = Date()) -> ModelContainer {
      let container = makeEmpty()
      let startDate = Calendar.current.startOfDay(for: now)
      for name in names {
        let budget = Budget(name: name, period: .monthly)
        budget.startDate = startDate
        budget.sortOrder = (try? Budget.nextSortOrder(for: container.mainContext)) ?? 0
        let change = AllocationChange(effectiveFrom: startDate, amount: 100)
        change.budget = budget
        budget.allocationChangesStorage = [change]
        container.mainContext.insert(budget)
        container.mainContext.insert(change)
      }
      try? container.mainContext.save()
      return container
    }
  #endif
}
