import XCTest

/// Screen object for SettingsView.
@MainActor
struct SettingsScreen {
  let app: XCUIApplication

  var navigationBar: XCUIElement {
    app.navigationBars["Settings"]
  }

  var doneButton: XCUIElement {
    app.buttons["Done"]
  }

  var carryOverToggle: XCUIElement {
    app.switches["Carry-Over"]
  }

  func tapDone() {
    doneButton.tap()
  }
}
