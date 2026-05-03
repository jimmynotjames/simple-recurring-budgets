import Foundation
import Testing

/// Canary test for the `@main` analytics test-host guard.
///
/// `simple_recurring_budgetsApp.isRunningTests` checks
/// `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`
/// to detect when the app process was launched by XCTest. When true, the app
/// substitutes `ConsoleAnalyticsClient` for `MixpanelAnalyticsClient`, which
/// prevents `app_opened` (and any other app-launch events) from reaching
/// Mixpanel during test runs.
///
/// This env var is a private XCTest implementation detail — Apple has not
/// documented it as a stable API. This test acts as an early-warning system:
/// if it starts failing after an Xcode update, the guard is broken and dev
/// Mixpanel events will fire on every test run. Fix by updating `isRunningTests`
/// — the documented fallback is a launch argument (see the comment in
/// `simple_recurring_budgetsApp.isRunningTests`).
@Suite("Analytics — test-host guard canary")
struct AnalyticsTestHostGuardTests {
  @Test("XCTestConfigurationFilePath env var is set when tests run")
  func xcTestConfigurationFilePathIsSetDuringTestRuns() {
    #expect(
      ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
      """
      XCTestConfigurationFilePath is not set. The isRunningTests guard in \
      simple_recurring_budgetsApp will return false, meaning Mixpanel events \
      will fire during test runs. Update isRunningTests to use the \
      --disable-analytics launch-argument fallback or another mechanism.
      """
    )
  }
}
