import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

@MainActor
struct AddEditExpenseViewModelTests {
  // MARK: - 5.1  Add-mode defaults

  @Test func addMode_defaults() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .weekly)
    context.insert(budget)
    try context.save()

    let beforeConstruction = Date()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)

    #expect(vm.amount == nil)
    #expect(vm.name == "")
    #expect(vm.date >= beforeConstruction)
    #expect(vm.date.timeIntervalSince(beforeConstruction) < 5)
    #expect(vm.currencyCode == "USD")
    #expect(vm.isEditing == false)
    #expect(vm.canSave == false)
  }

  // MARK: - 5.2  Edit-mode seeding (positive amount)

  @Test func editMode_seedsFromPositiveExpense() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "USD", period: .monthly)
    context.insert(budget)
    let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let expense = ExpenseItem(amount: 4.50, name: "Morning coffee", date: fixedDate)
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)

    #expect(vm.amount == 4.50)
    #expect(vm.name == "Morning coffee")
    #expect(vm.date == fixedDate)
    #expect(vm.currencyCode == "USD")
    #expect(vm.isEditing == true)
    #expect(vm.canSave == true)
  }

  // MARK: - 5.3  Edit-mode seeding (negative amount / isAddFunds)

  @Test func editMode_seedsAbsoluteValueForNegativeAmount() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "USD", period: .monthly)
    context.insert(budget)
    let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let expense = ExpenseItem(amount: -10, name: "Reimbursement", date: fixedDate)
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)

    // The field shows the absolute value; sign is NOT carried through
    #expect(vm.amount == 10)
    #expect(vm.name == "Reimbursement")
    #expect(vm.isEditing == true)
    #expect(vm.canSave == true)
  }

  // MARK: - 5.4  Edit-mode seeding (orphan expense — no budget)

  @Test func editMode_currencyFallsBackToLocaleWhenBudgetNil() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let expense = ExpenseItem(amount: 5)
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)

    let expected = Locale.current.currency?.identifier ?? "USD"
    #expect(vm.currencyCode == expected)
  }

  // MARK: - 5.5  canSave enumeration

  @Test func canSave_falseWhenAmountNil() {
    let budget = Budget()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = nil
    #expect(vm.canSave == false)
  }

  @Test func canSave_falseWhenAmountZero() {
    let budget = Budget()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 0
    #expect(vm.canSave == false)
  }

  @Test func canSave_falseWhenAmountNegative() {
    let budget = Budget()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = -1
    #expect(vm.canSave == false)
  }

  @Test func canSave_trueWhenPositiveAmountWithEmptyDescription() {
    let budget = Budget()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 5.00
    vm.name = ""
    #expect(vm.canSave == true)
  }

  @Test func canSave_trueWhenPositiveAmountWithDescription() {
    let budget = Budget()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 5.00
    vm.name = "Coffee"
    #expect(vm.canSave == true)
  }

  // MARK: - 5.6  Add-mode save: inserts expense attached to budget

  @Test func addMode_save_insertsOneExpenseAttachedToBudget() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .weekly)
    context.insert(budget)
    try context.save()

    let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 5.00
    vm.name = "Coffee"
    vm.date = fixedDate
    try vm.save(context: context)

    let all = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(all.count == 1)
    let saved = try #require(all.first)
    #expect(saved.amount == 5.00)
    #expect(saved.amount > 0)
    #expect(saved.name == "Coffee")
    #expect(saved.date == fixedDate)
    #expect(saved.budget?.name == "Groceries")
  }

  // MARK: - 5.7  Add-mode save: description trimming

  @Test func addMode_save_trimsWhitespaceFromDescription() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget); try context.save()

    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 5
    vm.name = "  Coffee  "
    try vm.save(context: context)

    let all = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(all.first?.name == "Coffee")
  }

  @Test func addMode_save_whitespaceOnlyDescriptionPersistsAsNil() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget); try context.save()

    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 5
    vm.name = "   "
    try vm.save(context: context)

    let all = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(all.first?.name == nil)
  }

  @Test func addMode_save_emptyDescriptionPersistsAsNil() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget); try context.save()

    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 5
    vm.name = ""
    try vm.save(context: context)

    let all = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(all.first?.name == nil)
  }

  // MARK: - 5.8  Add-mode save: guards on !canSave

  @Test func addMode_save_doesNotInsertWhenCanSaveFalse() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget); try context.save()

    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = nil
    try vm.save(context: context)

    let all = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(all.isEmpty)
  }

  // MARK: - 5.9  Edit-mode no-op save does not bump lastModified

  @Test func editMode_save_noOp_doesNotBumpLastModified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let originalLastModified = Date(timeIntervalSinceNow: -3600)
    let expense = ExpenseItem(amount: 5, name: "Coffee", date: Date(timeIntervalSinceReferenceDate: 800_000_000))
    expense.budget = budget
    expense.lastModified = originalLastModified
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    try vm.save(context: context)

    #expect(expense.lastModified == originalLastModified)
  }

  // MARK: - 5.10  Edit-mode single-field change: description

  @Test func editMode_save_singleFieldChange_name() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let expense = ExpenseItem(amount: 5, name: "Coffee", date: fixedDate)
    expense.budget = budget
    let originalLastModified = Date(timeIntervalSinceNow: -3600)
    expense.lastModified = originalLastModified
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    vm.name = "New name"
    try vm.save(context: context)

    #expect(expense.name == "New name")
    #expect(expense.lastModified > originalLastModified)
    #expect(expense.amount == 5)
    #expect(expense.date == fixedDate)
  }

  // MARK: - 5.11  Edit-mode sign preservation: negative row, amount changed

  @Test func editMode_save_signPreservation_negativeRow_amountChanged() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let expense = ExpenseItem(amount: -10, name: "Reimbursement", date: Date())
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    // Seeded with displayAmount (10); user changes it to 15
    vm.amount = 15
    try vm.save(context: context)

    // Sign must be restored: isAddFunds → amount = -15
    #expect(expense.amount == -15)
  }

  // MARK: - 5.12  Edit-mode sign preservation: negative row, amount unchanged

  @Test func editMode_save_signPreservation_negativeRow_amountUnchanged() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let expense = ExpenseItem(amount: -10, name: "Reimbursement", date: Date())
    expense.budget = budget
    let originalLastModified = Date(timeIntervalSinceNow: -3600)
    expense.lastModified = originalLastModified
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    // amount is seeded as displayAmount = 10; leave it at 10 (no change)
    #expect(vm.amount == 10)
    try vm.save(context: context)

    // No spurious flip; no lastModified bump
    #expect(expense.amount == -10)
    #expect(expense.lastModified == originalLastModified)
  }

  // MARK: - 5.13  Edit-mode multi-field change

  @Test func editMode_save_multiFieldChange_writesAllAndBumpsLastModifiedOnce() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let expense = ExpenseItem(amount: 5, name: "Old", date: Date(timeIntervalSinceReferenceDate: 800_000_000))
    expense.budget = budget
    let before = Date(timeIntervalSinceNow: -3600)
    expense.lastModified = before
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    vm.name = "New name"
    vm.amount = 99.99
    try vm.save(context: context)

    #expect(expense.name == "New name")
    #expect(expense.amount == 99.99)
    #expect(expense.lastModified > before)
    // Single coherent write: reading lastModified twice should be equal
    let captured = expense.lastModified
    #expect(expense.lastModified == captured)
  }

  // MARK: - 5.14  Edit-mode description trim/nullify on edit

  @Test func editMode_save_trimsDescription() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let expense = ExpenseItem(amount: 5, name: "Old", date: Date())
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    vm.name = "  New  "
    try vm.save(context: context)
    #expect(expense.name == "New")
  }

  @Test func editMode_save_nullifiesWhitespaceOnlyDescription() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let expense = ExpenseItem(amount: 5, name: "Old", date: Date())
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    vm.name = "   "
    try vm.save(context: context)
    #expect(expense.name == nil)
  }

  // MARK: - 5.15  Edit-mode sub-minute date drift is no-op

  @Test func editMode_save_subMinuteDateDrift_noOp() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let expense = ExpenseItem(amount: 5, name: "Coffee", date: fixedDate)
    expense.budget = budget
    let originalLastModified = Date(timeIntervalSinceNow: -3600)
    expense.lastModified = originalLastModified
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    // Drift by 20 seconds — under the .minute granularity threshold
    vm.date = fixedDate.addingTimeInterval(20)
    try vm.save(context: context)

    #expect(expense.lastModified == originalLastModified)
  }

  // MARK: - 5.16  Cancel semantics

  @Test func cancel_leavesStoreUnmodified() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let expense = ExpenseItem(amount: 5, name: "Coffee", date: fixedDate)
    expense.budget = budget
    let originalLastModified = Date(timeIntervalSinceNow: -3600)
    expense.lastModified = originalLastModified
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    vm.amount = 999
    vm.name = "Changed"
    vm.date = Date()
    // Deliberately NOT calling save — simulating Cancel

    #expect(expense.amount == 5)
    #expect(expense.name == "Coffee")
    #expect(expense.date == fixedDate)
    #expect(expense.lastModified == originalLastModified)
  }

  // MARK: - 5.17  Delete in Edit mode

  @Test func delete_editMode_removesExpenseFromStore() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let expense1 = ExpenseItem(amount: 5, name: "Coffee", date: Date())
    expense1.budget = budget
    context.insert(expense1)
    let expense2 = ExpenseItem(amount: 10, name: "Lunch", date: Date())
    expense2.budget = budget
    context.insert(expense2)
    try context.save()

    let originalCount = try context.fetch(FetchDescriptor<ExpenseItem>()).count
    #expect(originalCount == 2)

    let vm = AddEditExpenseViewModel(editing: expense1, weekStart: .sunday)
    try vm.delete(context: context)

    let remaining = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(remaining.count == originalCount - 1)
    #expect(!remaining.contains(where: { $0.name == "Coffee" }))
  }

  // MARK: - 5.18  Delete in Add mode is a no-op

  @Test func delete_addMode_isNoOp() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let existing = ExpenseItem(amount: 5, name: "Coffee", date: Date())
    existing.budget = budget
    context.insert(existing)
    try context.save()

    let originalCount = try context.fetch(FetchDescriptor<ExpenseItem>()).count

    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    try vm.delete(context: context)

    let afterCount = try context.fetch(FetchDescriptor<ExpenseItem>()).count
    #expect(afterCount == originalCount)
  }

  // MARK: - 5.19  EditableAmountConverter parsing

  @Test func optionalDecimalParse_emptyString_returnsNil() throws {
    let strategy = EditableAmountParser()
    let result = try strategy.parse("")
    #expect(result == nil)
  }

  @Test func optionalDecimalParse_whitespaceOnly_returnsNil() throws {
    let strategy = EditableAmountParser()
    let result = try strategy.parse("   ")
    #expect(result == nil)
  }

  @Test func optionalDecimalParse_validNumber_returnsDecimal() throws {
    let strategy = EditableAmountParser()
    // Use a locale-agnostic integer string to keep the assertion deterministic
    let result = try strategy.parse("25")
    #expect(result == Decimal(25))
  }

  @Test func optionalDecimalParse_malformedString_throws() throws {
    let strategy = EditableAmountParser()
    #expect(throws: CocoaError.self) {
      try strategy.parse("abc")
    }
  }

  @Test func optionalDecimalEditableText_nil_returnsEmpty() {
    let style = EditableAmountConverter(currencyCode: "USD")
    #expect(style.editableText(nil) == "")
  }

  @Test func optionalDecimalEditableText_nonNil_returnsSeedString() {
    let style = EditableAmountConverter(currencyCode: "USD")
    let result = style.editableText(Decimal(25))
    #expect(!result.isEmpty)
    // The seeded value should contain "25"
    #expect(result.contains("25"))
  }

  // MARK: - 5.20  Save signature: no AppSettings parameter (compile-time check)

  /// If this compiles, the correct `save(context:)` signature is present.
  @Test func saveMethod_doesNotRequireAppSettings() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Check", currencyCode: "USD", period: .daily)
    context.insert(budget)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 1
    try vm.save(context: context) // must compile with (context:) only
    let all = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(all.count == 1)
  }

  // MARK: - 5.21  Delete signature: no AppSettings parameter (compile-time check)

  /// If this compiles, the correct `delete(context:)` signature is present.
  @Test func deleteMethod_doesNotRequireAppSettings() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Check", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let expense = ExpenseItem(amount: 5, name: "Test", date: Date())
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    try vm.delete(context: context) // must compile with (context:) only
    let remaining = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(remaining.isEmpty)
  }

  // MARK: - Cancel button visibility (isEditing gate)

  /// Add mode: isEditing is false → Cancel button renders.
  @Test func addMode_isEditingIsFalse() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    try context.save()

    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(vm.isEditing == false)
  }

  /// Edit mode: isEditing is true → Cancel button is suppressed.
  @Test func editMode_isEditingIsTrue() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Food", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let expense = ExpenseItem(amount: 7, name: "Lunch")
    expense.budget = budget
    context.insert(expense)
    try context.save()

    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    #expect(vm.isEditing == true)
  }
}
