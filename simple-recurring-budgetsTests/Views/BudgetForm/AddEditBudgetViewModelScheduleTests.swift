import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Tests for the Schedule disclosure / per-period `startDate` / `endDate` semantics
/// on `AddEditBudgetViewModel` for recurring period types (F-7.05 + F-7.07).
///
/// Specific-dates behaviour is exercised in the original `AddEditBudgetViewModelTests`;
/// this suite covers recurring-only paths and the period-change re-anchoring rule.
@MainActor
struct AddEditBudgetViewModelScheduleTests {
  // MARK: - Add-mode init pre-fill (task 3.1)

  @Test func addInit_preFillsStartDateForDefaultDaily() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    let cal = Calendar.autoupdatingCurrent
    #expect(vm.startDate == cal.startOfDay(for: Date()))
    #expect(vm.endDate == nil)
  }

  @Test func addInit_capturesWeekStartDay() {
    // `weekStartDay` is private but observable via the re-anchoring side effect:
    // switching to weekly should land on the captured weekStartDay's most-recent
    // anchor, not on whatever AppSettings reads at that moment.
    let store = MockKeyValueStore()
    store.set(Int64(Weekday.monday.rawValue), forKey: AppSettings.weekStartDayKey)
    let settings = AppSettings(store: store)
    let vm = AddEditBudgetViewModel(settings: settings)
    vm.period = .weekly
    let cal = Calendar.autoupdatingCurrent
    let dayStart = cal.startOfDay(for: Date())
    let weekday = cal.component(.weekday, from: dayStart)
    let daysBack = (weekday - Weekday.monday.rawValue + 7) % 7
    let expected = cal.date(byAdding: .day, value: -daysBack, to: dayStart)
    #expect(vm.startDate == expected)
  }

  @Test func addInit_weekStartDay_frozenAtInit_doesNotTrackLaterAppSettingsChanges() {
    // Contract: VM captures `weekStartDay` at construction. Later mutations to
    // AppSettings.weekStartDay must NOT affect the VM's anchor computation —
    // the sheet's behavior should be stable for its lifetime even if the user
    // somehow flips the global setting underneath it.
    let store = MockKeyValueStore()
    store.set(Int64(Weekday.monday.rawValue), forKey: AppSettings.weekStartDayKey)
    let settings = AppSettings(store: store)
    let vm = AddEditBudgetViewModel(settings: settings)
    // Mutate the global setting AFTER VM init.
    settings.weekStartDay = .sunday
    // Force re-anchoring by toggling period.
    vm.period = .monthly
    vm.period = .weekly
    // Anchor must still be Monday's (captured at init), not Sunday's.
    let cal = Calendar.autoupdatingCurrent
    let dayStart = cal.startOfDay(for: Date())
    let weekday = cal.component(.weekday, from: dayStart)
    let mondayDaysBack = (weekday - Weekday.monday.rawValue + 7) % 7
    let expectedMondayAnchor = cal.date(byAdding: .day, value: -mondayDaysBack, to: dayStart)
    #expect(vm.startDate == expectedMondayAnchor)
  }

  // MARK: - period.didSet re-anchoring (task 3.2)

  @Test func periodChange_toDaily_anchorsStartOfDay() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.period = .monthly
    vm.period = .daily
    let cal = Calendar.autoupdatingCurrent
    #expect(vm.startDate == cal.startOfDay(for: Date()))
    #expect(vm.endDate == nil)
  }

  @Test func periodChange_toWeekly_anchorsToWeekStartDay() {
    let store = MockKeyValueStore()
    store.set(Int64(Weekday.sunday.rawValue), forKey: AppSettings.weekStartDayKey)
    let settings = AppSettings(store: store)
    let vm = AddEditBudgetViewModel(settings: settings)
    vm.period = .weekly
    let cal = Calendar.autoupdatingCurrent
    let dayStart = cal.startOfDay(for: Date())
    let weekday = cal.component(.weekday, from: dayStart)
    let daysBack = (weekday - Weekday.sunday.rawValue + 7) % 7
    let expected = cal.date(byAdding: .day, value: -daysBack, to: dayStart)
    #expect(vm.startDate == expected)
    #expect(vm.endDate == nil)
  }

  @Test func periodChange_toBiweekly_anchorsToWeekStartDay() {
    // biweekly uses the same anchor computation as weekly (the biweekly cycle
    // anchor itself is `Budget.startDate` at math-time, but at VM-init the
    // chosen value is the most-recent weekStartDay-aligned date).
    let store = MockKeyValueStore()
    store.set(Int64(Weekday.monday.rawValue), forKey: AppSettings.weekStartDayKey)
    let settings = AppSettings(store: store)
    let vm = AddEditBudgetViewModel(settings: settings)
    vm.period = .biweekly
    let cal = Calendar.autoupdatingCurrent
    let dayStart = cal.startOfDay(for: Date())
    let weekday = cal.component(.weekday, from: dayStart)
    let daysBack = (weekday - Weekday.monday.rawValue + 7) % 7
    let expected = cal.date(byAdding: .day, value: -daysBack, to: dayStart)
    #expect(vm.startDate == expected)
  }

  @Test func periodChange_toMonthly_anchorsToFirstOfMonth() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.period = .monthly
    let cal = Calendar.autoupdatingCurrent
    var comps = cal.dateComponents([.year, .month], from: Date())
    comps.day = 1
    comps.hour = 0
    comps.minute = 0
    comps.second = 0
    let expected = cal.date(from: comps)
    #expect(vm.startDate == expected)
    #expect(vm.endDate == nil)
  }

  @Test func periodChange_toSpecificDates_clearsBothDates() {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.endDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 30, to: Date())
    vm.period = .specificDates
    #expect(vm.startDate == nil)
    #expect(vm.endDate == nil)
  }

  @Test func periodChange_inEditMode_doesNotMutateDates() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let cal = Calendar.autoupdatingCurrent
    let originalStart = try #require(cal.date(from: DateComponents(year: 2026, month: 1, day: 12)))
    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .weekly, isCarryOverEnabled: true)
    budget.startDate = originalStart
    let change = AllocationChange(effectiveFrom: originalStart, amount: 7)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    context.insert(budget)

    let vm = AddEditBudgetViewModel(editing: budget)
    // Mutate `period` in Edit mode — the !isEditing guard MUST short-circuit
    // didSet so neither date is touched.
    vm.period = .monthly
    #expect(vm.startDate == originalStart)
    #expect(vm.endDate == nil)
  }

  // MARK: - saveNew honours user-overridden startDate (task 3.3)

  @Test func saveNew_recurring_honoursUserOverriddenStartDate() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let store = MockKeyValueStore()
    store.set(Int64(Weekday.monday.rawValue), forKey: AppSettings.weekStartDayKey)
    let settings = AppSettings(store: store)

    let vm = AddEditBudgetViewModel(settings: settings)
    vm.name = "Groceries"
    vm.allocation = 100
    vm.period = .weekly
    let cal = Calendar.autoupdatingCurrent
    // User picks a Thursday three weeks ago — the cycle anchor should become
    // Thursday per F-7.05 (`weekStart = budget.startDate.weekday`).
    let userPick = try #require(cal.date(from: DateComponents(year: 2026, month: 4, day: 30)))
    vm.startDate = userPick
    try vm.save(context: context)

    let saved = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
    #expect(saved.startDate == cal.startOfDay(for: userPick))
    let changes = try context.fetch(FetchDescriptor<AllocationChange>())
    #expect(changes.first?.effectiveFrom == cal.startOfDay(for: userPick))
  }

  @Test func saveNew_recurring_persistsOptionalEndDate() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = "Vacation Fund"
    vm.allocation = 500
    vm.period = .monthly
    let cal = Calendar.autoupdatingCurrent
    let endPick = try #require(cal.date(from: DateComponents(year: 2026, month: 12, day: 31)))
    vm.endDate = endPick
    try vm.save(context: context)

    let saved = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
    #expect(saved.endDate == cal.startOfDay(for: endPick))
  }

  // MARK: - saveEdit recurring date paths (task 3.4)

  @Test func saveEdit_recurring_startDateEdit_writesBudgetWithoutRealigningAllocation() throws {
    // Back-dating a recurring budget MUST NOT realign the AllocationChange row.
    // The calculator's allocationInEffect earliest-row fallback covers the
    // back-dated window — see Domain/AllocationInEffect.swift and the
    // back-dating integration tests in BudgetCalculatorTests.
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let cal = Calendar.autoupdatingCurrent
    let originalStart = try #require(cal.date(from: DateComponents(year: 2026, month: 4, day: 13)))
    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .weekly, isCarryOverEnabled: true)
    budget.startDate = originalStart
    let change = AllocationChange(effectiveFrom: originalStart, amount: 100)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    context.insert(budget)

    let vm = AddEditBudgetViewModel(editing: budget)
    let backDated = try #require(cal.date(from: DateComponents(year: 2026, month: 4, day: 6)))
    vm.startDate = backDated
    try vm.save(context: context)

    #expect(budget.startDate == cal.startOfDay(for: backDated))
    // The lone AllocationChange row must NOT be realigned for recurring.
    let allocs = try context.fetch(FetchDescriptor<AllocationChange>())
    #expect(allocs.first?.effectiveFrom == cal.startOfDay(for: originalStart))
  }

  @Test func saveEdit_recurring_endDateEdit_setsValue() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let cal = Calendar.autoupdatingCurrent
    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .weekly, isCarryOverEnabled: true)
    budget.startDate = try #require(cal.date(from: DateComponents(year: 2026, month: 4, day: 13)))
    let change = try AllocationChange(effectiveFrom: #require(budget.startDate), amount: 100)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    context.insert(budget)

    let vm = AddEditBudgetViewModel(editing: budget)
    let endPick = try #require(cal.date(from: DateComponents(year: 2026, month: 12, day: 31)))
    vm.endDate = endPick
    try vm.save(context: context)

    #expect(budget.endDate == cal.startOfDay(for: endPick))
  }

  @Test func saveEdit_recurring_clearingEndDate_setsNil() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let cal = Calendar.autoupdatingCurrent
    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .monthly, isCarryOverEnabled: true)
    budget.startDate = try #require(cal.date(from: DateComponents(year: 2026, month: 1, day: 1)))
    budget.endDate = try #require(cal.date(from: DateComponents(year: 2026, month: 12, day: 31)))
    let change = try AllocationChange(effectiveFrom: #require(budget.startDate), amount: 500)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    context.insert(budget)

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.endDate = nil
    try vm.save(context: context)

    #expect(budget.endDate == nil)
  }

  @Test func saveEdit_recurring_combinedStartDateAndAllocationEdit_stampsAllocationOnNewGrid() throws {
    // Audit L6: when one Save edits BOTH the startDate (re-anchoring the weekly
    // grid) and the allocation, the new amount must be stamped at the current
    // period start of the NEW grid. The old ordering computed it from the
    // pre-edit grid; when the new anchor moved the current period start
    // earlier, the freshly typed amount landed mid-period and the current
    // period silently kept the old allocation.
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let cal = Calendar.autoupdatingCurrent
    let today = cal.startOfDay(for: Date())

    // Old anchor: today's weekday (start two weeks ago) → old current period
    // starts today. New anchor: yesterday's weekday (start 15 days ago) → new
    // current period starts yesterday, i.e. EARLIER — the broken direction.
    let originalStart = try #require(cal.date(byAdding: .day, value: -14, to: today))
    let newStart = try #require(cal.date(byAdding: .day, value: -15, to: today))
    let expectedNewPeriodStart = try #require(cal.date(byAdding: .day, value: -1, to: today))

    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .weekly, isCarryOverEnabled: true)
    budget.startDate = originalStart
    let change = AllocationChange(effectiveFrom: originalStart, amount: 100)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    context.insert(budget)

    let vm = AddEditBudgetViewModel(editing: budget)
    vm.startDate = newStart
    vm.allocation = 150
    try vm.save(context: context)

    // The new amount's row sits on the new grid's current period boundary…
    let allocs = try context.fetch(FetchDescriptor<AllocationChange>())
    let newRow = try #require(allocs.first(where: { $0.amount == 150 }))
    #expect(newRow.effectiveFrom == expectedNewPeriodStart)
    // …so the user-visible current period actually uses the amount they typed.
    let snapshot = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: Date(), calendar: cal
    )
    #expect(snapshot.effectiveAllocation == 150)
  }

  @Test func saveEdit_specificDates_startDateEdit_stillRealignsAllocation() throws {
    // Defence: the specific-dates realignment must continue to work; the change
    // I made for recurring (no realignment) MUST NOT regress this case.
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let cal = Calendar.autoupdatingCurrent
    let originalStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let end = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 25)))
    let budget = Budget(name: "Trip", currencyCode: "EUR", period: .specificDates, isCarryOverEnabled: false)
    budget.startDate = originalStart
    budget.endDate = end
    let change = AllocationChange(effectiveFrom: originalStart, amount: 1500)
    change.budget = budget
    budget.allocationChangesStorage = [change]
    context.insert(budget)

    let vm = AddEditBudgetViewModel(editing: budget)
    let newStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 9)))
    vm.startDate = newStart
    try vm.save(context: context)

    #expect(budget.startDate == cal.startOfDay(for: newStart))
    let allocs = try context.fetch(FetchDescriptor<AllocationChange>())
    #expect(allocs.first?.effectiveFrom == cal.startOfDay(for: newStart))
  }

  // MARK: - startDate.didSet snap-forward cross-coupling (task 3.5)

  @Test func startDate_didSet_snapsEndForwardWhenCrossingPastEnd() throws {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.period = .specificDates // clears both, then we set them explicitly below
    let cal = Calendar.autoupdatingCurrent
    let originalStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 1)))
    let originalEnd = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 10)))
    vm.startDate = originalStart
    vm.endDate = originalEnd
    // Move start past end; endDate should snap forward to preserve the original 9-day duration.
    let newStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 15)))
    vm.startDate = newStart
    let expectedEnd = newStart.addingTimeInterval(originalEnd.timeIntervalSince(originalStart))
    #expect(vm.endDate == expectedEnd)
  }

  @Test func startDate_didSet_doesNotSnapWhenEndIsNil() throws {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    // Recurring default — endDate is nil. didSet should be a no-op for endDate.
    let cal = Calendar.autoupdatingCurrent
    let newStart = try #require(cal.date(from: DateComponents(year: 2026, month: 5, day: 15)))
    vm.startDate = newStart
    #expect(vm.endDate == nil)
  }
}
