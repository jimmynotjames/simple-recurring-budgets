> This change is **retroactive**: every task below describes work that already shipped in commits `8839adc` (#24) and `909f86d` (#25). All checkboxes are pre-checked. The list exists so the work is auditable against the proposal, design, and specs in this change folder.

## 1. Navigation infrastructure (PR #25)

- [x] 1.1 Create `App/Router.swift` with `@Observable @MainActor final class Router` exposing `path: [AppRoute] = []` and `sheet: SheetRoute?`.
- [x] 1.2 Create `App/AppRoute.swift` defining `enum AppRoute: Hashable` with `case budgetDetail(Budget)` for push destinations.
- [x] 1.3 Create `App/SheetRoute.swift` defining `enum SheetRoute: Hashable, Identifiable` with cases `.addBudget`, `.editBudget(Budget)`, `.addExpense(Budget)`, `.viewExpense(ExpenseItem)`, `.settings`, and `var id: Self { self }`.
- [x] 1.4 Rename `Views/ContentView.swift` → `Views/RootView.swift`. Keep the file as the navigation host; move any non-navigation responsibilities out.
- [x] 1.5 In `RootView`, host a single `NavigationStack(path: $router.path)` with `BudgetsView()` as the stack root. Resolve push destinations via `.navigationDestination(for: AppRoute.self)`.
- [x] 1.6 In `RootView`, present sheets via `.sheet(item: $router.sheet)` switching on the active `SheetRoute` case.
- [x] 1.7 In `RootView`, render placeholder `Text(...)` views for every `AppRoute` and `SheetRoute` case whose owning screen has not yet shipped (Budget detail, Add/Edit Budget, Add/Edit/View Expense, Settings). Documented as i18n-exempt in `docs/tech-design-doc.md` §5.1.
- [x] 1.8 In `simple_recurring_budgetsApp.swift`, add `@State private var router = Router()` and inject via `.environment(router)` alongside the existing `AppSettings` and `analytics` injections.
- [x] 1.9 Update `Previews/PreviewContainer.swift` and `BudgetsView`'s preview wrapper to inject a fresh `Router()` so previews compile and present sheets / pushes correctly.

## 2. Money colors and formatting helpers (PR #24)

- [x] 2.1 Create `Views/Color+Money.swift` exposing `Color.moneyDeficit` (alias of `.orange`) and `Color.moneySurplus` (alias of `.green`); document in code that high-contrast variants are intentionally deferred to T-4 theming work.
- [x] 2.2 Create `Formatting/BudgetPeriod+Display.swift` with `BudgetPeriod.listLabel` and `BudgetPeriod.inlineLabel`, each backed by a dedicated `String(localized:)` key per case (no `.lowercased()` derivation).

## 3. Carry-over chip (PR #24)

- [x] 3.1 Create `Views/CarryOverChip.swift` with a `CarryOverChip` view taking `amount: Decimal` and `currencyCode: String`.
- [x] 3.2 Render an SF Symbol arrow (`arrow.up` for surplus, `arrow.down` for deficit, no arrow for zero), the formatted amount, and a fixed localized "carry-over" trailing label.
- [x] 3.3 Apply `Color.moneySurplus` / `Color.moneyDeficit` to the chip foreground and a tinted capsule background.
- [x] 3.4 Branch on `colorSchemeContrast == .increased` to lower the background opacity (0.15 → 0.05) and raise the trailing-label opacity (0.8 → 1.0).
- [x] 3.5 Provide three accessibility-label keys (`carryOver.accessibilityLabel.surplus`, `.deficit`, `.zero`) so the chip announces direction-aware copy via VoiceOver.
- [x] 3.6 Add SwiftUI previews for surplus, deficit, and zero states.

## 4. Budgets list and row (PR #24)

- [x] 4.1 Create `Views/BudgetsView.swift` with a `List` driven by `@Query(sort: \Budget.sortOrder) private var budgets: [Budget]`.
- [x] 4.2 Add navigation title using key `budgets.navigationTitle` ("Budgets").
- [x] 4.3 Add a leading toolbar item presenting `SheetRoute.settings` (gearshape icon, localized accessibility label and hint).
- [x] 4.4 Add a trailing toolbar item presenting `SheetRoute.addBudget` (plus icon, localized accessibility label and hint).
- [x] 4.5 Implement `BudgetRowView` displaying `budget.name` (body, up to two lines), the formatted current-period remaining amount (largeTitle, `monospacedDigit()`), and the period label (callout, secondary color) sourced from `BudgetPeriod.listLabel`.
- [x] 4.6 Add a `RemainingBar` decorative indicator below the amount: filled fraction `clamp(remaining/allocation, 0, 1)` in the accent color when on-budget, fully filled in `Color.moneyDeficit` when over-budget. Hide from VoiceOver via `.accessibilityHidden(true)`.
- [x] 4.7 Render the `CarryOverChip` only when `budget.isCarryOverEnabled == true`. Pass `lifecycle?.carryOverAmount ?? budget.carryOverAmount`. Place the chip outside the row's drill-in `Button` so VoiceOver treats it as a separate static-text element; add `.accessibilityAddTraits(.isStaticText)`.
- [x] 4.8 Wrap name + amount + period + bar in a single `Button` with `buttonStyle(.plain)` whose action appends `.budgetDetail(budget)` to `router.path`. Provide composed VoiceOver labels for on-budget (key `budget.row.accessibilityLabel`) and over-budget (key `budget.row.accessibilityLabel.overBudget`, using the **positive** overage amount). Provide a hint (key `budget.row.accessibilityHint`).
- [x] 4.9 Add a sibling Add Expense `Button` (`plus.circle.fill`, tint color, fixed `60×44` minimum frame) that sets `router.sheet = .addExpense(budget)`. Provide localized accessibility label including the budget name, plus a hint.
- [x] 4.10 Use `@ScaledMetric` for row spacing, amount/period spacing, chip top spacing, and row vertical padding. Switch the amount/period container from `HStackLayout` to `VStackLayout` when `dynamicTypeSize >= .xxxLarge`.
- [x] 4.11 Drive `lifecycle: BudgetLifecycleResult?` via `.task(id: budget.persistentModelID)` calling `BudgetLifecycleService.refreshAndSave(_:settings:context:)`.
- [x] 4.12 Re-invoke `BudgetLifecycleService.refreshAndSave` on `.onChange(of: scenePhase)` when the new phase is `.active`.
- [x] 4.13 Add SwiftUI previews for Light Mode, Dark Mode, xxLarge (just below reformatting threshold), and xxxLarge (at reformatting threshold) to verify both branches of the layout switch and both color schemes.

## 5. Asset catalog updates (PR #24)

- [x] 5.1 Update `Assets.xcassets/AccentColor.colorset/Contents.json` with the new accent color values.
- [x] 5.2 Remove `Assets.xcassets/BudgetNegative.colorset/` and `Assets.xcassets/BudgetPositive.colorset/`. Confirm no production code references them; the `Color+Money.swift` aliases supersede them.

## 6. Localization registration (PR #24)

- [x] 6.1 Update `Resources/Localizable.xcstrings` with all new keys introduced by this change:
  - `budgets.navigationTitle`
  - `toolbar.settings.label`, `toolbar.settings.accessibilityHint`
  - `toolbar.addBudget.accessibilityLabel`, `toolbar.addBudget.accessibilityHint`
  - `budget.row.accessibilityLabel`, `budget.row.accessibilityLabel.overBudget`, `budget.row.accessibilityHint`
  - `budget.row.addExpense.accessibilityLabel`, `budget.row.addExpense.accessibilityHint`
  - `carryOver.label`, `carryOver.accessibilityLabel.surplus`, `carryOver.accessibilityLabel.deficit`, `carryOver.accessibilityLabel.zero`
  - `period.daily`, `period.weekly`, `period.biweekly`, `period.monthly`
  - `period.daily.inline`, `period.weekly.inline`, `period.biweekly.inline`, `period.monthly.inline`
- [x] 6.2 Each entry includes a `comment:` providing translator context (sentence position, casing intent, semantic meaning of "carry-over" / "remaining" / "over budget"). Translations into other locales are deferred to F-3.03 work.

## 7. Debug / preview data adjustments (PR #24)

- [x] 7.1 Update `Models/DebugData.swift` so previews exercise rows with surplus carry-over, deficit carry-over, on-budget remaining, and over-budget remaining states across at least daily and weekly periods.
- [x] 7.2 Confirm `PreviewContainer.swift` provides the `ModelContainer`, `Router`, and `AppSettings` that `BudgetsView` and `BudgetRowView` require for live previews.

## 8. Documentation alignment

- [x] 8.1 Confirm no `docs/*.md` updates are required for this retroactive change. `docs/main-prd.md` §6.7 is honored (remaining and carry-over shown as separate, independent figures; chip hidden when toggle is off; underlying math always runs). `docs/tech-design-doc.md` §2.1 (no VM by default), §2.2 (Router/AppRoute/SheetRoute), §5.1 (placeholder i18n exemption), §5.2 (Dynamic Type, VoiceOver, Dark Mode), and §5.4 (lifecycle service consumption) all describe the patterns that shipped. `docs/product-features-planning.md` F-2.01 partial implementation is captured; the F-2.01 swipe-to-delete and F-2.06 first-run empty state acceptance items remain open and will be addressed by a follow-up change.

## 9. Out of scope (tracked here so they don't get lost)

> The following are intentionally **not** in this change. They will be addressed in a follow-up change. They are listed here for traceability only and SHALL NOT be implemented as part of archiving `budgets-screen`.

- Swipe-to-delete with confirmation on a budget row (F-2.01 acceptance criterion).
- First-run / empty state on the Budgets screen when the data store contains no budgets (F-2.06).
- High-contrast variants of `Color.moneySurplus` / `Color.moneyDeficit` (T-4 theming work).
- Drag-to-reorder UI for `Budget.sortOrder` (no current feature spec).
- Automated unit/UI tests for `BudgetsView`, `BudgetRowView`, and `CarryOverChip` (deferred — services they depend on are already covered).
