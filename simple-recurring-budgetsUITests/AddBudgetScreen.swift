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

  /// The biweekly explanatory caption under the Period chips. Matched on a stable
  /// prefix so wording polish doesn't break the query.
  var biweeklyNote: XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Repeating 14-day period'")).firstMatch
  }

  /// The Edit-mode period-lock caption. Matched on a prefix that avoids the
  /// apostrophe in "can't".
  var periodLockCaption: XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Period type can'")).firstMatch
  }

  /// The weekly explanatory caption under the Period chips. Matched on a stable
  /// prefix so the interpolated weekday name and wording polish don't break it.
  var weeklyNote: XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'All weekly budgets start on'")).firstMatch
  }

  /// The "Change start of week" link below the weekly note (pushes the Start of
  /// Week screen). Matched by accessibility identifier to survive copy changes.
  var changeStartOfWeekLink: XCUIElement {
    app.buttons["addEditBudget.changeStartOfWeek"]
  }

  func tapChangeStartOfWeek() {
    changeStartOfWeekLink.tap()
  }

  /// The expanded Schedule disclosure's start-date chip. Only present when the
  /// disclosure is expanded (a collapsed disclosure does not render it), so its
  /// existence doubles as proof of auto-expand.
  var startDateChip: XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start date'")).firstMatch
  }

  /// The Save-time biweekly re-anchor confirmation alert.
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

  /// Replaces any existing name with `name`. Use when editing a budget whose
  /// name field is already populated.
  func replaceName(_ name: String) {
    nameField.tap()
    if let current = nameField.value as? String, !current.isEmpty {
      nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    }
    nameField.typeText(name)
  }

  func fillAllocation(_ amount: String) {
    // iOS-COMPAT(17+): UIViewRepresentable UITextField focus workaround.
    // Tap the GroupBox label to dismiss alpha keyboard, then double-tap the field.
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

  /// Taps "Delete Budget" in the form, then confirms via the action sheet.
  /// Uses app.sheets to scope the confirmation tap and avoid ambiguity with
  /// the form's own "Delete Budget" button (which stays in the hierarchy
  /// when the confirmation sheet presents on top).
  func tapDeleteAndConfirm() {
    deleteBudgetButton.tap()
    let sheet = app.sheets.firstMatch
    XCTAssertTrue(sheet.waitForExistence(timeout: 2))
    sheet.buttons["Delete Budget"].tap()
  }
}
