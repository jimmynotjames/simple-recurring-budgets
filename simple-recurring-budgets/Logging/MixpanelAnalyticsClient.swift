import Foundation
import Mixpanel
import OSLog
import SwiftData
import UIKit

// MARK: - BudgetCohortInfo

/// A `Sendable` snapshot of the Budget properties needed to compute cohort
/// people-properties (§10.3). Callers build this from their `Budget` model
/// objects and pass it into `refreshCohortPeopleProperties(budgets:)`.
struct BudgetCohortInfo {
  let currencyCode: String
  let periodRawValue: String
  let isCarryOverEnabled: Bool
}

// MARK: - MixpanelAnalyticsClient

/// Production `AnalyticsClient` backed by the Mixpanel SDK.
///
/// **Lazy init contract (§2.1.8 / §8):** `Mixpanel.initialize` is NOT called
/// in `init`. The SDK is created the first time `isOptedIn()` returns `true`
/// and a `track` or `identify` call arrives. Opted-out launches never create
/// a `MixpanelInstance` and never open a network connection.
///
/// Thread safety: `@unchecked Sendable` — all access to the `MixpanelInstance`
/// cell is serialised through `instanceLock`.
final class MixpanelAnalyticsClient: AnalyticsClient, @unchecked Sendable {
  // MARK: - Stored closures

  private let token: String
  private let isOptedIn: @Sendable () -> Bool
  private let distinctIdProvider: @Sendable () -> String?

  // Dynamic super-property sources (§10.2)
  private let weekStartDayProvider: @Sendable () -> String
  private let currencyDisplayProvider: @Sendable () -> String
  private let carryOverDefaultProvider: @Sendable () -> Bool
  private let syncStateProvider: @Sendable () -> String
  private let budgetsCountProvider: @Sendable () -> Int

  // MARK: - Lazy-init cell

  /// Serialises all reads and writes to `_instance`.
  private let instanceLock = NSLock()
  /// The lazily-created SDK instance. Nil until the first opted-in track call.
  /// `nonisolated(unsafe)` because access is serialised by `instanceLock`.
  nonisolated(unsafe) private var _instance: MixpanelInstance?

  // MARK: - Init

  /// Creates a client. The Mixpanel SDK is NOT initialised here.
  ///
  /// - Parameters:
  ///   - token: Mixpanel project token (`#if DEBUG` dev token or Release prod token).
  ///   - isOptedIn: Called on every `track` / `identify`; returns `false` → event dropped.
  ///   - distinctIdProvider: Returns the stable `analyticsDistinctId` from `AppSettings`.
  ///   - weekStartDayProvider: Returns the localised weekday string for the super property.
  ///   - currencyDisplayProvider: Returns the currency-display preference string.
  ///   - carryOverDefaultProvider: Returns the default carry-over toggle value.
  ///   - syncStateProvider: Returns a string representation of `SyncStatus.rowState`.
  ///   - budgetsCountProvider: Returns the current number of user Budgets.
  init(
    token: String,
    isOptedIn: @escaping @Sendable () -> Bool,
    distinctIdProvider: @escaping @Sendable () -> String?,
    weekStartDayProvider: @escaping @Sendable () -> String,
    currencyDisplayProvider: @escaping @Sendable () -> String,
    carryOverDefaultProvider: @escaping @Sendable () -> Bool,
    syncStateProvider: @escaping @Sendable () -> String,
    budgetsCountProvider: @escaping @Sendable () -> Int
  ) {
    self.token = token
    self.isOptedIn = isOptedIn
    self.distinctIdProvider = distinctIdProvider
    self.weekStartDayProvider = weekStartDayProvider
    self.currencyDisplayProvider = currencyDisplayProvider
    self.carryOverDefaultProvider = carryOverDefaultProvider
    self.syncStateProvider = syncStateProvider
    self.budgetsCountProvider = budgetsCountProvider
  }

  // MARK: - AnalyticsClient

  nonisolated func track(_ event: String, properties: [String: any Sendable]?) {
    guard isOptedIn() else { return }
    let instance = ensureInitialized()
    if event == AnalyticsEvent.appOpened {
      instance.people.set(properties: [AnalyticsProperty.lastAppOpenAt: Date()])
    }
    let mixProps = properties?.compactMapValues { $0 as? MixpanelType }
    instance.track(event: event, properties: mixProps)
  }

  nonisolated func identify(_ distinctId: String?) {
    guard isOptedIn() else { return }
    let instance = ensureInitialized()
    if let id = distinctId {
      instance.identify(distinctId: id)
    }
  }

  nonisolated func reset() {
    instanceLock.lock()
    _instance?.reset()
    _instance = nil
    instanceLock.unlock()
  }

  // MARK: - Concrete-type refresh methods (not on protocol)

  /// Re-registers the §10.2 super properties on the live `MixpanelInstance`.
  ///
  /// Call after any write to `AppSettings` that affects a super-property value
  /// (`week_start_day`, `currency_display_preference`, `carry_over_default_enabled`,
  /// `icloud_state`) or after a `budget_*` event changes `budgets_count_bucket`.
  /// No-op if the SDK has not yet been lazily initialised.
  nonisolated func refreshSuperProperties() {
    guard let instance = currentInstance() else { return }
    registerSuperProperties(on: instance)
  }

