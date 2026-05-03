import XCTest

final class simple_recurring_budgetsUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {}

  @MainActor
  func testExample() {
    makeApp().launch()
  }

  @MainActor
  func testLaunchPerformance() {
    measure(metrics: [XCTApplicationLaunchMetric()]) {
      makeApp().launch()
    }
  }
}

// MARK: - Helpers

/// Returns an `XCUIApplication` pre-configured to suppress Mixpanel analytics.
///
/// `IS_TESTING = "1"` is read by `simple_recurring_budgetsApp.isRunningTests`.
/// It must be set before every `launch()` call because the app under test is
/// a fresh process that does not inherit the test runner's environment.
@MainActor
private func makeApp() -> XCUIApplication {
  let app = XCUIApplication()
  app.launchEnvironment["IS_TESTING"] = "1"
  return app
}
