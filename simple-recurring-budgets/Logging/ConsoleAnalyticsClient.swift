/// An `AnalyticsClient` that prints product events to the Xcode console in
/// DEBUG builds. Silent no-op in release builds.
///
/// Used in DEBUG and as the SwiftUI environment default. Swap for
/// `MixpanelAnalyticsClient` at the app entry point in release builds once
/// the user has opted in to analytics.
final class ConsoleAnalyticsClient: AnalyticsClient {
  func track(_ event: String, properties: [String: any Sendable]?) {
    #if DEBUG
      if let properties, !properties.isEmpty {
        print("[analytics] \(event) \(properties)")
      } else {
        print("[analytics] \(event)")
      }
    #endif
  }

  func identify(_ distinctId: String?) {
    #if DEBUG
      print("[analytics] identify \(distinctId ?? "nil")")
    #endif
  }

  func reset() {
    #if DEBUG
      print("[analytics] reset")
    #endif
  }
}
