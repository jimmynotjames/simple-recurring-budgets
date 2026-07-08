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

  /// Regression (focus jump): with the cursor in the Amount field, tapping the
  /// Amount clear (✕) after a Recents tile fill must leave focus in the Amount
  /// field — it must NOT hand first responder to the Description field. The bug
  /// moved the cursor to the end of the Description after clearing the amount.
  @MainActor
  func testClearAmountAfterRecentsTapKeepsFocusInAmountField() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Test", in: app)
    addNamedExpense(amount: "12", name: "Lunch", to: "Test", in: app)

    app.buttons["Add expense for Test"].tap()
    XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 3))

    // Put the cursor in the Amount field explicitly (iOS-COMPAT: double-tap forces
    // UIViewRepresentable focus to register in XCUITest; autoFocus alone is flaky here).
    let amountField = expenseAmountField(in: app)
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    amountField.tap()
    amountField.tap()

    let recentsTile = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Lunch'")
    ).firstMatch
    XCTAssertTrue(recentsTile.waitForExistence(timeout: 2), "Recents tile should be visible")
    // The decimal pad is up; on a smaller device or larger type size it could cover
    // the tile row. Fail diagnosably here rather than tapping the keyboard.
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

  /// Regression for the reported bug: the Description field is focused (typing
  /// there is what filters the Recents row), a Recents tile fills both fields,
  /// and the user taps the Amount clear (✕). Before the fix the cursor stayed at
  /// the end of the Description field; the ✕ must move it into the Amount field
  /// (matching `UITextField`'s built-in clear-button behavior).
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

  /// Pins the full repeat cycle of the monotonic `focusRequest` trigger:
  /// clear (✕) → retype an amount → move focus to the Description and type
  /// (each keystroke re-renders the sheet; the Amount field must NOT steal
  /// focus back — the coordinator's equality check is what prevents it) →
  /// clear again (a fresh counter delta must hand focus to Amount again).
  @MainActor
  func testRepeatedClearCyclesKeepHandingFocusToAmountField() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Test", in: app)
    addNamedExpense(amount: "12", name: "Lunch", to: "Test", in: app)

    app.buttons["Add expense for Test"].tap()
    XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 3))

    // First cycle: type an amount, clear it, focus must land in Amount.
    let amountField = expenseAmountField(in: app)
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    amountField.tap()
    amountField.tap()
    amountField.typeText("25")

    let clearButton = app.buttons["Clear amount"]
    XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
    clearButton.tap()
    waitForKeyboardFocus(on: amountField, message: "First clear must hand focus to the Amount field")

    // Retype: the field is focused from the clear, so keystrokes land directly.
    amountField.typeText("42")

    // Move to the Description (dismiss the decimal pad via the section label first,
    // matching addNamedExpense's pattern) and type — filtering re-renders the sheet
    // on every keystroke, and the Amount field must not steal focus back.
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

    // Second cycle: clearing again is a fresh counter delta and must hand focus back.
    XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
    clearButton.tap()
    waitForKeyboardFocus(on: amountField, message: "Second clear must hand focus to the Amount field again")
    XCTAssertFalse(
      hasKeyboardFocus(descriptionField),
      "Focus must not remain in the Description field after the second clear"
    )
  }

  // MARK: - Helpers

  /// XCUITest exposes first-responder state through the element snapshot's
  /// `hasKeyboardFocus` attribute (no public Swift property on iOS).
  @MainActor
  private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
    (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
  }

  /// Deadline-based wait for keyboard focus (the refocus is a Task hop plus a keyboard
  /// presentation, so a fixed sleep either wastes time or flakes on loaded CI sims).
  /// The NSPredicate reads the same KVC `hasKeyboardFocus` attribute as the helper above.
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
