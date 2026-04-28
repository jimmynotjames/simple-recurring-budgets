//
//  SyncStatus.swift
//  simple-recurring-budgets
//

import Foundation
import Observation

// MARK: - SyncStatus

/// Tracks the app's iCloud sync availability and exposes a derived view-state
/// for the Settings screen's iCloud row.
///
/// `containerBacking` is determined once at app launch from the outcome of
/// `makeProductionModelContainer` and never changes. `accountStatus` is
/// updated asynchronously by `SettingsView` via `CKContainer.accountStatus()`
/// and `CKAccountChangedNotification` observers.
///
/// Inject via `.environment(syncStatus)` from `simple_recurring_budgetsApp`
/// and consume in views via `@Environment(SyncStatus.self)`.
@Observable
final class SyncStatus {

    // MARK: - Nested types

    /// How the live SwiftData `ModelContainer` is backed.
    /// Set once at launch; never mutated.
    enum ContainerBacking: Sendable {
        /// CloudKit-backed — data syncs across the user's iCloud-paired devices.
        case cloudKit
        /// Local-only fallback — CloudKit container construction failed at launch;
        /// data is stored on-device only until the user relaunches.
        case localFallback
    }

    /// The last-known iCloud account status.
    /// Initialized to `.checking`; updated by `SettingsView`.
    enum AccountStatus: Sendable {
        case checking
        case available
        case unavailable
    }

    /// Four-state row view-state for the Settings iCloud row.
    enum RowState: Sendable {
        /// Initial state while the account query is in-flight.
        case checking
        /// CloudKit-backed container and an available iCloud account.
        case available
        /// CloudKit-backed container but no iCloud account (not signed in).
        case unavailable
        /// Local-only container despite a potentially available iCloud account.
        case paused
    }

    // MARK: - State

    /// Immutable launch-time backing. Set once in `init`; read from `SettingsView`.
    let containerBacking: ContainerBacking

    /// Mutable account status. Updated by `SettingsView` asynchronously.
    var accountStatus: AccountStatus

    // MARK: - Init

    init(containerBacking: ContainerBacking, accountStatus: AccountStatus = .checking) {
        self.containerBacking = containerBacking
        self.accountStatus = accountStatus
    }
}

// MARK: - Derived row state

extension SyncStatus {
    /// Derives the Settings iCloud row view-state from `(containerBacking, accountStatus)`.
    ///
    /// Mapping (per `openspec/specs/settings-screen/spec.md`):
    ///
    /// | containerBacking | accountStatus | rowState   |
    /// |------------------|---------------|------------|
    /// | any              | .checking     | .checking  |
    /// | .cloudKit        | .available    | .available |
    /// | .cloudKit        | .unavailable  | .unavailable |
    /// | .localFallback   | .available    | .paused    |
    /// | .localFallback   | .unavailable  | .unavailable |
    var rowState: RowState {
        switch (containerBacking, accountStatus) {
        case (_, .checking):
            return .checking
        case (.cloudKit, .available):
            return .available
        case (.cloudKit, .unavailable):
            return .unavailable
        case (.localFallback, .available):
            return .paused
        case (.localFallback, .unavailable):
            return .unavailable
        }
    }
}
