import Foundation
@testable import simple_recurring_budgets

/// A test double that records every call made to `AnalyticsClient`.
///
/// Marked `@MainActor` so mutable stored state is protected by actor isolation
/// (satisfies `Sendable`). Protocol methods are `nonisolated` to match the
/// non-isolated protocol requirement; they use `MainActor.assumeIsolated` to
/// mutate state — safe because every call site in the test suite runs on the
/// main actor.
@MainActor
final class SpyAnalyticsClient: AnalyticsClient {
  struct TrackCall: Equatable {
    let event: String
    let properties: [String: String]?

    init(event: String, properties: [String: any Sendable]?) {
      self.event = event
      self.properties = properties.map { dict in
        dict.mapValues { "\($0)" }
      }
    }
  }

  private(set) var trackCalls: [TrackCall] = []
  private(set) var identifyCalls: [String?] = []
  private(set) var resetCallCount = 0

  nonisolated func track(_ event: String, properties: [String: any Sendable]?) {
    MainActor.assumeIsolated {
      trackCalls.append(TrackCall(event: event, properties: properties))
    }
  }

  nonisolated func identify(_ distinctId: String?) {
    MainActor.assumeIsolated {
      identifyCalls.append(distinctId)
    }
  }

  nonisolated func reset() {
    MainActor.assumeIsolated {
      resetCallCount += 1
    }
  }

  // MARK: - Convenience

  var trackedEvents: [String] {
    trackCalls.map(\.event)
  }
}