  /// Recomputes and persists §10.3 cohort people-properties from the current
  /// Budget collection. Must be called from the main actor (ViewModels are fine).
  ///
  /// Call immediately after `analytics.track("budget_created" / "budget_edited" /
  /// "budget_deleted")` so Mixpanel People stays in sync with the current state.
  nonisolated func refreshCohortPeopleProperties(budgets: [BudgetCohortInfo]) {
    guard let instance = currentInstance() else { return }
    setCohortPeopleProperties(on: instance, budgets: budgets)
  }

  // MARK: - Private: lazy init

  @discardableResult
  nonisolated private func ensureInitialized() -> MixpanelInstance {
    instanceLock.lock()
    if let existing = _instance {
      instanceLock.unlock()
      return existing
    }
    // First opted-in call — initialize the SDK.
    let newInstance = Mixpanel.initialize(token: token, trackAutomaticEvents: false)
    // Conservative flush batch size per §16 Low Data Mode guidance.
    newInstance.flushBatchSize = 50
    registerSuperProperties(on: newInstance)
    if let distinctId = distinctIdProvider() {
      newInstance.identify(distinctId: distinctId)
      setBaselinePeopleProperties(on: newInstance)
    }
    _instance = newInstance
    instanceLock.unlock()
    return newInstance
  }

  nonisolated private func currentInstance() -> MixpanelInstance? {
    instanceLock.lock()
    defer { instanceLock.unlock() }
    return _instance
  }

  // MARK: - Private: super properties (§10.2)

  nonisolated private func registerSuperProperties(on instance: MixpanelInstance) {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    let bundleId = Bundle.main.bundleIdentifier ?? ""
    let localeId = Locale.current.identifier
    let regionId = Locale.current.region?.identifier ?? ""
    let jurisdiction: String =
      ConsentJurisdiction.kind(for: Locale.current.region?.identifier) == .required
        ? "required" : "auto_optin"

    let props: [String: MixpanelType] = [
      AnalyticsProperty.appVersion: version,
      AnalyticsProperty.appBuild: build,
      AnalyticsProperty.deviceClass: Self.deviceClass,
      AnalyticsProperty.locale: localeId,
      AnalyticsProperty.region: regionId,
      AnalyticsProperty.consentJurisdiction: jurisdiction,
      AnalyticsProperty.bundleId: bundleId,
      AnalyticsProperty.weekStartDay: weekStartDayProvider(),
      AnalyticsProperty.currencyDisplayPreference: currencyDisplayProvider(),
      AnalyticsProperty.carryOverDefaultEnabled: carryOverDefaultProvider(),
      AnalyticsProperty.icloudState: syncStateProvider(),
      AnalyticsProperty.budgetsCountBucket: Self.bucket(count: budgetsCountProvider()),
    ]
    instance.registerSuperProperties(props)
  }

  // MARK: - Private: people properties (§10.3)

  nonisolated private func setBaselinePeopleProperties(on instance: MixpanelInstance) {
    let now = Date()
    instance.people.setOnce(properties: [AnalyticsProperty.firstSeenAt: now])
    instance.people.set(properties: [AnalyticsProperty.lastAppOpenAt: now])
  }

  nonisolated func setAnalyticsOptInAt(on instance: MixpanelInstance) {
    instance.people.set(properties: [AnalyticsProperty.analyticsOptInAt: Date()])
  }

  nonisolated private func setCohortPeopleProperties(
    on instance: MixpanelInstance,
    budgets: [BudgetCohortInfo]
  ) {
    let count = budgets.count
    let usesCarryOver = budgets.contains { $0.isCarryOverEnabled }
    let hasDisabledCarryOver = budgets.contains { !$0.isCarryOverEnabled }
    let carryOverOnCount = budgets.filter(\.isCarryOverEnabled).count
    let dominantPeriod = budgets.mostFrequent(keyPath: \.periodRawValue) ?? ""
    let defaultCurrency = budgets.mostFrequent(keyPath: \.currencyCode) ?? ""

    let props: [String: MixpanelType] = [
      AnalyticsProperty.budgetsCountBucket: Self.bucket(count: count),
      AnalyticsProperty.defaultCurrencyCode: defaultCurrency,
      AnalyticsProperty.dominantPeriod: dominantPeriod,
      AnalyticsProperty.usesCarryOver: usesCarryOver,
      AnalyticsProperty.hasDisabledCarryOver: hasDisabledCarryOver,
      AnalyticsProperty.budgetsWithCarryOverOnCountBucket: Self.bucket(count: carryOverOnCount),
    ]
    instance.people.set(properties: props)
  }

  // MARK: - Private: helpers

  nonisolated static func bucket(count: Int) -> String {
    switch count {
    case 0: "0"
    case 1: "1"
    case 2 ... 3: "2-3"
    case 4 ... 7: "4-7"
    default: "8+"
    }
  }

  nonisolated private static var deviceClass: String {
    switch UIDevice.current.userInterfaceIdiom {
    case .phone: "phone"
    case .pad: "pad"
    case .mac: "mac"
    default: "phone"
    }
  }
}

// MARK: - Collection helper

private extension Array {
  /// Returns the most frequently occurring value for the given key path,
  /// or `nil` for an empty array.
  nonisolated func mostFrequent<T: Hashable>(keyPath: KeyPath<Element, T>) -> T? {
    guard !isEmpty else { return nil }
    var counts: [T: Int] = [:]
    for item in self {
      counts[item[keyPath: keyPath], default: 0] += 1
    }
    return counts.max(by: { $0.value < $1.value })?.key
  }
}
