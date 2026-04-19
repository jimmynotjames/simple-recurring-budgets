//
//  AppSettings.swift
//  simple-recurring-budgets
//

import Foundation
import Observation

@Observable
final class AppSettings {
    static let defaultCarryOverEnabledKey = "defaultCarryOverEnabled"
    static let weekStartDayKey = "weekStartDay"

    private let store: KeyValueStore
    private var isApplyingFromStore = false
    private var notificationObserver: NSObjectProtocol?

    var defaultCarryOverEnabled: Bool {
        didSet {
            guard !isApplyingFromStore else { return }
            store.set(defaultCarryOverEnabled, forKey: Self.defaultCarryOverEnabledKey)
            _ = store.synchronize()
        }
    }

    var weekStartDay: Weekday {
        didSet {
            guard !isApplyingFromStore else { return }
            store.set(Int64(weekStartDay.rawValue), forKey: Self.weekStartDayKey)
            _ = store.synchronize()
        }
    }

    init(store: KeyValueStore = NSUbiquitousKeyValueStore.default) {
        self.store = store
        self.defaultCarryOverEnabled = Self.readCarryOver(from: store)
        self.weekStartDay = Self.readWeekStart(from: store)

        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store as AnyObject?,
            queue: .main
        ) { [weak self] notification in
            // Extract only Sendable data ([String]?) before entering the
            // @MainActor assumeIsolated block. Notification itself is not
            // Sendable (its object: AnyObject? member prevents conformance).
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            // The observer is registered on .main queue, so we are already on
            // the main actor. assumeIsolated makes isolation visible to the
            // compiler without crossing any actor boundary.
            MainActor.assumeIsolated {
                self?.applyChangedKeys(changedKeys)
            }
        }
    }

    deinit {
        // deinit is nonisolated in Swift 6; use assumeIsolated since AppSettings is
        // always owned by @MainActor code and will be deallocated on the main thread.
        MainActor.assumeIsolated {
            if let notificationObserver {
                NotificationCenter.default.removeObserver(notificationObserver)
            }
        }
    }

    private func applyChangedKeys(_ changedKeys: [String]?) {
        guard let changedKeys else {
            reloadAllFromStore()
            return
        }
        applyKeys(Set(changedKeys))
    }

    private func reloadAllFromStore() {
        applyKeys(Set([Self.defaultCarryOverEnabledKey, Self.weekStartDayKey]))
    }

    private func applyKeys(_ keys: Set<String>) {
        isApplyingFromStore = true
        defer { isApplyingFromStore = false }

        if keys.contains(Self.defaultCarryOverEnabledKey) {
            defaultCarryOverEnabled = Self.readCarryOver(from: store)
        }
        if keys.contains(Self.weekStartDayKey) {
            weekStartDay = Self.readWeekStart(from: store)
        }
    }

    private static func readCarryOver(from store: KeyValueStore) -> Bool {
        guard let obj = store.object(forKey: defaultCarryOverEnabledKey) else {
            return true
        }
        if let b = obj as? Bool {
            return b
        }
        if let n = obj as? NSNumber {
            return n.boolValue
        }
        return true
    }

    private static func readWeekStart(from store: KeyValueStore) -> Weekday {
        let localeDefault = Weekday.from(calendarFirstWeekday: Calendar.current.firstWeekday) ?? .sunday

        guard let obj = store.object(forKey: weekStartDayKey) else {
            return localeDefault
        }

        let raw: Int?
        if let i = obj as? Int {
            raw = i
        } else if let n = obj as? NSNumber {
            raw = n.intValue
        } else {
            raw = nil
        }

        guard let raw, let weekday = Weekday(rawValue: raw) else {
            return localeDefault
        }
        return weekday
    }
}
