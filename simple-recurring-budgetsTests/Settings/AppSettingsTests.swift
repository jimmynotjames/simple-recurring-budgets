import Foundation
@testable import simple_recurring_budgets
import Testing

@Suite("AppSettings")
struct AppSettingsTests {
  @Test func freshStore_defaultCarryOverIsTrue() {
    let mock = MockKeyValueStore()
    let settings = AppSettings(store: mock)
    #expect(settings.defaultCarryOverEnabled == true)
  }

  @Test func freshStore_weekStartMatchesLocale() {
    let mock = MockKeyValueStore()
    let settings = AppSettings(store: mock)
    let expected = Weekday.from(calendarFirstWeekday: Calendar.current.firstWeekday) ?? .sunday
    #expect(settings.weekStartDay == expected)
  }

  @Test func persistedCarryOver_readOnInit() {
    let mock = MockKeyValueStore()
    mock.set(false, forKey: AppSettings.defaultCarryOverEnabledKey)
    _ = mock.synchronize()

    let settings = AppSettings(store: mock)
    #expect(settings.defaultCarryOverEnabled == false)
  }

  @Test func persistedWeekStart_readOnInit() {
    let mock = MockKeyValueStore()
    mock.set(Int64(Weekday.monday.rawValue), forKey: AppSettings.weekStartDayKey)
    _ = mock.synchronize()

    let settings = AppSettings(store: mock)
    #expect(settings.weekStartDay == .monday)
  }

  @Test func settingCarryOver_persistsToStore() {
    let mock = MockKeyValueStore()
    let settings = AppSettings(store: mock)
    settings.defaultCarryOverEnabled = false

    let obj = mock.object(forKey: AppSettings.defaultCarryOverEnabledKey)
    #expect((obj as? Bool) == false)
  }

  @Test func settingWeekStart_persistsToStore() {
    let mock = MockKeyValueStore()
    let settings = AppSettings(store: mock)
    settings.weekStartDay = .monday

    let obj = mock.object(forKey: AppSettings.weekStartDayKey)
    #expect((obj as? Int64) == 2 || (obj as? Int) == 2 || (obj as? NSNumber)?.intValue == 2)
  }

  @Test func invalidWeekStart_fallsBackToLocale() {
    let mock = MockKeyValueStore()
    mock.set(Int64(99), forKey: AppSettings.weekStartDayKey)

    let settings = AppSettings(store: mock)
    let expected = Weekday.from(calendarFirstWeekday: Calendar.current.firstWeekday) ?? .sunday
    #expect(settings.weekStartDay == expected)
  }

  @Test @MainActor
  func externalNotification_updatesCarryOver() async {
    let mock = MockKeyValueStore()
    let settings = AppSettings(store: mock)
    #expect(settings.defaultCarryOverEnabled == true)

    mock.seedExternal(bool: false, forKey: AppSettings.defaultCarryOverEnabledKey)
    NotificationCenter.default.post(
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: mock,
      userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: [AppSettings.defaultCarryOverEnabledKey]]
    )

    await Task.yield()
    #expect(settings.defaultCarryOverEnabled == false)
  }

  @Test @MainActor
  func externalNotification_updatesWeekStart() async {
    let mock = MockKeyValueStore()
    let settings = AppSettings(store: mock)

    mock.seedExternal(int64: Int64(Weekday.friday.rawValue), forKey: AppSettings.weekStartDayKey)
    NotificationCenter.default.post(
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: mock,
      userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: [AppSettings.weekStartDayKey]]
    )

    await Task.yield()
    #expect(settings.weekStartDay == .friday)
  }

  // MARK: - currencyDisplay

  @Test func freshStore_currencyDisplayIsSymbol() {
    let mock = MockKeyValueStore()
    let settings = AppSettings(store: mock)
    #expect(settings.currencyDisplay == .symbol)
  }

  @Test func persistedCurrencyDisplay_readOnInit() {
    let mock = MockKeyValueStore()
    mock.set(CurrencyDisplayPreference.code.rawValue, forKey: AppSettings.currencyDisplayKey)
    _ = mock.synchronize()

    let settings = AppSettings(store: mock)
    #expect(settings.currencyDisplay == .code)
  }

  @Test func settingCurrencyDisplay_persistsRawValueToStore() {
    let mock = MockKeyValueStore()
    let settings = AppSettings(store: mock)
    settings.currencyDisplay = .codeAndSymbol

    let obj = mock.object(forKey: AppSettings.currencyDisplayKey)
    #expect((obj as? String) == "codeAndSymbol")
  }

  @Test func invalidCurrencyDisplayRawValue_fallsBackToSymbol() {
    let mock = MockKeyValueStore()
    mock.set("unknownValue", forKey: AppSettings.currencyDisplayKey)

    let settings = AppSettings(store: mock)
    #expect(settings.currencyDisplay == .symbol)
  }

  @Test @MainActor
  func externalNotification_updatesCurrencyDisplay() async {
    let mock = MockKeyValueStore()
    let settings = AppSettings(store: mock)
    #expect(settings.currencyDisplay == .symbol)

    mock.seedExternal(string: CurrencyDisplayPreference.code.rawValue, forKey: AppSettings.currencyDisplayKey)
    NotificationCenter.default.post(
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: mock,
      userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: [AppSettings.currencyDisplayKey]]
    )

    await Task.yield()
    #expect(settings.currencyDisplay == .code)
  }

  @Test @MainActor
  func externalNotification_nilChangedKeys_reloadsCurrencyDisplay() async {
    let mock = MockKeyValueStore()
    let settings = AppSettings(store: mock)

    mock.seedExternal(string: CurrencyDisplayPreference.codeAndSymbol.rawValue, forKey: AppSettings.currencyDisplayKey)
    // nil changed keys → full reload
    NotificationCenter.default.post(
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: mock,
      userInfo: nil
    )

    await Task.yield()
    #expect(settings.currencyDisplay == .codeAndSymbol)
  }
}
