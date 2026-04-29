import Foundation

/// The repeating time interval over which a Budget allocates funds.
///
/// Ordered from shortest to longest: `daily < weekly < biweekly < monthly`.
enum BudgetPeriod: String, Codable, CaseIterable, Comparable {
  case daily
  case weekly
  case biweekly
  case monthly

  private var sortOrder: Int {
    switch self {
    case .daily: 0
    case .weekly: 1
    case .biweekly: 2
    case .monthly: 3
    }
  }

  static func < (lhs: BudgetPeriod, rhs: BudgetPeriod) -> Bool {
    lhs.sortOrder < rhs.sortOrder
  }

  /// PAUSED (Reset Cadences): this mapping is retained as design knowledge but is NOT consumed
  /// by `Budget.init` while the feature is paused. Do not introduce new callers. When unpausing:
  /// restore `resetCadence ?? period.defaultResetCadence` in `Budget.init`.
  /// The recommended default reset cadence when first creating a budget with this period.
  ///
  /// This mapping is intentional and not derived from enum ordering:
  /// daily → weekly, weekly → monthly, biweekly → quarterly, monthly → quarterly.
  ///
  /// **PAUSED** — not consumed by `Budget.init` while Reset Cadences are paused.
  nonisolated var defaultResetCadence: ResetCadence {
    switch self {
    case .daily: .weekly
    case .weekly: .monthly
    case .biweekly: .quarterly
    case .monthly: .quarterly
    }
  }
}
