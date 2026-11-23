import XCTest

/// Ad-hoc localized-layout screenshot capture; not part of `make test`.
///
/// Drives the app in 13 locales at forced `.xxxLarge` and attaches a `.keepAlways` screenshot of
/// each key screen named `<lang>__<screen>`. It makes no layout assertions; a human/Claude inspects
/// the screenshots (see `scripts/translation-accessibility-size-check/`). Runs only when the
/// runner `-only-testing`s it.
///
/// Navigation is locale-invariant (accessibility identifiers + `cells.firstMatch`). Size is forced
/// via the `FORCE_DYNAMIC_TYPE` env hook because the `-UIPreferredContentSizeCategoryName` launch
/// arg was flaky on iOS 26.x. One test method per language so xcodebuild fans them across
/// simulator clones.
///
/// Depends on (update here if these change):
/// - `makeApp(seedBudgets:)` and the `SEED_BUDGETS` env contract (comma-delimited names, one
///   monthly $100 budget each); hence `longName` must not contain a comma.
/// - `InMemoryModelContainer.makeForUITests()` (DEBUG, gated by `IS_TESTING`), which parses it.
/// - Four production `.accessibilityIdentifier` handles, for which this is currently the only
///   consumer: `toolbar.settings.label`, `toolbar.addBudget.accessibilityLabel`,
///   `budget.row.addExpense.accessibilityLabel`, `budgetDetail.menu.accessibilityLabel`.
///   Renaming them silently breaks navigation here.
/// - `TestDynamicTypeOverride` (the `FORCE_DYNAMIC_TYPE` hook) at the app root.
/// - `scripts/translation-accessibility-size-check/run.sh`, which relies on the
///   `<lang>__<screen>` attachment names.
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

  @MainActor func testCaptureJapanese() {
    captureAll("ja")
  }

  @MainActor func testCaptureChineseSimplified() {
    captureAll("zh-Hans")
  }

  @MainActor func testCaptureHindi() {
    captureAll("hi")
  }

  /// ur is RTL/Nastaliq; ta and bn are new Indic scripts.
  @MainActor func testCaptureUrdu() {
    captureAll("ur")
  }

  @MainActor func testCaptureTamil() {
    captureAll("ta")
  }

  @MainActor func testCaptureBengali() {
    captureAll("bn")
  }

  // MARK: - Per-language sweep (7 screens; 8 shots: Add Budget captures top + scrolled)

  /// No comma: SEED_BUDGETS is comma-delimited, so a comma would split this into two budgets.
  private let longName = "Weekday Coffee & Breakfast Pastry Treats"

  @MainActor private func captureAll(_ lang: String) {
    capture("01-list-empty", lang, seed: []) { _ in true }
    capture("02-list-several", lang, seed: ["Groceries", longName, "Transport"]) { _ in true }
    captureAddBudget(lang)
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

  // MARK: - Add Budget (special-cased: keyboard + tall form)

  /// The auto-focused name field raises a keyboard that hides the period selector (notably the long
  /// Finnish "Kahden viikon välein" chip) and the cards below it. At xxxLarge the form is taller
  /// than one screen, so this dismisses the keyboard and captures two shots: top, then scrolled.
  @MainActor private func captureAddBudget(_ lang: String) {
    let app = launch(lang, seed: [])
    guard tap(app, "toolbar.addBudget.accessibilityLabel"),
          app.textFields.firstMatch.waitForExistence(timeout: 8)
    else {
      XCTFail("\(lang) 03-add-budget: could not open the sheet")
      app.terminate()
      return
    }
    dismissKeyboard(app)
    attach(app, "\(lang)__03-add-budget") // name + allocation + start of period selector
    app.swipeUp() // scroll down to reveal the rest of the form
    attach(app, "\(lang)__03b-add-budget-lower") // full period grid + schedule + carry-over
    app.terminate()
  }

  // MARK: - Helpers

  /// Taps a button by accessibility identifier (locale-invariant); `false` if not found.
  @MainActor private func tap(_ app: XCUIApplication, _ identifier: String) -> Bool {
    let element = app.buttons[identifier].firstMatch
    guard element.waitForExistence(timeout: 8) else { return false }
    element.tap()
    return true
  }

  /// Dismisses the auto-focused keyboard by tapping the selected period chip: tapping a chip ends
  /// editing, and re-selecting the selected one leaves the form unchanged.
  /// - A tap, not a downward drag: drags triggered the sheet's pull-to-dismiss and closed the sheet.
  /// - The chips have no `.accessibilityIdentifier`, so this taps the first chip's screen location
  ///   (period card, row 1, left column), which sits above the keyboard. The coordinate is stable
  ///   because the cards above it are fixed-height. If it misses, the keyboard stays in the shot.
  @MainActor private func dismissKeyboard(_ app: XCUIApplication) {
    guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else { return }
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.55)).tap()
    _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 2) // let it animate out
  }

  /// Launches in `lang` at forced xxxLarge with the given seed.
  @MainActor private func launch(_ lang: String, seed: [String]) -> XCUIApplication {
    let app = seed.isEmpty ? makeApp() : makeApp(seedBudgets: seed)
    app.launchEnvironment["FORCE_DYNAMIC_TYPE"] = "xxxLarge"
    app.launchArguments += ["-AppleLanguages", "(\(lang))", "-AppleLocale", localeID(lang)]
    app.launch()
    return app
  }

  /// Attaches a `.keepAlways` screenshot named `<lang>__<screen>` (run.sh renames by this).
  @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Launches, navigates, and attaches a screenshot; fails if `navigate` returns `false`.
  @MainActor private func capture(
    _ screen: String,
    _ lang: String,
    seed: [String],
    navigate: (XCUIApplication) -> Bool
  ) {
    let app = launch(lang, seed: seed)
    guard navigate(app) else {
      XCTFail("\(lang) \(screen): could not reach the screen")
      app.terminate()
      return
    }
    attach(app, "\(lang)__\(screen)")
    app.terminate()
  }

  private func localeID(_ lang: String) -> String {
    ["de": "de_DE", "fi": "fi_FI", "ru": "ru_RU", "th": "th_TH",
     "vi": "vi_VN", "ar": "ar_SA", "he": "he_IL",
     "ja": "ja_JP", "zh-Hans": "zh_CN", "hi": "hi_IN",
     // Region matches the App Store storefront.
     "bn": "bn_BD", "gu": "gu_IN", "kn": "kn_IN", "ml": "ml_IN", "mr": "mr_IN",
     "or": "or_IN", "pa": "pa_IN", "sl": "sl_SI", "ta": "ta_IN", "te": "te_IN",
     "ur": "ur_PK"][lang] ?? "\(lang)_\(lang.uppercased())"
  }
}
