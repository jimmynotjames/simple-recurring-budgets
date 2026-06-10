import Foundation

/// Persisted eligibility signals for the automatic App Store review prompt (F-6.03).
///
/// Backed by the iCloud key-value store through the shared `KeyValueStore`
/// abstraction, so the counters sync across the user's devices and are unit-testable
/// with the test target's in-memory `KeyValueStore` double. **Independent of analytics
/// consent** — these signals
/// drive prompt eligibility and must work for users who declined analytics. They
/// deliberately do **not** reuse `AppSettings.analyticsFirstOpenAt` (analytics state).
///
/// Dates are stored as the `timeIntervalSinceReferenceDate` string and counts as
/// `Int64`, mirroring the `AppSettings` persistence convention.
final class RatingPromptState {
  static let installedAtKey = "ratingPromptInstalledAt"
  static let loggedExpenseCountKey = "ratingPromptLoggedExpenseCount"
  static let distinctLogDayCountKey = "ratingPromptDistinctLogDayCount"
  static let lastLogDayStartKey = "ratingPromptLastLogDayStart"
  static let firstEligibleAtKey = "ratingPromptFirstEligibleAt"
  static let lastRequestedVersionKey = "ratingPromptLastRequestedVersion"

  private let store: KeyValueStore

  /// First-launch timestamp. Stamped once on first init with a fresh store; never updated.
  let installedAt: Date

  init(store: KeyValueStore = NSUbiquitousKeyValueStore.default) {
    self.store = store
    installedAt = Self.readOrCreateInstalledAt(from: store)
  }

  /// Lifetime count of successful Add-mode expense logs.
  var loggedExpenseCount: Int {
    get { Self.readInt(store, Self.loggedExpenseCountKey) }
    set {
      store.set(Int64(newValue), forKey: Self.loggedExpenseCountKey)
      _ = store.synchronize()
    }
  }

  /// Count of distinct calendar days on which an expense was logged.
  var distinctLogDayCount: Int {
    get { Self.readInt(store, Self.distinctLogDayCountKey) }
    set {
      store.set(Int64(newValue), forKey: Self.distinctLogDayCountKey)
      _ = store.synchronize()
    }
  }

  /// Start-of-day of the most recent logging day, used to detect a new distinct day.
  var lastLogDayStart: Date? {
    get { Self.readDate(store, Self.lastLogDayStartKey) }
    set { Self.writeDate(store, Self.lastLogDayStartKey, newValue) }
  }

  /// Timestamp the eligibility thresholds were first met (one-shot gate for the
  /// `rating_prompt_eligible` event).
  var firstEligibleAt: Date? {
    get { Self.readDate(store, Self.firstEligibleAtKey) }
    set { Self.writeDate(store, Self.firstEligibleAtKey, newValue) }
  }

  /// The app version (`CFBundleShortVersionString`) for which a review was last
  /// requested. The once-per-version guard.
  var lastRequestedVersion: String? {
    get { store.object(forKey: Self.lastRequestedVersionKey) as? String }
    set {
      if let newValue {
        store.set(newValue, forKey: Self.lastRequestedVersionKey)
      } else {
        store.removeObject(forKey: Self.lastRequestedVersionKey)
      }
      _ = store.synchronize()
    }
  }

  // MARK: - Private helpers

  private static func readInt(_ store: KeyValueStore, _ key: String) -> Int {
    switch store.object(forKey: key) {
    case let n as Int64: Int(n)
    case let n as Int: n
    case let n as NSNumber: n.intValue
    default: 0
    }
  }

  private static func readDate(_ store: KeyValueStore, _ key: String) -> Date? {
    guard let raw = store.object(forKey: key) as? String, let ti = TimeInterval(raw) else {
      return nil
    }
    return Date(timeIntervalSinceReferenceDate: ti)
  }

  private static func writeDate(_ store: KeyValueStore, _ key: String, _ date: Date?) {
    if let date {
      store.set(date.timeIntervalSinceReferenceDate.description, forKey: key)
    } else {
      store.removeObject(forKey: key)
    }
    _ = store.synchronize()
  }

  private static func readOrCreateInstalledAt(from store: KeyValueStore) -> Date {
    if let existing = readDate(store, installedAtKey) {
      return existing
    }
    let now = Date()
    store.set(now.timeIntervalSinceReferenceDate.description, forKey: installedAtKey)
    _ = store.synchronize()
    return now
  }
}
