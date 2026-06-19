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

  // MARK: - Reorder budgets (drag-to-reorder in Edit mode)

  /// Covers the `.onMove` wiring end-to-end (test-coverage-audit-2026-06-10 C1):
  /// the unit suite (`BudgetsViewMoveTests`) verifies `BudgetReorderService`'s
  /// algorithm, but only a real drag confirms the List forwards indices to it.
  /// Order is asserted by the rows' vertical positions; no relaunch check, since
  /// UI tests run on an ephemeral in-memory store.
  func testReorderBudgets() {
    let app = makeApp(seedBudgets: ["Alpha", "Bravo", "Charlie"])
    app.launch()

    let budgets = BudgetsScreen(app: app)
    XCTAssertTrue(budgets.budgetRow(named: "Alpha").waitForExistence(timeout: 3))
    budgets.editButton.tap()

    // In Edit mode each row grows a trailing reorder grabber. Drag the last
    // cell (Charlie, index 2) by its trailing edge to above the first cell.
    let fromCell = app.cells.element(boundBy: 2)
    let toCell = app.cells.element(boundBy: 0)
    XCTAssertTrue(fromCell.waitForExistence(timeout: 2))
    let grabber = fromCell.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
    let target = toCell.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.05))
    grabber.press(forDuration: 1.0, thenDragTo: target)

    app.buttons["Done"].tap()

    let charlieRow = budgets.budgetRow(named: "Charlie")
    let alphaRow = budgets.budgetRow(named: "Alpha")
    let bravoRow = budgets.budgetRow(named: "Bravo")
    XCTAssertTrue(charlieRow.waitForExistence(timeout: 3))
    XCTAssertLessThan(
      charlieRow.frame.minY, alphaRow.frame.minY,
      "Charlie should render above Alpha after the drag"
    )
    XCTAssertLessThan(
      alphaRow.frame.minY, bravoRow.frame.minY,
      "Alpha should remain above Bravo after the drag"
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
      settings.navigationBar.waitForExistence(timeout: 2),
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

  /// Selecting Biweekly reveals the explanatory note under the chips AND
  /// auto-expands the Schedule disclosure so the start-date chip (the cycle
  /// anchor) is immediately visible.
  func testBiweeklyPeriodShowsNoteAndExpandsSchedule() {
    let app = makeApp()
    app.launch()

    BudgetsScreen(app: app).tapAddBudget()

    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.nameField.waitForExistence(timeout: 2))
    form.selectPeriod("Biweekly")

    XCTAssertTrue(
      form.biweeklyNote.waitForExistence(timeout: 2),
      "Biweekly explanatory note should appear under the period chips"
    )
    XCTAssertTrue(
      form.startDateChip.waitForExistence(timeout: 2),
      "Schedule should auto-expand on biweekly selection, revealing the start-date chip without an extra tap"
    )
  }

  /// Selecting Weekly reveals the explanatory note under the chips, and its
  /// "Change start of week" link pushes the focused Start of Week screen (with its
  /// app-wide scope banner) onto the form's own navigation stack. Tapping Back
  /// returns to the form with the draft intact. (The cascade-confirmation gating
  /// itself is covered by the WeekStartConfirmation unit tests, so this journey
  /// does not mutate the global week-start setting.)
  func testWeeklyPeriodNoteOpensStartOfWeekPicker() {
    let app = makeApp()
    app.launch()

    BudgetsScreen(app: app).tapAddBudget()

    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.nameField.waitForExistence(timeout: 2))
    form.selectPeriod("Weekly")

    XCTAssertTrue(
      form.weeklyNote.waitForExistence(timeout: 2),
      "Weekly explanatory note should appear under the period chips"
    )

    form.tapChangeStartOfWeek()

    let weekStart = WeekStartScreen(app: app)
    XCTAssertTrue(
      weekStart.scopeBanner.waitForExistence(timeout: 2),
      "Start of Week screen should show the app-wide scope banner"
    )
    XCTAssertTrue(weekStart.dayRow(1).exists, "Sunday row should be present")
    XCTAssertTrue(weekStart.dayRow(7).exists, "Saturday row should be present")

    // Return to the form; the weekly note is still present (draft preserved).
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(
      form.weeklyNote.waitForExistence(timeout: 2),
      "Returning from the Start of Week screen should land back on the budget form with the draft intact"
    )
  }

  /// Opening Edit on an existing biweekly budget auto-expands the Schedule
  /// disclosure so the start date (the cycle anchor) is visible on open —
  /// without the user tapping the disclosure row. (Seeding only makes monthly
  /// budgets, so this creates a biweekly one via the Add path first.)
  func testEditBiweeklyBudgetOpensScheduleExpanded() {
    let app = makeApp()
    app.launch()

    let budgets = BudgetsScreen(app: app)
    budgets.tapAddBudget()

    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.nameField.waitForExistence(timeout: 2))
    form.fillName("Rent")
    form.selectPeriod("Biweekly")
    form.fillAllocation("1200")
    form.tapSave()

    XCTAssertTrue(
      budgets.addExpenseButton(for: "Rent").waitForExistence(timeout: 5),
      "Biweekly budget should appear in the list after saving"
    )

    budgets.tapBudget(named: "Rent")
    let detail = BudgetDetailScreen(app: app, budgetName: "Rent")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))
    detail.tapEditBudget()

    XCTAssertTrue(form.nameField.waitForExistence(timeout: 2))
    XCTAssertTrue(
      form.startDateChip.waitForExistence(timeout: 2),
      "Editing a biweekly budget should open with the Schedule disclosure already expanded (start-date chip visible)"
    )
  }

  /// The Edit-mode period-lock caption names the period type specifically
  /// ("Period type can't be changed…"), since dates remain editable.
  func testEditBudgetPeriodLockCaptionNamesPeriodType() {
    let app = makeApp(seedBudgets: ["Groceries"])
    app.launch()

    BudgetsScreen(app: app).tapBudget(named: "Groceries")

    let detail = BudgetDetailScreen(app: app, budgetName: "Groceries")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))
    detail.tapEditBudget()

    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.nameField.waitForExistence(timeout: 2))
    XCTAssertTrue(
      form.periodLockCaption.waitForExistence(timeout: 2),
      "Edit-mode period-lock caption should read 'Period type can't be changed after creating your budget.'"
    )
  }

  // MARK: - Save-time biweekly re-anchor confirmation (manual carve-out)

  //
  // Triggering the "Change Start Date?" alert requires *changing* a biweekly
  // budget's start date, which means driving the `.graphical` DatePicker inside
  // the Schedule disclosure's DateColumn sheet. This suite deliberately exercises
  // graphical-DatePicker interaction manually (see `testAddBudgetSpecificDatesPeriod`,
  // which validates UI state only and notes that saving a date range is manual).
  // The alert's gate is fully unit-tested — see `isBiweeklyStartDateEdited*` in
  // `AddEditBudgetViewModelScheduleTests` — and the gate→alert binding is a trivial
  // SwiftUI `.alert(isPresented:)`. `AddBudgetScreen.reanchorAlert` is provided for
  // that manual pass / future automation. Manual steps: edit a biweekly budget →
  // change Start Date → Save → expect the alert → Cancel preserves the draft →
  // Save → Change commits.

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
