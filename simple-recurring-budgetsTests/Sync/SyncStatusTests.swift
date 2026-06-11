import Foundation
@testable import simple_recurring_budgets
import Testing

@Suite("SyncStatus.rowState")
struct SyncStatusRowStateTests {
  // MARK: - Checking (any container, any status in .checking)

  @Test func checking_cloudKit_returnsChecking() {
    let s = SyncStatus(containerBacking: .cloudKit, accountStatus: .checking)
    #expect(s.rowState == .checking)
  }

  @Test func checking_localFallback_returnsChecking() {
    let s = SyncStatus(containerBacking: .localFallback, accountStatus: .checking)
    #expect(s.rowState == .checking)
  }

  // MARK: - Available

  @Test func cloudKit_available_returnsAvailable() {
    let s = SyncStatus(containerBacking: .cloudKit, accountStatus: .available)
    #expect(s.rowState == .available)
  }

  // MARK: - Unavailable

  @Test func cloudKit_unavailable_returnsUnavailable() {
    let s = SyncStatus(containerBacking: .cloudKit, accountStatus: .unavailable)
    #expect(s.rowState == .unavailable)
  }

  @Test func localFallback_unavailable_returnsUnavailable() {
    let s = SyncStatus(containerBacking: .localFallback, accountStatus: .unavailable)
    #expect(s.rowState == .unavailable)
  }

  // MARK: - Paused

  @Test func localFallback_available_returnsPaused() {
    let s = SyncStatus(containerBacking: .localFallback, accountStatus: .available)
    #expect(s.rowState == .paused)
  }

  // MARK: - Default accountStatus

  @Test func defaultAccountStatus_isChecking() {
    let s = SyncStatus(containerBacking: .cloudKit)
    #expect(s.accountStatus == .checking)
    #expect(s.rowState == .checking)
  }

  // MARK: - Observable mutation

  @Test @MainActor
  func accountStatusChange_updatesRowState() {
    let s = SyncStatus(containerBacking: .cloudKit, accountStatus: .checking)
    #expect(s.rowState == .checking)

    s.accountStatus = .available
    #expect(s.rowState == .available)

    s.accountStatus = .unavailable
    #expect(s.rowState == .unavailable)
  }

  @Test @MainActor
  func containerBackingChange_updatesRowState() {
    // Container-failure Retry recovery (general-code-audit-2026-06-11 L1): the
    // App seeds a placeholder `.localFallback` on the failure path, then writes
    // the retry's resolved backing. The row must follow the corrected backing —
    // here from `paused` (local + signed in) to `available`.
    let s = SyncStatus(containerBacking: .localFallback, accountStatus: .available)
    #expect(s.rowState == .paused)

    s.containerBacking = .cloudKit
    #expect(s.rowState == .available)
  }
}
