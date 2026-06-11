import Foundation
@testable import simple_recurring_budgets
import Testing

struct ExpenseItemPartitionTests {
  /// Convenience factory for non-persisted ExpenseItems.
  private func makeExpense(amount: Decimal = 1, name: String? = nil, date: Date) -> ExpenseItem {
    ExpenseItem(amount: amount, name: name, date: date)
  }

  private static let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
  /// Exclusive end of the current period — one day after `base`.
  private static let end = base.addingTimeInterval(86400)

  // MARK: nil bounds

  /// When periodStart is nil (lifecycle not yet resolved), all arrays are empty.
  @Test func partitioned_nilStart_returnsEmpty() {
    let expenses = [
      makeExpense(date: Self.base),
      makeExpense(date: Self.base.addingTimeInterval(-3600)),
    ]
    let result = expenses.partitioned(byPeriodStart: nil, periodEnd: Self.end)
    #expect(result.future.isEmpty)
    #expect(result.current.isEmpty)
    #expect(result.past.isEmpty)
  }

  /// When periodEnd is nil (lifecycle not yet resolved), all arrays are empty.
  @Test func partitioned_nilEnd_returnsEmpty() {
    let expenses = [makeExpense(date: Self.base)]
    let result = expenses.partitioned(byPeriodStart: Self.base, periodEnd: nil)
    #expect(result.future.isEmpty)
    #expect(result.current.isEmpty)
    #expect(result.past.isEmpty)
  }

  // MARK: Boundary inclusivity

  /// An expense exactly at periodStart falls in the CURRENT array (>= semantic).
  @Test func partitioned_dateEqualsStart_isCurrentNotPast() {
    let start = Self.base
    let onBoundary = makeExpense(date: start)
    let justBefore = makeExpense(date: start.addingTimeInterval(-1))

    let result = [onBoundary, justBefore].partitioned(byPeriodStart: start, periodEnd: Self.end)
    #expect(result.current.count == 1)
    #expect(result.current.first?.date == start)
    #expect(result.past.count == 1)
    #expect(result.past.first?.date == start.addingTimeInterval(-1))
  }

  /// An expense exactly at periodEnd falls in the FUTURE array (end is exclusive,
  /// matching `BudgetCalculator`'s `date < effectivePeriodEnd` inclusion rule).
  @Test func partitioned_dateEqualsEnd_isFutureNotCurrent() {
    let onBoundary = makeExpense(date: Self.end)
    let justBefore = makeExpense(date: Self.end.addingTimeInterval(-1))

    let result = [onBoundary, justBefore].partitioned(byPeriodStart: Self.base, periodEnd: Self.end)
    #expect(result.future.count == 1)
    #expect(result.future.first?.date == Self.end)
    #expect(result.current.count == 1)
    #expect(result.current.first?.date == Self.end.addingTimeInterval(-1))
  }

  // MARK: Future bucket — one bucket for all future periods

  /// Future-dated expenses from several different future periods collapse into
  /// the single future bucket (audit L2 decision).
  @Test func partitioned_multipleFuturePeriods_singleBucket() {
    let tomorrow = makeExpense(date: Self.end.addingTimeInterval(3600))
    let nextWeek = makeExpense(date: Self.end.addingTimeInterval(86400 * 6))
    let nextMonth = makeExpense(date: Self.end.addingTimeInterval(86400 * 30))

    let result = [nextWeek, nextMonth, tomorrow].partitioned(byPeriodStart: Self.base, periodEnd: Self.end)
    #expect(result.future.count == 3)
    #expect(result.current.isEmpty)
    #expect(result.past.isEmpty)
  }

  // MARK: Sort order — descending by date within each array

  @Test func partitioned_sortedDescendingInAllArrays() {
    let start = Self.base
    let f1 = makeExpense(date: Self.end.addingTimeInterval(7200)) // newer future
    let f2 = makeExpense(date: Self.end.addingTimeInterval(3600)) // older future
    let c1 = makeExpense(date: start.addingTimeInterval(3600)) // newer current
    let c2 = makeExpense(date: start.addingTimeInterval(1800)) // older current
    let c3 = makeExpense(date: start) // boundary → current
    let p1 = makeExpense(date: start.addingTimeInterval(-1800)) // newer past
    let p2 = makeExpense(date: start.addingTimeInterval(-3600)) // older past

    let result = [c2, f2, p2, c1, f1, p1, c3].partitioned(byPeriodStart: start, periodEnd: Self.end)

    // Future: newest first
    #expect(result.future.map(\.date) == [f1.date, f2.date])
    // Current: newest first
    #expect(result.current.map(\.date) == [c1.date, c2.date, c3.date])
    // Past: newest first
    #expect(result.past.map(\.date) == [p1.date, p2.date])
  }

  // MARK: All-current edge case

  @Test func partitioned_allExpensesInCurrentPeriod() {
    let start = Self.base
    let expenses = (1 ... 3).map { makeExpense(date: start.addingTimeInterval(Double($0) * 600)) }
    let result = expenses.partitioned(byPeriodStart: start, periodEnd: Self.end)
    #expect(result.future.isEmpty)
    #expect(result.current.count == 3)
    #expect(result.past.isEmpty)
  }

  // MARK: All-past edge case

  @Test func partitioned_allExpensesInPast() {
    let start = Self.base
    let expenses = (1 ... 3).map { makeExpense(date: start.addingTimeInterval(-Double($0) * 600)) }
    let result = expenses.partitioned(byPeriodStart: start, periodEnd: Self.end)
    #expect(result.future.isEmpty)
    #expect(result.current.isEmpty)
    #expect(result.past.count == 3)
  }

  // MARK: Empty input

  @Test func partitioned_emptyInput_returnsAllEmpty() {
    let result = [ExpenseItem]().partitioned(byPeriodStart: Self.base, periodEnd: Self.end)
    #expect(result.future.isEmpty)
    #expect(result.current.isEmpty)
    #expect(result.past.isEmpty)
  }

  // MARK: Section total convenience

  /// Sum of current array's `amount` matches what ExpenseSection would display
  /// as the section total — and excludes future-dated expenses, so the header
  /// total agrees with the Remaining headline (audit L2).
  @Test func partitioned_currentTotalMatchesReduce_excludingFuture() {
    let start = Self.base
    let expenses = [
      makeExpense(amount: 10, date: start.addingTimeInterval(100)),
      makeExpense(amount: 25, date: start.addingTimeInterval(200)),
      makeExpense(amount: 5, date: start.addingTimeInterval(-100)), // past
      makeExpense(amount: 99, date: Self.end.addingTimeInterval(100)), // future
    ]
    let result = expenses.partitioned(byPeriodStart: start, periodEnd: Self.end)
    let sectionTotal = result.current.reduce(Decimal.zero) { $0 + $1.amount }
    #expect(sectionTotal == 35)
  }
}
