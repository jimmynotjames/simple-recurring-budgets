//
//  AnalyticsEnvironment.swift
//  simple-recurring-budgets
//

import SwiftUI

private struct AnalyticsClientKey: EnvironmentKey {
    static let defaultValue: any AnalyticsClient = ConsoleAnalyticsClient()
}

extension EnvironmentValues {
    /// The active analytics client for the current environment.
    ///
    /// Inject a `SpyAnalyticsClient` in tests or SwiftUI Previews to capture
    /// events without producing real log output.
    var analytics: any AnalyticsClient {
        get { self[AnalyticsClientKey.self] }
        set { self[AnalyticsClientKey.self] = newValue }
    }
}
