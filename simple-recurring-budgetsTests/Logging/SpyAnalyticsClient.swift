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

  // MARK: - Super / people-property surface (AnalyticsClient protocol)

  /// Number of `refreshSuperProperties()` calls received.
  private(set) var refreshSuperPropertiesCallCount = 0
  /// Each `refreshCohortPeopleProperties(budgets:)` call's payload, in order.
  private(set) var cohortRefreshCalls: [[BudgetCohortInfo]] = []
  /// Dates passed to `setRatingPromptFirstEligible(_:)`, in order.
  private(set) var ratingPromptFirstEligibleDates: [Date] = []
  /// Dates passed to `setRatingPromptLastRequested(_:)`, in order.
  private(set) var ratingPromptLastRequestedDates: [Date] = []

  nonisolated func refreshSuperProperties() {
    MainActor.assumeIsolated {
      refreshSuperPropertiesCallCount += 1
    }
  }

  nonisolated func refreshCohortPeopleProperties(budgets: [BudgetCohortInfo]) {
    MainActor.assumeIsolated {
      cohortRefreshCalls.append(budgets)
    }
  }

  nonisolated func setRatingPromptFirstEligible(_ date: Date) {
    MainActor.assumeIsolated {
      ratingPromptFirstEligibleDates.append(date)
    }
  }

  nonisolated func setRatingPromptLastRequested(_ date: Date) {
    MainActor.assumeIsolated {
      ratingPromptLastRequestedDates.append(date)
    }
  }

  // MARK: - Super / people property recording (simulated Mixpanel SDK surface)

  /// Last dictionary passed to `registerSuperProperties`. Nil until first call.
  private(set) var superProperties: [String: String]?
  /// Accumulated people-property sets (via `people.set`).
  private(set) var peopleProperties: [String: String] = [:]
  /// Accumulated people-property setOnce values.
  private(set) var peopleSetOnceProperties: [String: String] = [:]

  /// Simulates `MixpanelAnalyticsClient.registerSuperProperties` for test assertions
  /// (§18.1 #9). Call sites that need to assert super-property attachment can set
  /// properties via this method rather than reaching into the Mixpanel SDK.
  func recordSuperProperties(_ props: [String: Any]) {
    superProperties = props.mapValues { "\($0)" }
  }

  /// Simulates `people.set` for cohort people-property assertions (§18.1 cohort tests).
  func recordPeopleSet(_ props: [String: Any]) {
    for (key, value) in props {
      peopleProperties[key] = "\(value)"
    }
  }

  /// Simulates `people.setOnce` for baseline people-property assertions.
  func recordPeopleSetOnce(_ props: [String: Any]) {
    for (key, value) in props {
      peopleSetOnceProperties[key] = "\(value)"
    }
  }

  // MARK: - Convenience

  var trackedEvents: [String] {
    trackCalls.map(\.event)
  }
}
