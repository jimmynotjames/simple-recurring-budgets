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
    /// For new rows, set from `nextSortOrder(for:)` immediately before `insert` (see extension).
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var lastModified: Date = Date()
    var carryOverAmount: Decimal = 0
    var carryOverLastProcessedDate: Date = Date()
    var carryOverLastResetDate: Date = Date()
    /// Stored as `ResetCadence.rawValue`.
    var resetCadence: String = ResetCadence.weekly.rawValue
    /// Sourced from `AppSettings.defaultCarryOverEnabled` when creating budgets; persisted per budget.
    var isCarryOverEnabled: Bool = true

    /// Optional to-many for CloudKit: SwiftData requires optional relationships when using CloudKit sync.
    @Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)
    var expenses: [ExpenseItem]? = nil

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

extension Budget {
    /// Expenses for this budget; `nil` and empty are treated the same for display and iteration.
    var expenseList: [ExpenseItem] {
        expenses ?? []
    }

    /// Returns the next `sortOrder` for a **new** budget: `0` if none exist, else `max(existing.sortOrder) + 1`.
    /// Call before `context.insert(_:)` so the fetch does not include the new instance.
    static func nextSortOrder(for context: ModelContext) throws -> Int {
        var descriptor = FetchDescriptor<Budget>()
        descriptor.sortBy = [SortDescriptor(\.sortOrder, order: .reverse)]
        descriptor.fetchLimit = 1
        guard let maxBudget = try context.fetch(descriptor).first else { return 0 }
        return maxBudget.sortOrder + 1
    }
}
