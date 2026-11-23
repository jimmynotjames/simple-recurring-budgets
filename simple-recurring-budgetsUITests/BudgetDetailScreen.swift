import XCTest

/// Screen object for BudgetDetailView.
@MainActor
struct BudgetDetailScreen {
  let app: XCUIApplication
  let budgetName: String

  var budgetOptionsButton: XCUIElement {
    app.buttons["Budget options"]
  }

  /// "Add expense to [name]" primary button (active budget).
  var addExpenseButton: XCUIElement {
    app.buttons["Add expense to \(budgetName)"]
  }

  /// "Resume [name]" primary button (paused budget).
  var resumeButton: XCUIElement {
    app.buttons["Resume \(budgetName)"]
  }

  /// Expense row button (pushes the edit form) whose label contains `text`.
  func expenseRow(containing text: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
  }

  /// Opens the "Budget options" (ellipsis) menu.
  func tapOptionsMenu() {
    budgetOptionsButton.tap()
  }

  func tapEditBudget() {
    tapOptionsMenu()
    app.buttons["Edit Budget"].tap()
  }

  func tapPauseBudget() {
    tapOptionsMenu()
    app.buttons["Pause Budget"].tap()
  }

  func tapResumeBudget() {
    tapOptionsMenu()
    app.buttons["Resume Budget"].tap()
  }
}
