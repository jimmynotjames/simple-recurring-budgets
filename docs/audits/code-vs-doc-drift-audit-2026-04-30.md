# Doc / Code Drift Audit — 2026-04-30

> **Temporary working artifact.** Delete or move when done.
> No Swift code was changed by this audit. No test run is required per `.cursor/rules/ios-build-test.mdc`.

## Summary

| Category | High | Medium | Low | Total |
|----------|------|--------|-----|-------|
| Doc fix (applied) | 2 | 6 | 2 | 10 |
| Spec fix (applied) | 1 | 0 | 1 | 2 |
| Flagged — not fixed (code / product) | 1 | 2 | 1 | 4 |
| **Total** | **4** | **8** | **4** | **16** |

---

## Findings (fixed)

### 1. tech-design §2.2: Router ownership says RootView, should say app entry point

- **Severity:** High
- **Doc:** [`docs/tech-design-doc.md`](docs/tech-design-doc.md) §2.2
- **Code:** [`simple-recurring-budgets/App/simple_recurring_budgetsApp.swift`](simple-recurring-budgets/App/simple_recurring_budgetsApp.swift):7, [`simple-recurring-budgets/App/Router.swift`](simple-recurring-budgets/App/Router.swift)
- **Evidence:** Tech-design §2.2 states: "A small `@Observable Router` (`path: [AppRoute]`, `sheet: SheetRoute?`) is owned by the navigation host (`RootView`) as `@State`." In the code, `Router` is owned by `simple_recurring_budgetsApp` as `@State` (line 7) and injected via `.environment(router)`. `RootView` consumes it via `@Environment(Router.self)`. The app-navigation spec already has this correct ("owned by the app entry point (`simple_recurring_budgetsApp`) as `@State`"). The tech-design is stale.
- **Fix applied:** Updated tech-design §2.2 to say Router is owned by the app entry point (`simple_recurring_budgetsApp`) as `@State`, consistent with the code and the app-navigation spec.

### 2. tech-design §8: Missing build.sh, _destination.sh, build Makefile target, lint-fix target

- **Severity:** High
- **Doc:** [`docs/tech-design-doc.md`](docs/tech-design-doc.md) §8.2 and §8.3
- **Code:** [`Makefile`](Makefile), [`scripts/build.sh`](scripts/build.sh), [`scripts/_destination.sh`](scripts/_destination.sh), [`lefthook.yml`](lefthook.yml)
- **Evidence:** (a) The pre-push hook in tech-design §8.2 says "`xcodebuild build` for scheme `simple-recurring-budgets`, iOS Simulator destination `name=iPhone 17,OS=latest`" — the actual `lefthook.yml` pre-push runs `bash scripts/build.sh` which sources `scripts/_destination.sh` for sophisticated destination resolution (SIMULATOR_UDID → booted sim → fallback). (b) `scripts/build.sh` and `scripts/_destination.sh` are not documented anywhere in §8. (c) §8.3 "Manual commands" lists `make system`, `make lint`, `make format`, `make test` — missing `make build` and `make lint-fix` and `make hooks-install` (hooks-install is mentioned in §8.1 but not §8.3). (d) The lefthook pre-commit commands include `swiftlint-fix` (auto-fix + re-stage) that §8.2 does not mention.
- **Fix applied:** Updated §8.2 to reference `scripts/build.sh` and the shared `_destination.sh` helper. Updated §8.3 to add `make build`, `make lint-fix`, and `make hooks-install`. Added `scripts/build.sh` and `scripts/_destination.sh` to the file references. Added `swiftlint --fix` to the pre-commit description.

### 3. budget-lifecycle spec: ViewModel consumption contract contradicts shipped code

- **Severity:** High
- **Spec:** [`openspec/specs/budget-lifecycle/spec.md`](openspec/specs/budget-lifecycle/spec.md) — "ViewModel consumption contract" requirement
- **Code:** [`simple-recurring-budgets/Views/BudgetsView.swift`](simple-recurring-budgets/Views/BudgetsView.swift) (`BudgetRowView`), [`simple-recurring-budgets/Views/BudgetDetailView.swift`](simple-recurring-budgets/Views/BudgetDetailView.swift)
- **Evidence:** The spec states: "The system SHALL be invoked from ViewModels (not from SwiftUI `View` bodies...)." Both `BudgetRowView` and `BudgetDetailView` call `BudgetLifecycleService.refreshAndSave` directly from the View — neither screen uses a ViewModel. This is consistent with tech-design §2.1 ("View + Services, ViewModels on demand") and §5.4 ("Per §2.1, simple screens invoke this directly from the view body / `.task`"). The budget-lifecycle spec was written before the budgets-screen and budget-detail changes shipped and was not updated.
- **Fix applied:** Updated the spec's ViewModel consumption contract to say "Screens (and any escalated ViewModels) SHALL call `refreshAndSave`..." matching the tech-design §2.1 / §5.4 language that allows direct View invocation for non-VM screens.

