# UI Testing Audit — 2026-05-31

> **Static-only audit.** No tests were executed and the Xcode scheme was not modified. No production code was changed by this audit. Item 1 (accessibility audit tests) was implemented in the same session.

## Summary

The **unit-test surface is strong; the UI-test target is essentially empty.** 60 Swift Testing unit-test files cover domain logic, ViewModels, settings, analytics, formatting, and SwiftData models thoroughly. The `simple-recurring-budgetsUITests` target has three files — `simple_recurring_budgetsUITests.swift`, `simple_recurring_budgetsUITestsLaunchTests.swift`, and `SnapshotHelper.swift` — that together contain exactly two tests (`testExample` / `testLaunchPerformance`), both of which are skipped by `make test` due to documented simulator-reliability constraints. No flow-based UI tests exist, no accessibility audit tests exist, and the visual-snapshot infrastructure (`SnapshotHelper.swift`, which wraps Fastlane's screenshot tool) has zero callers.

This audit identifies six distinct testing layers that are absent or underdeveloped, ordered by expected impact at the current feature-freeze / pre-release stage.

---

## Gap inventory

### 1. Accessibility audit tests — absent (high impact)

`XCUIApplication.performAccessibilityAudit()` (Xcode 15+) is a single method call that runs ~20 automated accessibility checks per screen: missing VoiceOver labels, tap-target size, text clipping, element detectability, and more. The app has thorough manual VoiceOver annotations across every screen (confirmed by the 2026-04-30 localization+voiceover audit), but there is no automated regression gate to catch future regressions.

The existing `makeApp()` helper and `IS_TESTING=1` infrastructure wire up cleanly to this API with no production code changes required.

**Implemented in this session.** See `simple-recurring-budgetsUITests/AccessibilityAuditTests.swift` — 18 tests covering 7 distinct screens in default appearance, plus 6 large-text variant audits targeting `.textClipping`.

---

### 2. XCUITest user-journey flows — absent (high impact)

The UI-test target contains no end-to-end flow coverage: create budget, add expense, reorder, delete, pause/resume, reset, settings toggle, navigation. These catch view-wiring regressions (a missing `.onMove`, a removed toolbar button, a broken sheet route) that unit and ViewModel tests cannot catch, because those tests inline the algorithm rather than invoking the View.

This is the largest gap. The existing `test-coverage-audit-2026-04-30.md` identified the same gap (finding #3) but no implementation followed.

**Effort:** M (1–3 days). Requires a `createBudget` / `addExpense` helper pattern (already written for the accessibility tests) plus additional flow assertions. No production code changes are required beyond adding `.accessibilityIdentifier` to any elements that prove hard to query reliably.

---

### 3. SwiftData schema-migration tests — absent (high risk for release)

`BudgetMigrationPlan.stages` is empty today (confirmed in `test-coverage-audit-2026-04-30.md`, finding #7). When a V2 schema lands, there is no in-memory migration harness to verify that existing user data survives the upgrade. For an app approaching release this is lower risk *now* (no migration yet) but high risk *immediately post-launch* when the first schema change ships to real user data.

**Effort:** S (< 1 day) to write the harness; the `TestModelContainer.make()` helper already demonstrates the pattern.

---

### 4. Performance baseline tests — minimal

`testLaunchPerformance()` exists but uses only `XCTApplicationLaunchMetric`. Available native metrics that are not yet used: `XCTMemoryMetric`, `XCTCPUMetric`, `XCTOSSignpostMetric` (wraps `os_signpost` intervals), `XCTOSSignpostMetric.scrollDecelerationMetric`. The budgets list scroll path and the SwiftData `BudgetLifecycleService.result(for:)` hot path are natural candidates for baseline measurement.

**Effort:** S (half a day). No production code changes; `os_signpost` markers would need to be added to the hot path for custom metric measurement.

---

### 5. Visual regression tests — absent (no native option)

There is no native Apple framework for pixel-diffing. `SnapshotHelper.swift` is Fastlane's screenshot capture utility (designed for App Store submission screenshots), not a regression tool — it has no diffing logic and zero callers.

The realistic options are:

| Approach | Native? | Effort | Automation |
|---|---|---|---|
| `swift-snapshot-testing` (Point-Free) | No | M | Fully automated; diffs on CI |
| Fastlane `snapshot` + manual PR comparison | Partially | S | Manual review only |
| Xcode 16 Test Report screenshots on failure | Yes | Zero | Surfaced in test navigator; manual review |

Given the preference for native tooling, the Xcode 16 Test Report approach costs nothing — screenshots are automatically captured and attached to the test report when any XCUITest fails. Adding `XCTAttachment(screenshot: app.screenshot())` to teardown captures the final screen state for all failures. This is not visual regression (no baseline comparison), but it reduces the debugging cost of UI-test failures significantly.

**Effort:** S (a few lines in `tearDownWithError`). True automated visual regression requires `swift-snapshot-testing`.

---

### 6. Localization / RTL smoke tests — absent

The app ships to 38 App Store storefronts and has a full translation pipeline. No UI test verifies that key labels are non-empty (indicating a missing translation) or that RTL layout doesn't clip. This can be caught by launching with `-AppleLocale` / `-AppleLanguages` arguments and running the accessibility audit, which includes `.textClipping` checks.

**Effort:** S (< 1 day). Extend `AccessibilityAuditTests.swift` with RTL launch arguments once the core audit suite is confirmed green.

---

## Method and scope

- **Type of audit:** Static. Every Swift file under `simple-recurring-budgetsUITests/` was read; the Makefile, `scripts/test.sh`, and the main view files (`BudgetsView.swift`, `BudgetDetailView.swift`, `SettingsView.swift`, `AddEditBudgetView.swift`, `AddEditExpenseView.swift`, `AnalyticsConsentSheet.swift`, `RootView.swift`) were reviewed for screen structure and accessibility-identifier availability.
- **Out of scope:** `xcodebuild` runs, live simulator sessions, scheme edits.
- **Relation to prior audits:** Extends `test-coverage-audit-2026-04-30.md` findings #3 (UI-test target empty) and #9 (accessibility untested). Does not repeat findings from `localization+voiceover-audit-2026-04-30.md`.

---

## Prioritized recommendations

| # | Gap | Effort | Suggested timing |
|---|---|---|---|
| 1 | Accessibility audit tests | **Done** | This session |
| 2 | XCUITest user-journey flows | M | Pre-release / first sprint post-freeze |
| 3 | Teardown screenshot attachment | S | Bundle with #2 |
| 4 | SwiftData migration harness | S | Before first post-launch schema change |
| 5 | Performance baselines | S | Post-launch once baseline is stable |
| 6 | Localization RTL smoke tests | S | After #1 suite is confirmed green |
| 7 | Visual regression (automated diffing) | M | Post-launch |
