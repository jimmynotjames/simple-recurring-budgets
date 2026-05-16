import Foundation
@testable import simple_recurring_budgets
import Testing

private func d(_ year: Int, _ month: Int, _ day: Int) -> Date {
  var comps = DateComponents()
  comps.year = year; comps.month = month; comps.day = day
  comps.hour = 0; comps.minute = 0; comps.second = 0
  comps.timeZone = TimeZone(identifier: "UTC")
  return Calendar(identifier: .gregorian).date(from: comps)!
}

private func change(from date: Date, amount: Decimal, lastModified: Date = Date()) -> AllocationChange {
  AllocationChange(effectiveFrom: date, amount: amount, lastModified: lastModified)
}

struct AllocationInEffectTests {
  @Test func singleRow_beforeDate_returnsAmount() {
    let history = [change(from: d(2026, 4, 1), amount: 20)]
    #expect(allocationInEffect(at: d(2026, 4, 15), sortedHistory: history) == 20)
  }

  @Test func twoRows_latestApplicableWins() {
    let history = [
      change(from: d(2026, 4, 1), amount: 20),
      change(from: d(2026, 4, 10), amount: 25),
    ]
    #expect(allocationInEffect(at: d(2026, 4, 15), sortedHistory: history) == 25)
    #expect(allocationInEffect(at: d(2026, 4, 5), sortedHistory: history) == 20)
  }

  @Test func exactDateMatch_rowIsApplicable() {
    let history = [change(from: d(2026, 4, 10), amount: 30)]
    #expect(allocationInEffect(at: d(2026, 4, 10), sortedHistory: history) == 30)
  }

  @Test func noEligibleRow_fallsBackToEarliest() {
    let history = [change(from: d(2026, 4, 10), amount: 30)]
    // Query date is before the only row
    #expect(allocationInEffect(at: d(2026, 4, 5), sortedHistory: history) == 30)
  }

  @Test func tieOnEffectiveFrom_laterLastModifiedWins() {
    // Input must be pre-sorted by (effectiveFrom, lastModified); the later row sorts last
    // and wins by the "last entry with effectiveFrom <= date" rule.
    let earlier = change(from: d(2026, 4, 10), amount: 20, lastModified: d(2026, 4, 10))
    let later = change(from: d(2026, 4, 10), amount: 25, lastModified: d(2026, 4, 11))
    let history = [earlier, later]
    #expect(allocationInEffect(at: d(2026, 4, 15), sortedHistory: history) == 25)
  }

  @Test func emptyHistory_returnsZero() {
    #expect(allocationInEffect(at: d(2026, 4, 15), sortedHistory: []) == 0)
  }

  @Test func manyRows_picksCorrectRowForEachQuery() {
    // Exercise a budget that's had several allocation edits over time.
    let history = [
      change(from: d(2026, 1, 1), amount: 100),
      change(from: d(2026, 2, 1), amount: 150),
      change(from: d(2026, 3, 1), amount: 175),
      change(from: d(2026, 4, 1), amount: 200),
    ]
    #expect(allocationInEffect(at: d(2026, 1, 15), sortedHistory: history) == 100)
    #expect(allocationInEffect(at: d(2026, 2, 28), sortedHistory: history) == 150)
    #expect(allocationInEffect(at: d(2026, 3, 1), sortedHistory: history) == 175) // exact boundary
    #expect(allocationInEffect(at: d(2026, 4, 30), sortedHistory: history) == 200)
  }

  @Test func threeWayTieOnEffectiveFrom_latestLastModifiedWins() {
    // CloudKit cross-device scenario: three concurrent edits to the same period.
    let first = change(from: d(2026, 4, 10), amount: 20, lastModified: d(2026, 4, 10))
    let middle = change(from: d(2026, 4, 10), amount: 30, lastModified: d(2026, 4, 11))
    let latest = change(from: d(2026, 4, 10), amount: 25, lastModified: d(2026, 4, 12))
    // Already sorted by (effectiveFrom ASC, lastModified ASC). Latest by lastModified wins.
    let history = [first, middle, latest]
    #expect(allocationInEffect(at: d(2026, 4, 15), sortedHistory: history) == 25)
  }
}
