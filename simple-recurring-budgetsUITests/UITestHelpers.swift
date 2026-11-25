import XCTest

// Shared factories and navigation helpers for all UITest targets (all @MainActor).

// MARK: - App factories

/// App with IS_TESTING=1, which suppresses Mixpanel analytics, and UI_TESTS=1, which marks a UI-test
/// launch (the unit tests' host app gets IS_TESTING from the scheme but never UI_TESTS).
///
/// `FORCE_ANIMATIONS` is passed through from the test runner's environment when it is set (CI sets
/// `TEST_RUNNER_FORCE_ANIMATIONS=off`; xcodebuild strips the prefix), so the app turns animations off
/// (`TestAnimationsOverride` in the app). `keepsAnimations` opts a test out of that.
@MainActor
func makeApp(keepsAnimations: Bool = false) -> XCUIApplication {
  let app = XCUIApplication()
  app.launchEnvironment["IS_TESTING"] = "1"
  app.launchEnvironment["UI_TESTS"] = "1"
  if !keepsAnimations, let animations = ProcessInfo.processInfo.environment["FORCE_ANIMATIONS"] {
    app.launchEnvironment["FORCE_ANIMATIONS"] = animations
  }
  return app
}

/// App that launches with pre-seeded budgets in the in-memory store.
///
/// Each name becomes a monthly $100 budget inserted before the root view renders.
///
/// Names are comma-joined and split by `InMemoryModelContainer.makeForUITests()`, so a name
/// must not contain a comma (it would seed two budgets). `LocalizationScreenshotCapture`
/// relies on this too.
@MainActor
func makeApp(seedBudgets names: [String], keepsAnimations: Bool = false) -> XCUIApplication {
  let app = makeApp(keepsAnimations: keepsAnimations)
  app.launchEnvironment["SEED_BUDGETS"] = names.joined(separator: ",")
  return app
}

/// App at the largest system accessibility text size.
@MainActor
func largeTextApp(keepsAnimations: Bool = false) -> XCUIApplication {
  let app = makeApp(keepsAnimations: keepsAnimations)
  app.launchArguments += [
    "-UIPreferredContentSizeCategoryName",
    "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
  ]
  return app
}

// MARK: - Navigation helpers

/// Creates a budget with `name` and a $100 allocation via the Add Budget form and waits for
/// its row. Precondition: the budgets list is showing.
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
  // DecimalInputField wraps UITextField (iOS 17+ SwiftUI binding bugs; see DecimalInputField.swift),
  // and XCUITest focus tracking doesn't reliably sync with its first-responder state.
  // Workaround: tap a non-interactive label to dismiss the alpha keyboard, then double-tap
  // the field before typeText(). Remove when the workaround is no longer needed.
  app.staticTexts["Allocation"].tap()
  amountField.tap()
  amountField.tap()
  amountField.typeText("100")

  app.buttons["Save"].tap()

  // "Add expense for NAME" exists only on the budgets list, so it confirms both sheet dismissal
  // and the SwiftData @Query refresh.
  XCTAssertTrue(
    app.buttons["Add expense for \(name)"].waitForExistence(timeout: 5),
    "Budget row should appear after saving"
  )
}

/// Fills the Add Expense form and saves. Precondition: the Add Expense sheet is open.
@MainActor
func addExpense(description: String, amount: String, in app: XCUIApplication) {
  let amountField = app.textFields.matching(
    NSPredicate(format: "label BEGINSWITH 'Expense amount'")
  ).firstMatch
  XCTAssertTrue(amountField.waitForExistence(timeout: 2))
  // iOS-COMPAT(17+): same UIViewRepresentable focus workaround as the allocation field;
  // the double-tap makes first-responder state register before typeText().
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
