//
//  SpyAnalyticsClient.swift
//  simple-recurring-budgetsTests
//

import Foundation
@testable import simple_recurring_budgets

/// A test double that records every call made to `AnalyticsClient`.
///
/// Marked `@MainActor` so that:
/// - Mutable stored state is protected by actor isolation (satisfies `Sendable`).
/// - `AnalyticsChannel.Equatable` (also `@MainActor` under the app target's default
///   isolation) can be used freely in filter closures.
///
/// Protocol methods are `nonisolated` to match the non-isolated protocol requirement;
/// they use `MainActor.assumeIsolated` to mutate state — safe because every call site
/// in the test suite runs on the main actor (sync tests in Swift Testing execute on the
/// main thread; async tests carry the `@MainActor` annotation explicitly).
@MainActor
final class SpyAnalyticsClient: AnalyticsClient {

    struct TrackCall: Equatable {
        let event: String
        let channel: AnalyticsChannel
        let level: AnalyticsLevel
        let properties: [String: String]?

        init(event: String, channel: AnalyticsChannel, level: AnalyticsLevel, properties: [String: any Sendable]?) {
            self.event = event
            self.channel = channel
            self.level = level
            // Flatten to [String: String] for equatability in assertions.
            self.properties = properties.map { dict in
                dict.mapValues { "\($0)" }
            }
        }
    }

    private(set) var trackCalls: [TrackCall] = []
    private(set) var identifyCalls: [String?] = []
    private(set) var resetCallCount = 0

    nonisolated func track(_ event: String, channel: AnalyticsChannel, level: AnalyticsLevel, properties: [String: any Sendable]?) {
        MainActor.assumeIsolated {
            trackCalls.append(TrackCall(event: event, channel: channel, level: level, properties: properties))
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

    var trackedEvents: [String] { trackCalls.map(\.event) }
    var productEvents: [TrackCall] { trackCalls.filter { $0.channel == .product } }
    var diagnosticEvents: [TrackCall] { trackCalls.filter { $0.channel != .product } }
}
