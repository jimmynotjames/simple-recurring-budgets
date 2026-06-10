import CloudKit
import Foundation
import OSLog

/// Queries the iCloud account status and writes the mapped result into
/// `SyncStatus.accountStatus` — the half of the Settings iCloud row that was
/// previously unreachable from unit tests because `CKContainer` cannot be
/// stubbed (test-coverage-audit-2026-06-10 I2). The query is an injected
/// closure: production uses the live `CKContainer` call below; tests inject
/// available / unavailable / throwing providers.
struct ICloudStatusLoader {
  /// Returns the live account status.
  var accountStatus: () async throws -> CKAccountStatus = {
    #if DEBUG
      // UI tests: CKContainer.accountStatus() hangs on the account-less
      // Simulator, pinning the iCloud row to a spinner so XCUITest can't open
      // Settings (#211). Skip the query; `.noAccount` maps to `.unavailable`
      // in `load(into:)`. DEBUG-only, like the SyncStatus override.
      if ProcessInfo.processInfo.environment["IS_TESTING"] != nil {
        return .noAccount
      }
    #endif
    return try await CKContainer.default().accountStatus()
  }

  /// Queries the provider, maps the result (`.available` → available, anything
  /// else or a thrown error → unavailable), writes it into `syncStatus`, and
  /// logs state transitions.
  func load(into syncStatus: SyncStatus) async {
    let old = syncStatus.accountStatus
    do {
      let status = try await accountStatus()
      syncStatus.accountStatus = status == .available ? .available : .unavailable
    } catch {
      syncStatus.accountStatus = .unavailable
    }
    let new = syncStatus.accountStatus
    if old != new {
      Logger.cloudKit.notice("cloudkit.account.transition: \(String(describing: old), privacy: .public) → \(String(describing: new), privacy: .public)")
    }
  }
}
