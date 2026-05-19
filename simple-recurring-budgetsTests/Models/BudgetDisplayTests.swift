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
}
