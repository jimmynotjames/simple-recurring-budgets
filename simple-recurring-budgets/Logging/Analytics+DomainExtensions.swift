import Foundation

// MARK: - Weekday

extension Weekday {
  /// Snake-case string value for the analytics `week_start_day` super property.
  var analyticsValue: String {
    switch self {
    case .sunday: "sunday"
    case .monday: "monday"
    case .tuesday: "tuesday"
    case .wednesday: "wednesday"
    case .thursday: "thursday"
    case .friday: "friday"
    case .saturday: "saturday"
    }
  }
}

// MARK: - CurrencyDisplayPreference

extension CurrencyDisplayPreference {
  /// Snake-case string value for the `currency_display_preference` super property.
  var analyticsValue: String {
    switch self {
    case .symbol: "symbol"
    case .code: "code"
    case .codeAndSymbol: "code_and_symbol"
    }
  }
}

// MARK: - SyncStatus.RowState

extension SyncStatus.RowState {
  /// String value for the `icloud_state` super property.
  var analyticsValue: String {
    switch self {
    case .checking: "checking"
    case .available: "available"
    case .unavailable: "unavailable"
    case .paused: "paused"
    }
  }
}

// MARK: - BudgetPeriod

extension BudgetPeriod {
  /// Analytics value for the `period` per-event property (§10.1).
  var analyticsValue: String {
    switch self {
    case .daily: "daily"
    case .weekly: "weekly"
    case .biweekly: "biweekly"
    case .monthly: "monthly"
    case .specificDates: "specific_dates"
    }
  }
}

// MARK: - Time-bucket helpers

/// Buckets a duration (in seconds) since first app open into the
/// `time_since_first_app_open_bucket` property values (§10.1).
func timeSinceFirstOpenBucket(seconds: TimeInterval) -> String {
  switch seconds {
  case ..<300: "<5m"
  case ..<3600: "<1h"
  case ..<86400: "<1d"
  case ..<604_800: "<7d"
  default: "≥7d"
  }
}

/// Buckets a duration since budget creation into the
/// `time_since_budget_created_bucket` property values (§10.1).
func timeSinceBudgetCreatedBucket(seconds: TimeInterval) -> String {
  switch seconds {
  case ..<300: "<5m"
  case ..<3600: "<1h"
  case ..<86400: "<1d"
  default: "≥1d"
  }
}