### 4. product-features-planning.md: Multiple implemented features still marked "Open"

- **Severity:** Medium
- **Doc:** [`docs/product-features-planning.md`](docs/product-features-planning.md)
- **Code:** Various — the features exist as shipped code
- **Evidence:** The following features are marked "Open" but are implemented:
  - **F-1.01 App Scaffolding** — Xcode project, folders, git repo all exist.
  - **F-1.02 Data Architecture** — SwiftData models + CloudKit sync are in place.
  - **F-2.01 Budgets screen** — `BudgetsView` with all ACs (empty state, drag-to-reorder, carry-over chip, lifecycle refresh).
  - **F-2.05 Settings screen** — `SettingsView` with all 6 sections per spec.
  - **F-2.06 First-run empty state** — empty state implemented in `BudgetsView` (ContentUnavailableView + create button).
  - **F-5.01 Start of week** — `AppSettings.weekStartDay` + Settings picker with confirmation.
- **Fix applied:** Updated statuses to "Implemented" with short change-attribution notes.

### 5. product-features-planning.md: F-3.01, F-3.02, F-3.04, F-3.05 partially implemented but marked "Open"

- **Severity:** Medium
- **Doc:** [`docs/product-features-planning.md`](docs/product-features-planning.md)
- **Code:** All shipped Views use semantic text styles, VoiceOver labels, color assets with light/dark variants, locale-aware currency formatting
- **Evidence:** Dynamic Type (F-3.01), VoiceOver (F-3.02), Currency i18n (F-3.04), and Dark Mode (F-3.05) are implemented on all shipped screens — adaptive layouts (`@ScaledMetric`, `dynamicTypeSize` checks), composed accessibility labels, named color assets with light/dark appearances, `CurrencyPickerView` and locale-aware formatting. These remain "Open" in the doc. Since these are cross-cutting and not formally audited per-screen, marking as "Partially implemented" is most accurate.
- **Fix applied:** Updated F-3.01, F-3.02, F-3.04, F-3.05 status to "Partially implemented" with notes.

### 6. product-features-planning.md: F-6.01 and F-6.02 partially implemented but marked "Open"

- **Severity:** Medium
- **Doc:** [`docs/product-features-planning.md`](docs/product-features-planning.md)
- **Code:** `ExpenseItem.isAddFunds`, `ExpenseItem.displayAmount`, `ExpenseItem.expenseType`; `AddEditExpenseViewModel` sign preservation on edit
- **Evidence:** F-6.01 (Add Funds) has the full model layer shipped: negative-amount convention, `isAddFunds`/`displayAmount` computed properties, budget-detail display with `Color.moneySurplus` tint and VoiceOver. Only the Add Expense UI toggle is missing. F-6.02 (Expense Type) has the schema done: `expenseType: String?` on `ExpenseItem`. Both marked "Open."
- **Fix applied:** Updated F-6.01 to "Partially implemented" with model-layer detail. Updated F-6.02 to "Partially implemented" noting schema is done.

### 7. ux-design-brief.md: Key Screens says "Add/Edit Expense (sheet or expanded section)" — stale

- **Severity:** Medium
- **Doc:** [`docs/ux-design-brief.md`](docs/ux-design-brief.md) — "Key Screens" section
- **Code:** [`simple-recurring-budgets/App/SheetRoute.swift`](simple-recurring-budgets/App/SheetRoute.swift), [`simple-recurring-budgets/App/AppRoute.swift`](simple-recurring-budgets/App/AppRoute.swift), [`simple-recurring-budgets/Views/RootView.swift`](simple-recurring-budgets/Views/RootView.swift)
- **Evidence:** The doc says "Add/Edit Expense (sheet or expanded section): Amount field focused on open; everything else optional. Designed to dismiss in seconds." In the shipped code, Add Expense is a sheet (`SheetRoute.addExpense`) and Edit/View Expense is push navigation (`AppRoute.expenseDetail`). The "(sheet or expanded section)" language doesn't reflect the final implementation.
- **Fix applied:** Updated to "Add/Edit Expense (sheet for add, push for edit)".

### 8. ux-design-brief.md: Settings lists "skin selection" — not implemented

