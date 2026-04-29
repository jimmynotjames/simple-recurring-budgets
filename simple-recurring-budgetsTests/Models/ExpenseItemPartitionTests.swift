import Foundation
@testable import simple_recurring_budgets
import Testing

struct ExpenseItemPartitionTests {
  /// Convenience factory for non-persisted ExpenseItems.
  private func makeExpense(amount: Decimal = 1, name: String? = nil, date: Date) -> ExpenseItem {
    ExpenseItem(amount: amount, name: name, date: date)
  }

  private static let base = Date(timeIntervalSinceReferenceDate: 1_000_000)

  // MARK: nil periodStart

  /// When periodStart is nil (lifecycle not yet resolved), both arrays are empty.
  @Test func partitioned_nilStart_returnsEmpty() {
    let expenses = [
      makeExpense(date: Self.base),
      makeExpense(date: Self.base.addingTimeInterval(-3600)),
    ]
    let result = expenses.partitioned(byPeriodStart: nil)
    #expect(result.current.isEmpty)
    #expect(result.past.isEmpty)
  }

  // MARK: Boundary inclusivity

  /// An expense exactly at periodStart falls in the CURRENT array (>= semantic).
  @Test func partitioned_dateEqualsStart_isCurrentNotPast() {
    let start = Self.base
    let onBoundary = makeExpense(date: start)
    let justBefore = makeExpense(date: start.addingTimeInterval(-1))

    let result = [onBoundary, justBefore].partitioned(byPeriodStart: start)
    #expect(result.current.count == 1)
    #expect(result.current.first?.date == start)
    #expect(result.past.count == 1)
    #expect(result.past.first?.date == start.addingTimeInterval(-1))
  }

  // MARK: Sort order — descending by date within each array

  @Test func partitioned_sortedDescendingInBothArrays() {
    let start = Self.base
    let c1 = makeExpense(date: start.addingTimeInterval(3600)) // newer current
    let c2 = makeExpense(date: start.addingTimeInterval(1800)) // older current
    let c3 = makeExpense(date: start) // boundary → current
    let p1 = makeExpense(date: start.addingTimeInterval(-1800)) // newer past
    let p2 = makeExpense(date: start.addingTimeInterval(-3600)) // older past

    let result = [c2, p2, c1, p1, c3].partitioned(byPeriodStart: start)

    // Current: newest first
    #expect(result.current.map(\.date) == [c1.date, c2.date, c3.date])
    // Past: newest first
    #expect(result.past.map(\.date) == [p1.date, p2.date])
  }

  // MARK: All-current edge case

  @Test func partitioned_allExpensesInCurrentPeriod() {
    let start = Self.base
    let expenses = (1 ... 3).map { makeExpense(date: start.addingTimeInterval(Double($0) * 600)) }
    let result = expenses.partitioned(byPeriodStart: start)
    #expect(result.current.count == 3)
    #expect(result.past.isEmpty)
  }

  // MARK: All-past edge case

  @Test func partitioned_allExpensesInPast() {
    let start = Self.base
    let expenses = (1 ... 3).map { makeExpense(date: start.addingTimeInterval(-Double($0) * 600)) }
    let result = expenses.partitioned(byPeriodStart: start)
    #expect(result.current.isEmpty)
    #expect(result.past.count == 3)
  }

  // MARK: Empty input

  @Test func partitioned_emptyInput_returnsBothEmpty() {
    let result = [ExpenseItem]().partitioned(byPeriodStart: Self.base)
    #expect(result.current.isEmpty)
    #expect(result.past.isEmpty)
  }

  // MARK: Section total convenience

  /// Sum of current array's `amount` matches what ExpenseSection would display
  /// as the section total.
  @Test func partitioned_currentTotalMatchesReduce() {
    let start = Self.base
    let expenses = [
      makeExpense(amount: 10, date: start.addingTimeInterval(100)),
      makeExpense(amount: 25, date: start.addingTimeInterval(200)),
      makeExpense(amount: 5, date: start.addingTimeInterval(-100)), // past
    ]
    let result = expenses.partitioned(byPeriodStart: start)
    let sectionTotal = result.current.reduce(Decimal.zero) { $0 + $1.amount }
    #expect(sectionTotal == 35)
  }
}
