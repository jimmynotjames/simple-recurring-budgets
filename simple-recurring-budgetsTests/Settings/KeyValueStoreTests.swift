import Foundation
@testable import simple_recurring_budgets
import Testing

/// The `NSUbiquitousKeyValueStore: KeyValueStore` shim's `set(_:forKey:)` String overload must
/// store the value so `object(forKey:)` reads it back. The simulator store is a local cache,
/// so no iCloud account is needed.
@Suite("NSUbiquitousKeyValueStore KeyValueStore conformance")
struct KeyValueStoreTests {
  @Test func stringSetter_roundTripsThroughObjectForKey() {
    let store: KeyValueStore = NSUbiquitousKeyValueStore.default
    let key = "KeyValueStoreTests.stringRoundTrip"
    defer { store.removeObject(forKey: key) }

    store.set("wren", forKey: key)

    #expect(store.object(forKey: key) as? String == "wren")
  }
}
