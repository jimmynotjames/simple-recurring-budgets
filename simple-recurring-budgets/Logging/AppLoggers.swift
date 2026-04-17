//
//  AppLoggers.swift
//  simple-recurring-budgets
//

import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "simple-recurring-budgets"

    /// Covers app startup, container creation, and first-run seeding.
    static let bootstrap = Logger(subsystem: subsystem, category: "bootstrap")

    /// Covers CloudKit sync status, configuration, and fallback decisions.
    static let cloudKit = Logger(subsystem: subsystem, category: "cloudkit")

    /// Covers view lifecycle events and user-initiated UI actions.
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
