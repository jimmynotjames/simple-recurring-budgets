import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Tests for `AddEditExpenseViewModel`'s F-7.04 Recents API surface — the cached
/// candidate corpus, the typed-query filter and its display cap, the Add-mode-only
/// visibility gate, the provenance-aware `applyRecent` (including its analytics
/// emission), and the double-tap `applyRecentFullReplace`. The static algorithm itself
/// is covered separately by `RecentsAlgorithmTests`; here we exercise the VM-level wiring.
@MainActor
struct AddEditExpenseViewModelRecentsTests {
  // MARK: - Helpers

  /// Compact spec for table-style fixture construction. Avoids a 3-tuple (lint cap = 2).
  private struct ExpenseSpec {
    let name: String?
    let amount: Decimal
    let hoursAgo: Double
  }

  private func makeBudgetWithExpenses(_ specs: [ExpenseSpec]) throws -> Budget {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    context.insert(budget)
    let now = Date()
    for spec in specs {
      let expense = ExpenseItem(
        amount: spec.amount,
        name: spec.name,
        date: now.addingTimeInterval(-spec.hoursAgo * 3600)
      )
      expense.budget = budget
      context.insert(expense)
    }
    try context.save()
    return budget
  }

  // MARK: - hasRecentSources

  @Test func hasRecentSources_trueWhenBudgetHasEligibleExpenses() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(vm.hasRecentSources == true)
  }

  @Test func hasRecentSources_falseWhenBudgetIsEmpty() throws {
    let budget = try makeBudgetWithExpenses([])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(vm.hasRecentSources == false)
  }

  @Test func hasRecentSources_falseWhenAllExpensesAreIneligible() throws {
    // All Add Funds entries → all filtered out → no sources.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Refund A", amount: -10.00, hoursAgo: 1),
      ExpenseSpec(name: "Refund B", amount: -20.00, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(vm.hasRecentSources == false)
  }

  // MARK: - filteredRecentSuggestions

  @Test func filteredRecents_emptyQuery_returnsAllCandidates() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(vm.name == "") // Add-mode default
    #expect(vm.filteredRecentSuggestions.count == 2)
  }

  @Test func filteredRecents_substringMatch_narrowsResults() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
      ExpenseSpec(name: "Groceries", amount: 42.00, hoursAgo: 3),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.name = "co"
    #expect(vm.filteredRecentSuggestions.map(\.name) == ["Coffee"])
  }

  @Test func filteredRecents_caseInsensitiveMatch() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.name = "COFFEE"
    #expect(vm.filteredRecentSuggestions.count == 1)
  }

  @Test func filteredRecents_diacriticInsensitiveMatch() throws {
    // Typing "cafe" finds "Café"; typing "Café" finds "cafe". Same equivalence class
    // the dedup uses (see RecentsAlgorithmTests.dedupIsDiacriticInsensitive).
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Café", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Smoothie", amount: 8.75, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.name = "cafe"
    #expect(vm.filteredRecentSuggestions.map(\.name) == ["Café"])
  }

  @Test func filteredRecents_noMatch_returnsEmpty() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.name = "Pizza"
    #expect(vm.filteredRecentSuggestions.isEmpty)
  }

  @Test func filteredRecents_whitespaceOnlyQuery_treatedAsEmpty() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.name = "   "
    #expect(vm.filteredRecentSuggestions.count == 2) // all candidates
  }

  // MARK: - Display cap vs corpus (Caps A/B vs C)

  @Test func filteredRecents_emptyQuery_cappedAtDisplayLimit() throws {
    // 35 unique names → all 35 live in the corpus, but the unfiltered row renders at
    // most `recentsDisplayLimit`.
    let specs = (0 ..< 35).map { i in
      ExpenseSpec(name: "Item \(i)", amount: Decimal(i + 1), hoursAgo: Double(i))
    }
    let budget = try makeBudgetWithExpenses(specs)
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(vm.filteredRecentSuggestions.count == AddEditExpenseViewModel.recentsDisplayLimit)
  }

  @Test func filteredRecents_querySurfacesNameBeyondDisplayedRow() throws {
    // "Zebra" is the oldest of 31 names, so it falls outside the 30-tile unfiltered
    // row — but typing must still find it, because the filter searches the corpus,
    // not the rendered row. This is the search-depth defect the cap decoupling fixed.
    var specs = (0 ..< 30).map { i in
      ExpenseSpec(name: "Item \(i)", amount: Decimal(i + 1), hoursAgo: Double(i))
    }
    specs.append(ExpenseSpec(name: "Zebra", amount: 99.00, hoursAgo: 500))
    let budget = try makeBudgetWithExpenses(specs)
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(!vm.filteredRecentSuggestions.contains { $0.name == "Zebra" }) // not in row
    vm.name = "zeb"
    #expect(vm.filteredRecentSuggestions.map(\.name) == ["Zebra"]) // but searchable
  }

  // MARK: - shouldShowRecentsSection

  @Test func shouldShowRecentsSection_trueInAddModeWithSources() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(vm.shouldShowRecentsSection == true)
  }

  @Test func shouldShowRecentsSection_falseInAddModeWithoutSources() throws {
    let budget = try makeBudgetWithExpenses([])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(vm.shouldShowRecentsSection == false)
  }

  @Test func shouldShowRecentsSection_falseInEditModeWithNonBlankDescription() throws {
    // Edit mode with a non-blank description: latch is not set, so section is hidden.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let firstExpense = try #require(budget.expenseItems.first { $0.name == "Coffee" })
    let vm = AddEditExpenseViewModel(editing: firstExpense, weekStart: .sunday)
    #expect(vm.hasRecentSources == true) // candidates were computed
    #expect(vm.recentsRevealedInEdit == false) // latch not set: name is "Coffee"
    #expect(vm.shouldShowRecentsSection == false) // section hidden until latch fires
  }

  // MARK: - recentsRevealedInEdit latch

  @Test func recentsRevealedInEdit_trueOnOpenWhenDescriptionIsBlank() throws {
    // A nil-name expense opens with the reveal latch set immediately.
    // Uses the same container as the budget so the relationship is valid.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 2),
      ExpenseSpec(name: nil, amount: 3.00, hoursAgo: 1), // blank-named expense under test
    ])
    let blankExpense = try #require(budget.expenseItems.first { $0.name == nil })
    let vm = AddEditExpenseViewModel(editing: blankExpense, weekStart: .sunday)
    #expect(vm.recentsRevealedInEdit == true)
    #expect(vm.shouldShowRecentsSection == true) // hasRecentSources true ("Coffee" qualifies)
  }

  @Test func recentsRevealedInEdit_falseOnOpenWhenDescriptionIsNonBlank() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let expense = try #require(budget.expenseItems.first { $0.name == "Coffee" })
    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    #expect(vm.recentsRevealedInEdit == false)
    #expect(vm.shouldShowRecentsSection == false)
  }

  @Test func recentsRevealedInEdit_flipsWhenDescriptionClearedMidSession() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let expense = try #require(budget.expenseItems.first { $0.name == "Coffee" })
    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    #expect(vm.recentsRevealedInEdit == false)
    vm.name = "" // user clears the field
    #expect(vm.recentsRevealedInEdit == true)
    #expect(vm.shouldShowRecentsSection == true)
  }

  @Test func recentsRevealedInEdit_persistsAfterReTypingDescription() throws {
    // Latch is one-way: once set by clearing, it stays set even after re-typing.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let expense = try #require(budget.expenseItems.first { $0.name == "Coffee" })
    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    vm.name = "" // clear → latch fires
    vm.name = "Retype" // re-type non-empty
    #expect(vm.recentsRevealedInEdit == true) // still latched
    #expect(vm.shouldShowRecentsSection == true)
  }

  @Test func recentsRevealedInEdit_persistsAfterTileTap() throws {
    // A tile tap fills the description (now non-empty) but the latch must remain set.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let expense = try #require(budget.expenseItems.first { $0.name == "Coffee" })
    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    vm.name = "" // reveal
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: SpyAnalyticsClient())
    // name is now "Coffee" (non-empty), but latch stays true.
    #expect(vm.recentsRevealedInEdit == true)
    #expect(vm.shouldShowRecentsSection == true)
  }

  @Test func recentsRevealedInEdit_doesNotAffectAddMode() throws {
    // In Add mode shouldShowRecentsSection depends only on hasRecentSources,
    // not on the latch (which is only meaningful in Edit mode).
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    #expect(vm.recentsRevealedInEdit == false) // latch is irrelevant in Add
    #expect(vm.shouldShowRecentsSection == true) // shown because !isEditing && hasRecentSources
  }

  // MARK: - Edit-mode amount provenance (single tap protects the existing amount)

  @Test func editMode_singleTap_fillsDescriptionOnly_leavesExistingAmount() throws {
    // The edit-seeded amount is classified .userTyped, so a single tap fills the
    // description but leaves the amount untouched.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let expense = try #require(budget.expenseItems.first { $0.name == "Coffee" })
    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    #expect(vm.amount == 5.50) // seeded from expense
    // Reveal the section then tap the Lunch tile.
    vm.name = ""
    let lunchTile = try #require(vm.filteredRecentSuggestions.first { $0.name == "Lunch" })
    vm.applyRecent(lunchTile, visibleCount: 2, tapPosition: 1, analytics: SpyAnalyticsClient())
    #expect(vm.name == "Lunch")
    #expect(vm.amount == 5.50) // existing amount preserved (edit-seeded = userTyped)
  }

  @Test func editMode_doubleTap_overridesBothDescriptionAndAmount() throws {
    // Double-tap full replace still works: unconditionally writes name + amount.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let expense = try #require(budget.expenseItems.first { $0.name == "Coffee" })
    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    vm.name = ""
    let lunchTile = try #require(vm.filteredRecentSuggestions.first { $0.name == "Lunch" })
    vm.applyRecentFullReplace(lunchTile)
    #expect(vm.name == "Lunch")
    #expect(vm.amount == 14.25)
  }

  @Test func editMode_clearingAmountReArmsFill() throws {
    // After clearing the amount in Edit mode, a single tap re-arms and fills it.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let expense = try #require(budget.expenseItems.first { $0.name == "Coffee" })
    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    vm.amount = nil // clear via ✕
    vm.name = ""
    let lunchTile = try #require(vm.filteredRecentSuggestions.first { $0.name == "Lunch" })
    vm.applyRecent(lunchTile, visibleCount: 2, tapPosition: 1, analytics: SpyAnalyticsClient())
    #expect(vm.amount == 14.25) // re-armed after clear
  }

  // MARK: - applyRecent

  @Test func applyRecent_writesNameAndAmount_whenAmountEmpty() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: SpyAnalyticsClient())
    #expect(vm.name == "Coffee")
    #expect(vm.amount == 5.50)
  }

  // MARK: - applyRecent amount provenance (smart apply)

  @Test func applyRecent_preservesUserTypedAmount() throws {
    // The core smart-apply rule: a user-typed amount is fresher intent than the
    // tile's historical amount, so the tap fills the description only.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 12.80 // simulates a keystroke-originated binding write
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: SpyAnalyticsClient())
    #expect(vm.name == "Coffee")
    #expect(vm.amount == 12.80) // user's amount survives
  }

  @Test func applyRecent_replacesTileSeededAmount_onSuggestionSwitch() throws {
    // Tapping a second tile is suggestion-switching: the first tile's seed is not
    // user input, so the second tap replaces it fully.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    let suggestions = vm.filteredRecentSuggestions
    let coffee = try #require(suggestions.first { $0.name == "Coffee" })
    let lunch = try #require(suggestions.first { $0.name == "Lunch" })
    vm.applyRecent(coffee, visibleCount: 2, tapPosition: 0, analytics: SpyAnalyticsClient())
    vm.applyRecent(lunch, visibleCount: 2, tapPosition: 1, analytics: SpyAnalyticsClient())
    #expect(vm.name == "Lunch")
    #expect(vm.amount == 14.25)
  }

  @Test func applyRecent_clearedAmount_reArmsFilling() throws {
    // Typing an amount then clearing it (✕ / delete-all) returns the draft to empty
    // provenance, so the next tile tap fills again.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 12.80
    vm.amount = nil // ✕ clear
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: SpyAnalyticsClient())
    #expect(vm.amount == 5.50)
  }

  @Test func applyRecent_userTypedAmountSurvivesSuggestionSwitching() throws {
    // A typed amount stays sticky across multiple tile taps — browsing names must
    // not clobber it.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 12.80
    let suggestions = vm.filteredRecentSuggestions
    let coffee = try #require(suggestions.first { $0.name == "Coffee" })
    let lunch = try #require(suggestions.first { $0.name == "Lunch" })
    vm.applyRecent(coffee, visibleCount: 2, tapPosition: 0, analytics: SpyAnalyticsClient())
    vm.applyRecent(lunch, visibleCount: 2, tapPosition: 1, analytics: SpyAnalyticsClient())
    #expect(vm.name == "Lunch")
    #expect(vm.amount == 12.80)
  }

  // MARK: - applyRecentFullReplace (double-tap)

  @Test func fullReplace_overridesUserTypedAmount() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 12.80
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.applyRecentFullReplace(pick)
    #expect(vm.name == "Coffee")
    #expect(vm.amount == 5.50) // explicit double-tap wins over provenance
  }

  @Test func fullReplace_seedIsReplaceableByLaterTap() throws {
    // A full replace marks the amount tile-seeded, so a later single tap on another
    // tile still applies fully.
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.amount = 12.80
    let suggestions = vm.filteredRecentSuggestions
    let coffee = try #require(suggestions.first { $0.name == "Coffee" })
    let lunch = try #require(suggestions.first { $0.name == "Lunch" })
    vm.applyRecentFullReplace(coffee)
    vm.applyRecent(lunch, visibleCount: 2, tapPosition: 1, analytics: SpyAnalyticsClient())
    #expect(vm.amount == 14.25)
  }

  @Test func fullReplace_resetsIsAddFunds() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.isAddFunds = true
    vm.applyRecentFullReplace(pick)
    #expect(vm.isAddFunds == false)
  }

  @Test func applyRecent_resetsIsAddFundsToFalse_whenWasOn() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    // Capture the pick first — toggling `isAddFunds` from false to true triggers the
    // didSet that seeds `name = "Add funds"`, which would filter our candidate set down
    // to zero before we could grab a suggestion. F-6.01 seeding behavior, not under test.
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.isAddFunds = true
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: SpyAnalyticsClient())
    #expect(vm.isAddFunds == false) // a Recents tile is a prior expense, not Add Funds
  }

  @Test func applyRecent_leavesIsAddFundsFalse_whenAlreadyOff() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    let pick = try #require(vm.filteredRecentSuggestions.first)
    #expect(vm.isAddFunds == false)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: SpyAnalyticsClient())
    #expect(vm.isAddFunds == false)
  }

  @Test func applyRecent_emitsAnalyticsEventWithCategoricalProperties() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.name = "co" // a 2-char query
    let spy = SpyAnalyticsClient()
    let visible = vm.filteredRecentSuggestions
    let pick = try #require(visible.first)
    vm.applyRecent(pick, visibleCount: visible.count, tapPosition: 0, analytics: spy)
    #expect(spy.trackCalls.count == 1)
    let call = try #require(spy.trackCalls.first)
    #expect(call.event == AnalyticsEvent.expenseRecentReused)
    let props = call.properties ?? [:]
    #expect(props[AnalyticsProperty.period] == "daily")
    #expect(props[AnalyticsProperty.recentsTapPosition] == "0")
    // visibleCount = 1 (only "co" matched "Coffee") → bucket "1"
    #expect(props[AnalyticsProperty.recentsVisibleCount] == "1")
    // query "co" length 2 → bucket "1-2"
    #expect(props[AnalyticsProperty.nameQueryLength] == "1-2")
    // Add mode → "add_sheet"
    #expect(props[AnalyticsProperty.fromScreen] == "add_sheet")
  }

  @Test func applyRecent_fromScreen_isAddSheetInAddMode() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    let spy = SpyAnalyticsClient()
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: spy)
    let props = spy.trackCalls.first?.properties ?? [:]
    #expect(props[AnalyticsProperty.fromScreen] == "add_sheet")
  }

  @Test func applyRecent_fromScreen_isBudgetDetailInEditMode() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
      ExpenseSpec(name: "Lunch", amount: 14.25, hoursAgo: 2),
    ])
    let expense = try #require(budget.expenseItems.first { $0.name == "Coffee" })
    let vm = AddEditExpenseViewModel(editing: expense, weekStart: .sunday)
    vm.name = "" // reveal Recents
    let spy = SpyAnalyticsClient()
    let lunchTile = try #require(vm.filteredRecentSuggestions.first { $0.name == "Lunch" })
    vm.applyRecent(lunchTile, visibleCount: 1, tapPosition: 0, analytics: spy)
    let props = spy.trackCalls.first?.properties ?? [:]
    #expect(props[AnalyticsProperty.fromScreen] == "budget_detail")
  }

  @Test func applyRecent_eventHasNoPII() throws {
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    let spy = SpyAnalyticsClient()
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: spy)
    let call = try #require(spy.trackCalls.first)
    let props = call.properties ?? [:]
    // Never the description or amount value.
    let allValues = props.values.joined(separator: " ")
    #expect(!allValues.contains("Coffee"))
    #expect(!allValues.contains("5.50"))
    #expect(!allValues.contains("5.5"))
    // Property keys are the categorical set only.
    let allowedKeys: Set<String> = [
      AnalyticsProperty.period,
      AnalyticsProperty.recentsVisibleCount,
      AnalyticsProperty.recentsTapPosition,
      AnalyticsProperty.nameQueryLength,
      AnalyticsProperty.fromScreen,
    ]
    #expect(Set(props.keys).isSubset(of: allowedKeys))
  }

  @Test func applyRecent_capturesQueryLengthBeforeOverwritingName() throws {
    // The query-length analytic must reflect what the user was typing AT THE MOMENT of
    // the tap, not the suggestion's name. So a tap on "Coffee" while the user has typed
    // "co" should yield bucket "1-2", not "3+" (the length of "Coffee").
    let budget = try makeBudgetWithExpenses([
      ExpenseSpec(name: "Coffee", amount: 5.50, hoursAgo: 1),
    ])
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.name = "co"
    let spy = SpyAnalyticsClient()
    let pick = try #require(vm.filteredRecentSuggestions.first)
    vm.applyRecent(pick, visibleCount: 1, tapPosition: 0, analytics: spy)
    let props = spy.trackCalls.first?.properties ?? [:]
    #expect(props[AnalyticsProperty.nameQueryLength] == "1-2")
  }
}
