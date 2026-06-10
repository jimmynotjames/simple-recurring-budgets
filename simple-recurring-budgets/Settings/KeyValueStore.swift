import Foundation

/// Subset of `NSUbiquitousKeyValueStore` used by `AppSettings`, for testing with an in-memory implementation.
protocol KeyValueStore: AnyObject {
  func object(forKey key: String) -> Any?
  func set(_ value: Bool, forKey defaultName: String)
  func set(_ value: Int64, forKey defaultName: String)
  func set(_ value: String, forKey defaultName: String)
  func removeObject(forKey defaultName: String)
  @discardableResult
  func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueStore {
  func set(_ value: String, forKey defaultName: String) {
    set(value as Any, forKey: defaultName)
  }
}

// The in-memory `MockKeyValueStore` test double lives in the test target
// (simple-recurring-budgetsTests/Helpers/MockKeyValueStore.swift) so it does
// not ship in the app binary.
