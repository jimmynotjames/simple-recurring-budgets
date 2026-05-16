import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

@MainActor
struct AddEditBudgetViewModelTests {
  // MARK: - Add-mode defaults

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

  // MARK: - Edit-mode seeding

  @Test func editMode_seedsFieldsFromBudget() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "EUR", period: .monthly, isCarryOverEnabled: false)
    let change = AllocationChange(effectiveFrom: Date(), amount: 300)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    context.insert(budget)

    let vm = AddEditBudgetViewModel(editing: budget)

    #expect(vm.name == "Food")
    #expect(vm.allocation == 300)
    #expect(vm.currencyCode == "EUR")
    #expect(vm.period == .monthly)
    #expect(vm.isCarryOverEnabled == false)
  }

  @Test func editMode_unrecognisedPeriodFallsBackToDaily() {
    let budget = Budget()
    budget.period = "quinquennial"
    let vm = AddEditBudgetViewModel(editing: budget)
    #expect(vm.period == .daily)
  }

  // MARK: - canSave

  @Test func canSave_initialState_false() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    #expect(!vm.canSave)
  }

  @Test func canSave_falseWhenNameIsEmpty() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = ""; vm.allocation = 50
    #expect(!vm.canSave)
  }

  @Test func canSave_falseWhenAllocationNil() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Coffee"; vm.allocation = nil
    #expect(!vm.canSave)
  }

  @Test func canSave_falseWhenWhitespaceName() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "   "; vm.allocation = 50
    #expect(!vm.canSave)
  }

  @Test func canSave_falseWhenAllocationZero() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Groceries"; vm.allocation = 0
    #expect(!vm.canSave)
  }

  @Test func canSave_trueWhenValid() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Groceries"; vm.allocation = 100
    #expect(vm.canSave)
  }

  // MARK: - Add-mode save: inserts Budget + AllocationChange

  @Test func addMode_save_insertsBudgetWithInitialAllocationChange() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Transit"
    vm.allocation = 80
    vm.currencyCode = "CAD"
    vm.period = .weekly
    vm.isCarryOverEnabled = false

    vm.save(context: context)

    let budgets = try context.fetch(FetchDescriptor<Budget>())
    #expect(budgets.count == 1)
    let saved = try #require(budgets.first)
    #expect(saved.name == "Transit")
    #expect(saved.currencyCode == "CAD")
    #expect(saved.period == BudgetPeriod.weekly.rawValue)
    #expect(saved.isCarryOverEnabled == false)
    #expect(saved.sortOrder == 0)
    #expect(saved.currentAllocation == 80)

    // Must have an initial AllocationChange
    let changes = try context.fetch(FetchDescriptor<AllocationChange>())
    #expect(changes.count == 1)
    #expect(changes.first?.amount == 80)
    #expect(saved.startDate != nil)
  }

  @Test func addMode_save_invalid_doesNotInsert() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Groceries"; vm.allocation = nil
    vm.save(context: context)

    let budgets = try context.fetch(FetchDescriptor<Budget>())
    #expect(budgets.isEmpty)
  }

  @Test func addMode_save_sortOrderIsMaxPlusOne() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let b1 = Budget(name: "A"); b1.sortOrder = 0; context.insert(b1)
    let b2 = Budget(name: "B"); b2.sortOrder = 1; context.insert(b2)
    try context.save()

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "C"; vm.allocation = 1
    vm.save(context: context)

    let all = try context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.sortOrder)]))
    #expect(all.last?.name == "C")
    #expect(all.last?.sortOrder == 2)
  }

  // MARK: - Edit-mode save

  @Test func editMode_save_noOp_doesNotModifyLastModified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let original = Date(timeIntervalSinceNow: -3600)
    let budget = Budget(name: "Rent", currencyCode: "USD", period: .monthly)
    budget.lastModified = original
    let change = AllocationChange(effectiveFrom: Date(), amount: 1200)
    change.budget = budget; budget.allocationChangesStorage = [change]
    context.insert(budget); try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.save(context: context)

    #expect(budget.lastModified == original)
  }

  @Test func editMode_save_nameChange_bumpsLastModified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let before = Date(timeIntervalSinceNow: -3600)
    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .weekly)
    budget.lastModified = before
    let change = AllocationChange(effectiveFrom: Date(), amount: 500)
    change.budget = budget; budget.allocationChangesStorage = [change]
    context.insert(budget); try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.name = "Food"
    vm.save(context: context)

    #expect(budget.name == "Food")
    #expect(budget.lastModified > before)
  }

  // MARK: - Period immutability

  @Test func editMode_save_periodChangeIsIgnored() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let original = Date(timeIntervalSinceNow: -3600)
    let budget = Budget(name: "Transport", currencyCode: "USD", period: .weekly)
    budget.lastModified = original
    let change = AllocationChange(effectiveFrom: Date(), amount: 100)
    change.budget = budget; budget.allocationChangesStorage = [change]
    context.insert(budget); try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.period = .monthly
    vm.save(context: context)

    #expect(budget.period == BudgetPeriod.weekly.rawValue)
    #expect(budget.lastModified == original)
  }

  // MARK: - Delete

  @Test func delete_inEditMode_removesBudgetFromStore() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .weekly)
    context.insert(budget); try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.delete(context: context)

    #expect(try context.fetch(FetchDescriptor<Budget>()).isEmpty)
  }

  @Test func delete_inAddMode_isNoOp() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let existing = Budget(name: "Rent", currencyCode: "USD", period: .monthly)
    context.insert(existing); try context.save()

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.delete(context: context)

    #expect(try context.fetch(FetchDescriptor<Budget>()).count == 1)
  }

  @Test func delete_cascadesToExpenseItems() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Entertainment", currencyCode: "USD", period: .monthly)
    context.insert(budget)
    for i in 1 ... 2 {
      let e = ExpenseItem(amount: Decimal(i) * 10)
      e.budget = budget; context.insert(e)
    }
    try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.delete(context: context)

    #expect(try context.fetch(FetchDescriptor<ExpenseItem>()).isEmpty)
  }

  // MARK: - save(context:) convenience overload compiles

  @Test func saveMethod_doesNotRequireAppSettings() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "SignatureCheck"; vm.allocation = 1
    vm.save(context: context)
    #expect(try context.fetch(FetchDescriptor<Budget>()).count == 1)
  }
}
