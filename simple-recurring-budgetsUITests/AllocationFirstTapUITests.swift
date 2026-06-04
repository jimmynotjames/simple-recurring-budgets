import XCTest

/// Regression guard: typing into the Allocation field must register on the **first** tap.
///
/// Mirrors the manual flow that broke: open Add Budget, type a name (which focuses the Name
/// field via `@FocusState`), then single-tap the Allocation field and type — with NO "tap the
/// GroupBox label" / double-tap workaround.
///
/// The amount field is a UIKit-backed `DecimalInputField`. The Allocation card clears the Name
/// field's `@FocusState` when the amount field begins editing (so the iPadOS `.decimalPad`
/// popover anchors correctly — issue #126). Doing that mutation *synchronously* inside the UIKit
/// `textFieldDidBeginEditing` re-entered SwiftUI's focus machinery mid-transition and dropped the
/// first keystrokes; the fix defers it one main-actor turn. This test fails if that synchronous
/// clear ever returns.
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

    // The reported flow: a SINGLE tap straight from the Name field, then type.
    amountField.tap()
    amountField.typeText("25")

    // If the first-responder session dropped the keystrokes, the field value
    // will not contain "25" and Save stays disabled.
    let value = (amountField.value as? String) ?? ""
    XCTAssertTrue(
      value.contains("25"),
      "Allocation field should contain typed '25' after a single tap; got '\(value)'"
    )
    XCTAssertTrue(app.buttons["Save"].isEnabled, "Save should be enabled once allocation is entered")
  }
}