- **Severity:** Medium
- **Doc:** [`docs/ux-design-brief.md`](docs/ux-design-brief.md) — "Key Screens — Settings"
- **Code:** [`simple-recurring-budgets/Views/SettingsView.swift`](simple-recurring-budgets/Views/SettingsView.swift) — has Budgets, Calendar, Display, iCloud, Support, and About sections; no skin/theme UI
- **Evidence:** The brief says the Settings screen includes "skin selection." No such UI exists. This feature is future (F-4.01–02).
- **Fix applied:** Updated Settings description to list the six actual sections and mark skin selection as future (F-4.01–02).

### 9. ux-design-brief.md: Navigation says iPad two-column split view — not implemented

- **Severity:** Medium
- **Doc:** [`docs/ux-design-brief.md`](docs/ux-design-brief.md) — "Navigation" section
- **Code:** [`simple-recurring-budgets/Views/RootView.swift`](simple-recurring-budgets/Views/RootView.swift) — uses single `NavigationStack`
- **Evidence:** The brief says "On iPad and macOS, prefer a two-column split view with Budgets as the sidebar." The app uses a single `NavigationStack` for all form factors. No `NavigationSplitView` exists.
- **Fix applied:** Updated to say current implementation uses a single `NavigationStack`; two-column split on iPad is a future enhancement.

### 10. PRD §8.3: Budgets screen says "current allocations" — UI shows "remaining"

- **Severity:** Low
- **Doc:** [`docs/main-prd.md`](docs/main-prd.md) §8.3 — Information Architecture
- **Code:** [`simple-recurring-budgets/Views/BudgetsView.swift`](simple-recurring-budgets/Views/BudgetsView.swift), `BudgetRowView` — displays remaining for current period
- **Evidence:** PRD §8.3 says "Budgets screen — List of Recurring Budgets with current allocations." The actual UI foregrounds "remaining this period" (per §6.7 Over/Under rules), not the allocation amount.
- **Fix applied:** Updated to "remaining for the current Budget Period."

### 11. tech-design §3.2: Broken anchor link to PRD §6.7

- **Severity:** Low
- **Doc:** [`docs/tech-design-doc.md`](docs/tech-design-doc.md) §3.2
- **Code:** N/A (doc-only)
- **Evidence:** §3.2 links `main-prd.md#67-overunder-carryover-behavior` but the PRD heading is "6.7 Carry-over behavior" (anchor: `#67-carry-over-behavior`). §2.1 already uses the correct anchor.
- **Fix applied:** Corrected anchor to `#67-carry-over-behavior`.

### 12. tech-design §5.5: Color-literal exceptions undocumented

- **Severity:** Low (clarification)
- **Doc:** [`docs/tech-design-doc.md`](docs/tech-design-doc.md) §5.5
- **Code:** `Views/Color+Money.swift` (`Color.moneySurplus` / `.moneyDeficit` as `.green` / `.orange`), `SettingsView.swift` (iCloud status icons), various views (`.tint(.red)` on destructive buttons)
- **Evidence:** §5.5 says "never hard-coded color literals." Multiple views use system color literals for semantic purposes (money signals, sync status, destructive tints). These are intentional and adapt to dark mode via the system palette. The doc was absolutist without documenting the allowed exceptions.
- **Fix applied:** Added an "Exceptions" paragraph to §5.5 documenting the three categories of permitted system color usage and noting they can be promoted to named assets if future theming (F-4.01–02) requires it.

### 13. tech-design §9: F-5.01 still in Future table but shipped; F-6.01/F-6.02 notes stale

- **Severity:** Medium
- **Doc:** [`docs/tech-design-doc.md`](docs/tech-design-doc.md) §9
- **Code:** `AppSettings.weekStartDay`, `PeriodCalculator`, `SettingsView` calendar section (F-5.01); `ExpenseItem.isAddFunds`, `ExpenseItem.expenseType` (F-6.01/F-6.02)
- **Evidence:** F-5.01 (Start of Week) is fully shipped via AppSettings + PeriodCalculator + Settings calendar section, but §9 still lists it as a future consideration with design notes. F-6.01 lists "Negative expense amount or separate Transaction type" as undecided — but the negative-amount convention is shipped. F-6.02 lists schema as future — but `expenseType: String?` already exists.
- **Fix applied:** Marked F-5.01 as shipped (strikethrough) in the §9 table. Updated F-6.01 and F-6.02 rows with partial-implementation notes.

### 14. settings-screen spec: About section requires header — code uses headerless section

- **Severity:** Low
- **Spec:** [`openspec/specs/settings-screen/spec.md`](openspec/specs/settings-screen/spec.md) — About section requirement
- **Code:** [`simple-recurring-budgets/Views/SettingsView.swift`](simple-recurring-budgets/Views/SettingsView.swift) — `aboutSection` uses `Section` without an explicit header
- **Evidence:** The spec says the screen "SHALL include an 'About' section." The implementation uses a headerless `Section` containing a version row. The section header is a UX detail — headerless is cleaner for a single-row section.
- **Fix applied:** Updated spec to say "(header optional)" for the About section.

