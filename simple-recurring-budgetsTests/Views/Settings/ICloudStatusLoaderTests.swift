import CloudKit
@testable import simple_recurring_budgets
import Testing

/// Drives `ICloudStatusLoader.load(into:)` (the query + mapping half of the Settings iCloud row)
/// through injected account-status providers. `SettingsICloudNotificationTests` covers only the
/// `accountStatus → rowState` derivation.
@Suite("ICloudStatusLoader — provider-driven accountStatus writes")
@MainActor
struct ICloudStatusLoaderTests {
  @Test func availableProvider_writesAvailable() async {
    let syncStatus = SyncStatus(containerBacking: .cloudKit, accountStatus: .checking)
    let loader = ICloudStatusLoader(accountStatus: { .available })

    await loader.load(into: syncStatus)

    #expect(syncStatus.accountStatus == .available)
    #expect(syncStatus.rowState == .available)
  }

  @Test func noAccountProvider_writesUnavailable() async {
    let syncStatus = SyncStatus(containerBacking: .cloudKit, accountStatus: .checking)
    let loader = ICloudStatusLoader(accountStatus: { .noAccount })

    await loader.load(into: syncStatus)

    #expect(syncStatus.accountStatus == .unavailable)
  }

  @Test func couldNotDetermineProvider_writesUnavailable() async {
    let syncStatus = SyncStatus(containerBacking: .cloudKit, accountStatus: .checking)
    let loader = ICloudStatusLoader(accountStatus: { .couldNotDetermine })

    await loader.load(into: syncStatus)

    #expect(syncStatus.accountStatus == .unavailable)
  }

  @Test func throwingProvider_writesUnavailable() async {
    let syncStatus = SyncStatus(containerBacking: .cloudKit, accountStatus: .checking)
    let loader = ICloudStatusLoader(accountStatus: {
      throw CKError(.networkUnavailable)
    })

    await loader.load(into: syncStatus)

    #expect(syncStatus.accountStatus == .unavailable)
  }

  /// Re-query after sign-in: the notification-driven path (`SettingsView.observeSingleNotification` on
  /// CKAccountChanged / NSUbiquityIdentityDidChange) transitions unavailable → available.
  @Test func reload_afterSignIn_transitionsToAvailable() async {
    let syncStatus = SyncStatus(containerBacking: .cloudKit, accountStatus: .checking)
    let signedIn = SignedInFlag()
    let loader = ICloudStatusLoader(accountStatus: {
      signedIn.value ? .available : .noAccount
    })

    await loader.load(into: syncStatus)
    #expect(syncStatus.accountStatus == .unavailable)

    signedIn.value = true
    await loader.load(into: syncStatus)
    #expect(syncStatus.accountStatus == .available)
    #expect(syncStatus.rowState == .available)
  }
}

/// Mutable flag the provider closure can capture (closures can't capture
/// `inout`/`var` test locals across await boundaries).
@MainActor
private final class SignedInFlag {
  var value = false
}
