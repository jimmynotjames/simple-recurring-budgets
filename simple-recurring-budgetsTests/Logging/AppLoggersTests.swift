import OSLog
@testable import simple_recurring_budgets
import Testing

/// Structural tests for AppLoggers.
///
/// `os.Logger` does not expose its `subsystem` or `category` for direct read-back.
/// These tests assert the three constants are reachable by name, conform to the
/// expected type, and are usable — which is the compile-time structural guarantee
/// that the `diagnostic-logging` spec's "AppLoggers categories" requirement needs.
///
/// The subsystem/category string contract (`"bootstrap"`, `"cloudkit"`, `"ui"`) is
/// source-controlled in `AppLoggers.swift` and enforced by code review against the
/// capability spec.
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
    // We cannot compare `Logger` values directly (no Equatable), but we can
    // verify they are structurally distinct by examining their raw bytes via
    // `withUnsafeBytes`. Different subsystem+category pairs produce different
    // internal pointer values in the `os.Logger` struct.
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
