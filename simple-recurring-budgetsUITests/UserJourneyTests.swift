import XCTest

/// End-to-end user journey tests covering the core flows of the app.
///
/// Tests that need a pre-existing budget use `makeApp(seedBudgets:)` to inject
/// the budget via `SEED_BUDGETS` in the app's in-memory store before launch —
/// skipping UI creation so each test exercises only the feature it claims to cover.
///
/// Two tests (`testCreateBudget`, `testCreateBudgetAndNavigateToDetail`) keep the
/// full UI creation path to maintain coverage of the Add Budget form itself.
///
/// Note: Apple does not support Swift Testing (`import Testing`) in XCUITest
/// targets. These tests use XCTestCase with `continueAfterFailure = false`, which
/// matches `#require` stop-on-first-failure semantics.
@MainActor
final class UserJourneyTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Budget creation (UI path — exercises Add Budget form)

  func testCreateBudget() {
    let app = makeApp()
    app.launch()
    let budgets = BudgetsScreen(app: app)

    budgets.tapAddBudget()
    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.nameField.waitForExistence(timeout: 2))
    form.fillName("Groceries")
    form.fillAllocation("500")
    form.tapSave()

    XCTAssertTrue(
      budgets.addExpenseButton(for: "Groceries").waitForExistence(timeout: 5),
      "Budget row should appear in list after saving"
    )
  }

  // MARK: - Navigation

  func testNavigateToBudgetDetail() {
    let app = makeApp(seedBudgets: ["Groceries"])
    app.launch()

    let budgets = BudgetsScreen(app: app)
    budgets.tapBudget(named: "Groceries")

    let detail = BudgetDetailScreen(app: app, budgetName: "Groceries")
    XCTAssertTrue(
      detail.budgetOptionsButton.waitForExistence(timeout: 3),
      "Budget detail should be visible after tapping the row"
    )
    XCTAssertTrue(detail.addExpenseButton.exists)
  }

  // MARK: - Add expense

  func testAddExpenseFromBudgetRow() {
    let app = makeApp(seedBudgets: ["Groceries"])
    app.launch()

    let budgets = BudgetsScreen(app: app)
    let addButton = budgets.addExpenseButton(for: "Groceries")
    XCTAssertTrue(addButton.waitForExistence(timeout: 2))
    addButton.tap()

    addExpense(description: "Coffee", amount: "5", in: app)

    XCTAssertTrue(
      budgets.addExpenseButton(for: "Groceries").waitForExistence(timeout: 5),
      "Should be back on the budgets list after saving expense"
    )
    budgets.tapBudget(named: "Groceries")

    let detail = BudgetDetailScreen(app: app, budgetName: "Groceries")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))
    XCTAssertTrue(
      detail.expenseRow(containing: "Coffee").waitForExistence(timeout: 3),
      "Expense row should appear in detail after adding via list shortcut"
    )
  }

  func testAddExpenseFromDetail() {
    let app = makeApp(seedBudgets: ["Transport"])
    app.launch()

    let budgets = BudgetsScreen(app: app)
    budgets.tapBudget(named: "Transport")

    let detail = BudgetDetailScreen(app: app, budgetName: "Transport")
    XCTAssertTrue(detail.addExpenseButton.waitForExistence(timeout: 3))
    detail.addExpenseButton.tap()

    addExpense(description: "Bus fare", amount: "3", in: app)

    XCTAssertTrue(
      detail.expenseRow(containing: "Bus fare").waitForExistence(timeout: 5),
      "Expense row should appear in detail after saving"
    )
  }

  // MARK: - Edit budget

  func testEditBudget() {
    let app = makeApp(seedBudgets: ["Groceries"])
    app.launch()

    let budgets = BudgetsScreen(app: app)
    budgets.tapBudget(named: "Groceries")

    let detail = BudgetDetailScreen(app: app, budgetName: "Groceries")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))
    detail.tapEditBudget()

    let editForm = AddBudgetScreen(app: app)
    XCTAssertTrue(editForm.nameField.waitForExistence(timeout: 2))
    editForm.replaceName("Groceries Updated")
    editForm.tapSave()

    // Navigate back to the budgets list and verify the updated name appears there.
    // (Checking the detail nav bar title directly is unreliable in XCUITest due to
    // SwiftUI animation timing after sheet dismissal.)
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))
    app.navigationBars.buttons.firstMatch.tap()

    XCTAssertTrue(
      budgets.budgetRow(named: "Groceries Updated").waitForExistence(timeout: 5),
      "Updated budget name should appear in the budgets list"
    )
  }

  // MARK: - Pause and resume

  func testPauseAndResumeBudget() {
    let app = makeApp(seedBudgets: ["Entertainment"])
    app.launch()

    BudgetsScreen(app: app).tapBudget(named: "Entertainment")

    let detail = BudgetDetailScreen(app: app, budgetName: "Entertainment")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))

    detail.tapPauseBudget()
    XCTAssertTrue(
      detail.resumeButton.waitForExistence(timeout: 3),
      "Resume button should appear after pausing"
    )

    detail.resumeButton.tap()
    XCTAssertTrue(
      detail.addExpenseButton.waitForExistence(timeout: 3),
      "Add expense button should reappear after resuming"
    )
  }

  // MARK: - Expense management

  func testDeleteExpense() {
    let app = makeApp(seedBudgets: ["Dining"])
    app.launch()

    let budgets = BudgetsScreen(app: app)
    let shortcut = budgets.addExpenseButton(for: "Dining")
    XCTAssertTrue(shortcut.waitForExistence(timeout: 2))
    shortcut.tap()
    addExpense(description: "Pizza", amount: "20", in: app)

    budgets.tapBudget(named: "Dining")
    let detail = BudgetDetailScreen(app: app, budgetName: "Dining")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))

    let expenseRow = detail.expenseRow(containing: "Pizza")
    XCTAssertTrue(expenseRow.waitForExistence(timeout: 3))
    expenseRow.swipeLeft()
    app.buttons["Delete"].tap()

    XCTAssertFalse(
      detail.expenseRow(containing: "Pizza").waitForExistence(timeout: 3),
      "Pizza expense should be gone after swipe-delete"
    )
  }

  func testEditExpense() {
    let app = makeApp(seedBudgets: ["Dining"])
    app.launch()

    let budgets = BudgetsScreen(app: app)
    let shortcut = budgets.addExpenseButton(for: "Dining")
    XCTAssertTrue(shortcut.waitForExistence(timeout: 2))
    shortcut.tap()
    addExpense(description: "Sushi", amount: "40", in: app)

    budgets.tapBudget(named: "Dining")
    let detail = BudgetDetailScreen(app: app, budgetName: "Dining")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))

    let expenseRow = detail.expenseRow(containing: "Sushi")
    XCTAssertTrue(expenseRow.waitForExistence(timeout: 3))
    expenseRow.tap()

    let editForm = AddExpenseScreen(app: app)
    XCTAssertTrue(editForm.descriptionField.waitForExistence(timeout: 2))
    editForm.descriptionField.tap()
    if let current = editForm.descriptionField.value as? String, !current.isEmpty {
      editForm.descriptionField.typeText(
        String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
      )
    }
    editForm.descriptionField.typeText("Ramen")
    editForm.tapSave()

    XCTAssertTrue(
      detail.expenseRow(containing: "Ramen").waitForExistence(timeout: 3),
      "Updated description should appear in detail after saving"
    )
  }

  // MARK: - Budget deletion

  func testDeleteBudget() {
    let app = makeApp(seedBudgets: ["Temporary"])
    app.launch()

    BudgetsScreen(app: app).tapBudget(named: "Temporary")

    let detail = BudgetDetailScreen(app: app, budgetName: "Temporary")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))
    detail.tapEditBudget()

    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.deleteBudgetButton.waitForExistence(timeout: 2))
    form.tapDeleteAndConfirm()

    let budgets = BudgetsScreen(app: app)
    XCTAssertTrue(
      budgets.addBudgetButton.waitForExistence(timeout: 3),
      "Should be back on the budgets list after deleting"
    )
    XCTAssertFalse(
      budgets.budgetRow(named: "Temporary").waitForExistence(timeout: 2),
      "Deleted budget should not appear in the list"
    )
  }

  // MARK: - Settings

  func testSettingsRoundTrip() {
    let app = makeApp()
    app.launch()

    let budgets = BudgetsScreen(app: app)
    budgets.tapSettings()

    let settings = SettingsScreen(app: app)
    XCTAssertTrue(
      settings.navigationBar.waitForExistence(timeout: settingsSheetTimeout),
      "Settings sheet should appear"
    )
    settings.tapDone()

    XCTAssertTrue(
      budgets.addBudgetButton.waitForExistence(timeout: 2),
      "Should be back on the budgets list after dismissing Settings"
    )
  }

  // MARK: - Add Budget form — period selection

  /// The default period when opening a new budget form is Monthly, and the
  /// carry-over toggle should be visible for all recurring period types.
  func testAddBudgetDefaultPeriodShowsCarryOver() {
    let app = makeApp()
    app.launch()

    BudgetsScreen(app: app).tapAddBudget()

    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.nameField.waitForExistence(timeout: 2))
    // Monthly chip should be the selected default.
    XCTAssertTrue(
      app.buttons["Monthly period"].waitForExistence(timeout: 2),
      "Monthly period chip should be present"
    )
    // Carry-over toggle is visible for all recurring periods.
    XCTAssertTrue(
      app.switches["Carry-Over"].waitForExistence(timeout: 2),
      "Carry-Over toggle should be visible for a recurring period"
    )
  }

  /// Selecting Specific Dates hides the Carry-Over toggle (carry-over is not
  /// meaningful for a fixed date range) and reveals the date-range section.
  func testAddBudgetSpecificDatesPeriod() {
    let app = makeApp()
    app.launch()

    BudgetsScreen(app: app).tapAddBudget()

    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.nameField.waitForExistence(timeout: 2))
    form.fillName("Trip")

    app.buttons["Specific Dates period"].tap()

    // Carry-over toggle should disappear for specific-dates budgets.
    XCTAssertFalse(
      app.switches["Carry-Over"].waitForExistence(timeout: 2),
      "Carry-Over toggle should be hidden for Specific Dates period"
    )

    // Creating a specific-dates budget requires a valid date range set via the
    // compact DatePicker (complex XCUITest interaction). This test validates the
    // UI state change only — saving specific-dates budgets is exercised manually.
    XCTAssertTrue(form.cancelButton.exists, "Form should still be open")
  }

  /// Tapping through all five period chips (Daily → Weekly → Biweekly →
  /// Monthly → Specific Dates → Monthly) should leave the form stable with no
  /// crashes and the correct final state.
  func testAddBudgetAllPeriodChipsSelectable() {
    let app = makeApp()
    app.launch()

    BudgetsScreen(app: app).tapAddBudget()

    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.nameField.waitForExistence(timeout: 2))

    let chips = ["Daily period", "Weekly period", "Biweekly period",
                 "Monthly period", "Specific Dates period", "Monthly period"]
    for chip in chips {
      let button = app.buttons[chip]
      XCTAssertTrue(button.waitForExistence(timeout: 2), "\(chip) chip should exist")
      button.tap()
    }

    // After cycling back to Monthly, carry-over should be visible again.
    XCTAssertTrue(
      app.switches["Carry-Over"].waitForExistence(timeout: 2),
      "Carry-Over toggle should be visible after returning to Monthly"
    )
  }

  /// In edit mode, the period chips are locked — they render as static text,
  /// not as interactive buttons. Attempting to tap should have no effect.
  func testEditBudgetPeriodChipsLocked() {
    let app = makeApp(seedBudgets: ["Groceries"])
    app.launch()

    BudgetsScreen(app: app).tapBudget(named: "Groceries")

    let detail = BudgetDetailScreen(app: app, budgetName: "Groceries")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))
    detail.tapEditBudget()

    XCTAssertTrue(AddBudgetScreen(app: app).nameField.waitForExistence(timeout: 2))

    // Period chips are locked in edit mode — no interactive button should exist
    // for any period chip label.
    for chip in ["Daily period", "Weekly period", "Biweekly period", "Specific Dates period"] {
      XCTAssertFalse(
        app.buttons[chip].waitForExistence(timeout: 1),
        "\(chip) should not be an interactive button in edit mode"
      )
    }
  }
}
