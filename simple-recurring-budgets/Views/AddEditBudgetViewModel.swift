//
//  AddEditBudgetViewModel.swift
//  simple-recurring-budgets
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AddEditBudgetViewModel {

    // MARK: - Mode

    private enum Mode {
        case add
        case edit(Budget)
    }

    // MARK: - Draft state

    var name: String
    var allocation: Decimal?
    var currencyCode: String
    var period: BudgetPeriod
    var isCarryOverEnabled: Bool

    private let mode: Mode

    // MARK: - Mode introspection

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    // MARK: - Validation

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (allocation ?? 0) > 0
    }

    // MARK: - Init (Add mode)

    /// Seeds Add-mode defaults from `AppSettings`. Does NOT retain a reference to `settings`
    /// after initialisation (reads `defaultCarryOverEnabled` once and captures the value).
    init(settings: AppSettings) {
        self.name = ""
        self.allocation = nil
        self.currencyCode = Locale.current.currency?.identifier ?? "USD"
        self.period = .daily
        self.isCarryOverEnabled = settings.defaultCarryOverEnabled
        self.mode = .add
    }

    // MARK: - Init (Edit mode)

    init(editing budget: Budget) {
        self.name = budget.name
        self.allocation = budget.allocation
        self.currencyCode = budget.currencyCode
        self.period = BudgetPeriod(rawValue: budget.period) ?? .daily
        self.isCarryOverEnabled = budget.isCarryOverEnabled
        self.mode = .edit(budget)
    }

    // MARK: - Save

    /// Persists the draft to `context`. In Add mode, inserts a new `Budget`; in Edit
    /// mode, applies only the fields that actually changed so other mutable properties
    /// (carry-over amounts, sort order, etc.) are untouched. The view reads
    /// `@Environment(\.modelContext)` and passes it here; the VM never stores `context`.
    func save(context: ModelContext) {
        switch mode {
        case .add:
            guard canSave, let allocation = allocation else { return }
            let budget = Budget(
                name: name,
                allocation: allocation,
                currencyCode: currencyCode,
                period: period,
                resetCadence: nil,  // keeps the paused `.never` default from Budget.init
                isCarryOverEnabled: isCarryOverEnabled
            )
            budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0
            context.insert(budget)
            try? context.save()

        case .edit(let budget):
            var changed = false
            if budget.name != name {
                budget.name = name
                changed = true
            }
            if let newAlloc = allocation, budget.allocation != newAlloc {
                budget.allocation = newAlloc
                changed = true
            }
            if budget.currencyCode != currencyCode {
                budget.currencyCode = currencyCode
                changed = true
            }
            if budget.period != period.rawValue {
                budget.period = period.rawValue
                changed = true
            }
            if budget.isCarryOverEnabled != isCarryOverEnabled {
                budget.isCarryOverEnabled = isCarryOverEnabled
                changed = true
            }
            if changed {
                budget.lastModified = Date()
                try? context.save()
            }
        }
    }
}
