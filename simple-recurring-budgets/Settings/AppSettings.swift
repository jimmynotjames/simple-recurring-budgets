import Foundation
import Observation

@Observable
final class AppSettings {
  static let defaultCarryOverEnabledKey = "defaultCarryOverEnabled"
  static let weekStartDayKey = "weekStartDay"
  static let currencyDisplayKey = "currencyDisplay"
  static let analyticsOptInKey = "analyticsOptIn"
  static let analyticsDistinctIdKey = "analyticsDistinctId"
  static let analyticsFirstOpenAtKey = "analyticsFirstOpenAt"

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

  var currencyDisplay: CurrencyDisplayPreference {
    didSet {
      guard !isApplyingFromStore else { return }
      store.set(currencyDisplay.rawValue, forKey: Self.currencyDisplayKey)
      _ = store.synchronize()
    }
  }

  /// Whether the user has opted in to product analytics (Mixpanel).
  ///
  /// The **default is locale-aware**: in strict-opt-in jurisdictions (§7.2) the
  /// default resolves to `false`; in auto-opt-in jurisdictions it resolves to
  /// `true`. The resolved default is **not** written to the backing store —
  /// persistence happens only on an explicit write (Settings toggle or first-run
  /// consent sheet decision). `@Observable` change notifications emit on every write.
  var analyticsOptIn: Bool {
    didSet {
      guard !isApplyingFromStore else { return }
      store.set(analyticsOptIn, forKey: Self.analyticsOptInKey)
      _ = store.synchronize()
    }
  }

  /// `true` iff the backing store contains an explicit value for `"analyticsOptIn"`.
  ///
  /// Consumed by the first-run consent-sheet trigger: `false` means the user has
  /// never made a consent decision and the sheet should appear in strict-opt-in
  /// jurisdictions after the first Budget is created.
  var analyticsOptInExplicitlySet: Bool {
    store.object(forKey: Self.analyticsOptInKey) != nil
  }

  /// The timestamp of the app's first launch, used to compute
  /// `time_since_first_app_open_bucket` on `budget_created` where `is_first_budget = true`
  /// (§10.1 analytics-spec.md). Generated and persisted on first access; never updated.
  private(set) var analyticsFirstOpenAt: Date {
    didSet {
      guard !isApplyingFromStore else { return }
      store.set(analyticsFirstOpenAt.timeIntervalSinceReferenceDate.description, forKey: Self.analyticsFirstOpenAtKey)
      _ = store.synchronize()
    }
  }

  /// A stable UUIDv4 string used as the Mixpanel `distinct_id`.
  ///
  /// On first init with a fresh store a new UUID is generated, written to the
  /// backing store, and returned. Subsequent reads return the stored value.
  /// The setter is `private(set)` — external callers must not rotate the ID;
  /// `MixpanelAnalyticsClient.reset()` handles the SDK side.
  private(set) var analyticsDistinctId: String {
    didSet {
      guard !isApplyingFromStore else { return }
      store.set(analyticsDistinctId, forKey: Self.analyticsDistinctIdKey)
      _ = store.synchronize()
    }
  }

  init(store: KeyValueStore = NSUbiquitousKeyValueStore.default) {
    self.store = store
    defaultCarryOverEnabled = Self.readCarryOver(from: store)
    weekStartDay = Self.readWeekStart(from: store)
    currencyDisplay = Self.readCurrencyDisplay(from: store)
    // Locale-aware default; absent from store → NOT persisted (init doesn't trigger didSet).
    analyticsOptIn = Self.readAnalyticsOptIn(from: store)
    // Generates + persists a UUID if the store has no value yet.
    analyticsDistinctId = Self.readOrCreateDistinctId(from: store)
    // Records first launch timestamp; generated once, never updated.
    analyticsFirstOpenAt = Self.readOrCreateFirstOpenAt(from: store)

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
    applyKeys(Set([
      Self.defaultCarryOverEnabledKey,
      Self.weekStartDayKey,
      Self.currencyDisplayKey,
      Self.analyticsOptInKey,
      Self.analyticsDistinctIdKey,
      Self.analyticsFirstOpenAtKey,
    ]))
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
    if keys.contains(Self.currencyDisplayKey) {
      currencyDisplay = Self.readCurrencyDisplay(from: store)
    }
    if keys.contains(Self.analyticsOptInKey) {
      analyticsOptIn = Self.readAnalyticsOptIn(from: store)
    }
    if keys.contains(Self.analyticsDistinctIdKey) {
      analyticsDistinctId = Self.readOrCreateDistinctId(from: store)
    }
    if keys.contains(Self.analyticsFirstOpenAtKey) {
      analyticsFirstOpenAt = Self.readOrCreateFirstOpenAt(from: store)
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

  private static func readCurrencyDisplay(from store: KeyValueStore) -> CurrencyDisplayPreference {
    guard let raw = store.object(forKey: currencyDisplayKey) as? String else {
      return .symbol
    }
    return CurrencyDisplayPreference(rawValue: raw) ?? .symbol
  }

  private static func readWeekStart(from store: KeyValueStore) -> Weekday {
    let localeDefault = Weekday.from(calendarFirstWeekday: Calendar.current.firstWeekday) ?? .sunday

    guard let obj = store.object(forKey: weekStartDayKey) else {
      return localeDefault
    }

    let raw: Int? = if let i = obj as? Int {
      i
    } else if let n = obj as? NSNumber {
      n.intValue
    } else {
      nil
    }

    guard let raw, let weekday = Weekday(rawValue: raw) else {
      return localeDefault
    }
    return weekday
  }

  /// Reads `analyticsOptIn` from the store, falling back to a locale-aware default
  /// if no value has been persisted. The default is NOT written to the store.
  private static func readAnalyticsOptIn(from store: KeyValueStore) -> Bool {
    guard let obj = store.object(forKey: analyticsOptInKey) else {
      let regionId = Locale.current.region?.identifier
      return ConsentJurisdiction.kind(for: regionId) == .autoOptin
    }
    if let b = obj as? Bool { return b }
    if let n = obj as? NSNumber { return n.boolValue }
    let regionId = Locale.current.region?.identifier
    return ConsentJurisdiction.kind(for: regionId) == .autoOptin
  }

  /// Reads the stored `analyticsDistinctId`. If absent, generates a new UUIDv4,
  /// persists it immediately (so the same ID is returned on subsequent reads), and
  /// returns it.
  private static func readOrCreateDistinctId(from store: KeyValueStore) -> String {
    if let existing = store.object(forKey: analyticsDistinctIdKey) as? String, !existing.isEmpty {
      return existing
    }
    let newId = UUID().uuidString
    store.set(newId, forKey: analyticsDistinctIdKey)
    _ = store.synchronize()
    return newId
  }

  /// Reads the stored first-open timestamp. If absent, records `Date.now`,
  /// persists it immediately, and returns it.
  private static func readOrCreateFirstOpenAt(from store: KeyValueStore) -> Date {
    if let raw = store.object(forKey: analyticsFirstOpenAtKey) as? String, let ti = TimeInterval(raw) {
      return Date(timeIntervalSinceReferenceDate: ti)
    }
    let now = Date()
    store.set(now.timeIntervalSinceReferenceDate.description, forKey: analyticsFirstOpenAtKey)
    _ = store.synchronize()
    return now
  }
}
