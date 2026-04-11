//
//  ResetCadence.swift
//  simple-recurring-budgets
//
//  Created by Jimmy Ho on 4/11/26.
//

import Foundation

/// How often a Budget's carry-over amount is automatically cleared.
///
/// Not `Comparable` — use `isBroaderThan(_:)` for cross-type comparison with `BudgetPeriod`.
/// `.quarterly` and `.never` are only valid as reset cadences, not as budget periods.
enum ResetCadence: String, Codable, CaseIterable {
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"
    case quarterly = "quarterly"
    case never = "never"

    /// Returns `true` when this cadence is strictly broader than the given `BudgetPeriod`,
    /// meaning it is a valid reset cadence for that period (resets cannot be more frequent
    /// than the period itself).
    ///
    /// `.never` and `.quarterly` are always valid for any period.
    func isBroaderThan(_ period: BudgetPeriod) -> Bool {
        switch self {
        case .never: return true
        case .quarterly: return true
        case .monthly: return period < .monthly
        case .biweekly: return period < .biweekly
        case .weekly: return period < .weekly
        }
    }

    /// Returns all `ResetCadence` options that are valid for the given `BudgetPeriod`.
    static func validResetCadences(for period: BudgetPeriod) -> [ResetCadence] {
        ResetCadence.allCases.filter { $0.isBroaderThan(period) }
    }
}
