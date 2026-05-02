import Foundation

/// Product analytics abstraction. Routes business-metric events to the
/// configured backend (Mixpanel in production; console print in debug builds).
///
/// Diagnostic / operational events (container bootstrap, CloudKit sync, etc.)
/// are logged directly via `OSLog.Logger` in `AppLoggers.swift` and never
/// pass through this protocol.
protocol AnalyticsClient: AnyObject, Sendable {
  func track(_ event: String, properties: [String: any Sendable]?)
  func identify(_ distinctId: String?)
  func reset()
}

extension AnalyticsClient {
  func track(_ event: String) {
    track(event, properties: nil)
  }
}

/// Canonical product event-name constants.
enum AnalyticsEvent {
  static let appLaunched = "app.launched"
}
