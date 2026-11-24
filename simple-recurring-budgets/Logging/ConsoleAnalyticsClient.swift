/// An `AnalyticsClient` that prints product events to the Xcode console in DEBUG; silent no-op in release.
/// Used in DEBUG and as the SwiftUI environment default.
final class ConsoleAnalyticsClient: AnalyticsClient {
  func track(_ event: String, properties: [String: any Sendable]?) {
    #if DEBUG
      if let properties, !properties.isEmpty {
        print("[analytics] \(event) \(properties)") // check-strings:ignore
      } else {
        print("[analytics] \(event)") // check-strings:ignore
      }
    #endif
  }

  func identify(_ distinctId: String?) {
    #if DEBUG
      print("[analytics] identify \(distinctId ?? "nil")") // check-strings:ignore
    #endif
  }

  func reset() {
    #if DEBUG
      print("[analytics] reset") // check-strings:ignore
    #endif
  }
}
