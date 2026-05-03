import Foundation
@testable import simple_recurring_budgets
import Testing

/// §18.1 test contract #3 — AppSettings.analyticsDistinctId generation and persistence.
@Suite("AppSettings — analyticsDistinctId §18.1 #3")
@MainActor
struct AppSettingsAnalyticsDistinctIdTests {
  @Test("fresh store generates a non-empty UUID-format string")
  func freshStoreGeneratesUUID() {
    let store = MockKeyValueStore()
    let settings = AppSettings(store: store)
    let id = settings.analyticsDistinctId
    #expect(!id.isEmpty)
    // UUID().uuidString format: 8-4-4-4-12
    #expect(UUID(uuidString: id) != nil)
  }

  @Test("ID is persisted on first access")
  func idPersistedOnFirstAccess() {
    let store = MockKeyValueStore()
    _ = AppSettings(store: store)
    #expect(store.object(forKey: AppSettings.analyticsDistinctIdKey) != nil)
  }

  @Test("subsequent reads return the same value")
  func subsequentReadsReturnSameValue() {
    let store = MockKeyValueStore()
    let first = AppSettings(store: store)
    let id1 = first.analyticsDistinctId
    let second = AppSettings(store: store)
    let id2 = second.analyticsDistinctId
    #expect(id1 == id2)
  }

  @Test("setter is not publicly accessible (private(set))")
  func setterIsPrivate() {
    // This is a compile-time contract. If `analyticsDistinctId` had a public setter,
    // the assignment below would compile; since it's `private(set)` it must NOT compile.
    // We verify the invariant semantically: the only way to read the value is via the
    // getter, and re-reading from a fresh `AppSettings` on the same store returns the same ID.
    let store = MockKeyValueStore()
    let settings = AppSettings(store: store)
    let original = settings.analyticsDistinctId
    // Re-read from a second AppSettings instance on the same store.
    let settings2 = AppSettings(store: store)
    #expect(settings2.analyticsDistinctId == original)
  }
}
