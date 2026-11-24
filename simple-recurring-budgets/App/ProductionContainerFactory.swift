import OSLog
import SwiftData

/// Builds the production persistence stack: CloudKit-backed when possible, else local on disk. Separate
/// from the App so branch selection is unit-testable: `make` takes the two container factories as
/// injectable closures (defaulting to the real inits) because real `ModelContainer` inits can't be made
/// to fail deterministically.
enum ProductionContainerFactory {
  typealias MakeContainer = @MainActor (ModelConfiguration) throws -> ModelContainer

  /// CloudKit if available, else local on disk. Returns the container and the matching
  /// `SyncStatus.ContainerBacking`. Throws when both fail; `AppStartup` catches and shows `ContainerFailureView`.
  static func make(
    cloud: MakeContainer = realContainer,
    local: MakeContainer = realContainer
  ) throws -> (ModelContainer, SyncStatus.ContainerBacking) {
    let schema = SchemaV1.swiftDataSchema

    // Pin both configurations to one explicit on-disk store URL. Relying on SwiftData's implicit default path
    // risks a "split-brain": an offline first launch writes one file and a later online launch opens a
    // different, empty one, so first-session data appears to vanish. Taking the default configuration's own
    // `url` (not a hardcoded path) pins to the location existing installs already use; only CloudKit
    // mirroring differs.
    let storeURL = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false).url

    // Try CloudKit first (needs an active iCloud account); fall back to local-only (e.g. Simulator without
    // iCloud, offline first launch). Both share `storeURL`, so the local store is promoted to CloudKit in
    // place once iCloud is available.
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
      // Both paths failed: log, then surface to `AppStartup` instead of crashing.
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
