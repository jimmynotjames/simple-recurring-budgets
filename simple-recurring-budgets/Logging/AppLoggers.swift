import OSLog

extension Logger {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "simple-recurring-budgets"

  /// Covers app startup, container creation, and first-run seeding.
  static let bootstrap = Logger(subsystem: subsystem, category: "bootstrap")

  /// Covers CloudKit sync status, configuration, and fallback decisions.
  static let cloudKit = Logger(subsystem: subsystem, category: "cloudkit")

  /// Covers view lifecycle events and user-initiated UI actions.
  static let ui = Logger(subsystem: subsystem, category: "ui")

  /// Covers SwiftData write failures surfaced by the shared persistence-save
  /// helper. Success paths emit nothing on this channel. See the
  /// `diagnostic-logging` capability and `docs/analytics-spec.md` §17 for the
  /// architectural boundary with `AnalyticsClient`.
  static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