---

## Flagged — not fixed (code / product)

### F1. PRD §6.1: Platform list includes macOS but no macOS target exists

- **Severity:** Medium
- **Category:** Governing constraint
- **Doc:** [`docs/main-prd.md`](docs/main-prd.md) §6.1 — "iOS, iPadOS, macOS. Primary focus on iOS."
- **Code:** [`simple-recurring-budgets.xcodeproj`](simple-recurring-budgets.xcodeproj) — target is universal iPhone + iPad only; no macOS destination is configured.
- **Evidence:** The PRD lists macOS as a target platform. The Xcode project, the test scripts, and the build scripts all target iOS Simulator only. No macOS build destination or Catalyst configuration exists. The tech-design §1 system overview also says "iOS, iPadOS, macOS" but the test/build infrastructure targets only iOS Simulator.
- **Recommendation:** Either add macOS to the Xcode target (Mac Catalyst or native) or update the PRD and tech-design to scope macOS out of the current release. This is a product decision, not a doc edit.

### F2. BudgetDetailView: Hard-coded English `Button("Cancel")` in confirmation dialogs

- **Severity:** High
- **Category:** Governing constraint — violates tech-design §5.1 (String Catalog / no hard-coded English in production views)
- **Code:** [`simple-recurring-budgets/Views/BudgetDetailView.swift`](simple-recurring-budgets/Views/BudgetDetailView.swift) — `confirmationDialog` Reset Budget (~line 152–153) and `alert` Reset Carry-Over (~line 177–178) both use `Button("Cancel", role: .cancel)` with a hard-coded English string literal.
- **Recommendation:** Replace with `String(localized:defaultValue:comment:)` keys and add entries to `Localizable.xcstrings`. Alternatively, remove the explicit Cancel button entirely (SwiftUI provides an implicit one for `confirmationDialog` and `alert`).

### F3. Settings currency picker rows: Spec requires `"<label> — <example>"` but code shows only `example()`

- **Severity:** Medium
- **Category:** Spec-vs-code mismatch (settings-screen spec is governing)
- **Spec:** [`openspec/specs/settings-screen/spec.md`](openspec/specs/settings-screen/spec.md) — Currency Display preference picker
- **Code:** [`simple-recurring-budgets/Views/SettingsView.swift`](simple-recurring-budgets/Views/SettingsView.swift) (~line 183–185) — `ForEach` renders `option.example()` only
- **Recommendation:** Compose the row title as `"\(option.label) — \(option.example())"` or equivalent to match the spec.

### F4. CurrencyPickerView: Missing `appBackground()` / `CellBackground` — violates §5.5 list pattern

- **Severity:** Low
- **Category:** Governing constraint — tech-design §5.5 says all list screens use `appBackground()` + `CellBackground`
- **Code:** [`simple-recurring-budgets/Views/CurrencyPickerView.swift`](simple-recurring-budgets/Views/CurrencyPickerView.swift) — `List` lacks `.scrollContentBackground(.hidden)`, `Color("CellBackground")`, and `appBackground()` unlike `BudgetsView`, `BudgetDetailView`, and `SettingsView`.
- **Recommendation:** Align the currency picker list with the documented background and row styling pattern.

---

## Excluded (borderline / trivial)

- **tech-design revision history date ordering** — revision rows in Appendix B are not strictly chronological (two rows labeled 0.6 with different dates). Not non-trivial per the plan's rule 5: the body prose for those revisions is accurate; the version numbering is a style choice.
- **PRD §10.3 "Last Updated: 2026-04-10"** — the PRD body has been updated by archived changes (carry-over, reset cadence, etc.) but the header date is stale. Per the plan's rule 5, a stale Last Updated date alone is not non-trivial. We update it as a side effect of the body edits in this audit.
- **product-features-planning.md "Last Updated: 2026-04-10"** — same; updated as side effect of status changes.
- **F-3.03 "Description: VoiceOver is supported"** — the description text says "VoiceOver" but should say "Internationalization of text". This is a typo, excluded per plan scope.
- **settings-screen spec notification name** (`CKAccountChangedNotification` vs `Notification.Name.CKAccountChanged`) — both refer to the same notification; functionally correct but naming is inconsistent across artifacts. Too trivial to fix.
- **BudgetDetailView explicit Cancel button in confirmationDialog** — the add-edit-budget and add-edit-expense specs say destructive confirmations should rely on SwiftUI's implicit Cancel. BudgetDetailView adds an explicit `Button("Cancel", role: .cancel)`. Already captured as F2 above (hard-coded English). The redundancy is a minor UX inconsistency.
