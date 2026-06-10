import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Tests for `AddEditExpenseViewModel.computeRecentCandidates(for:limit:)` — the pure,
/// static F-7.04 algorithm that builds the Recents candidate set from a budget's history.
///
/// The helper is exercised directly (not through a VM init) so the cases stay focused on
/// the algorithm itself: sort order, dedup-by-description, exclusion filters, and the
/// cap. VM-level integration (cached at init, exposed via `hasRecentSources` etc.) lives
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
    // Two "Coffee" entries at different amounts; the more recent (date(0)) wins.
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

  @Test func defaultCap_isFifteen() throws {
    let expenses = (0 ..< 25).map { i in
      ExpenseItem(amount: Decimal(i + 1), name: "Item \(i)", date: date(TimeInterval(-i * 60)))
    }
    let budget = try makeBudget(with: expenses)
    let result = AddEditExpenseViewModel.computeRecentCandidates(for: budget)
    #expect(result.count == AddEditExpenseViewModel.recentsDisplayLimit)
    #expect(result.count == 15)
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
