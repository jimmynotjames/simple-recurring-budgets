import XCTest

final class simple_recurring_budgetsUITestsLaunchTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunch() {
    let app = XCUIApplication()
    // IS_TESTING suppresses Mixpanel analytics in the app under test.
    // The app is a separate process and does not inherit the test runner's
    // environment, so this must be set explicitly before every launch().
    app.launchEnvironment["IS_TESTING"] = "1"
    app.launch()

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Launch Screen"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
