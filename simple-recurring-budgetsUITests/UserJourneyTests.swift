import XCTest

/// End-to-end user journeys for the core app flows.
///
/// Tests needing an existing budget seed it with `makeApp(seedBudgets:)` so each exercises only
/// its own feature. Tests that create budgets through the UI cover the Add Budget form itself.
///
/// XCUITest targets don't support Swift Testing (`import Testing`); these use XCTestCase with
/// `continueAfterFailure = false`, matching `#require` stop-on-first-failure.
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

    // Verify via the budgets list; the detail nav bar title is unreliable in XCUITest because of
    // SwiftUI animation timing after sheet dismissal.
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

  /// Covers the `.onMove` wiring end-to-end: `BudgetsViewMoveTests` covers `BudgetReorderService`,
  /// but only a real drag confirms the List forwards indices to it. Order is asserted by rows'
  /// vertical positions; there is no relaunch check because the UI-test store is in-memory.
  func testReorderBudgets() {
    let app = makeApp(seedBudgets: ["Alpha", "Bravo", "Charlie"])
    app.launch()

    let budgets = BudgetsScreen(app: app)
    let alphaRow = budgets.budgetRow(named: "Alpha")
    let bravoRow = budgets.budgetRow(named: "Bravo")
    let charlieRow = budgets.budgetRow(named: "Charlie")
    XCTAssertTrue(charlieRow.waitForExistence(timeout: 3))
    // The drag below picks cells by index, so first confirm the seed order it assumes.
    XCTAssertLessThan(alphaRow.frame.minY, bravoRow.frame.minY, "Seed order should start Alpha, Bravo")
    XCTAssertLessThan(bravoRow.frame.minY, charlieRow.frame.minY, "Seed order should end Bravo, Charlie")

    // Synthesized drags occasionally don't register on CI simulators (the order stays unchanged), so allow
    // one more attempt. A drag that registers but lands wrong still fails the asserts below.
    for _ in 0 ..< 2 {
      dragLastBudgetToTop(app: app, budgets: budgets)
      XCTAssertTrue(charlieRow.waitForExistence(timeout: 3))
      if charlieRow.frame.minY < alphaRow.frame.minY {
        break
      }
    }

    XCTAssertLessThan(
      charlieRow.frame.minY, alphaRow.frame.minY,
      "Charlie should render above Alpha after the drag"
    )
    XCTAssertLessThan(
      alphaRow.frame.minY, bravoRow.frame.minY,
      "Alpha should remain above Bravo after the drag"
    )
  }

  /// Enters Edit mode, drags the last of three cells above the first by its trailing reorder grabber, then taps Done.
  private func dragLastBudgetToTop(app: XCUIApplication, budgets: BudgetsScreen) {
    budgets.editButton.tap()
    let fromCell = app.cells.element(boundBy: 2)
    let toCell = app.cells.element(boundBy: 0)
    XCTAssertTrue(fromCell.waitForExistence(timeout: 2))
    let grabber = fromCell.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
    let target = toCell.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.05))
    // Don't speed up or drop the hold: with default velocity and no post-drag hold, the GitHub CI
    // simulator made one fast jump. Too few touch samples for List's reorder recognizer to see a
    // continuous drag, and no settle time before touch-up for .onMove to commit, so the order
    // silently didn't change. Slow velocity plus a hold before release fixes both.
    grabber.press(forDuration: 1.0, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
    app.buttons["Done"].tap()
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

  /// A new budget form defaults to Monthly with the carry-over toggle visible.
  func testAddBudgetDefaultPeriodShowsCarryOver() {
    let app = makeApp()
    app.launch()

    BudgetsScreen(app: app).tapAddBudget()

    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.nameField.waitForExistence(timeout: 2))
    XCTAssertTrue(
      app.buttons["Monthly period"].waitForExistence(timeout: 2),
      "Monthly period chip should be present"
    )
    XCTAssertTrue(
      app.switches["Carry-Over"].waitForExistence(timeout: 2),
      "Carry-Over toggle should be visible for a recurring period"
    )
  }

  /// Specific Dates hides the Carry-Over toggle (meaningless for a fixed date range).
  func testAddBudgetSpecificDatesPeriod() {
    let app = makeApp()
    app.launch()

    BudgetsScreen(app: app).tapAddBudget()

    let form = AddBudgetScreen(app: app)
    XCTAssertTrue(form.nameField.waitForExistence(timeout: 2))
    form.fillName("Trip")

    app.buttons["Specific Dates period"].tap()

    XCTAssertFalse(
      app.switches["Carry-Over"].waitForExistence(timeout: 2),
      "Carry-Over toggle should be hidden for Specific Dates period"
    )

    // Saving needs a date range from the compact DatePicker (complex in XCUITest), so this
    // validates UI state only; saving specific-dates budgets is tested manually.
    XCTAssertTrue(form.cancelButton.exists, "Form should still be open")
  }

  /// Cycling through every period chip and back to Monthly leaves the form stable.
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

    XCTAssertTrue(
      app.switches["Carry-Over"].waitForExistence(timeout: 2),
      "Carry-Over toggle should be visible after returning to Monthly"
    )
  }

  /// Biweekly shows the explanatory note and auto-expands the Schedule disclosure so the
  /// start-date chip (the cycle anchor) is visible.
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

  /// Weekly shows the note; its "Change start of week" link pushes the Start of Week screen onto
  /// the form's navigation stack, and Back returns with the draft intact. Doesn't change the
  /// global week-start setting (cascade confirmation is covered by WeekStartConfirmation unit tests).
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

    // Back to the form.
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(
      form.weeklyNote.waitForExistence(timeout: 2),
      "Returning from the Start of Week screen should land back on the budget form with the draft intact"
    )
  }

  /// Editing a biweekly budget opens with the Schedule disclosure already expanded. Seeding only
  /// makes monthly budgets, so this creates a biweekly one via the Add form first.
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

  /// The Edit-mode period-lock caption names the period type ("Period type can't be changed…")
  /// because dates stay editable.
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
  // The "Change Start Date?" alert needs a changed biweekly start date, which means driving the
  // `.graphical` DatePicker in the Schedule disclosure's DateColumn sheet; that is tested manually.
  // The alert's gate is unit-tested (`isBiweeklyStartDateEdited*` in
  // `AddEditBudgetViewModelScheduleTests`) and the gate-to-alert binding is a plain `.alert`.
  // `AddBudgetScreen.reanchorAlert` exists for the manual pass or future automation. Manual steps:
  // edit a biweekly budget → change Start Date → Save → alert appears → Cancel preserves the
  // draft → Save → Change commits.

  /// In edit mode the period chips are locked: static text, not buttons.
  func testEditBudgetPeriodChipsLocked() {
    let app = makeApp(seedBudgets: ["Groceries"])
    app.launch()

    BudgetsScreen(app: app).tapBudget(named: "Groceries")

    let detail = BudgetDetailScreen(app: app, budgetName: "Groceries")
    XCTAssertTrue(detail.budgetOptionsButton.waitForExistence(timeout: 3))
    detail.tapEditBudget()

    XCTAssertTrue(AddBudgetScreen(app: app).nameField.waitForExistence(timeout: 2))

    for chip in ["Daily period", "Weekly period", "Biweekly period", "Specific Dates period"] {
      XCTAssertFalse(
        app.buttons[chip].waitForExistence(timeout: 1),
        "\(chip) should not be an interactive button in edit mode"
      )
    }
  }
}
