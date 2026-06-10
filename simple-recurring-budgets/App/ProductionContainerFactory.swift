import OSLog
import SwiftData

/// Builds the production persistence stack: CloudKit-backed when possible,
/// local on-disk fallback otherwise. Extracted from
/// `simple_recurring_budgetsApp` so the branch selection is unit-testable
/// (test-coverage-audit-2026-06-10 B1): the real `ModelContainer` initializers
/// cannot be made to fail deterministically in tests, so `make` takes the two
/// container factories as injectable closures that default to the real inits.
enum ProductionContainerFactory {
  typealias MakeContainer = @MainActor (ModelConfiguration) throws -> ModelContainer

  /// CloudKit if available, else local on disk. Returns the container and the
  /// `SyncStatus.ContainerBacking` that reflects which path was taken
  /// (`.cloudKit` or `.localFallback`). Throws when both paths fail —
  /// `AppStartup` catches and presents `ContainerFailureView`.
  static func make(
    cloud: MakeContainer = realContainer,
    local: MakeContainer = realContainer
  ) throws -> (ModelContainer, SyncStatus.ContainerBacking) {
    let schema = SchemaV1.swiftDataSchema

    // Anchor both the CloudKit-enabled and local-only configurations to a single
    // explicit on-disk store URL. Without this, the two configurations rely on
    // SwiftData's *implicit* default store path; if those paths ever diverged
    // (the "split-brain" risk in issue #1), an offline first launch would write
    // to one file and a later online launch would open a different, empty file,
    // making the user's first-session data appear to vanish. Asking SwiftData
    // for the default configuration's own `url` (rather than hardcoding a path)
    // guarantees we pin to the exact location existing installs already use, so
    // both configurations resolve to the same file across launches — only the
    // CloudKit mirroring differs.
    let storeURL = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false).url

    // Try CloudKit-backed storage first. CloudKit requires an active iCloud account;
    // fall back to local-only storage when unavailable (e.g., Simulator without a
    // signed-in account, or offline first launch). Both paths share `storeURL`, so
    // the local-only store is promoted to CloudKit-backed in place once iCloud
    // becomes available — no data is stranded in a forked store.
    let cloudConfig = ModelConfiguration(
      schema: schema,
      url: storeURL,
      cloudKitDatabase: .automatic
    )
    if let container = try? cloud(cloudConfig) {
      Logger.cloudKit.info("cloudkit.container.backed")
      return (container, .cloudKit)
    }

    Logger.cloudKit.notice("cloudkit.container.localFallback")

    let localConfig = ModelConfiguration(
      schema: schema,
      url: storeURL,
      cloudKitDatabase: .none
    )
    do {
      let container = try local(localConfig)
      Logger.cloudKit.info("cloudkit.container.localSuccess")
      return (container, .localFallback)
    } catch {
      // Both creation paths failed. Log the diagnostic per the
      // `diagnostic-logging` capability, then surface the error to
      // `AppStartup` instead of crashing — `ContainerFailureView` presents
      // Retry + Send Feedback. See `container-creation-recovery` spec.
      Logger.cloudKit.error("cloudkit.container.failed: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }

  /// The real `ModelContainer` initializer both closures default to.
  static func realContainer(for config: ModelConfiguration) throws -> ModelContainer {
    try ModelContainer(
      for: SchemaV1.swiftDataSchema,
      migrationPlan: BudgetMigrationPlan.self,
      configurations: config
    )
  }
}
