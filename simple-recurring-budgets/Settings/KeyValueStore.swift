//
//  KeyValueStore.swift
//  simple-recurring-budgets
//

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

/// In-memory store for unit tests (`NSUbiquitousKeyValueStore` cannot use a custom suite).
final class MockKeyValueStore: NSObject, KeyValueStore {
    private var storage: [String: Any] = [:]

    func object(forKey key: String) -> Any? {
        storage[key]
    }

    func set(_ value: Bool, forKey defaultName: String) {
        storage[defaultName] = value
    }

    func set(_ value: Int64, forKey defaultName: String) {
        storage[defaultName] = value
    }

    func set(_ value: String, forKey defaultName: String) {
        storage[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }

    func synchronize() -> Bool {
        true
    }

    /// Simulate another device writing before posting `didChangeExternallyNotification`.
    func seedExternal(bool value: Bool, forKey key: String) {
        storage[key] = value
    }

    func seedExternal(int64 value: Int64, forKey key: String) {
        storage[key] = value
    }

    func seedExternal(string value: String, forKey key: String) {
        storage[key] = value
    }
}
