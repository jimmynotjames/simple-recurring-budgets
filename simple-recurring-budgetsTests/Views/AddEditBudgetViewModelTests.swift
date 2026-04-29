import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

@MainActor
struct AddEditBudgetViewModelTests {
  // MARK: - 7.1.a  Add-mode defaults

  @Test func addMode_defaultsWithCarryOverOn() {
    let store = MockKeyValueStore()
    store.set(true, forKey: AppSettings.defaultCarryOverEnabledKey)
    let settings = AppSettings(store: store)

    let vm = AddEditBudgetViewModel(settings: settings)

    #expect(vm.name == "")
    #expect(vm.allocation == nil)
    #expect(vm.period == .daily)
    #expect(vm.isCarryOverEnabled == true)
    #expect(vm.currencyCode == (Locale.current.currency?.identifier ?? "USD"))
  }

  @Test func addMode_defaultsWithCarryOverOff() {
    let store = MockKeyValueStore()
    store.set(false, forKey: AppSettings.defaultCarryOverEnabledKey)
    let settings = AppSettings(store: store)

    let vm = AddEditBudgetViewModel(settings: settings)

    #expect(vm.isCarryOverEnabled == false)
  }

  // MARK: - 7.1.b  Edit-mode seeding

  @Test func editMode_seedsFieldsFromBudget() {
    let budget = Budget(
      name: "Food",
      allocation: 300,
      currencyCode: "EUR",
      period: .monthly,
      isCarryOverEnabled: false
    )

    let vm = AddEditBudgetViewModel(editing: budget)

    #expect(vm.name == "Food")
    #expect(vm.allocation == 300)
    #expect(vm.currencyCode == "EUR")
    #expect(vm.period == .monthly)
    #expect(vm.isCarryOverEnabled == false)
  }

  @Test func editMode_unrecognisedPeriodFallsBackToDaily() {
    let budget = Budget()
    budget.period = "quinquennial" // not a valid BudgetPeriod raw value

    let vm = AddEditBudgetViewModel(editing: budget)

    #expect(vm.period == .daily)
  }

  // MARK: - 7.1.c  canSave

