import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Persistent store URL stability

/// Guards the single-store invariant behind issue #1 ("Possible DB forking on
/// first-time launch if not connected").
///
/// `makeProductionModelContainer` builds two on-disk configurations from one
/// shared `storeURL` — a CloudKit-enabled config tried first, and a local-only
/// fallback. The fix's correctness depends on a `ModelConfiguration`'s on-disk
/// `url` being independent of its `cloudKitDatabase` setting: only then can the
/// offline-first store be promoted to CloudKit-backed in place rather than
/// forking into a second, empty file. These tests pin that SwiftData behavior so
/// a future regression surfaces here instead of as silent data loss on device.
struct PersistentStoreURLTests {
  /// The default (implicit-URL) configuration exposes a concrete on-disk URL we
  /// can anchor both real configurations to.
  @Test func defaultConfigurationExposesStableURL() {
    let schema = SchemaV1.swiftDataSchema
    let first = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    let second = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    #expect(first.url == second.url)
  }

  /// Pinning the same explicit `url` yields the same store file regardless of
  /// whether CloudKit mirroring is enabled — the core guarantee that prevents
  /// the offline→online launch from forking the database.
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
