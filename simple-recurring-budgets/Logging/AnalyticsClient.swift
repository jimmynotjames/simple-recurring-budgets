import Foundation

/// Product analytics abstraction. Routes business-metric events to the
/// configured backend (Mixpanel in production; console print in debug builds).
///
/// Diagnostic / operational events (container bootstrap, CloudKit sync, etc.)
/// are logged directly via `OSLog.Logger` in `AppLoggers.swift` and never
/// pass through this protocol.
///
/// **Allow/deny contract (§5 analytics-spec.md):**
/// - Allowed per event: categorical Budget properties (`period`, `carry_over_enabled`,
///   `currency_code`), bucketed counts, Boolean flags, and the two accepted-risk
///   exceptions (`budget_name`, `budget_allocation_amount`).
/// - **Hard ban**: No `ExpenseItem` field (name, amount, date, notes) is ever
///   transmitted by value. No free-text other than `budget_name`. No money-shaped
///   value other than `budget_allocation_amount`.
/// - No `OSLog`-sourced data passes through this protocol; the two channels are
///   architecturally independent (§8, §17 analytics-spec.md).
protocol AnalyticsClient: AnyObject, Sendable {
  func track(_ event: String, properties: [String: any Sendable]?)
  func identify(_ distinctId: String?)
  func reset()
}

extension AnalyticsClient {
  func track(_ event: String) {
    track(event, properties: nil)
  }
}

// MARK: - Canonical event names

/// Canonical event-name constants for Phase 1 (analytics-spec.md §9).
///
/// All names are `snake_case`. Use these constants at every call site — never
/// inline string literals — so typos are caught at compile time.
enum AnalyticsEvent {
  nonisolated static let appOpened = "app_opened"
  nonisolated static let budgetCreated = "budget_created"
  nonisolated static let budgetEdited = "budget_edited"
  nonisolated static let budgetDeleted = "budget_deleted"
  nonisolated static let budgetReset = "budget_reset"
  nonisolated static let budgetPaused = "budget_paused"
  nonisolated static let budgetResumed = "budget_resumed"
  nonisolated static let carryOverReset = "carry_over_reset"
  nonisolated static let expenseLogged = "expense_logged"
  nonisolated static let expenseEdited = "expense_edited"
  nonisolated static let expenseDeleted = "expense_deleted"
  nonisolated static let settingsOpened = "settings_opened"
  nonisolated static let settingChanged = "setting_changed"
  nonisolated static let analyticsConsentChanged = "analytics_consent_changed"
}

// MARK: - Canonical property keys

/// Canonical property-key constants for Phase 1 (analytics-spec.md §10).
///
/// Keys match the `snake_case` names defined in the spec exactly. Use these
/// constants at every `track(_:properties:)` call site — never inline string
/// literals.
enum AnalyticsProperty {
  // MARK: Per-event — budget_*

  nonisolated static let period = "period"
  nonisolated static let carryOverEnabled = "carry_over_enabled"
  nonisolated static let currencyCode = "currency_code"
  nonisolated static let isFirstBudget = "is_first_budget"
  nonisolated static let timeSinceFirstAppOpenBucket = "time_since_first_app_open_bucket"
  /// Accepted-risk allow-listed per analytics-spec.md §5.4.
  nonisolated static let budgetName = "budget_name"
  /// Accepted-risk allow-listed per analytics-spec.md §5.4. Always paired with `currency_code`.
  nonisolated static let budgetAllocationAmount = "budget_allocation_amount"

  // MARK: Per-event — expense_*

  nonisolated static let isAddFunds = "is_add_funds"
  nonisolated static let fromScreen = "from_screen"
  nonisolated static let timeSinceBudgetCreatedBucket = "time_since_budget_created_bucket"

  // MARK: Per-event — setting_changed

  nonisolated static let settingName = "setting_name"
  nonisolated static let newValue = "new_value"
  nonisolated static let oldValue = "old_value"

  // MARK: Super properties (analytics-spec.md §10.2)

  nonisolated static let appVersion = "app_version"
  nonisolated static let appBuild = "app_build"
  nonisolated static let deviceClass = "device_class"
  nonisolated static let locale = "locale"
  nonisolated static let region = "region"
  nonisolated static let weekStartDay = "week_start_day"
  nonisolated static let currencyDisplayPreference = "currency_display_preference"
  nonisolated static let icloudState = "icloud_state"
  nonisolated static let budgetsCountBucket = "budgets_count_bucket"
  nonisolated static let carryOverDefaultEnabled = "carry_over_default_enabled"
  nonisolated static let consentJurisdiction = "consent_jurisdiction"
  nonisolated static let bundleId = "bundle_id"

  // MARK: People properties (analytics-spec.md §10.3)

  nonisolated static let firstSeenAt = "first_seen_at"
  nonisolated static let analyticsOptInAt = "analytics_opt_in_at"
  nonisolated static let lastAppOpenAt = "last_app_open_at"
  nonisolated static let dominantPeriod = "dominant_period"
  nonisolated static let usesCarryOver = "uses_carry_over"
  nonisolated static let hasDisabledCarryOver = "has_disabled_carry_over"
  nonisolated static let budgetsWithCarryOverOnCountBucket = "budgets_with_carry_over_on_count_bucket"
  nonisolated static let defaultCurrencyCode = "default_currency_code"
}
