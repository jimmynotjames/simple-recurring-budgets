import XCTest

/// End-to-end user journey tests covering the core flows of the app.
///
/// Note: Apple explicitly does not support Swift Testing (`import Testing`) in XCUITest
/// targets — only in hosted unit test bundles. These tests use XCTestCase instead.
///
/// Each test launches a fresh app process (IS_TESTING=1 suppresses Mixpanel) and
/// runs a single independent flow. `continueAfterFailure = false` means any failed
/// assertion stops the test immediately, matching `#require` semantics.
@MainActor
final class UserJourneyTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Budget creation

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
      "Budget row should appear in the list after saving"
    )
  }

  // MARK: - Navigation

  func testNavigateToBudgetDetail() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Groceries", in: app)

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
    let app = makeApp()
    app.launch()
    createBudget(named: "Groceries", in: app)

    let budgets = BudgetsScreen(app: app)
    let addButton = budgets.addExpenseButton(for: "Groceries")
    XCTAssertTrue(addButton.waitForExistence(timeout: 2))
    addButton.tap()

    addExpense(description: "Coffee", amount: "5", in: app)

    // After saving the sheet we're back on the list; navigate to detail to verify.
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
    let app = makeApp()
    app.launch()
    createBudget(named: "Transport", in: app)

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
    let app = makeApp()
    app.launch()
    createBudget(named: "Groceries", in: app)

    let budgets = BudgetsScreen(app: app)
    budgets.tapBudget(named: "Groceries")

    let detail = BudgetDetailScreen(app: app, budgetName: "Groceries")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))
    detail.tapEditBudget()

    let editForm = AddBudgetScreen(app: app)
    XCTAssertTrue(editForm.nameField.waitForExistence(timeout: 2))
    editForm.nameField.tap()
    editForm.nameField.doubleTap()
    editForm.nameField.typeText("Groceries Updated")
    editForm.tapSave()

    XCTAssertTrue(
      app.navigationBars["Groceries Updated"].waitForExistence(timeout: 3),
      "Detail nav title should reflect the updated budget name"
    )
  }

  // MARK: - Pause and resume

  func testPauseAndResumeBudget() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Entertainment", in: app)

    let budgets = BudgetsScreen(app: app)
    budgets.tapBudget(named: "Entertainment")

    let detail = BudgetDetailScreen(app: app, budgetName: "Entertainment")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))

    detail.tapPauseBudget()
    XCTAssertTrue(
      detail.resumeButton.waitForExistence(timeout: 3),
      "Resume button should appear after pausing"
    )

    // Resume via the primary button to test both code paths.
    detail.resumeButton.tap()
    XCTAssertTrue(
      detail.addExpenseButton.waitForExistence(timeout: 3),
      "Add expense button should reappear after resuming"
    )
  }

  // MARK: - Expense management

  func testDeleteExpense() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Dining", in: app)

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
    let app = makeApp()
    app.launch()
    createBudget(named: "Dining", in: app)

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
    editForm.descriptionField.doubleTap()
    editForm.descriptionField.typeText("Ramen")
    editForm.tapSave()

    XCTAssertTrue(
      detail.expenseRow(containing: "Ramen").waitForExistence(timeout: 3),
      "Updated description should appear in detail after saving"
    )
  }

  // MARK: - Budget deletion

  func testDeleteBudget() {
    let app = makeApp()
    app.launch()
    createBudget(named: "Temporary", in: app)

    let budgets = BudgetsScreen(app: app)
    budgets.tapBudget(named: "Temporary")

    let detail = BudgetDetailScreen(app: app, budgetName: "Temporary")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))
    detail.tapEditBudget()

    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.deleteBudgetButton.waitForExistence(timeout: 2))
    form.tapDeleteAndConfirm()

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
      settings.navigationBar.waitForExistence(timeout: 2),
      "Settings sheet should appear"
    )
    settings.tapDone()

    XCTAssertTrue(
      budgets.addBudgetButton.waitForExistence(timeout: 2),
      "Should be back on the budgets list after dismissing Settings"
    )
  }
}
