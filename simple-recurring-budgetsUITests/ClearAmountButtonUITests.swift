import XCTest

/// Exercises the expense Amount card's clear button, one interaction path per test (originally
/// to isolate an EXC_BAD_ACCESS in AddEditExpenseView).
final class ClearAmountButtonUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Sheet open

  /// Baseline: Add Expense opens cleanly on a budget with no expenses (no Recents section).
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

  /// Add Expense opens cleanly with a Recents section alongside the amount card.
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

  // MARK: - Typing an amount (viewModel.amount becomes non-nil → button appears)

  /// Typing an amount flips the clear button's opacity from 0 to 1.
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

  /// Clearing the typed amount re-disables Save.
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

  /// Tapping a Recents tile fills the amount and shows the clear button.
  @MainActor
  func testRecentsTileFillsAmount() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Test", in: app)
    addNamedExpense(amount: "12", name: "Lunch", to: "Test", in: app)

    app.buttons["Add expense for Test"].tap()
    XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 3))

    // Tile label is "{name}, {formatted amount}"; match the name prefix.
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

  /// Regression (focus jump): with the cursor in Amount, tapping clear (✕) after a Recents tile
  /// fill must keep focus in Amount, not hand first responder to Description.
  @MainActor
  func testClearAmountAfterRecentsTapKeepsFocusInAmountField() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Test", in: app)
    addNamedExpense(amount: "12", name: "Lunch", to: "Test", in: app)

    app.buttons["Add expense for Test"].tap()
    XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 3))

    // iOS-COMPAT: double-tap forces UIViewRepresentable focus to register in XCUITest;
    // autoFocus alone is flaky here.
    let amountField = expenseAmountField(in: app)
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    amountField.tap()
    amountField.tap()

    let recentsTile = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Lunch'")
    ).firstMatch
    XCTAssertTrue(recentsTile.waitForExistence(timeout: 2), "Recents tile should be visible")
    // The decimal pad could cover the tile row on a small device or large type; fail here
    // diagnosably rather than tap the keyboard.
    XCTAssertTrue(recentsTile.isHittable, "Recents tile must not be covered by the keyboard")
    recentsTile.tap()

    let clearButton = app.buttons["Clear amount"]
    XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
    clearButton.tap()

    waitForKeyboardFocus(on: amountField, message: "Focus should stay in the Amount field after clearing it")
    let descriptionField = app.textFields["Expense description"]
    XCTAssertFalse(
      hasKeyboardFocus(descriptionField),
      "Focus must not jump to the Description field after clearing the Amount"
    )
  }

  /// Regression: with Description focused (typing filters Recents) and a Recents tile filling both
  /// fields, tapping Amount clear (✕) must move focus into Amount, like `UITextField`'s built-in
  /// clear button; it used to stay in Description.
  @MainActor
  func testClearAmountWhileDescriptionFocused() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Test", in: app)
    addNamedExpense(amount: "12", name: "Lunch", to: "Test", in: app)

    app.buttons["Add expense for Test"].tap()
    XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 3))

    let descriptionField = app.textFields["Expense description"]
    XCTAssertTrue(descriptionField.waitForExistence(timeout: 2))
    descriptionField.tap()
    descriptionField.typeText("Lu")

    let recentsTile = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Lunch'")
    ).firstMatch
    XCTAssertTrue(recentsTile.waitForExistence(timeout: 2))
    recentsTile.tap()

    let clearButton = app.buttons["Clear amount"]
    XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
    clearButton.tap()

    waitForKeyboardFocus(
      on: expenseAmountField(in: app),
      message: "The clear button must hand focus to the Amount field"
    )
    XCTAssertFalse(
      hasKeyboardFocus(descriptionField),
      "Focus must not sit in the Description field after clearing the Amount (description-focused variant)"
    )
  }

  /// Pins the repeat cycle of the monotonic `focusRequest` trigger: clear → retype → type in
  /// Description (each keystroke re-renders the sheet; the coordinator's equality check stops
  /// Amount stealing focus back) → clear again (a fresh counter delta must refocus Amount).
  @MainActor
  func testRepeatedClearCyclesKeepHandingFocusToAmountField() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Test", in: app)
    addNamedExpense(amount: "12", name: "Lunch", to: "Test", in: app)

    app.buttons["Add expense for Test"].tap()
    XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 3))

    // First cycle: clear must land focus in Amount.
    let amountField = expenseAmountField(in: app)
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    amountField.tap()
    amountField.tap()
    amountField.typeText("25")

    let clearButton = app.buttons["Clear amount"]
    XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
    clearButton.tap()
    waitForKeyboardFocus(on: amountField, message: "First clear must hand focus to the Amount field")

    // The field is already focused from the clear, so keystrokes land directly.
    amountField.typeText("42")

    // Dismiss the decimal pad via the section label first (as in addNamedExpense), then type in
    // Description.
    let descriptionLabel = app.staticTexts["Description (optional)"]
    XCTAssertTrue(descriptionLabel.waitForExistence(timeout: 2))
    descriptionLabel.tap()

    let descriptionField = app.textFields["Expense description"]
    XCTAssertTrue(descriptionField.waitForExistence(timeout: 2))
    descriptionField.tap()
    descriptionField.typeText("Lu")

    XCTAssertTrue(
      hasKeyboardFocus(descriptionField),
      "Typing in the Description must keep focus there — the Amount field must not steal it back"
    )
    XCTAssertFalse(hasKeyboardFocus(amountField))

    // Second cycle.
    XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
    clearButton.tap()
    waitForKeyboardFocus(on: amountField, message: "Second clear must hand focus to the Amount field again")
    XCTAssertFalse(
      hasKeyboardFocus(descriptionField),
      "Focus must not remain in the Description field after the second clear"
    )
  }

  // MARK: - Helpers

  /// First-responder state via the snapshot's `hasKeyboardFocus` attribute (no public property on iOS).
  @MainActor
  private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
    (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
  }

  /// Deadline-based wait for keyboard focus; the refocus is a Task hop plus keyboard
  /// presentation, so a fixed sleep wastes time or flakes on loaded CI sims.
  @MainActor
  private func waitForKeyboardFocus(on element: XCUIElement, message: String) {
    let focused = expectation(
      for: NSPredicate(format: "hasKeyboardFocus == true"),
      evaluatedWith: element
    )
    let result = XCTWaiter.wait(for: [focused], timeout: 5)
    XCTAssertEqual(result, .completed, message)
  }

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
    // iOS-COMPAT: double-tap forces UIViewRepresentable focus to register in XCUITest.
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

    // The decimal pad has no Done key; tap the section label above Description to dismiss it.
    let descriptionLabel = app.staticTexts["Description (optional)"]
    if descriptionLabel.waitForExistence(timeout: 2) {
      descriptionLabel.tap()
    }

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
