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

// makeApp() is provided by UITestHelpers.swift (shared across all UI test files).
