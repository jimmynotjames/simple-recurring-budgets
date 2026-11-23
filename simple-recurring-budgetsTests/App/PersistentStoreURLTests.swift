import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Persistent store URL stability

/// Guards the single-store invariant (no DB forking on first launch while offline).
///
/// `makeProductionModelContainer` builds a CloudKit-enabled config (tried first) and a
/// local-only fallback from one shared `storeURL`. That only works if a `ModelConfiguration`'s
/// on-disk `url` is independent of its `cloudKitDatabase`, so an offline-first store is
/// promoted to CloudKit in place instead of forking into a second, empty file. Pinned here so
/// a regression isn't silent data loss on device.
struct PersistentStoreURLTests {
  /// The default (implicit-URL) configuration exposes a concrete URL to anchor both configurations to.
  @Test func defaultConfigurationExposesStableURL() {
    let schema = SchemaV1.swiftDataSchema
    let first = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    let second = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    #expect(first.url == second.url)
  }

  /// The same explicit `url` yields the same store file whether or not CloudKit mirroring is
  /// enabled; this prevents an offline→online launch from forking the database.
  @Test func cloudAndLocalConfigsShareStoreURLWhenPinned() {
    let schema = SchemaV1.swiftDataSchema
    let storeURL = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false).url

    let cloud = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .automatic)
    let local = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)

    #expect(cloud.url == storeURL)
    #expect(local.url == storeURL)
    #expect(cloud.url == local.url)
  }
}
