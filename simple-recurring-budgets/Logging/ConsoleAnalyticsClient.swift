//
//  ConsoleAnalyticsClient.swift
//  simple-recurring-budgets
//

import OSLog

/// An `AnalyticsClient` that routes events based on their channel:
///
/// - **Diagnostic channels** (`.bootstrap`, `.cloudKit`, `.ui`): routed to the
///   matching `OSLog.Logger` at the requested severity level. These fire in all
///   build configurations and are visible in Console.app and the Xcode console.
///
/// - **Product channel** (`.product`): printed to the Xcode console via `print`
///   behind `#if DEBUG`. Silent no-op in release builds.
///
/// When a real analytics backend (e.g. Mixpanel) is ready, replace or extend
/// this type at the single construction site in `simple_recurring_budgetsApp`.
final class ConsoleAnalyticsClient: AnalyticsClient {

    func track(_ event: String, channel: AnalyticsChannel, level: AnalyticsLevel, properties: [String: any Sendable]?) {
        switch channel {
        case .bootstrap:
            log(event, to: .bootstrap, level: level, properties: properties)
        case .cloudKit:
            log(event, to: .cloudKit, level: level, properties: properties)
        case .ui:
            log(event, to: .ui, level: level, properties: properties)
        case .product:
            #if DEBUG
            if let properties, !properties.isEmpty {
                print("[analytics] \(event) \(properties)")
            } else {
                print("[analytics] \(event)")
            }
            #endif
        }
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

    // MARK: - Private

    private func log(
        _ event: String,
        to logger: Logger,
        level: AnalyticsLevel,
        properties: [String: any Sendable]?
    ) {
        let message: String = {
            guard let properties, !properties.isEmpty else { return event }
            return "\(event) \(properties.description)"
        }()

        switch level {
        case .info:   logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .error:  logger.error("\(message, privacy: .public)")
        }
    }
}
