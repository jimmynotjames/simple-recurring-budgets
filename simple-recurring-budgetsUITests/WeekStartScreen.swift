import XCTest

/// Screen object for `WeekStartPickerScreen` — the focused, pushable Start of Week
/// picker reachable from the Add/Edit Budget weekly note's "Change start of week" link.
@MainActor
struct WeekStartScreen {
  let app: XCUIApplication

  /// The app-wide scope banner above the weekday list. Matched on a stable prefix.
  var scopeBanner: XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'App-wide setting'")).firstMatch
  }

  /// The weekday row for a `Weekday` raw value (sunday = 1 … saturday = 7).
  /// Matched by accessibility identifier so it survives localization.
  func dayRow(_ weekdayRawValue: Int) -> XCUIElement {
    app.buttons["weekStart.day.\(weekdayRawValue)"]
  }

  /// The cascade-warning confirmation alert shown before a change commits.
  var confirmAlert: XCUIElement {
    app.alerts["Change Start of Week?"]
  }

  var confirmButton: XCUIElement {
    confirmAlert.buttons["Change"]
  }

  var cancelButton: XCUIElement {
    confirmAlert.buttons["Cancel"]
  }

  /// Selects a weekday and confirms the cascade alert.
  func selectAndConfirm(_ weekdayRawValue: Int) {
    dayRow(weekdayRawValue).tap()
    XCTAssertTrue(confirmAlert.waitForExistence(timeout: 2))
    confirmButton.tap()
  }
}
