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

  /// Taps "Delete Budget", then confirms the destructive alert.
  func tapDeleteAndConfirm() {
    deleteBudgetButton.tap()
    app.buttons["Delete Budget"].tap() // confirmation dialog button
  }
}
