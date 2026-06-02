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
