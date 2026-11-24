import XCTest

/// Warms a freshly booted simulator before a CI `ui-tests` shard runs.
///
/// Not part of any shard (scripts/ci/ui_shards.py skips it). ci.yml runs it on its own first, so
/// the first real tests don't pay for the cold start: launching the app and the test runner,
/// starting the accessibility audit engine, and the first render of a sheet with a DatePicker.
/// Locally, `make unit-tests` plays this role before `make ui-tests`.
///
/// It asserts nothing about the app. Every audit finding is suppressed; only a crash or a hang
/// fails it, and ci.yml doesn't let that fail the job.
final class SimulatorWarmUpTests: XCTestCase {
  @MainActor
  func testWarmUp() throws {
    let app = makeApp(seedBudgets: ["Groceries"])
    app.launch()
    let addExpenseButton = app.buttons["Add expense for Groceries"]
    XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 30))
    addExpenseButton.tap()
    XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 30))
    try app.performAccessibilityAudit { _ in true }
  }
}
