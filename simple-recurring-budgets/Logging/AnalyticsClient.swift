//
//  AnalyticsClient.swift
//  simple-recurring-budgets
//

import Foundation

/// The subsystem that determines how an event is routed by the analytics implementation.
///
/// Diagnostic channels map to the corresponding `OSLog.Logger` category.
/// The `.product` channel routes to the configured product analytics backend
/// (currently console `print` in debug builds; later Mixpanel).
enum AnalyticsChannel {
    case bootstrap
    case cloudKit
    case ui
    case product
}

/// Severity level for events routed to a diagnostic channel.
///
/// Ignored for `.product` channel events, which have no log-level concept.
enum AnalyticsLevel {
    case info
    case notice
    case error
}

/// Single abstraction over both diagnostic logging and product analytics.
///
/// All events — whether they describe runtime behaviour for the developer or
/// product metrics for the business — travel through this one protocol. The
/// `channel` parameter tells the implementation how to route each event:
/// diagnostic channels go to `OSLog`, the `.product` channel goes to the
/// configured analytics backend (currently `print`; later Mixpanel).
protocol AnalyticsClient: AnyObject, Sendable {

    /// The primary entry point. Route via `channel`; use `level` to set OSLog
    /// severity for diagnostic channels (ignored for `.product`).
    func track(_ event: String, channel: AnalyticsChannel, level: AnalyticsLevel, properties: [String: any Sendable]?)

    /// Associate subsequent product events with a known user identity.
    func identify(_ distinctId: String?)

    /// Clear the current product identity (e.g. on sign-out).
    func reset()
}

extension AnalyticsClient {

    /// Tracks a **product** event with optional properties. Defaults to the
    /// `.product` channel at `.info` level.
    func track(_ event: String, properties: [String: any Sendable]? = nil) {
        track(event, channel: .product, level: .info, properties: properties)
    }

    /// Tracks a **diagnostic** event on the given channel at the given level,
    /// with no properties.
    func track(_ event: String, channel: AnalyticsChannel, level: AnalyticsLevel = .info) {
        track(event, channel: channel, level: level, properties: nil)
    }
}

/// Canonical event-name constants. Use these at call sites to catch typos at
/// compile time rather than at runtime.
enum AnalyticsEvent {
    // Product events
    static let appLaunched              = "app.launched"
    static let firstRunSeeded           = "firstRun.seeded"
    static let firstRunSkipped          = "firstRun.skipped"
    static let firstRunError            = "firstRun.error"

    // Diagnostic events — CloudKit container bootstrap
    static let cloudKitContainerBacked       = "cloudkit.container.backed"
    static let cloudKitContainerLocalFallback = "cloudkit.container.localFallback"
    static let cloudKitContainerLocalSuccess  = "cloudkit.container.localSuccess"
    static let cloudKitContainerFailed       = "cloudkit.container.failed"
}
