import XCTest

/// **Ad-hoc** localized-layout screenshot capture — NOT part of `make test`.
///
/// Drives the app in 7 locales at forced `.xxxLarge` and saves a screenshot of each key screen as a
/// `.keepAlways` attachment named `<lang>__<screen>`. It makes **no layout assertions** — it never
/// "fails" on truncation; a human/Claude inspects the screenshots (see
/// `scripts/translation-accessibility-size-check/`). Runs only when the runner `-only-testing`s it.
///
/// Navigation is locale-invariant (accessibility identifiers + `cells.firstMatch`); size is forced via
/// the `FORCE_DYNAMIC_TYPE` env hook (the `-UIPreferredContentSizeCategoryName` launch arg was flaky on
/// iOS 26.x). One test method per language so xcodebuild fans them across many simulator clones.
final class LocalizationScreenshotCapture: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = true
  }

  @MainActor func testCaptureGerman() {
    captureAll("de")
  }

  @MainActor func testCaptureFinnish() {
    captureAll("fi")
  }

  @MainActor func testCaptureRussian() {
    captureAll("ru")
  }

  @MainActor func testCaptureThai() {
    captureAll("th")
  }

  @MainActor func testCaptureVietnamese() {
    captureAll("vi")
  }

  @MainActor func testCaptureArabic() {
    captureAll("ar")
  }

  @MainActor func testCaptureHebrew() {
    captureAll("he")
  }

  // MARK: - Per-language sweep (7 screens/states)

  /// No comma: SEED_BUDGETS is comma-delimited, so a comma here would split this into two budgets.
  private let longName = "Weekday Coffee & Breakfast Pastry Treats"

  @MainActor private func captureAll(_ lang: String) {
    capture("01-list-empty", lang, seed: []) { _ in true }
    capture("02-list-several", lang, seed: ["Groceries", longName, "Transport"]) { _ in true }
    capture("03-add-budget", lang, seed: []) { app in
      guard self.tap(app, "toolbar.addBudget.accessibilityLabel") else { return false }
      return app.textFields.firstMatch.waitForExistence(timeout: 8)
    }
    capture("04-settings", lang, seed: []) { app in
      guard self.tap(app, "toolbar.settings.label") else { return false }
      return app.navigationBars.firstMatch.waitForExistence(timeout: 8)
    }
    capture("05-detail", lang, seed: ["Groceries"]) { app in
      app.cells.firstMatch.tap()
      return app.buttons["budgetDetail.menu.accessibilityLabel"].waitForExistence(timeout: 8)
    }
    capture("06-detail-menu", lang, seed: ["Groceries"]) { app in
      app.cells.firstMatch.tap()
      guard self.tap(app, "budgetDetail.menu.accessibilityLabel") else { return false }
      _ = app.staticTexts.firstMatch.waitForExistence(timeout: 1) // let the menu animate in
      return true
    }
    capture("07-add-expense", lang, seed: ["Groceries"]) { app in
      guard self.tap(app, "budget.row.addExpense.accessibilityLabel") else { return false }
      return app.textFields.firstMatch.waitForExistence(timeout: 8)
    }
  }

  // MARK: - Helpers

  /// Tap a control by its accessibility identifier (locale-invariant). Returns false if not found.
  @MainActor private func tap(_ app: XCUIApplication, _ identifier: String) -> Bool {
    let element = app.buttons[identifier].firstMatch
    guard element.waitForExistence(timeout: 8) else { return false }
    element.tap()
    return true
  }

  /// Launch in `lang` at forced xxxLarge with the given seed, navigate, and attach a screenshot.
  @MainActor private func capture(
    _ screen: String,
    _ lang: String,
    seed: [String],
    navigate: (XCUIApplication) -> Bool
  ) {
    let app = seed.isEmpty ? makeApp() : makeApp(seedBudgets: seed)
    app.launchEnvironment["FORCE_DYNAMIC_TYPE"] = "xxxLarge"
    app.launchArguments += ["-AppleLanguages", "(\(lang))", "-AppleLocale", localeID(lang)]
    app.launch()
    guard navigate(app) else {
      XCTFail("\(lang) \(screen): could not reach the screen")
      app.terminate()
      return
    }
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "\(lang)__\(screen)"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.terminate()
  }

  private func localeID(_ lang: String) -> String {
    ["de": "de_DE", "fi": "fi_FI", "ru": "ru_RU", "th": "th_TH",
     "vi": "vi_VN", "ar": "ar_SA", "he": "he_IL"][lang] ?? "\(lang)_\(lang.uppercased())"
  }
}
