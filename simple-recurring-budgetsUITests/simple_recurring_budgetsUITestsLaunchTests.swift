import XCTest

final class simple_recurring_budgetsUITestsLaunchTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunch() {
    let app = makeApp() // shared factory from UITestHelpers.swift
    app.launch()

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Launch Screen"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
