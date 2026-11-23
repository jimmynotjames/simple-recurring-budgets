import XCTest

/// Screen object for BudgetsView (the budgets list).
@MainActor
struct BudgetsScreen {
  let app: XCUIApplication

  var addBudgetButton: XCUIElement {
    app.buttons["Add budget"]
  }

  var settingsButton: XCUIElement {
    app.buttons["Settings"]
  }

  var editButton: XCUIElement {
    app.buttons["Edit"]
  }

  /// Row navigation button for the named budget. List NavigationLink rows are buttons whose
  /// label starts with the budget name, then a comma-separated summary.
  func budgetRow(named name: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
  }

  /// Row "+" shortcut that opens the Add Expense sheet.
  func addExpenseButton(for name: String) -> XCUIElement {
    app.buttons["Add expense for \(name)"]
  }

  func tapAddBudget() {
    addBudgetButton.tap()
  }

  func tapSettings() {
    settingsButton.tap()
  }

  /// Pushes BudgetDetailView.
  func tapBudget(named name: String) {
    budgetRow(named: name).tap()
  }
}
