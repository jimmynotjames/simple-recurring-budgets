import XCTest

/// Screen object for AddEditBudgetView (both add and edit modes).
@MainActor
struct AddBudgetScreen {
  let app: XCUIApplication

  var nameField: XCUIElement {
    app.textFields["Budget name"]
  }

  var allocationField: XCUIElement {
    app.textFields.matching(NSPredicate(format: "label BEGINSWITH 'Allocation amount'")).firstMatch
  }

  var saveButton: XCUIElement {
    app.buttons["Save"]
  }

  var cancelButton: XCUIElement {
    app.buttons["Cancel"]
  }

  var deleteBudgetButton: XCUIElement {
    app.buttons["Delete Budget"]
  }

  /// Biweekly caption under the Period chips; prefix match survives wording changes.
  var biweeklyNote: XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Repeating 14-day period'")).firstMatch
  }

  /// Edit-mode period-lock caption; prefix stops before the apostrophe in "can't".
  var periodLockCaption: XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Period type can'")).firstMatch
  }

  /// Weekly caption under the Period chips; prefix match skips the interpolated weekday.
  var weeklyNote: XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'All weekly budgets start on'")).firstMatch
  }

  /// "Change start of week" link below the weekly note; matched by identifier to survive copy changes.
  var changeStartOfWeekLink: XCUIElement {
    app.buttons["addEditBudget.changeStartOfWeek"]
  }

  func tapChangeStartOfWeek() {
    changeStartOfWeekLink.tap()
  }

  /// Start-date chip, rendered only when the Schedule disclosure is expanded, so its existence
  /// proves auto-expand.
  var startDateChip: XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start date'")).firstMatch
  }

  /// Save-time biweekly re-anchor confirmation alert.
  var reanchorAlert: XCUIElement {
    app.alerts["Change Start Date?"]
  }

  func selectPeriod(_ label: String) {
    app.buttons["\(label) period"].tap()
  }

  func fillName(_ name: String) {
    nameField.tap()
    nameField.typeText(name)
  }

  /// Replaces any existing name with `name`.
  func replaceName(_ name: String) {
    nameField.tap()
    if let current = nameField.value as? String, !current.isEmpty {
      nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    }
    nameField.typeText(name)
  }

  func fillAllocation(_ amount: String) {
    // iOS-COMPAT(17+): UIViewRepresentable UITextField focus workaround. Tap the GroupBox
    // label to dismiss the alpha keyboard, then double-tap the field. See `createBudget`.
    app.staticTexts["Allocation"].tap()
    allocationField.tap()
    allocationField.tap()
    allocationField.typeText(amount)
  }

  func tapSave() {
    saveButton.tap()
  }

  func tapCancel() {
    cancelButton.tap()
  }

  /// Taps "Delete Budget", then confirms in the action sheet. The tap is scoped to `app.sheets`
  /// because the form's own "Delete Budget" button stays in the hierarchy behind the sheet.
  func tapDeleteAndConfirm() {
    deleteBudgetButton.tap()
    let sheet = app.sheets.firstMatch
    XCTAssertTrue(sheet.waitForExistence(timeout: 2))
    sheet.buttons["Delete Budget"].tap()
  }
}
