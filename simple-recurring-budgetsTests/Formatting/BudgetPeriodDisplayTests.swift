@testable import simple_recurring_budgets
import Testing

/// Exercises both localized label forms in `BudgetPeriod+Display.swift` for
/// every period case. Exact wording is owned by the String Catalog (and varies
/// by run locale), so these tests assert the structural contract instead:
/// every case resolves to a non-empty label, and no two cases collapse to the
/// same string.
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
