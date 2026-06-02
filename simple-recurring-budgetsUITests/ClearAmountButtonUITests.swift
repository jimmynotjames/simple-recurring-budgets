import XCTest

/// Exercises the clear-amount button added to the expense Amount card.
/// Each test isolates a specific interaction path that could trigger the
/// EXC_BAD_ACCESS crash reported against AddEditExpenseView.swift:395.
final class ClearAmountButtonUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Sheet open

  /// Baseline: open Add Expense on a budget with NO prior expenses.
  /// Recents section does not render. Validates the sheet opens cleanly.
  @MainActor
  func testOpenAddExpenseNoRecents() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Test", in: app)

    app.buttons["Add expense for Test"].tap()
    XCTAssertTrue(
      app.navigationBars["Add Expense"].waitForExistence(timeout: 3),
      "Add Expense sheet should appear"
    )
  }

  /// Open Add Expense on a budget that already has a named expense.
  /// Recents section WILL render — exercises the Recents + amount card layout together.
  @MainActor
  func testOpenAddExpenseWithRecents() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Test", in: app)
    addNamedExpense(amount: "15", name: "Coffee", to: "Test", in: app)

    app.buttons["Add expense for Test"].tap()
    XCTAssertTrue(
      app.navigationBars["Add Expense"].waitForExistence(timeout: 3),
      "Add Expense sheet should appear when Recents section is present"
    )
  }

  // MARK: - Typing an amount (makes viewModel.amount non-nil → button appears)

  /// Type an amount in Add Expense so viewModel.amount goes from nil → non-nil.
  /// This is when the clear button's opacity flips from 0 to 1.
  @MainActor
  func testTypeAmountMakesClearButtonVisible() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Test", in: app)

    app.buttons["Add expense for Test"].tap()
    XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 3))

    let amountField = expenseAmountField(in: app)
    amountField.tap()
    amountField.tap()
    amountField.typeText("25")

    XCTAssertTrue(
      app.buttons["Clear amount"].waitForExistence(timeout: 2),
      "Clear button should become visible after typing an amount"
    )
  }

  // MARK: - Clear button tap

  /// Type an amount then tap the clear button; Save should re-disable.
  @MainActor
  func testClearButtonResetsAmount() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Test", in: app)

    app.buttons["Add expense for Test"].tap()
    XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 3))

    let amountField = expenseAmountField(in: app)
    amountField.tap()
    amountField.tap()
    amountField.typeText("25")

    let clearButton = app.buttons["Clear amount"]
    XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
    clearButton.tap()

    XCTAssertFalse(
      app.buttons["Save"].isEnabled,
      "Save should be disabled after clearing the amount"
    )
  }

  // MARK: - Recents tile tap (sets both name and amount)

  /// Tap a Recents tile; verifies amount is filled and clear button appears.
  @MainActor
  func testRecentsTileFillsAmount() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Test", in: app)
    addNamedExpense(amount: "12", name: "Lunch", to: "Test", in: app)

    app.buttons["Add expense for Test"].tap()
    XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 3))

    // Tile label is "{name}, {formatted amount}" — match by expense name prefix
    let recentsTile = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Lunch'")
    ).firstMatch
    XCTAssertTrue(recentsTile.waitForExistence(timeout: 2), "Recents tile should be visible")
    recentsTile.tap()

    XCTAssertTrue(
      app.buttons["Clear amount"].waitForExistence(timeout: 2),
      "Clear button should appear after tapping a Recents tile"
    )
  }

  // MARK: - Helpers

  @MainActor
  private func makeApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["IS_TESTING"] = "1"
    return app
  }

  @MainActor
  private func expenseAmountField(in app: XCUIApplication) -> XCUIElement {
    app.textFields.matching(
      NSPredicate(format: "label == 'Expense amount'")
    ).firstMatch
  }

  /// Creates a budget named `name` with a $100 allocation.
  @MainActor
  private func createBudget(named name: String, in app: XCUIApplication) {
    app.buttons["Add budget"].tap()

    let nameField = app.textFields["Budget name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 2))
    nameField.tap()
    nameField.typeText(name)

    let allocationField = app.textFields.matching(
      NSPredicate(format: "label BEGINSWITH 'Allocation amount'")
    ).firstMatch
    XCTAssertTrue(allocationField.waitForExistence(timeout: 2))
    // iOS-COMPAT: double-tap forces UIViewRepresentable focus to register in XCUITest
    app.staticTexts["Allocation"].tap()
    allocationField.tap()
    allocationField.tap()
    allocationField.typeText("100")

    app.buttons["Save"].tap()
    XCTAssertTrue(
      app.buttons["Add expense for \(name)"].waitForExistence(timeout: 5)
    )
  }

  /// Adds a named expense and waits for the sheet to dismiss.
  @MainActor
  private func addNamedExpense(amount: String, name: String, to budgetName: String, in app: XCUIApplication) {
    app.buttons["Add expense for \(budgetName)"].tap()
    XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 3))

    let amountField = expenseAmountField(in: app)
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    amountField.tap()
    amountField.tap()
    amountField.typeText(amount)

    // The decimal pad does not have a Done key. Tap the section label above the
    // description field to dismiss the keyboard before refocusing.
    let descriptionLabel = app.staticTexts["Description (optional)"]
    if descriptionLabel.waitForExistence(timeout: 2) { descriptionLabel.tap() }

    let descriptionField = app.textFields["Expense description"]
    XCTAssertTrue(descriptionField.waitForExistence(timeout: 2))
    descriptionField.tap()
    descriptionField.typeText(name)

    app.buttons["Save"].tap()
    XCTAssertTrue(
      app.buttons["Add expense for \(budgetName)"].waitForExistence(timeout: 5)
    )
  }
}
