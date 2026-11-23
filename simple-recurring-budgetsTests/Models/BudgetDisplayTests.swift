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
    // Locale-aware output: assert both abbreviated month names, not an en-US spelling.
    let label = budget.periodDisplayLabel
    #expect(label.contains("May"))
    #expect(label.contains("8"))
    #expect(label.contains("25"))
  }

  @Test func periodDisplayLabel_specificDates_sameDayWindow_rendersSingleDate() {
    // A 1-day Specific Dates budget (start == end), reachable via the VM's snap-forward collapse.
    // Must render the single date alone; an empty Range<Date> in IntervalFormatStyle is undefined.
    let budget = Budget(period: .specificDates)
    let day = Self.d(2026, 5, 20)
    budget.startDate = day
    budget.endDate = day
    let label = budget.periodDisplayLabel
    #expect(label.contains("May"))
    #expect(label.contains("20"))
    // No range separator ("–", "-", "to"); renders just "May 20, 2026" (or locale equivalent).
    #expect(!label.contains("–"))
  }

  @Test func specificDatesDisplayLabel_invertedWindow_rendersStartDateWithoutTrapping() {
    // Inverted window (endDate < startDate), typically a partial CloudKit sync. `Range`
    // construction would trap; the helper must degrade to the start date so the Budgets list
    // can't crash on a corrupt record. Calls the static helper directly because
    // `periodDisplayLabel` debug-asserts on this state, which would trip under the test runner.
    let label = Budget.specificDatesDisplayLabel(
      start: Self.d(2026, 5, 25),
      end: Self.d(2026, 5, 8)
    )
    #expect(label.contains("May"))
    #expect(label.contains("25"))
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
    // Only asserts it differs from the generic specificDates inlineLabel.
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
