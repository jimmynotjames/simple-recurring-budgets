//
//  AppSettingsTests.swift
//  simple-recurring-budgetsTests
//

import Foundation
import Testing
@testable import simple_recurring_budgets

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
}
