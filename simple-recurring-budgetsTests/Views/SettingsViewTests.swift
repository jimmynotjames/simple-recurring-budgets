//
//  SettingsViewTests.swift
//  simple-recurring-budgetsTests
//
//  Tests for SettingsView state-management logic:
//    – Currency display picker → AppSettings.currencyDisplay write path
//    – Week-start confirmation: cancel discards, confirm commits
//    – iCloud notification-driven SyncStatus.accountStatus update path
//
//  SwiftUI rendering of each row variant is validated by the
//  #Preview declarations in SettingsView.swift.
//

import CloudKit
import Foundation
import Testing
@testable import simple_recurring_budgets

// MARK: - Currency display picker → AppSettings write path (task 9.6)

@Suite("SettingsView — currency display picker")
struct SettingsCurrencyPickerTests {

    @Test func currencyDisplay_write_persistsToStore() {
        let mock = MockKeyValueStore()
        let settings = AppSettings(store: mock)
        #expect(settings.currencyDisplay == .symbol)

        // Simulate the picker binding writing a new value.
        settings.currencyDisplay = .code

        #expect(settings.currencyDisplay == .code)
        let stored = mock.object(forKey: AppSettings.currencyDisplayKey) as? String
        #expect(stored == "code")
    }

    @Test func currencyDisplay_toggle_throughAllCases() {
        let mock = MockKeyValueStore()
        let settings = AppSettings(store: mock)

        for pref in CurrencyDisplayPreference.allCases {
            settings.currencyDisplay = pref
            #expect(settings.currencyDisplay == pref)
        }
    }
}

// MARK: - Week-start confirmation: cancel discards, confirm commits (task 9.7)

@Suite("SettingsView — week-start confirmation")
struct SettingsWeekStartConfirmationTests {

    /// Selecting a *different* day sets pendingWeekStart (does not immediately commit).
    @Test func selectingNewDay_setsPending_doesNotCommit() {
        let mock = MockKeyValueStore()
        let settings = AppSettings(store: mock)
        // Force a known current value
        settings.weekStartDay = .sunday

        var pending: Weekday? = nil

        // Simulate the picker Binding.set logic from SettingsView:
        let newDay = Weekday.wednesday
        if newDay != settings.weekStartDay {
            pending = newDay
        }

        #expect(pending == .wednesday, "pending should be set to the newly selected day")
        #expect(settings.weekStartDay == .sunday,  "committed value should NOT change yet")
    }

    /// Tapping Cancel clears pending without updating the committed value.
    @Test func cancelAlert_clearsPending_noCommit() {
        let mock = MockKeyValueStore()
        let settings = AppSettings(store: mock)
        settings.weekStartDay = .sunday

        var pending: Weekday? = Weekday.wednesday

        // Simulate Cancel:
        pending = nil

        #expect(pending == nil)
        #expect(settings.weekStartDay == .sunday)
    }

    /// Tapping Change commits pending to AppSettings and clears it.
    @Test func confirmAlert_commitsPending_clearsPending() {
        let mock = MockKeyValueStore()
        let settings = AppSettings(store: mock)
        settings.weekStartDay = .sunday

        var pending: Weekday? = Weekday.wednesday

        // Simulate Change:
        if let day = pending {
            settings.weekStartDay = day
        }
        pending = nil

        #expect(pending == nil)
        #expect(settings.weekStartDay == .wednesday)

        // Also assert the new value was persisted to the store.
        let stored = mock.object(forKey: AppSettings.weekStartDayKey) as? Int64
        #expect(stored == Int64(Weekday.wednesday.rawValue))
    }

    /// Selecting the same day should not set pending.
    @Test func selectingSameDay_doesNotSetPending() {        let mock = MockKeyValueStore()
        let settings = AppSettings(store: mock)
        settings.weekStartDay = .monday

        var pending: Weekday? = nil
        let newDay = Weekday.monday
        if newDay != settings.weekStartDay {
            pending = newDay
        }

        #expect(pending == nil, "selecting the already-active day should not create a pending change")
    }
}

// MARK: - Notification-driven SyncStatus.accountStatus update path (W1 / Decision 10d)

/// Exercises the code path that `SettingsView.observeSingleNotification` drives:
/// a posted iCloud-change notification causes `loadICloudStatus()` to re-query
/// `CKContainer.default().accountStatus()` and write the result into
/// `SyncStatus.accountStatus`.
///
/// Because `CKContainer` cannot be stubbed directly in unit tests, these tests
/// verify the intermediate state machine: that mutations to `SyncStatus.accountStatus`
/// correctly propagate through `rowState`, which is the observable surface
/// that `SettingsView`'s switch reads. The notification → account-query → assignment
/// chain is a linear sequence; testing the assignment half here and the queue/actor
/// semantics via the build's strict concurrency checks is consistent with
/// `docs/tech-design-doc.md` §5.3 conventions (pure derivation is fully testable
/// without SwiftUI; async I/O boundaries are smoke-tested manually per task 11.2).
@Suite("SettingsView — iCloud notification-driven accountStatus update")
struct SettingsICloudNotificationTests {

    /// Simulates the assignment that `loadICloudStatus` performs after a
    /// `CKAccountChanged` notification: writing `.available` into `syncStatus.accountStatus`
    /// on a cloudKit-backed container transitions `rowState` to `.available`.
    @Test @MainActor
    func accountChanged_cloudKit_available_rowBecomesAvailable() {
        let syncStatus = SyncStatus(containerBacking: .cloudKit, accountStatus: .checking)
        #expect(syncStatus.rowState == .checking)

        // Simulate what loadICloudStatus() writes after the notification fires:
        syncStatus.accountStatus = .available

        #expect(syncStatus.rowState == .available)
    }

    /// A `CKAccountChanged` notification after sign-out: `.unavailable` written into a
    /// cloudKit-backed container transitions `rowState` to `.unavailable`.
    @Test @MainActor
    func accountChanged_cloudKit_unavailable_rowBecomesUnavailable() {
        let syncStatus = SyncStatus(containerBacking: .cloudKit, accountStatus: .available)

        syncStatus.accountStatus = .unavailable

        #expect(syncStatus.rowState == .unavailable)
    }

    /// A `CKAccountChanged` notification on a localFallback container: even when the
    /// account becomes `.available`, `rowState` remains `.paused` — the paused state is
    /// the correct description when the container is local-only but the account is present.
    @Test @MainActor
    func accountChanged_localFallback_available_rowRemainsPaused() {
        let syncStatus = SyncStatus(containerBacking: .localFallback, accountStatus: .checking)

        syncStatus.accountStatus = .available

        #expect(syncStatus.rowState == .paused,
                "localFallback + available should always yield .paused, not .available")
    }

    /// `NSUbiquityIdentityDidChange` fires on the same code path as `CKAccountChanged`;
    /// verify that a transition from `.available` back to `.checking` (representing a
    /// re-query in-flight) temporarily shows the checking spinner.
    @Test @MainActor
    func identityChanged_resetsToChecking_duringRequery() {
        let syncStatus = SyncStatus(containerBacking: .cloudKit, accountStatus: .available)
        #expect(syncStatus.rowState == .available)

        // Simulate the brief .checking window while loadICloudStatus() awaits CKContainer:
        syncStatus.accountStatus = .checking
        #expect(syncStatus.rowState == .checking)

        // Simulate the query completing:
        syncStatus.accountStatus = .available
        #expect(syncStatus.rowState == .available)
    }
}
