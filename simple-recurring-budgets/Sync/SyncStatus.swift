import Foundation
import Observation

// MARK: - SyncStatus

/// Tracks the app's iCloud sync availability and exposes a derived view-state
/// for the Settings screen's iCloud row.
///
/// `containerBacking` is determined at app launch from the outcome of
/// `ProductionContainerFactory.make` and changes at runtime in exactly one
/// case: when container creation failed at launch and a later **Retry** from
/// `ContainerFailureView` succeeds, the `@main` App writes the retry's
/// resolved backing here so Settings doesn't misreport local-only after
/// recovery. `accountStatus` is updated asynchronously by `SettingsView` via
/// `ICloudStatusLoader` and `CKAccountChangedNotification` observers.
///
/// Inject via `.environment(syncStatus)` from `simple_recurring_budgetsApp`
/// and consume in views via `@Environment(SyncStatus.self)`.
@Observable
final class SyncStatus {
  // MARK: - Nested types

  /// How the live SwiftData `ModelContainer` is backed.
  /// Set at launch; re-written only by a successful container-failure Retry.
  enum ContainerBacking {
    /// CloudKit-backed — data syncs across the user's iCloud-paired devices.
    case cloudKit
    /// Local-only fallback — CloudKit container construction failed at launch;
    /// data is stored on-device only until the user relaunches.
    case localFallback
  }

  /// The last-known iCloud account status.
  /// Initialized to `.checking`; updated by `SettingsView`.
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

  /// Launch-time backing, read from `SettingsView`. Mutable for one writer
  /// only: the `@main` App's container-failure Retry handler, which corrects
  /// the placeholder `.localFallback` seed once a successful retry resolves
  /// the real backing (see the class doc).
  var containerBacking: ContainerBacking

  /// Mutable account status. Updated by `SettingsView` asynchronously.
  var accountStatus: AccountStatus

  #if DEBUG
    /// **Screenshot-capture override.** When `true`, `rowState` always reports
    /// `.available` so App Store marketing screenshots show iCloud sync as active even
    /// though the Simulator has no iCloud account (CloudKit can't run there, so the
    /// real status would otherwise read "unavailable").
    ///
    /// Safeguard: this property and its use in `rowState` are compiled out of Release
    /// builds entirely (`#if DEBUG`), and it is set in exactly one place — the `@main`
    /// App init, only when the `SCREENSHOT_SYNC_OK` launch-environment flag is present
    /// (set solely by the `AppStoreScreenshots` UI test). No production or normal-dev
    /// path ever sets it, so it cannot misrepresent sync status to a real user.
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
    #if DEBUG
      // Screenshot-capture override (see `screenshotForcesAvailableState`). Compiled
      // out of Release; only ever true under the AppStoreScreenshots launch flag.
      if screenshotForcesAvailableState { return .available }
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
