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

  /// The budget row cell for the named budget. The row's accessibility label begins
  /// with the budget name followed by a comma-separated summary.
  func budgetRow(named name: String) -> XCUIElement {
    app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
  }

  /// The inline "+" shortcut button on a budget row that opens the Add Expense sheet.
  func addExpenseButton(for name: String) -> XCUIElement {
    app.buttons["Add expense for \(name)"]
  }

  func tapAddBudget() {
    addBudgetButton.tap()
  }

  func tapSettings() {
    settingsButton.tap()
  }

  /// Taps a budget row to push BudgetDetailView.
  func tapBudget(named name: String) {
    budgetRow(named: name).tap()
  }
}
