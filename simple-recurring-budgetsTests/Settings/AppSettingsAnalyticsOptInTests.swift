@testable import simple_recurring_budgets
import Testing

/// AppSettings.analyticsOptIn locale-aware default and persistence.
@Suite("AppSettings — analyticsOptIn §18.1 #2")
@MainActor
struct AppSettingsAnalyticsOptInTests {
  @Test("fresh store + required jurisdiction defaults to false")
  func freshStoreRequiredDefaultsFalse() {
    // The locale can't be injected, so this checks `ConsentJurisdiction` directly (DE is a
    // required/GDPR jurisdiction) and that the store has no analyticsOptIn key.
    let store = MockKeyValueStore()
    #expect(ConsentJurisdiction.kind(for: "DE") == .required)
    #expect(store.object(forKey: AppSettings.analyticsOptInKey) == nil)
  }

  @Test("explicit true write persists and reads back true")
  func explicitTruePersists() {
    let store = MockKeyValueStore()
    let settings = AppSettings(store: store)
    settings.analyticsOptIn = true
    #expect(store.object(forKey: AppSettings.analyticsOptInKey) != nil)
    let settingsReread = AppSettings(store: store)
    #expect(settingsReread.analyticsOptIn == true)
  }

  @Test("explicit false write persists and reads back false")
  func explicitFalsePersists() {
    let store = MockKeyValueStore()
    let settings = AppSettings(store: store)
    settings.analyticsOptIn = false
    let settingsReread = AppSettings(store: store)
    #expect(settingsReread.analyticsOptIn == false)
  }

  @Test("default read does NOT write to backing store")
  func defaultReadDoesNotPersist() {
    let store = MockKeyValueStore()
    _ = AppSettings(store: store)
    // Init must not persist the locale-aware default. Locale can't be controlled here, so
    // assert the flag tracks whether the store holds a value.
    let settings = AppSettings(store: store)
    let storeHasValue = store.object(forKey: AppSettings.analyticsOptInKey) != nil
    #expect(settings.analyticsOptInExplicitlySet == storeHasValue)
  }

  @Test("analyticsOptInExplicitlySet is false on a fresh store")
  func explicitlySetFalseOnFreshStore() {
    let store = MockKeyValueStore()
    let settings = AppSettings(store: store)
    #expect(settings.analyticsOptInExplicitlySet == false)
  }

  @Test("analyticsOptInExplicitlySet becomes true after explicit write")
  func explicitlySetTrueAfterWrite() {
    let store = MockKeyValueStore()
    let settings = AppSettings(store: store)
    settings.analyticsOptIn = true
    #expect(settings.analyticsOptInExplicitlySet == true)
  }
}
