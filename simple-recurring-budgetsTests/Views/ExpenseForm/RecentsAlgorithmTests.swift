import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Tests for `AddEditExpenseViewModel.computeRecentCandidates(for:limit:)` — the pure,
/// static F-7.04 algorithm that builds the Recents candidate corpus from a budget's
/// history.
///
/// The helper is exercised directly (not through a VM init) so the cases stay focused on
/// the algorithm itself: sort order, per-name base tiles, recurrence-gated amount
/// variants, exclusion filters, and the corpus cap. VM-level integration (cached at
/// init, display capping in `filteredRecentSuggestions`, provenance-aware apply) lives
/// in `AddEditExpenseViewModelRecentsTests`.
@MainActor
struct RecentsAlgorithmTests {
  // MARK: - Helpers

  /// Build a budget in an in-memory container and attach the supplied expenses.
  private func makeBudget(with expenses: [ExpenseItem]) throws -> Budget {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget(name: "Test", currencyCode: "USD", period: .daily)
    context.insert(budget)
    for expense in expenses {
      expense.budget = budget
      context.insert(expense)
    }
    try context.save()
    return budget
  }

  /// Standard test date with offset in seconds (negative = earlier).
  private func date(_ offsetSeconds: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: 800_000_000 + offsetSeconds)
  }

  // MARK: - Trivial inputs

  @Test func nilBudget_returnsEmpty() {
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: nil)
    #expect(result.isEmpty)
  }

  @Test func emptyBudget_returnsEmpty() throws {
    let budget = try makeBudget(with: [])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.isEmpty)
  }

  // MARK: - Sort order (recency-first)

  @Test func uniqueEntries_sortedByDateDescending() throws {
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 5.50, name: "Coffee", date: date(-3600)), // 1h ago
      ExpenseItem(amount: 14.25, name: "Lunch", date: date(0)), // now
      ExpenseItem(amount: 42.00, name: "Groceries", date: date(-86400)), // yesterday
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.map(\.name) == ["Lunch", "Coffee", "Groceries"])
  }

  // MARK: - Deduplication

  @Test func duplicatesByName_keepMostRecentOccurrenceAmount() throws {
    // Two "Coffee" entries at different amounts, each logged ONCE; the more recent
    // (date(0)) is the base tile, and the older singleton pair stays below the
    // recurrence threshold so no variant tile appears.
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 5.50, name: "Coffee", date: date(-86400)), // older Coffee
      ExpenseItem(amount: 6.00, name: "Coffee", date: date(0)), // newer Coffee
      ExpenseItem(amount: 14.25, name: "Lunch", date: date(-3600)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.count == 2)
    #expect(result[0].name == "Coffee")
    #expect(result[0].amount == 6.00) // newer occurrence's amount
    #expect(result[1].name == "Lunch")
  }

  @Test func dedupIsCaseInsensitive() throws {
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 5.50, name: "coffee", date: date(-3600)),
      ExpenseItem(amount: 6.00, name: "Coffee", date: date(0)),
      ExpenseItem(amount: 7.00, name: "COFFEE", date: date(-1800)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.count == 1)
    #expect(result[0].amount == 6.00) // most recent across case variants
  }

  @Test func dedupTrimsWhitespaceBeforeComparing() throws {
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 5.50, name: "  Coffee  ", date: date(0)),
      ExpenseItem(amount: 6.00, name: "Coffee", date: date(-3600)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.count == 1)
    #expect(result[0].name == "Coffee") // whitespace-trimmed name surfaces
    #expect(result[0].amount == 5.50)
  }

  @Test func dedupIsDiacriticInsensitive() throws {
    // "Café", "cafe", and "CAFÉ" should all collapse to one entry, with the most
    // recent occurrence's name + amount surviving. The folded comparison aligns the
    // dedup equivalence class with the filter's `range(of:options:)` semantics, so
    // the user can't end up with two visibly-identical-looking entries.
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 5.50, name: "cafe", date: date(-86400)),
      ExpenseItem(amount: 6.00, name: "Café", date: date(0)),
      ExpenseItem(amount: 7.00, name: "CAFÉ", date: date(-3600)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.count == 1)
    #expect(result[0].amount == 6.00) // most recent across all folded variants
    #expect(result[0].name == "Café") // most recent occurrence's display name
  }

  // MARK: - Exclusion filters

  @Test func addFundsEntries_areExcluded() throws {
    // Negative amount makes ExpenseItem.isAddFunds == true.
    let budget = try makeBudget(with: [
      ExpenseItem(amount: -25.00, name: "Refund", date: date(0)),
      ExpenseItem(amount: 5.50, name: "Coffee", date: date(-3600)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.map(\.name) == ["Coffee"])
  }

  @Test func unnamedEntries_areExcluded_nilName() throws {
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 9.99, name: nil, date: date(0)),
      ExpenseItem(amount: 5.50, name: "Coffee", date: date(-3600)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.map(\.name) == ["Coffee"])
  }

  @Test func unnamedEntries_areExcluded_whitespaceOnly() throws {
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 9.99, name: "   ", date: date(0)),
      ExpenseItem(amount: 5.50, name: "Coffee", date: date(-3600)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.map(\.name) == ["Coffee"])
  }

  // MARK: - Cap enforcement

  @Test func capEnforced_whenInputExceedsLimit() throws {
    // 20 unique-named expenses, cap of 5 → exactly 5 results.
    let expenses = (0 ..< 20).map { i in
      ExpenseItem(amount: Decimal(i + 1), name: "Item \(i)", date: date(TimeInterval(-i * 60)))
    }
    let budget = try makeBudget(with: expenses)
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget, limit: 5)
    #expect(result.count == 5)
    // Top 5 most recent are "Item 0" through "Item 4".
    #expect(result.map(\.name) == (0 ..< 5).map { "Item \($0)" })
  }

  @Test func defaultLimit_isCorpusCapNotDisplayCap() throws {
    // 25 unique names exceed the old 15-tile display default but sit well under the
    // corpus cap: the algorithm's default must return ALL of them — display trimming
    // happens downstream in `filteredRecentSuggestions`, never here. This is the
    // corpus/display decoupling that lets a typed query surface names beyond the row.
    let expenses = (0 ..< 25).map { i in
      ExpenseItem(amount: Decimal(i + 1), name: "Item \(i)", date: date(TimeInterval(-i * 60)))
    }
    let budget = try makeBudget(with: expenses)
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.count == 25)
  }

  @Test func capConstants_pinWorkshopDecisions() {
    // Deliberate pins for the cap design: display (Caps A/B) = 30, corpus (Cap C) =
    // 200, variant recurrence gate = 3, extra variants per name = 2. Changing any of
    // these is a product decision — update the test alongside the constant.
    #expect(AddEditExpenseViewModel.recentsDisplayLimit == 30)
    #expect(AddEditExpenseViewModel.recentsCorpusLimit == 200)
    #expect(AddEditExpenseViewModel.variantRecurrenceThreshold == 3)
    #expect(AddEditExpenseViewModel.maxVariantsPerName == 2)
  }

  // MARK: - Recurrence-gated amount variants

  @Test func recurringSecondAmount_earnsVariantTile() throws {
    // "Coffee" at 5.75 once (most recent → base tile) and at 4.50 three times
    // (meets the recurrence threshold → variant tile), clustered base-first.
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 5.75, name: "Coffee", date: date(0)),
      ExpenseItem(amount: 4.50, name: "Coffee", date: date(-3600)),
      ExpenseItem(amount: 4.50, name: "Coffee", date: date(-7200)),
      ExpenseItem(amount: 4.50, name: "Coffee", date: date(-10800)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.map(\.name) == ["Coffee", "Coffee"])
    #expect(result.map(\.amount) == [5.75, 4.50])
  }

  @Test func secondAmountBelowThreshold_doesNotEarnVariantTile() throws {
    // The 4.50 pair occurs only twice — one short of the threshold — so only the
    // base tile (most recent amount) surfaces.
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 5.75, name: "Coffee", date: date(0)),
      ExpenseItem(amount: 4.50, name: "Coffee", date: date(-3600)),
      ExpenseItem(amount: 4.50, name: "Coffee", date: date(-7200)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.count == 1)
    #expect(result[0].amount == 5.75)
  }

  @Test func priceJitter_collapsesToSingleBaseTile() throws {
    // Three one-off "Groceries" amounts (the canonical jitter case the gate exists
    // for): no pair recurs, so only the most recent amount surfaces.
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 103.55, name: "Groceries", date: date(0)),
      ExpenseItem(amount: 91.10, name: "Groceries", date: date(-86400)),
      ExpenseItem(amount: 87.32, name: "Groceries", date: date(-172_800)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.count == 1)
    #expect(result[0].amount == 103.55)
  }

  @Test func variantsPerName_cappedAtTwoExtras_byPairRecency() throws {
    // Base (9.99, most recent) plus three qualifying variant pairs; only the two
    // most recently used variants survive the per-name cap (1.00's pair is oldest).
    var expenses = [ExpenseItem(amount: 9.99, name: "Coffee", date: date(0))]
    for (amount, baseOffset) in [(Decimal(2.00), -1000.0), (Decimal(3.00), -2000.0), (Decimal(1.00), -3000.0)] {
      for occurrence in 0 ..< 3 {
        expenses.append(ExpenseItem(
          amount: amount, name: "Coffee", date: date(baseOffset - Double(occurrence) * 10000)
        ))
      }
    }
    let budget = try makeBudget(with: expenses)
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.map(\.amount) == [9.99, 2.00, 3.00])
  }

  @Test func variantTiles_clusterAfterBase_groupsOrderedByRecency() throws {
    // "Lunch" is the most recent name overall, but "Coffee" has a qualifying variant:
    // groups order by their most recent date, and Coffee's variant stays adjacent to
    // its base rather than interleaving by raw date.
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 14.25, name: "Lunch", date: date(0)),
      ExpenseItem(amount: 5.75, name: "Coffee", date: date(-50)),
      ExpenseItem(amount: 4.50, name: "Coffee", date: date(-3600)),
      ExpenseItem(amount: 4.50, name: "Coffee", date: date(-7200)),
      ExpenseItem(amount: 4.50, name: "Coffee", date: date(-10800)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.map(\.name) == ["Lunch", "Coffee", "Coffee"])
    #expect(result.map(\.amount) == [14.25, 5.75, 4.50])
  }

  @Test func variantOccurrences_countAcrossCaseAndDiacriticFolds() throws {
    // The recurrence count aggregates across the folded-name equivalence class:
    // "coffee" + "Coffee" + "COFFEE" at 4.50 are THREE occurrences of one pair.
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 5.75, name: "Coffee", date: date(0)),
      ExpenseItem(amount: 4.50, name: "coffee", date: date(-3600)),
      ExpenseItem(amount: 4.50, name: "Coffee", date: date(-7200)),
      ExpenseItem(amount: 4.50, name: "COFFEE", date: date(-10800)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.map(\.amount) == [5.75, 4.50])
  }

  // MARK: - Mixed input

  @Test func mixedEligibleAndIneligible_filtersThenSortsThenCaps() throws {
    // 3 eligible expenses, 2 Add Funds entries (excluded), 1 nil-name (excluded), 1
    // whitespace-name (excluded). Cap of 5; should yield 3 sorted by recency.
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 5.50, name: "Coffee", date: date(0)),
      ExpenseItem(amount: -50.00, name: "Refund", date: date(-100)), // Add Funds
      ExpenseItem(amount: 14.25, name: "Lunch", date: date(-3600)),
      ExpenseItem(amount: 9.99, name: nil, date: date(-200)), // unnamed
      ExpenseItem(amount: 42.00, name: "Groceries", date: date(-86400)),
      ExpenseItem(amount: 7.50, name: "  ", date: date(-300)), // whitespace
      ExpenseItem(amount: -10.00, name: "Adjust", date: date(-500)), // Add Funds
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget, limit: 5)
    #expect(result.map(\.name) == ["Coffee", "Lunch", "Groceries"])
  }

  // MARK: - Surfaced amount uses ExpenseItem.displayAmount

  @Test func surfacedAmount_isAbsoluteValue() throws {
    // Defensive: even if a positive amount is stored, displayAmount is what surfaces.
    let budget = try makeBudget(with: [
      ExpenseItem(amount: 5.50, name: "Coffee", date: date(0)),
    ])
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result[0].amount == 5.50)
  }
}
