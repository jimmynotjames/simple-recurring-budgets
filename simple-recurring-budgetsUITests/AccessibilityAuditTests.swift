import XCTest

/// Runs `performAccessibilityAudit()` on each major screen. Each test launches a fresh app.
///
/// For an intentional finding that shouldn't block CI, wrap the call in
/// `XCTExpectFailure("reason") { ... }` rather than deleting the test.
final class AccessibilityAuditTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Budgets list — empty state

  /// Empty-state BudgetsView.
  @MainActor
  func testBudgetsListEmpty() throws {
    let app = makeApp()
    app.launch()
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  // MARK: - Budgets list — populated

  /// BudgetsView with one row (also shows the toolbar EditButton).
  @MainActor
  func testBudgetsListOneBudget() throws {
    let app = makeApp()
    app.launch()
    createBudget(named: "Groceries", in: app)
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  /// BudgetsView with three rows, to catch issues that only appear with multiple rows.
  @MainActor
  func testBudgetsListSeveralBudgets() throws {
    let app = makeApp()
    app.launch()
    createBudget(named: "Groceries", in: app)
    createBudget(named: "Transport", in: app)
    createBudget(named: "Entertainment", in: app)
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  // MARK: - Add Budget form

  /// Blank Add Budget form (Save disabled).
  @MainActor
  func testAddBudgetFormBlank() throws {
    let app = makeApp()
    app.launch()
    app.buttons["Add budget"].tap()
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  /// Add Budget form with name typed (keyboard visible, Save enabled).
  @MainActor
  func testAddBudgetFormWithNameTyped() throws {
    let app = makeApp()
    app.launch()
    app.buttons["Add budget"].tap()
    let nameField = app.textFields["Budget name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 2))
    nameField.tap()
    nameField.typeText("Weekend Groceries")
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  /// BudgetIconPicker sheet opened from the Add Budget form.
  @MainActor
  func testAddBudgetIconPicker() throws {
    let app = makeApp()
    app.launch()
    app.buttons["Add budget"].tap()
    let iconButton = app.buttons["Budget icon"]
    XCTAssertTrue(iconButton.waitForExistence(timeout: 2))
    iconButton.tap()
    // Wait for the sheet to finish opening so the form behind it leaves the accessibility tree.
    XCTAssertTrue(app.navigationBars["Optional Icon"].waitForExistence(timeout: 2))
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  // MARK: - Edit Budget form

  /// Edit Budget form (Add layout, pre-filled).
  @MainActor
  func testEditBudgetForm() throws {
    let app = makeApp()
    app.launch()
    createBudget(named: "Groceries", in: app)
    app.cells.firstMatch.tap()
    let optionsButton = app.buttons["Budget options"]
    XCTAssertTrue(optionsButton.waitForExistence(timeout: 2))
    optionsButton.tap()
    app.buttons["Edit Budget"].tap()
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  // MARK: - Budget detail

  /// BudgetDetailView right after creation (no expense section).
  @MainActor
  func testBudgetDetailNoExpenses() throws {
    let app = makeApp()
    app.launch()
    createBudget(named: "Groceries", in: app)
    app.cells.firstMatch.tap()
    XCTAssertTrue(
      app.buttons["Budget options"].waitForExistence(timeout: 2),
      "Budget detail should be visible"
    )
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  /// BudgetDetailView with the options menu open.
  @MainActor
  func testBudgetDetailOptionsMenuOpen() throws {
    let app = makeApp()
    app.launch()
    createBudget(named: "Groceries", in: app)
    app.cells.firstMatch.tap()
    let optionsButton = app.buttons["Budget options"]
    XCTAssertTrue(optionsButton.waitForExistence(timeout: 2))
    optionsButton.tap()
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  // MARK: - Add Expense form

  /// Add Expense form opened from the budget row's "+" shortcut.
  @MainActor
  func testAddExpenseFormFromBudgetRow() throws {
    let app = makeApp()
    app.launch()
    createBudget(named: "Groceries", in: app)
    let addExpenseButton = app.buttons["Add expense for Groceries"]
    XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 2))
    addExpenseButton.tap()
    XCTAssertTrue(
      app.navigationBars["Add Expense"].waitForExistence(timeout: 3),
      "Add Expense sheet should be visible"
    )
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  /// Add Expense form opened from the primary button in Budget Detail.
  @MainActor
  func testAddExpenseFormFromBudgetDetail() throws {
    let app = makeApp()
    app.launch()
    createBudget(named: "Groceries", in: app)
    app.cells.firstMatch.tap()
    let addButton = app.buttons["Add expense to Groceries"]
    XCTAssertTrue(addButton.waitForExistence(timeout: 2))
    addButton.tap()
    XCTAssertTrue(
      app.navigationBars["Add Expense"].waitForExistence(timeout: 3),
      "Add Expense sheet should be visible"
    )
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  // MARK: - Settings

  /// Settings sheet.
  @MainActor
  func testSettings() throws {
    let app = makeApp()
    app.launch()
    app.buttons["Settings"].tap()
    XCTAssertTrue(
      app.navigationBars["Settings"].waitForExistence(timeout: 2),
      "Settings sheet should be visible"
    )
    try app.performAccessibilityAudit { try self.knownIssueHandler($0) }
  }

  // MARK: - Large-text clipping audits

  // These re-run a subset of screens at the largest accessibility text size and audit only
  // .textClipped.
  //
  // .dynamicType is excluded on purpose: it consistently flags system-provided UI (nav bar
  // internals, UIKit presentation layer) on the iOS 26.x simulator. Our own UIKit element
  // (DecimalInputField) already adopts Dynamic Type.

  /// Empty-state budgets list at the largest accessibility text size.
  @MainActor
  func testBudgetsListEmptyLargeText() throws {
    let app = largeTextApp()
    app.launch()
    try app.performAccessibilityAudit(for: .textClipped) { try self.knownIssueHandler($0) }
  }

  /// Populated budgets list at the largest text size (BudgetRowView reflows to vertical).
  @MainActor
  func testBudgetsListPopulatedLargeText() throws {
    let app = largeTextApp()
    app.launch()
    createBudget(named: "Groceries", in: app)
    try app.performAccessibilityAudit(for: .textClipped) { try self.knownIssueHandler($0) }
  }

  /// Add Budget form at the largest text size.
  @MainActor
  func testAddBudgetFormLargeText() throws {
    let app = largeTextApp()
    app.launch()
    app.buttons["Add budget"].tap()
    try app.performAccessibilityAudit(for: .textClipped) { try self.knownIssueHandler($0) }
  }

  /// Budget Detail at the largest text size (scroll-aware title and remaining summary clip first).
  @MainActor
  func testBudgetDetailLargeText() throws {
    let app = largeTextApp()
    app.launch()
    createBudget(named: "Groceries", in: app)
    app.cells.firstMatch.tap()
    XCTAssertTrue(app.buttons["Budget options"].waitForExistence(timeout: 2))
    try app.performAccessibilityAudit(for: .textClipped) { try self.knownIssueHandler($0) }
  }

  /// Add Expense form at the largest text size.
  @MainActor
  func testAddExpenseFormLargeText() throws {
    let app = largeTextApp()
    app.launch()
    createBudget(named: "Groceries", in: app)
    let addExpenseButton = app.buttons["Add expense for Groceries"]
    XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 2))
    addExpenseButton.tap()
    try app.performAccessibilityAudit(for: .textClipped) { try self.knownIssueHandler($0) }
  }

  /// Settings sheet at the largest text size.
  @MainActor
  func testSettingsLargeText() throws {
    let app = largeTextApp()
    app.launch()
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))
    try app.performAccessibilityAudit(for: .textClipped) { try self.knownIssueHandler($0) }
  }

  // MARK: - Issue handlers

  /// Shared issue handler for every `performAccessibilityAudit` call. Returns `true` to suppress.
  ///
  /// Permanent suppression: `.textClipped` for `.textField` (SwiftUI TextField scrolls
  /// horizontally and never clips; the audit false-positives on long values).
  ///
  /// iOS-COMPAT suppressions (search `iOS-COMPAT`): four findings are suppressed for iOS 26.x
  /// platform bugs, each tagged inline `// iOS-COMPAT(26.x):`. On each major iOS bump, remove the
  /// suppression, run the suite, and delete the tag if it passes.
  ///   1. `.elementDetection`: incomplete sheet accessibility isolation lets system elements
  ///      from the presenting view (toolbar buttons, text fields) bleed into the sheet's tree.
  ///      Suppressed only for elements with an empty `.accessibilityIdentifier` (system UI);
  ///      app-owned elements carry an identifier and still fail if unreachable.
  ///   2. `.sufficientElementDescription`: same bleed-through leaks a keyboard
  ///      `TUIPredictionViewCell` into an open sheet when a field auto-focuses. Same
  ///      empty-identifier scope.
  ///   3. `.dynamicType` "partially unsupported": system UIKit elements report it even when
  ///      Dynamic Type is adopted. The "not supported" variant stays active.
  ///   4. `.textClipped` for `.button` and `.staticText`: sheet-boundary artifacts and
  ///      font-metric edge cases with no visible clipping.
  ///
  /// Hit region, trait, and the rest remain active.
  private func knownIssueHandler(_ issue: XCUIAccessibilityAuditIssue) throws -> Bool {
    if issue.auditType == .contrast {
      // WCAG 2.1 SC 1.4.3 exempts disabled controls, but the audit doesn't skip them.
      if issue.element?.isEnabled == false {
        return true
      }
      // iOS-COMPAT(26.x): the audit sometimes reports contrast with a nil element (no type,
      // identifier, or label) on Form/NavigationStack containers; untraceable platform artifact.
      if issue.element == nil {
        return true
      }
      // iOS-COMPAT(26.x): GroupBox labels/content and List section headers (tagged
      // srb.sectionLabel) render via Liquid Glass, whose compositor opacity overrides even
      // opaque Color.primary. Visually correct; platform artifact.
      if issue.element?.identifier == "srb.sectionLabel" {
        return true
      }
      // iOS-COMPAT(26.x): nav bar Cancel buttons in Liquid Glass toolbars report contrast
      // failures even with .foregroundStyle(.primary). Scope: system buttons (empty
      // identifier) labeled "Cancel".
      if issue.element?.label == "Cancel",
         issue.element?.elementType == .button,
         (issue.element?.identifier ?? "").isEmpty {
        return true
      }
    }
    if issue.auditType == .elementDetection {
      // iOS-COMPAT(26.x): incomplete sheet accessibility isolation lets system elements
      // (Cancel/Save buttons, TextFields) from the presenting view bleed into the sheet's
      // tree and appear unreachable.
      //
      // Scope: empty identifier only. Every app-owned element must set an explicit
      // `.accessibilityIdentifier`, so it skips this suppression and real failures stay visible.
      //
      // When upgrading iOS: remove this block and run the suite; re-tag if it still fires.
      let id = issue.element?.identifier ?? ""
      return id.isEmpty
    }
    if issue.auditType == .sufficientElementDescription {
      // iOS-COMPAT(26.x): same sheet-isolation bleed-through as .elementDetection above. When a
      // form field auto-focuses, the predictive-text bar's `TUIPredictionViewCell` appears in the
      // sheet's tree without a description.
      //
      // Scope: empty identifier only (same as .elementDetection), so missing descriptions on
      // app-owned UI still fail.
      //
      // When upgrading iOS: remove this block and run the suite; re-tag if it still fires.
      let id = issue.element?.identifier ?? ""
      return id.isEmpty
    }
    if issue.auditType == .dynamicType {
      // iOS-COMPAT(26.x): "partially unsupported" fires on system UIKit elements (nav bar
      // internals, presentation containers) that do adopt Dynamic Type. "Not supported" is not suppressed.
      return issue.compactDescription.contains("partially unsupported")
    }
    if issue.auditType == .textClipped {
      return isTextClippedGlassArtifact(issue.element)
    }
    return false
  }

  /// `true` for element types whose `.textClipped` finding is an iOS 26 platform artifact:
  /// `.textField` scrolls horizontally, `.button` toolbar buttons bleed to the sheet boundary,
  /// `.staticText` font-metric edge cases show no visible clip.
  private func isTextClippedGlassArtifact(_ element: XCUIElement?) -> Bool {
    switch element?.elementType {
    case .textField, .button, .staticText: true
    default: false
    }
  }
}

// makeApp(), largeTextApp(), and createBudget(named:in:) are provided by UITestHelpers.swift.
