import XCTest

// Shared factory functions and navigation helpers for all UITest targets.
// All functions are @MainActor — XCUITest element interactions must run on the main thread.

// MARK: - App factories

/// Returns an XCUIApplication pre-configured with IS_TESTING=1 to suppress Mixpanel analytics.
@MainActor
func makeApp() -> XCUIApplication {
  let app = XCUIApplication()
  app.launchEnvironment["IS_TESTING"] = "1"
  return app
}

/// Returns an app pre-configured with the largest system accessibility text size.
@MainActor
func largeTextApp() -> XCUIApplication {
  let app = makeApp()
  app.launchArguments += [
    "-UIPreferredContentSizeCategoryName",
    "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
  ]
  return app
}

// MARK: - Navigation helpers

/// Navigates through the Add Budget form, fills `name` and a $100 allocation,
/// saves, and waits for the budget row to appear in the list.
///
/// Precondition: the budgets list is the current screen.
@MainActor
func createBudget(named name: String, in app: XCUIApplication) {
  app.buttons["Add budget"].tap()

  let nameField = app.textFields["Budget name"]
  XCTAssertTrue(nameField.waitForExistence(timeout: 2))
  nameField.tap()
  nameField.typeText(name)

  let amountField = app.textFields.matching(
    NSPredicate(format: "label BEGINSWITH 'Allocation amount'")
  ).firstMatch
  XCTAssertTrue(amountField.waitForExistence(timeout: 2))
  // iOS-COMPAT(17+): UIViewRepresentable UITextField focus in XCUITest.
  // DecimalInputField wraps UITextField because of iOS 17+ SwiftUI binding bugs
  // (see DecimalInputField.swift). XCUITest's focus tracking doesn't sync reliably
  // with the UITextField's first-responder state. Workaround: tap a non-interactive
  // label to dismiss the alpha keyboard, then double-tap the field before typeText().
  app.staticTexts["Allocation"].tap()
  amountField.tap()
  amountField.tap()
  amountField.typeText("100")

  app.buttons["Save"].tap()

  // Wait for the budget-specific "Add expense for NAME" button: it only exists on the
  // budgets list (not the form), confirming both sheet dismissal and SwiftData @Query refresh.
  XCTAssertTrue(
    app.buttons["Add expense for \(name)"].waitForExistence(timeout: 5),
    "Budget row should appear after saving"
  )
}

/// Fills the Add Expense form with the given description and amount, then saves.
///
/// Precondition: the Add Expense sheet is open.
@MainActor
func addExpense(description: String, amount: String, in app: XCUIApplication) {
  let amountField = app.textFields.matching(
    NSPredicate(format: "label BEGINSWITH 'Amount'")
  ).firstMatch
  XCTAssertTrue(amountField.waitForExistence(timeout: 2))
  // iOS-COMPAT(17+): same UIViewRepresentable focus workaround as the allocation field.
  // Double-tap ensures first-responder state registers before typeText().
  amountField.tap()
  amountField.tap()
  amountField.typeText(amount)

  if !description.isEmpty {
    let descField = app.textFields["Expense description"]
    XCTAssertTrue(descField.waitForExistence(timeout: 2))
    descField.tap()
    descField.typeText(description)
  }

  app.buttons["Save"].tap()
}