  @Test func addMode_initialState_saveDisabledUntilNameAndAllocation() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())

    #expect(vm.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(vm.allocation == nil)
    #expect(!vm.canSave)
  }

  @Test func canSave_falseWhenNameIsEmpty() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = ""
    vm.allocation = 50
    #expect(!vm.canSave)
  }

  @Test func canSave_falseWhenAllocationUnsetEvenIfNameProvided() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Coffee"
    vm.allocation = nil
    #expect(!vm.canSave)
  }

  @Test func canSave_falseWhenNameIsWhitespaceOnly() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "   "
    vm.allocation = 50
    #expect(!vm.canSave)
  }

  @Test func canSave_falseWhenAllocationIsZero() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Groceries"
    vm.allocation = 0
    #expect(!vm.canSave)
  }

  @Test func canSave_falseWhenAllocationIsNegative() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Groceries"
    vm.allocation = -1
    #expect(!vm.canSave)
  }

  @Test func canSave_trueWhenNameNonEmptyAndAllocationPositive() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Groceries"
    vm.allocation = 100
    #expect(vm.canSave)
  }

  // MARK: - 7.1.d  Add-mode save: insert + sortOrder

  @Test func addMode_save_insertsOneBudgetWithDraftedValues_emptyStore() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Transit"
    vm.allocation = 80
    vm.currencyCode = "CAD"
    vm.period = .weekly
    vm.isCarryOverEnabled = false

    vm.save(context: context)

    let all = try context.fetch(FetchDescriptor<Budget>())
    #expect(all.count == 1)
    let saved = try #require(all.first)
    #expect(saved.name == "Transit")
    #expect(saved.allocation == 80)
    #expect(saved.currencyCode == "CAD")
    #expect(saved.period == BudgetPeriod.weekly.rawValue)
    #expect(saved.isCarryOverEnabled == false)
    #expect(saved.sortOrder == 0)
  }

  @Test func addMode_save_whenInvalidDoesNotInsert_budget() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let vmMissingAllocation = AddEditBudgetViewModel(settings: AppSettings())
    vmMissingAllocation.name = "Groceries"
    vmMissingAllocation.allocation = nil
    vmMissingAllocation.save(context: context)
    let afterMissingAllocation = try context.fetch(FetchDescriptor<Budget>())
    #expect(afterMissingAllocation.isEmpty)

    let vmMissingName = AddEditBudgetViewModel(settings: AppSettings())
    vmMissingName.name = ""
    vmMissingName.allocation = 100
    vmMissingName.save(context: context)
    let afterMissingName = try context.fetch(FetchDescriptor<Budget>())
    #expect(afterMissingName.isEmpty)
  }

  @Test func addMode_save_sortOrderIsMaxPlusOne_withExistingBudgets() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let b1 = Budget(name: "A"); b1.sortOrder = 0; context.insert(b1)
    let b2 = Budget(name: "B"); b2.sortOrder = 1; context.insert(b2)
    try context.save()

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "C"
    vm.allocation = 1
    vm.save(context: context)

    let all = try context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.sortOrder)]))
    #expect(all.last?.name == "C")
    #expect(all.last?.sortOrder == 2)
  }

  // MARK: - 7.1.e  Edit-mode save: no-op

  @Test func editMode_save_noOp_doesNotModifyLastModified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let original = Date(timeIntervalSinceNow: -3600)
    let budget = Budget(name: "Rent", allocation: 1200, currencyCode: "USD", period: .monthly)
    budget.lastModified = original
    context.insert(budget)
    try context.save()

    // Edit VM seeded from the same values — nothing changed
    let vm = AddEditBudgetViewModel(editing: budget)
    vm.save(context: context)

    #expect(budget.lastModified == original)
  }

  // MARK: - 7.1.f  Edit-mode save: single-field change

  @Test func editMode_save_singleFieldChange_updatesFieldAndLastModified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let before = Date(timeIntervalSinceNow: -3600)
    let budget = Budget(name: "Groceries", allocation: 500, currencyCode: "USD", period: .weekly)
    budget.lastModified = before
    budget.carryOverAmount = 42
    budget.sortOrder = 7
    context.insert(budget)
    try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.name = "Food" // only change
    vm.save(context: context)

    #expect(budget.name == "Food")
    #expect(budget.lastModified >= before)
    #expect(budget.lastModified != before)
    // Other fields untouched
    #expect(budget.allocation == 500)
    #expect(budget.currencyCode == "USD")
    #expect(budget.period == BudgetPeriod.weekly.rawValue)
    #expect(budget.carryOverAmount == 42)
    #expect(budget.sortOrder == 7)
  }

  // MARK: - 7.1.g  Edit-mode save: multi-field change

  @Test func editMode_save_multiFieldChange_updatesBothFieldsAndOneLastModified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let before = Date(timeIntervalSinceNow: -3600)
    let budget = Budget(name: "Original", allocation: 100, currencyCode: "USD", period: .daily)
    budget.lastModified = before
    context.insert(budget)
    try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.name = "Updated"
    vm.allocation = 200
    vm.save(context: context)

    #expect(budget.name == "Updated")
    #expect(budget.allocation == 200)
    // lastModified set exactly once
    let lastMod = budget.lastModified
    #expect(lastMod != before)
    // Reading again — should be identical (synchronous save)
    #expect(budget.lastModified == lastMod)
  }

  // MARK: - 7.1.h  Cancel semantics

  @Test func cancel_leavesStoreUnmodified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Bills", allocation: 750, currencyCode: "USD", period: .monthly)
    context.insert(budget)
    try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.name = "Changed" // mutate but do NOT call save
    vm.allocation = 9999

    // Re-fetch to confirm nothing persisted
    let all = try context.fetch(FetchDescriptor<Budget>())
    #expect(all.count == 1)
    #expect(all.first?.name == "Bills")
    #expect(all.first?.allocation == 750)
  }

  // MARK: - 7.1.i  Save signature: no AppSettings parameter

  /// Compile-time guard: if this test compiles, the correct signature is present.
  /// The call `vm.save(context: context)` would fail to compile if an overload
  /// requiring AppSettings were the only option.
  @Test func saveMethod_doesNotRequireAppSettings() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "SignatureCheck"
    vm.allocation = 1 // satisfy canSave guard in save(context:)
    vm.save(context: context) // must compile with (context:) only
    let all = try context.fetch(FetchDescriptor<Budget>())
    #expect(all.count == 1)
  }

  // MARK: - 7.1.j  Delete

  @Test func delete_inEditMode_removesBudgetFromStore() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Groceries", allocation: 200, currencyCode: "USD", period: .weekly)
    context.insert(budget)
    try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.delete(context: context)

    let remaining = try context.fetch(FetchDescriptor<Budget>())
    #expect(remaining.isEmpty, "Budget should be removed after delete(context:)")
  }

  @Test func delete_inAddMode_isNoOp() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let existing = Budget(name: "Rent", allocation: 1500, currencyCode: "USD", period: .monthly)
    context.insert(existing)
    try context.save()

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.delete(context: context) // should do nothing in Add mode

    let all = try context.fetch(FetchDescriptor<Budget>())
    #expect(all.count == 1, "No budget should be deleted when VM is in Add mode")
    #expect(all.first?.name == "Rent")
  }

  @Test func delete_inEditMode_doesNotAffectOtherBudgets() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let target = Budget(name: "Target", allocation: 50, currencyCode: "USD", period: .weekly)
    let other = Budget(name: "Other", allocation: 200, currencyCode: "USD", period: .monthly)
    context.insert(target)
    context.insert(other)
    try context.save()

    let vm = AddEditBudgetViewModel(editing: target)
    vm.delete(context: context)

    let remaining = try context.fetch(FetchDescriptor<Budget>())
    #expect(remaining.count == 1, "Only the target budget should be deleted")
    #expect(remaining.first?.name == "Other", "The non-target budget should be unaffected")
  }

  @Test func delete_inEditMode_cascadesToExpenseItems() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Entertainment", allocation: 100, currencyCode: "USD", period: .monthly)
    context.insert(budget)

    let expense1 = ExpenseItem(amount: 15)
    expense1.budget = budget
    context.insert(expense1)
    budget.expenseItems.append(expense1)

    let expense2 = ExpenseItem(amount: 30)
    expense2.budget = budget
    context.insert(expense2)
    budget.expenseItems.append(expense2)

    try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.delete(context: context)

    let remainingBudgets = try context.fetch(FetchDescriptor<Budget>())
    #expect(remainingBudgets.isEmpty, "Budget should be removed after delete")

    let remainingExpenses = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(remainingExpenses.isEmpty, "Cascade delete should remove all ExpenseItems belonging to the deleted budget")
  }
}
