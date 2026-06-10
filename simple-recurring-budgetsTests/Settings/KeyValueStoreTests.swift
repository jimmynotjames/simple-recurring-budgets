import Foundation
@testable import simple_recurring_budgets
import Testing

/// Covers the `NSUbiquitousKeyValueStore: KeyValueStore` conformance shim —
/// specifically the `set(_:forKey:)` String overload, which must store the
/// value so `object(forKey:)` reads it back. On the simulator the store acts
/// as a local cache, so no iCloud account is required.
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
