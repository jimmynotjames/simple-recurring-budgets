import XCTest

/// App Store marketing screenshot capture for fastlane `snapshot`: Budgets list, Add Expense,
/// Budget detail, Add/Edit Budget, Settings, across the `fastlane/Snapfile` device/locale matrix
/// at default Dynamic Type and Light mode, with per-locale demo content. Not the same as
/// `LocalizationScreenshotCapture` (forces `.xxxLarge`).
///
/// Excluded from every test pipeline: `ALWAYS_SKIPPED` in `scripts/ci/ui_shards.py` (the UI
/// selection for `make ui-tests` and CI) lists this class, and the unit pass skips the whole UI
/// target, so it never runs in `make tests` or CI. Its only runner is the Snapfile `only_testing`
/// via `fastlane screenshots`.
///
/// Depends on (update here if these change):
/// - Four production `.accessibilityIdentifier` nav handles (locale-invariant):
///   `budget.row.addExpense.accessibilityLabel`, `budgetDetail.menu.accessibilityLabel`,
///   `toolbar.addBudget.accessibilityLabel`, `toolbar.settings.label`.
/// - The DEBUG-only `SEED_SCREENSHOTS_JSON` launch-env contract (decoded by `ScreenshotSeed`) and
///   the `ScreenshotSeeds/<lang>.json` catalog from `scripts/screenshot_content/`. Each catalog
///   also has a top-level `primaryLocale` (region-qualified, e.g. `de_DE`) that sets
///   `-AppleLocale`; the production decoder ignores that key.
/// - `SnapshotHelper.swift` (`setupSnapshot`, `Snapshot.deviceLanguage`, `snapshot(_:)`).
final class AppStoreScreenshots: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor func testCaptureAppStoreScreenshots() throws {
    let app = XCUIApplication()
    setupSnapshot(app)

    // Snapshot.deviceLanguage is the code the seed catalog is keyed by; en-US outside fastlane.
    let lang = Snapshot.deviceLanguage.isEmpty ? "en-US" : Snapshot.deviceLanguage
    app.launchEnvironment["IS_TESTING"] = "1"
    // Shows the Settings iCloud row as "Active" (the Simulator has no iCloud account).
    // DEBUG-only override; see SyncStatus.swift.
    app.launchEnvironment["SCREENSHOT_SYNC_OK"] = "1"
    let seed = try XCTUnwrap(
      Self.seedJSON(for: lang),
      "No screenshot seed catalog (ScreenshotSeeds/\(lang).json) bundled for language \(lang)"
    )
    app.launchEnvironment["SEED_SCREENSHOTS_JSON"] = seed

    // fastlane sets only `-AppleLanguages`; for language-only locales (de, ja, nb, …)
    // `-AppleLocale` stays region-less, so `Locale.autoupdatingCurrent.currency` is nil and the
    // Settings currency example falls back to USD. Override with the seed's region-qualified
    // `primaryLocale` so every shot uses the market's currency and number formatting.
    if let primaryLocale = Self.primaryLocale(fromSeed: seed) {
      Self.overrideAppleLocale(app, with: primaryLocale)
    }

    // 01 — Budgets list (hero).
    app.launch()
    XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 30), "budgets list did not appear")
    snapshot("01_budgets")

    // 02 — Add Expense: inline "+" on the first (food) budget row.
    relaunch(app)
    let addExpense = app.buttons["budget.row.addExpense.accessibilityLabel"].firstMatch
    XCTAssertTrue(addExpense.waitForExistence(timeout: 20), "add-expense button not found")
    addExpense.tap()
    _ = app.textFields.firstMatch.waitForExistence(timeout: 15)
    snapshot("02_add_expense")

    // 03 — Budget detail: first budget row.
    relaunch(app)
    XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 20), "budget cell not found")
    app.cells.firstMatch.tap()
    _ = app.buttons["budgetDetail.menu.accessibilityLabel"].waitForExistence(timeout: 15)
    snapshot("03_detail")

    // 04 — Add Budget sheet with the auto-keyboard dismissed.
    relaunch(app)
    let addBudget = app.buttons["toolbar.addBudget.accessibilityLabel"].firstMatch
    XCTAssertTrue(addBudget.waitForExistence(timeout: 20), "add-budget button not found")
    addBudget.tap()
    _ = app.textFields.firstMatch.waitForExistence(timeout: 15)
    dismissAddBudgetKeyboard(app)
    snapshot("04_add_budget")

    // 05 — Settings.
    relaunch(app)
    let settings = app.buttons["toolbar.settings.label"].firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 20), "settings button not found")
    settings.tap()
    _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
    snapshot("05_settings")
  }

  // MARK: - Helpers

  /// Relaunches so each shot starts from the seeded budgets list; launch args/env on `app` persist.
  @MainActor private func relaunch(_ app: XCUIApplication) {
    app.terminate()
    app.launch()
  }

  /// Dismisses the Add Budget auto-focused keyboard by tapping the Daily chip: the chip's action
  /// resigns the keyboard in-app, and re-selecting the default period changes nothing.
  @MainActor private func dismissAddBudgetKeyboard(_ app: XCUIApplication) {
    guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else { return }
    let dailyChip = app.buttons["budgetPeriod.daily"].firstMatch
    if dailyChip.waitForExistence(timeout: 5) {
      dailyChip.tap()
    }
    _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
  }

  /// Top-level `primaryLocale` of a seed catalog JSON string, if present.
  private static func primaryLocale(fromSeed json: String) -> String? {
    guard let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let locale = object["primaryLocale"] as? String,
          !locale.isEmpty
    else { return nil }
    return locale
  }

  /// Replaces any `-AppleLocale` value `setupSnapshot` appended (or appends one) so exactly one
  /// exists, avoiding reliance on duplicate-argument precedence in the NSArgumentDomain.
  private static func overrideAppleLocale(_ app: XCUIApplication, with locale: String) {
    let existing = app.launchArguments.firstIndex(of: "-AppleLocale")
    if let existing, existing + 1 < app.launchArguments.count {
      app.launchArguments[existing + 1] = locale
    } else {
      app.launchArguments += ["-AppleLocale", locale]
    }
  }

  /// Loads the bundled seed catalog. Synchronized file groups copy resources flat, so try the
  /// subdirectory form, then the flat form.
  private static func seedJSON(for lang: String) -> String? {
    let bundle = Bundle(for: AppStoreScreenshots.self)
    let candidates = [
      bundle.url(forResource: lang, withExtension: "json", subdirectory: "ScreenshotSeeds"),
      bundle.url(forResource: lang, withExtension: "json"),
    ]
    for case let url? in candidates {
      if let contents = try? String(contentsOf: url, encoding: .utf8) {
        return contents
      }
    }
    return nil
  }
}
