import Foundation

// PAUSED (Reset Cadences): The Reset Cadences feature is currently paused.
// - No UI surfaces this type today; do not introduce new UI, Figma designs, or specs that use it.
// - The type, cases, and `isBroaderThan`/`validResetCadences` methods are retained for the
//   (currently unused) scheduled-reset code path and for the future un-pause.
// - All new `Budget` instances default to `.never` (see `Budget.init`).
// - To un-pause: restore `period.defaultResetCadence` in `Budget.init` and remove these comments.

/// How often a Budget's carry-over amount is automatically cleared.
///
/// Not `Comparable` — use `isBroaderThan(_:)` for cross-type comparison with `BudgetPeriod`.
/// `.quarterly` and `.never` are only valid as reset cadences, not as budget periods.
enum ResetCadence: String, Codable, CaseIterable {
  case weekly
  case biweekly
  case monthly
  case quarterly
  case never

  /// Returns `true` when this cadence is strictly broader than the given `BudgetPeriod`,
  /// meaning it is a valid reset cadence for that period (resets cannot be more frequent
  /// than the period itself).
  ///
  /// `.never` and `.quarterly` are always valid for any period.
  func isBroaderThan(_ period: BudgetPeriod) -> Bool {
    switch self {
    case .never: true
    case .quarterly: true
    case .monthly: period < .monthly
    case .biweekly: period < .biweekly
    case .weekly: period < .weekly
    }
  }

  /// Returns all `ResetCadence` options that are valid for the given `BudgetPeriod`.
  static func validResetCadences(for period: BudgetPeriod) -> [ResetCadence] {
    ResetCadence.allCases.filter { $0.isBroaderThan(period) }
  }
}
