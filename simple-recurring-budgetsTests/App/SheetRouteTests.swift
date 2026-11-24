import Foundation
@testable import simple_recurring_budgets
import Testing

/// `SheetRoute` binds to `.sheet(item:)` via `Identifiable`, so `id` is the case itself: two
/// routes are the same presentation iff equal, including carried model UUIDs.
@Suite("SheetRoute identity")
struct SheetRouteTests {
  @Test func id_equalsSelf_forAllCases() {
    let budgetID = UUID()
    let routes: [SheetRoute] = [
      .addBudget,
      .editBudget(budgetID),
      .addExpense(budgetID),
      .settings,
      .analyticsConsent,
    ]
    for route in routes {
      #expect(route.id == route)
    }
  }

  @Test func editBudget_idDistinguishesDifferentBudgets() {
    let first = SheetRoute.editBudget(UUID())
    let second = SheetRoute.editBudget(UUID())
    #expect(first.id != second.id)
  }
}
