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
  /// Analytics value for the `period` per-event property.
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

/// Buckets seconds since first app open into `time_since_first_app_open_bucket` values.
func timeSinceFirstOpenBucket(seconds: TimeInterval) -> String {
  switch seconds {
  case ..<300: "<5m"
  case ..<3600: "<1h"
  case ..<86400: "<1d"
  case ..<604_800: "<7d"
  default: "≥7d"
  }
}

/// Buckets seconds since budget creation into `time_since_budget_created_bucket` values.
func timeSinceBudgetCreatedBucket(seconds: TimeInterval) -> String {
  switch seconds {
  case ..<300: "<5m"
  case ..<3600: "<1h"
  case ..<86400: "<1d"
  default: "≥1d"
  }
}

// MARK: - F-7.04 Recents bucketing helpers

// All three helpers produce short, stable categorical labels (as the analytics-spec.md §10 pipeline expects) with deliberately coarse boundaries to avoid pseudo-identification.

/// Buckets the number of Recents tiles visible at tap time into `recents_visible_count` values. The top
/// bucket is open-ended (`"8+"`): the product question is dense-vs-sparse, so finer granularity above 8
/// isn't worth the cardinality. Negative inputs fold into `"0"`.
func recentsVisibleCountBucket(_ count: Int) -> String {
  switch count {
  case ..<1: "0"
  case 1: "1"
  case 2 ... 3: "2-3"
  case 4 ... 7: "4-7"
  default: "8+"
  }
}

/// Buckets the 0-indexed position of the tapped Recents tile into `recents_tap_position` values. `0` and `1`
/// stay separate buckets because the key product question is whether users overwhelmingly tap the first
/// tile; collapsing them would erase that. Negative inputs fold into `"0"` (defensive; never reached).
func recentsTapPositionBucket(_ position: Int) -> String {
  switch position {
  case ..<1: "0"
  case 1: "1"
  case 2 ... 4: "2-4"
  default: "5+"
  }
}

/// Buckets the length of the typed Description query at tap time into `name_query_length` values. Separates
/// open-and-tap (`"0"`) from type-then-tap without exposing the raw count.
func nameQueryLengthBucket(_ length: Int) -> String {
  switch length {
  case ..<1: "0"
  case 1 ... 2: "1-2"
  default: "3+"
  }
}
