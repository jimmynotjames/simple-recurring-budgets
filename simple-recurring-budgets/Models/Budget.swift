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
    // PAUSED (Reset Cadences): feature is paused; stored default is `.never` while paused.
    // Do not surface Reset Cadence in any UI or plan while this pause is in effect.
    /// Stored as `ResetCadence.rawValue`. Default is `"never"` while Reset Cadences are paused.
    var resetCadence: String = ResetCadence.never.rawValue
    /// Sourced from `AppSettings.defaultCarryOverEnabled` when creating budgets; persisted per budget.
    var isCarryOverEnabled: Bool = true

    /// Persisted one-to-many relationship to `ExpenseItem` rows (cascade delete on the parent).
    ///
    /// CloudKit requires every relationship to be optional in the persisted model, not only during
    /// sync: the server does not process relationship updates atomically, and related records can
    /// arrive out of order or remain temporarily unresolved. `nil` or an empty collection can also
    /// appear in edge cases outside normal app flows. Use `expenseItems` everywhere in application
    /// code so callers never branch on optionality; treat this property as storage for SwiftData only.
    @Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)
    var expenses: [ExpenseItem]? = []

    /// Non-optional view of the same relationship for app code (`expenses ?? []`).
    var expenseItems: [ExpenseItem] {
        get { expenses ?? [] }
        set {
            // Replacing the whole array assigns a new relationship collection, not an in-place merge.
            // That can detach or remove linked `ExpenseItem`s (per delete rules and context) in ways
            // that differ from appending, removing, or setting `ExpenseItem.budget`. Use full assignment
            // only when you intend to replace the entire set; otherwise mutate the array or the child.
            expenses = newValue
        }
    }

    // PAUSED (Reset Cadences): `Budget.init` defaults to `.never` while the feature is paused.
    // Do NOT pass `period.defaultResetCadence` as the fallback here until the pause is lifted.
    // When unpausing: restore `resetCadence ?? period.defaultResetCadence` and remove these comments.
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
        self.resetCadence = (resetCadence ?? .never).rawValue
        self.isCarryOverEnabled = isCarryOverEnabled
    }
}

extension Budget {
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
