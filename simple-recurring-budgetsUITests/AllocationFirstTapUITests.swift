import XCTest

/// Regression guard: typing into the Allocation field must register on the first tap, with no
/// GroupBox-label/double-tap workaround.
///
/// The Allocation card clears the Name field's `@FocusState` when the UIKit-backed
/// `DecimalInputField` begins editing (so the iPadOS `.decimalPad` popover anchors correctly).
/// Doing that synchronously inside `textFieldDidBeginEditing` re-entered SwiftUI's focus
/// machinery mid-transition and dropped the first keystrokes; the clear is deferred one
/// main-actor turn. This test fails if the synchronous clear returns.
@MainActor
final class AllocationFirstTapUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testSingleTapAllocationRegistersDigits() {
    let app = makeApp()
    app.launch()

    app.buttons["Add budget"].tap()

    let nameField = app.textFields["Budget name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 2))
    nameField.tap()
    nameField.typeText("Test 1")

    let amountField = app.textFields.matching(
      NSPredicate(format: "label BEGINSWITH 'Allocation amount'")
    ).firstMatch
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))

    // A single tap straight from the Name field, then type.
    amountField.tap()
    amountField.typeText("25")

    // Dropped keystrokes leave the value without "25" and Save disabled.
    let value = (amountField.value as? String) ?? ""
    XCTAssertTrue(
      value.contains("25"),
      "Allocation field should contain typed '25' after a single tap; got '\(value)'"
    )
    XCTAssertTrue(app.buttons["Save"].isEnabled, "Save should be enabled once allocation is entered")
  }
}
