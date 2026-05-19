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

  // MARK: - Specific Dates

  @Test func addMode_specificDates_defaultsAreNil() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    #expect(vm.startDate == nil)
    #expect(vm.endDate == nil)
  }

  @Test func addMode_specificDates_selectingPeriodDoesNotPrePopulateDates() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.period = .specificDates
    #expect(vm.startDate == nil)
    #expect(vm.endDate == nil)
  }

  @Test func canSave_specificDates_falseWhenDatesNil() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Trip"; vm.allocation = 1000; vm.period = .specificDates
    #expect(!vm.canSave)
  }

  @Test func canSave_specificDates_falseWhenStartAfterEnd() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Trip"; vm.allocation = 1000; vm.period = .specificDates
    let cal = Calendar.autoupdatingCurrent
    vm.startDate = cal.date(from: DateComponents(year: 2026, month: 5, day: 20))
    vm.endDate = cal.date(from: DateComponents(year: 2026, month: 5, day: 10))
    #expect(!vm.canSave)
  }

  @Test func canSave_specificDates_trueWhenAllSet() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Trip"; vm.allocation = 1000; vm.period = .specificDates
    let cal = Calendar.autoupdatingCurrent
    vm.startDate = cal.date(from: DateComponents(year: 2026, month: 5, day: 10))
    vm.endDate = cal.date(from: DateComponents(year: 2026, month: 5, day: 20))
    #expect(vm.canSave)
  }

  @Test func addMode_specificDates_save_writesBothDatesNormalised() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let cal = Calendar.autoupdatingCurrent
    let rawStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 18)))
    let rawEnd = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 25, hour: 9)))

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Italy Trip"; vm.allocation = 1500
    vm.period = .specificDates
    vm.startDate = rawStart; vm.endDate = rawEnd
    vm.save(context: context)

    let saved = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
    #expect(saved.period == BudgetPeriod.specificDates.rawValue)
    #expect(saved.startDate == cal.startOfDay(for: rawStart))
    #expect(saved.endDate == cal.startOfDay(for: rawEnd))

    let changes = try context.fetch(FetchDescriptor<AllocationChange>())
    #expect(changes.count == 1)
    #expect(changes.first?.effectiveFrom == cal.startOfDay(for: rawStart))
    #expect(changes.first?.amount == 1500)
  }

  @Test func addMode_specificDates_save_clampsIsCarryOverEnabledToFalse() throws {
    // Repro: user opens Add Budget with settings.defaultCarryOverEnabled=true (default).
    // VM seeds isCarryOverEnabled=true. User then switches to .specificDates — UI hides
    // the toggle but the VM value stays true. Without the saveNew clamp, the persisted
    // budget would carry `isCarryOverEnabled=true`, polluting analytics events and
    // Mixpanel cohorts that read `budget.isCarryOverEnabled` directly.
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let store = MockKeyValueStore()
    store.set(true, forKey: AppSettings.defaultCarryOverEnabledKey)
    let settings = AppSettings(store: store)

    let vm = AddEditBudgetViewModel(settings: settings)
    #expect(vm.isCarryOverEnabled == true) // seeded from settings default
    vm.name = "Italy Trip"
    vm.allocation = 1500
    vm.period = .specificDates
    let cal = Calendar.autoupdatingCurrent
    vm.startDate = cal.date(from: DateComponents(year: 2026, month: 5, day: 8))
    vm.endDate = cal.date(from: DateComponents(year: 2026, month: 5, day: 25))
    vm.save(context: context)

    let saved = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
    #expect(saved.isCarryOverEnabled == false)
  }

  @Test func addMode_recurring_save_preservesIsCarryOverEnabled() throws {
    // Sanity check: the clamp only applies to .specificDates.
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let store = MockKeyValueStore()
    store.set(true, forKey: AppSettings.defaultCarryOverEnabledKey)
    let settings = AppSettings(store: store)

    let vm = AddEditBudgetViewModel(settings: settings)
    vm.name = "Groceries"
    vm.allocation = 200
    vm.period = .weekly
    vm.save(context: context)

    let saved = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
    #expect(saved.isCarryOverEnabled == true)
  }

  @Test func editMode_specificDates_seedsStartAndEndFromBudget() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let cal = Calendar.autoupdatingCurrent
    let start = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let end = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 25)))

    let budget = Budget(name: "Italy Trip", currencyCode: "EUR", period: .specificDates, isCarryOverEnabled: false)
    budget.startDate = start; budget.endDate = end
    let change = AllocationChange(effectiveFrom: start, amount: 1500)
    change.budget = budget; budget.allocationChangesStorage = [change]
    context.insert(budget)

    let vm = AddEditBudgetViewModel(editing: budget)
    #expect(vm.period == .specificDates)
    #expect(vm.startDate == start)
    #expect(vm.endDate == end)
    #expect(vm.allocation == 1500)
  }

  @Test func editMode_specificDates_changingEndDateOnly_updatesBudgetAndBumpsLastModified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let cal = Calendar.autoupdatingCurrent
    let start = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let originalEnd = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 25)))
    let newEnd = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 30)))
    let before = Date(timeIntervalSinceNow: -3600)

    let budget = Budget(name: "Italy Trip", currencyCode: "EUR", period: .specificDates, isCarryOverEnabled: false)
    budget.startDate = start; budget.endDate = originalEnd
    budget.lastModified = before
    let change = AllocationChange(effectiveFrom: start, amount: 1500)
    change.budget = budget; budget.allocationChangesStorage = [change]
    context.insert(budget); try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.endDate = newEnd
    vm.save(context: context)

    #expect(budget.endDate == newEnd)
    #expect(budget.startDate == start)
    #expect(budget.lastModified > before)
    let changes = try context.fetch(FetchDescriptor<AllocationChange>())
    #expect(changes.count == 1)
    #expect(changes.first?.effectiveFrom == start)
  }

  // MARK: - Snap-forward: when startDate crosses past endDate, preserve window duration

  @Test func snapForward_startMovesPastEnd_preservesOriginalDuration() throws {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.period = .specificDates
    let cal = Calendar.autoupdatingCurrent
    let originalStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let originalEnd = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 15))) // 7-day window
    vm.startDate = originalStart
    vm.endDate = originalEnd

    // Move start past end: snap end forward to maintain the 7-day window.
    let newStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 20)))
    vm.startDate = newStart

    let expectedEnd = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 27)))
    #expect(vm.endDate == expectedEnd)
  }

  @Test func snapForward_startMovesBeforeEnd_leavesEndAlone() throws {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.period = .specificDates
    let cal = Calendar.autoupdatingCurrent
    let originalStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let originalEnd = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 25)))
    vm.startDate = originalStart
    vm.endDate = originalEnd

    let newStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 10)))
    vm.startDate = newStart

    #expect(vm.endDate == originalEnd)
  }

  @Test func snapForward_startSetWithEndNil_doesNothing() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.period = .specificDates
    let cal = Calendar.autoupdatingCurrent
    vm.startDate = cal.date(from: DateComponents(year: 2026, month: 5, day: 8))
    #expect(vm.endDate == nil)
  }

  @Test func snapForward_startSetFromNil_pastExistingEnd_collapsesToZeroWindow() throws {
    // No prior startDate means there's no duration to preserve — snap to a 0-day window.
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.period = .specificDates
    let cal = Calendar.autoupdatingCurrent
    let end = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 10)))
    vm.endDate = end
    let newStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 20)))
    vm.startDate = newStart
    #expect(vm.endDate == newStart)
  }

  @Test func snapForward_editModeSeeding_doesNotMutateEnd() throws {
    // Seed Edit mode with an inverted window (start > end) so the snap-forward
    // didSet WOULD fire if it leaked into init. The test passes only if Swift's
    // didSet/init contract holds: `endDate` must remain the seeded value, NOT
    // snap forward to `start + (end - start)` as it would on a regular setter call.
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let cal = Calendar.autoupdatingCurrent
    let start = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 25)))
    let end = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let budget = Budget(name: "Italy Trip", currencyCode: "EUR", period: .specificDates, isCarryOverEnabled: false)
    budget.startDate = start; budget.endDate = end
    let change = AllocationChange(effectiveFrom: end, amount: 1500)
    change.budget = budget; budget.allocationChangesStorage = [change]
    context.insert(budget)

    let vm = AddEditBudgetViewModel(editing: budget)
    #expect(vm.startDate == start)
    // If didSet leaked into init, endDate would have snapped to `start` (duration=0
    // collapse path). Seeding-preserved means didSet was correctly suppressed.
    #expect(vm.endDate == end)
  }

  @Test func editMode_specificDates_changingStartDate_realignsAllocationEffectiveFrom() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let cal = Calendar.autoupdatingCurrent
    let originalStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let newStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 9)))
    let end = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 25)))

    let budget = Budget(name: "Italy Trip", currencyCode: "EUR", period: .specificDates, isCarryOverEnabled: false)
    budget.startDate = originalStart; budget.endDate = end
    let change = AllocationChange(effectiveFrom: originalStart, amount: 1500)
    change.budget = budget; budget.allocationChangesStorage = [change]
    context.insert(budget); try context.save()

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.startDate = newStart
    vm.save(context: context)

    #expect(budget.startDate == newStart)
    let changes = try context.fetch(FetchDescriptor<AllocationChange>())
    #expect(changes.count == 1)
    #expect(changes.first?.effectiveFrom == newStart)
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
