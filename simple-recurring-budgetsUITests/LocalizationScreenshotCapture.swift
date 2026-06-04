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
///
/// **Depends on existing code (don't break these without updating this capture):**
/// - `UITestHelpers.makeApp()` / `makeApp(seedBudgets:)` and the `SEED_BUDGETS` launch-env contract
///   (comma-delimited names → one monthly $100 budget each). The comma delimiter is why `longName`
///   below must not contain a comma.
/// - `InMemoryModelContainer.makeForUITests()` (DEBUG, gated by `IS_TESTING`) — parses `SEED_BUDGETS`.
/// - Four `.accessibilityIdentifier(...)` handles in the production views, which this is currently the
///   *only* consumer of: `toolbar.settings.label`, `toolbar.addBudget.accessibilityLabel`,
///   `budget.row.addExpense.accessibilityLabel` (BudgetsView), `budgetDetail.menu.accessibilityLabel`
///   (BudgetDetailView). Removing/renaming them silently breaks navigation here.
/// - `TestDynamicTypeOverride` (the `FORCE_DYNAMIC_TYPE` hook) applied at the app root.
/// - The runner `scripts/translation-accessibility-size-check/run.sh` (`-only-testing`s this class;
///   relies on the `<lang>__<screen>` attachment names and `scripts/_destination.sh` / `build.sh`).
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

  // MARK: - Per-language sweep (7 screens; 8 shots — Add Budget captures top + scrolled)

  /// No comma: SEED_BUDGETS is comma-delimited, so a comma here would split this into two budgets.
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

  /// The Add Budget sheet auto-focuses the name field, raising the keyboard over the lower form —
  /// which hides the period selector (notably the long Finnish "Kahden viikon välein" chip) and the
  /// schedule / carry-over cards below it. At xxxLarge the whole form is taller than one screen, so
  /// this captures **two** shots — top, then scrolled — after dismissing the keyboard.
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

  /// Tap a control by its accessibility identifier (locale-invariant). Returns false if not found.
  @MainActor private func tap(_ app: XCUIApplication, _ identifier: String) -> Bool {
    let element = app.buttons[identifier].firstMatch
    guard element.waitForExistence(timeout: 8) else { return false }
    element.tap()
    return true
  }

  /// Dismiss the auto-focused name-field keyboard by **tapping the selected period chip**. Tapping a
  /// period chip ends editing (dismisses the keyboard) and re-selecting the already-selected one leaves
  /// the form state unchanged. Two things make this the right move here:
  /// - A **tap** (not a downward drag) can't trigger the sheet's pull-to-dismiss, which closed the whole
  ///   sheet when we tried `.scrollDismissesKeyboard`-style drags.
  /// - The chips have **no** `.accessibilityIdentifier` (we're not changing production), so we tap the
  ///   first chip's on-screen location — period card, row 1, left column — which sits above the keyboard.
  /// The coordinate is stable: the period card is the 3rd card and the name/allocation cards above it are
  /// fixed-height (label + field). If it ever misses, the keyboard simply stays and the shot shows it.
  @MainActor private func dismissKeyboard(_ app: XCUIApplication) {
    guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else { return }
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.55)).tap()
    _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 2) // let it animate out
  }

  /// Launch in `lang` at forced xxxLarge with the given seed.
  @MainActor private func launch(_ lang: String, seed: [String]) -> XCUIApplication {
    let app = seed.isEmpty ? makeApp() : makeApp(seedBudgets: seed)
    app.launchEnvironment["FORCE_DYNAMIC_TYPE"] = "xxxLarge"
    app.launchArguments += ["-AppleLanguages", "(\(lang))", "-AppleLocale", localeID(lang)]
    app.launch()
    return app
  }

  /// Attach a `.keepAlways` screenshot named `<lang>__<screen>` (run.sh renames by this).
  @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Launch in `lang` at forced xxxLarge with the given seed, navigate, and attach a screenshot.
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
     "vi": "vi_VN", "ar": "ar_SA", "he": "he_IL"][lang] ?? "\(lang)_\(lang.uppercased())"
  }
}
