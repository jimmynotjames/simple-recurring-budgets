import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Budget icon (F-4.03): Add/Edit view-model wiring

@MainActor
struct AddEditBudgetViewModelIconTests {
  // MARK: - Add mode

  @Test func addMode_iconDefaultsToNil() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    #expect(vm.icon == nil)
  }

  @Test func addMode_save_withIcon_persistsIcon() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Coffee"; vm.allocation = 7; vm.period = .daily
    vm.icon = "☕"
    vm.save(context: context)

    let saved = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
    #expect(saved.icon == "☕")
  }

  @Test func addMode_save_withoutIcon_leavesNil() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Coffee"; vm.allocation = 7; vm.period = .daily
    vm.save(context: context)

    let saved = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
    #expect(saved.icon == nil)
  }

  // MARK: - Edit mode

  @Test func editMode_seedsIconFromBudget() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .daily, icon: "☕")
    let change = AllocationChange(effectiveFrom: Date(), amount: 7)
    change.budget = budget; budget.allocationChangesStorage = [change]
    context.insert(budget)

    let vm = AddEditBudgetViewModel(editing: budget)
    #expect(vm.icon == "☕")
  }

  @Test func editMode_changingIcon_updatesBudgetAndBumpsLastModified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let before = Date(timeIntervalSinceNow: -3600)
    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .daily, icon: "☕")
    budget.lastModified = before
    let change = AllocationChange(effectiveFrom: Date(), amount: 7)
    change.budget = budget; budget.allocationChangesStorage = [change]
    context.insert(budget); try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.icon = "🍔"
    vm.save(context: context)

    #expect(budget.icon == "🍔")
    #expect(budget.lastModified > before)
  }

  @Test func editMode_removingIcon_setsNil() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .daily, icon: "☕")
    let change = AllocationChange(effectiveFrom: Date(), amount: 7)
    change.budget = budget; budget.allocationChangesStorage = [change]
    context.insert(budget); try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.icon = nil
    vm.save(context: context)

    #expect(budget.icon == nil)
  }

  @Test func editMode_iconOnlyChange_stillSaves() throws {
    // An icon-only edit must satisfy the Save-needed gate (iconChanged) and persist,
    // bumping lastModified even though no other field changed.
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let before = Date(timeIntervalSinceNow: -3600)
    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .daily, icon: nil)
    budget.lastModified = before
    let change = AllocationChange(effectiveFrom: Date(), amount: 7)
    change.budget = budget; budget.allocationChangesStorage = [change]
    context.insert(budget); try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.icon = "☕"
    vm.save(context: context)

    #expect(budget.icon == "☕")
    #expect(budget.lastModified > before)
  }
}
