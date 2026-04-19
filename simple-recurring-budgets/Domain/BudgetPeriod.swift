//
//  BudgetPeriod.swift
//  simple-recurring-budgets
//
//  Created by Jimmy Ho on 4/11/26.
//

import Foundation

/// The repeating time interval over which a Budget allocates funds.
///
/// Ordered from shortest to longest: `daily < weekly < biweekly < monthly`.
enum BudgetPeriod: String, Codable, CaseIterable, Comparable {
    case daily = "daily"
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"

    private var sortOrder: Int {
        switch self {
        case .daily: return 0
        case .weekly: return 1
        case .biweekly: return 2
        case .monthly: return 3
        }
    }

    static func < (lhs: BudgetPeriod, rhs: BudgetPeriod) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    /// The recommended default reset cadence when first creating a budget with this period.
    ///
    /// This mapping is intentional and not derived from enum ordering:
    /// daily → weekly, weekly → monthly, biweekly → quarterly, monthly → quarterly.
    nonisolated var defaultResetCadence: ResetCadence {
        switch self {
        case .daily: return .weekly
        case .weekly: return .monthly
        case .biweekly: return .quarterly
        case .monthly: return .quarterly
        }
    }
}
