@testable import simple_recurring_budgets
import Testing

/// Both localized label forms in `BudgetPeriod+Display.swift` for every period case.
/// Wording lives in the String Catalog and varies by run locale, so assert structure: every
/// case has a non-empty label and no two labels collide.
@Suite("BudgetPeriod display labels")
struct BudgetPeriodDisplayTests {
  private let allPeriods: [BudgetPeriod] = [.daily, .weekly, .biweekly, .monthly, .specificDates]

  @Test func listLabel_nonEmptyAndDistinct_forAllCases() {
    let labels = allPeriods.map(\.listLabel)
    for label in labels {
      #expect(!label.isEmpty)
    }
    #expect(Set(labels).count == allPeriods.count, "list labels must not collapse across cases")
  }

  @Test func inlineLabel_nonEmptyAndDistinct_forAllCases() {
    let labels = allPeriods.map(\.inlineLabel)
    for label in labels {
      #expect(!label.isEmpty)
    }
    #expect(Set(labels).count == allPeriods.count, "inline labels must not collapse across cases")
  }
}
