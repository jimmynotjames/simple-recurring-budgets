import XCTest

/// Screen object for AddEditExpenseView (both add and edit modes).
@MainActor
struct AddExpenseScreen {
  let app: XCUIApplication

  var amountField: XCUIElement {
    app.textFields.matching(NSPredicate(format: "label BEGINSWITH 'Expense amount'")).firstMatch
  }

  var descriptionField: XCUIElement {
    app.textFields["Expense description"]
  }

  var saveButton: XCUIElement {
    app.buttons["Save"]
  }

  var cancelButton: XCUIElement {
    app.buttons["Cancel"]
  }

  var deleteExpenseButton: XCUIElement {
    app.buttons["Delete Expense"]
  }

  func fillAmount(_ amount: String) {
    // iOS-COMPAT(17+): UIViewRepresentable UITextField focus workaround.
    // Double-tap ensures first-responder state registers before typeText().
    amountField.tap()
    amountField.tap()
    amountField.typeText(amount)
  }

  func fillDescription(_ text: String) {
    descriptionField.tap()
    descriptionField.typeText(text)
  }

  func tapSave() {
    saveButton.tap()
  }

  func tapCancel() {
    cancelButton.tap()
  }

  /// Taps "Delete Expense", then confirms the destructive alert.
  func tapDeleteAndConfirm() {
    deleteExpenseButton.tap()
    app.buttons["Delete Expense"].tap() // confirmation dialog button
  }
}
