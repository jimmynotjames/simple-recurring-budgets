//
//  Budget.swift
//  simple-recurring-budgets
//
//  Created by Jimmy Ho on 4/11/26.
//

import Foundation
import SwiftData

/// A recurring budget that allocates a fixed `allocation` per `period`.
///
/// All monetary values use `Decimal`. The `period` and `resetCadence` properties
/// are stored as their `String` raw values for human-readable CloudKit records.
@Model
final class Budget {
    var id: UUID = UUID()
    var name: String = "Budget"
    var allocation: Decimal = 10
    var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    /// Stored as `BudgetPeriod.rawValue`.
    var period: String = BudgetPeriod.daily.rawValue
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var lastModified: Date = Date()
    var carryOverAmount: Decimal = 0
    var carryOverLastProcessedDate: Date = Date()
    var carryOverLastResetDate: Date = Date()
    /// Stored as `ResetCadence.rawValue`.
    var resetCadence: String = ResetCadence.weekly.rawValue
    var isCarryOverEnabled: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)
    var expenses: [ExpenseItem] = []

    init(
        name: String = "Budget",
        allocation: Decimal = 10,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
        period: BudgetPeriod = .daily,
        resetCadence: ResetCadence? = nil,
        isCarryOverEnabled: Bool = true
    ) {
        self.name = name
        self.allocation = allocation
        self.currencyCode = currencyCode
        self.period = period.rawValue
        self.resetCadence = (resetCadence ?? period.defaultResetCadence).rawValue
        self.isCarryOverEnabled = isCarryOverEnabled
    }
}
