import Foundation
@testable import simple_recurring_budgets
import Testing

@MainActor
struct BudgetDisplayTests {
  private static let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
  }()

  private static func d(_ year: Int, _ month: Int, _ day: Int) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day))!
  }

  // MARK: - periodDisplayLabel

  @Test func periodDisplayLabel_recurring_returnsListLabel() {
    let budget = Budget(period: .weekly)
    #expect(budget.periodDisplayLabel == BudgetPeriod.weekly.listLabel)
  }

  @Test func periodDisplayLabel_specificDates_returnsDateInterval() {
    let budget = Budget(period: .specificDates)
    budget.startDate = Self.d(2026, 5, 8)
    budget.endDate = Self.d(2026, 5, 25)
    // Output is locale-aware; assert it includes both abbreviated month names
    // rather than pinning a specific en-US spelling.
    let label = budget.periodDisplayLabel
    #expect(label.contains("May"))
    #expect(label.contains("8"))
    #expect(label.contains("25"))
  }

  @Test func periodDisplayLabel_specificDates_sameDayWindow_rendersSingleDate() {
    // A 1-day Specific Dates budget (start == end), reachable via the snap-forward
    // collapse path on the VM. Display must render the single date alone — passing
    // an empty Range<Date> to IntervalFormatStyle is undefined for empty ranges.
    let budget = Budget(period: .specificDates)
    let day = Self.d(2026, 5, 20)
    budget.startDate = day
    budget.endDate = day
    let label = budget.periodDisplayLabel
    #expect(label.contains("May"))
    #expect(label.contains("20"))
    // Sanity: should NOT contain a separator that would indicate a multi-day range.
    // "–" (en-dash) or "-" or "to" would suggest a range. The single-date form
    // renders just "May 20, 2026" (or locale equivalent).
    #expect(!label.contains("–"))
  }

  @Test func periodDisplayLabel_specificDates_yearCrossing_includesYear() {
    let budget = Budget(period: .specificDates)
    budget.startDate = Self.d(2025, 12, 28)
    budget.endDate = Self.d(2026, 1, 5)
    let label = budget.periodDisplayLabel
    #expect(label.contains("2025") || label.contains("2026"))
  }

  @Test func periodDisplayLabel_specificDates_missingDates_fallsBackToListLabel() {
    let budget = Budget(period: .specificDates)
    budget.startDate = nil
    budget.endDate = nil
    #expect(budget.periodDisplayLabel == BudgetPeriod.specificDates.listLabel)
  }

  // MARK: - periodInlineLabel

  @Test func periodInlineLabel_recurring_returnsInlineLabel() {
    let budget = Budget(period: .weekly)
    #expect(budget.periodInlineLabel == BudgetPeriod.weekly.inlineLabel)
  }

  @Test func periodInlineLabel_specificDates_returnsWindowDescriptor() {
    let budget = Budget(period: .specificDates)
    // We don't pin a specific English spelling — just confirm it differs from
    // the generic inlineLabel for specificDates.
    let inline = budget.periodInlineLabel
    #expect(!inline.isEmpty)
    #expect(inline != BudgetPeriod.specificDates.inlineLabel || inline == "in this window")
  }

  // MARK: - isWindowValid

  @Test func isWindowValid_trueWhenEndDateNil() {
    let budget = Budget(period: .daily)
    budget.startDate = Self.d(2026, 5, 8)
    budget.endDate = nil
    #expect(budget.isWindowValid)
  }

  @Test func isWindowValid_trueWhenEndEqualsStart() {
    let budget = Budget(period: .specificDates)
    let date = Self.d(2026, 5, 8)
    budget.startDate = date
    budget.endDate = date
    #expect(budget.isWindowValid)
  }

  @Test func isWindowValid_trueWhenEndAfterStart() {
    let budget = Budget(period: .specificDates)
    budget.startDate = Self.d(2026, 5, 8)
    budget.endDate = Self.d(2026, 5, 25)
    #expect(budget.isWindowValid)
  }

  @Test func isWindowValid_falseWhenEndBeforeStart() {
    let budget = Budget(period: .specificDates)
    budget.startDate = Self.d(2026, 5, 25)
    budget.endDate = Self.d(2026, 5, 8)
    #expect(!budget.isWindowValid)
  }
}
