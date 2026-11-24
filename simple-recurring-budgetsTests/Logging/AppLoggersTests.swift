import OSLog
@testable import simple_recurring_budgets
import Testing

/// Structural tests for AppLoggers. `os.Logger` doesn't expose `subsystem`/`category`, so
/// these assert the three constants exist by name and are usable. The category strings
/// (`"bootstrap"`, `"cloudkit"`, `"ui"`) live in `AppLoggers.swift` and are enforced by review.
@Suite("AppLoggers — structural existence")
struct AppLoggersTests {
  @Test("Logger.bootstrap is accessible by name and emittable")
  func bootstrapExists() {
    // Compiles only if `Logger.bootstrap` exists as a static member of `Logger`.
    // Emitting at debug level so the line is a no-op in release test runs.
    Logger.bootstrap.debug("test: AppLoggersTests.bootstrapExists")
  }

  @Test("Logger.cloudKit is accessible by name and emittable")
  func cloudKitExists() {
    Logger.cloudKit.debug("test: AppLoggersTests.cloudKitExists")
  }

  @Test("Logger.ui is accessible by name and emittable")
  func uiExists() {
    Logger.ui.debug("test: AppLoggersTests.uiExists")
  }

  @Test("All three AppLoggers constants are distinct Logger values")
  func allThreeAreDistinct() {
    // `Logger` isn't Equatable; compare raw bytes via `withUnsafeBytes` instead (different
    // subsystem+category pairs yield different internal pointers).
    var bootstrap = Logger.bootstrap
    var cloudKit = Logger.cloudKit
    var ui = Logger.ui

    let bootstrapBytes = withUnsafeBytes(of: &bootstrap) { Data($0) }
    let cloudKitBytes = withUnsafeBytes(of: &cloudKit) { Data($0) }
    let uiBytes = withUnsafeBytes(of: &ui) { Data($0) }

    #expect(bootstrapBytes != cloudKitBytes, "bootstrap and cloudKit must be distinct loggers")
    #expect(bootstrapBytes != uiBytes, "bootstrap and ui must be distinct loggers")
    #expect(cloudKitBytes != uiBytes, "cloudKit and ui must be distinct loggers")
  }
}
