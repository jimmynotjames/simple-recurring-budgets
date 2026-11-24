import Foundation
import Observation

// MARK: - SyncStatus

/// Tracks the app's iCloud sync availability and exposes a derived view-state for the Settings iCloud row.
///
/// `containerBacking` is set at launch from `ProductionContainerFactory.make` and changes at runtime in
/// exactly one case: container creation failed at launch and a later **Retry** from `ContainerFailureView`
/// succeeds, so the `@main` App writes the resolved backing here and Settings doesn't misreport local-only.
/// `accountStatus` is updated asynchronously by `SettingsView` via `ICloudStatusLoader` and
/// `CKAccountChangedNotification` observers.
///
/// Inject via `.environment(syncStatus)` from `simple_recurring_budgetsApp`; consume via
/// `@Environment(SyncStatus.self)`.
@Observable
final class SyncStatus {
  // MARK: - Nested types

  /// How the live SwiftData `ModelContainer` is backed. Set at launch; rewritten only by a successful container-failure Retry.
  enum ContainerBacking {
    /// CloudKit-backed — data syncs across the user's iCloud-paired devices.
    case cloudKit
    /// Local-only fallback: CloudKit container construction failed at launch; data stays on-device until relaunch.
    case localFallback
  }

  /// Last-known iCloud account status; starts `.checking`, updated by `SettingsView`.
  enum AccountStatus {
    case checking
    case available
    case unavailable
  }

  /// Four-state row view-state for the Settings iCloud row.
  enum RowState {
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

  /// Launch-time backing, read by `SettingsView`. Written only by the `@main` App's container-failure Retry
  /// handler, which corrects the placeholder `.localFallback` seed (see class doc).
  var containerBacking: ContainerBacking

  /// Mutable account status. Updated by `SettingsView` asynchronously.
  var accountStatus: AccountStatus

  #if DEBUG
    /// **Screenshot-capture override.** When `true`, `rowState` always reports `.available` so App Store
    /// screenshots show iCloud sync as active; the Simulator has no iCloud account, so the real status would
    /// read "unavailable".
    ///
    /// Safeguard: this property and its use in `rowState` are compiled out of Release (`#if DEBUG`), and it is
    /// set only in the `@main` App init when the `SCREENSHOT_SYNC_OK` launch-environment flag is present (set
    /// solely by the `AppStoreScreenshots` UI test), so it can't misrepresent sync status to a real user.
    var screenshotForcesAvailableState = false
  #endif

  // MARK: - Init

  init(containerBacking: ContainerBacking, accountStatus: AccountStatus = .checking) {
    self.containerBacking = containerBacking
    self.accountStatus = accountStatus
  }
}

// MARK: - Derived row state

extension SyncStatus {
  /// Derives the Settings iCloud row view-state from `(containerBacking, accountStatus)`
  /// (per `openspec/specs/settings-screen/spec.md`):
  ///
  /// | containerBacking | accountStatus | rowState   |
  /// |------------------|---------------|------------|
  /// | any              | .checking     | .checking  |
  /// | .cloudKit        | .available    | .available |
  /// | .cloudKit        | .unavailable  | .unavailable |
  /// | .localFallback   | .available    | .paused    |
  /// | .localFallback   | .unavailable  | .unavailable |
  var rowState: RowState {
    #if DEBUG
      // Screenshot-capture override (see `screenshotForcesAvailableState`); compiled out of Release.
      if screenshotForcesAvailableState {
        return .available
      }
    #endif
    return switch (containerBacking, accountStatus) {
    case (_, .checking):
      .checking
    case (.cloudKit, .available):
      .available
    case (.cloudKit, .unavailable):
      .unavailable
    case (.localFallback, .available):
      .paused
    case (.localFallback, .unavailable):
      .unavailable
    }
  }
}
