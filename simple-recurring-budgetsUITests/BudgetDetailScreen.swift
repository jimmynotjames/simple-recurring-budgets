import XCTest

/// Screen object for BudgetDetailView.
@MainActor
struct BudgetDetailScreen {
  let app: XCUIApplication
  let budgetName: String

  var budgetOptionsButton: XCUIElement {
    app.buttons["Budget options"]
  }

  /// "Add expense to [name]" primary action button (visible when budget is active).
  var addExpenseButton: XCUIElement {
    app.buttons["Add expense to \(budgetName)"]
  }

  /// "Resume [name]" primary action button (visible when budget is paused).
  var resumeButton: XCUIElement {
    app.buttons["Resume \(budgetName)"]
  }

  /// An expense row button whose accessibility label contains the given description text.
  /// In BudgetDetailView, expense rows are navigable buttons (they push the edit expense form).
  func expenseRow(containing text: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
  }

  /// Opens the "Budget options" menu (ellipsis toolbar button).
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
