//
//  SpyAnalyticsClient.swift
//  simple-recurring-budgetsTests
//

import Foundation
@testable import simple_recurring_budgets

/// A test double that records every call made to `AnalyticsClient`.
///
/// Use in place of `ConsoleAnalyticsClient` whenever a test needs to assert on
/// which events were tracked, on which channel, at which level, and with what
/// properties — or how `identify`/`reset` were called.
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

    func track(_ event: String, channel: AnalyticsChannel, level: AnalyticsLevel, properties: [String: any Sendable]?) {
        trackCalls.append(TrackCall(event: event, channel: channel, level: level, properties: properties))
    }

    func identify(_ distinctId: String?) {
        identifyCalls.append(distinctId)
    }

    func reset() {
        resetCallCount += 1
    }

    // MARK: - Convenience

    var trackedEvents: [String] { trackCalls.map(\.event) }
    var productEvents: [TrackCall] { trackCalls.filter { $0.channel == .product } }
    var diagnosticEvents: [TrackCall] { trackCalls.filter { $0.channel != .product } }
}
