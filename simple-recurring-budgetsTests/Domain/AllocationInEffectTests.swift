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
    #expect(allocationInEffect(at: d(2026, 4, 15), history: history) == 20)
  }

  @Test func twoRows_latestApplicableWins() {
    let history = [
      change(from: d(2026, 4, 1), amount: 20),
      change(from: d(2026, 4, 10), amount: 25),
    ]
    #expect(allocationInEffect(at: d(2026, 4, 15), history: history) == 25)
    #expect(allocationInEffect(at: d(2026, 4, 5), history: history) == 20)
  }

  @Test func exactDateMatch_rowIsApplicable() {
    let history = [change(from: d(2026, 4, 10), amount: 30)]
    #expect(allocationInEffect(at: d(2026, 4, 10), history: history) == 30)
  }

  @Test func noEligibleRow_fallsBackToEarliest() {
    let history = [change(from: d(2026, 4, 10), amount: 30)]
    // Query date is before the only row
    #expect(allocationInEffect(at: d(2026, 4, 5), history: history) == 30)
  }

  @Test func tieOnEffectiveFrom_laterLastModifiedWins() {
    let earlier = change(from: d(2026, 4, 10), amount: 20, lastModified: d(2026, 4, 10))
    let later = change(from: d(2026, 4, 10), amount: 25, lastModified: d(2026, 4, 11))
    let history = [earlier, later]
    #expect(allocationInEffect(at: d(2026, 4, 15), history: history) == 25)
  }

  @Test func emptyHistory_returnsZero() {
    #expect(allocationInEffect(at: d(2026, 4, 15), history: []) == 0)
  }
}
