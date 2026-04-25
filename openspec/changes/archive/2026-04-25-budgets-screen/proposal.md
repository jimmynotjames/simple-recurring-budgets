## Why

The Budgets list screen and its supporting navigation infrastructure shipped in commits `8839adc` (#24, "Created Budgets screen") and `909f86d` (#25, "Updated navigation with routers and renamed ContentView placeholder"). They land the first end-to-end UI in the app — the root screen, the toolbar entry points, and a centralized `Router` that other screens (F-2.02 through F-2.05) will reuse.

This change is **retroactive**: it captures the contract for what shipped so future work can build on, refactor, and verify against a documented baseline. No code changes are proposed here; gaps (swipe-to-delete on F-2.01 and the F-2.06 first-run empty state) are deferred to a follow-up change.

## What Changes

- **Add `Views/BudgetsView.swift`** — Root screen presenting a `List` of `Budget` rows sorted by `sortOrder`, fed by `@Query`. Toolbar exposes a Settings entry (leading) and Add Budget entry (trailing). Hosted by the app's `NavigationStack`.
- **Add `BudgetRowView`** (private to `BudgetsView.swift`) — Per-budget row showing name, current-period remaining amount with period label, a fuel-gauge `RemainingBar`, the carry-over `CarryOverChip` (when enabled), and a per-row Add Expense button for the one-tap logging signature element from the UX brief. Layout adapts horizontal → vertical when `dynamicTypeSize >= .xxxLarge`. Lifecycle integration: each row calls `BudgetLifecycleService.refreshAndSave` via `.task(id:)` and on `scenePhase == .active`.
- **Add `Views/CarryOverChip.swift`** — Reusable signed carry-over chip with directional arrow, surplus/deficit semantic colors, and a localized accessibility label that distinguishes surplus, deficit, and zero states. Honors `colorSchemeContrast` for chip background opacity.
- **Add `Views/Color+Money.swift`** — Semantic color extensions `Color.moneyDeficit` and `Color.moneySurplus` aliasing system dynamic colors that auto-adapt to light/dark mode (high-contrast variants intentionally deferred).
- **Add `Formatting/BudgetPeriod+Display.swift`** — `BudgetPeriod.listLabel` and `BudgetPeriod.inlineLabel` with per-locale strings (rather than `.lowercased()`) so translators control casing.
- **Replace `Color/AccentColor.colorset`** and **remove** `BudgetNegative.colorset` / `BudgetPositive.colorset` — Asset catalog tweaks for the new accent and money semantic colors.
- **Add `App/Router.swift`, `App/AppRoute.swift`, `App/SheetRoute.swift`** — `@Observable @MainActor` `Router` owning `path: [AppRoute]` and `sheet: SheetRoute?`; route enums for push (`.budgetDetail(Budget)`) and sheet (`.addBudget`, `.editBudget(Budget)`, `.addExpense(Budget)`, `.viewExpense(ExpenseItem)`, `.settings`).
- **Rename `Views/ContentView.swift` → `Views/RootView.swift`** — Owns the `NavigationStack(path:)` and `.sheet(item:)` driven by the `Router`. Sheet and push destinations for screens not yet built (F-2.02–F-2.05) render placeholder `Text` views; this is intentional and documented in `docs/tech-design-doc.md` §5.1.
- **Wire `Router` and `RootView` into `simple_recurring_budgetsApp`** — `@State private var router = Router()` injected into the environment alongside `AppSettings` and `analytics`.
- **Localization strings** — All user-visible copy on the screen and chip is registered with `String(localized:defaultValue:comment:)` in `Localizable.xcstrings`. Translations are not yet provided.

This change documents the implementation **as shipped**. Items explicitly **out of scope** (deferred to a follow-up change):

- F-2.01 swipe-to-delete on a budget row with confirmation.
- F-2.06 first-run / empty state for the Budgets screen when the data store contains no budgets.
- High-contrast variants of `Color.moneyDeficit` / `Color.moneySurplus` (a known follow-up; called out in the source).
- Drag-to-reorder UI for `Budget.sortOrder` (the field exists; UI does not).

## Capabilities

### New Capabilities

- `budgets-screen`: The root Budgets list UI — list-of-rows layout, toolbar entry points (Settings, Add Budget), per-row content (name, remaining, period label, indicator bar, carry-over chip, per-row Add Expense button), Dynamic Type adaptive layout, VoiceOver labels and hints, and the eager `BudgetLifecycleService.refreshAndSave` integration for current-period display.
- `app-navigation`: The `Router`/`AppRoute`/`SheetRoute` pattern — an `@Observable @MainActor` navigation host owned by `RootView` and injected via `@Environment`, with type-safe push and sheet route enums. Defines how leaf screens trigger navigation without holding navigation state themselves.

### Modified Capabilities

_(none — this change adds two new capabilities only.)_

## Impact

- **New files (UI):** `Views/BudgetsView.swift`, `Views/CarryOverChip.swift`, `Views/Color+Money.swift`, `Formatting/BudgetPeriod+Display.swift`.
- **New files (navigation):** `App/Router.swift`, `App/AppRoute.swift`, `App/SheetRoute.swift`.
- **Renamed file:** `Views/ContentView.swift` → `Views/RootView.swift` (placeholder host evolved into the navigation host).
- **Modified files:** `App/simple_recurring_budgetsApp.swift` (router injection), `Models/DebugData.swift` (preview data adjustments), `Previews/PreviewContainer.swift` (preview wiring), `Resources/Localizable.xcstrings` (new strings registered).
- **Asset catalog:** `Assets.xcassets/AccentColor.colorset` updated; `BudgetNegative.colorset` and `BudgetPositive.colorset` removed in favor of `Color.moneyDeficit` / `Color.moneySurplus` aliases.
- **Dependencies:** None added. Uses SwiftUI, SwiftData, and the existing `BudgetLifecycleService` from change `2026-04-17-budget-lifecycle-service`.
- **Tests:** No new automated tests added in the original commits (the screen relies on previews — Light, Dark, xxLarge, xxxLarge — for design-time verification). Backfill is not in scope here.
- **Doc updates:** None required for this retroactive change. `docs/tech-design-doc.md` §2.2 (NavigationStack with value-based routing) and §5.1 (RootView placeholder exemption) already describe the navigation pattern that shipped.

## Doc alignment

- **Aligned** with `docs/main-prd.md` §6.7 — the row shows **remaining for current Budget Period** and **carry-over** as separate, independent figures. Carry-over chip respects the "not displayed when carry-over is off" rule via `if budget.isCarryOverEnabled`.
- **Aligned** with `docs/main-prd.md` §6.4 (Dynamic Type, VoiceOver) and §6.5 (locale-aware formatting; per-budget currency).
- **Aligned** with `docs/ux-design-brief.md` — Budgets is the root, no bottom tab bar, Settings reached via toolbar; one-tap Add Expense per row delivers the "fast expense logging" signature element; carry-over presented as a chip; system typography and `monospacedDigit()` on amounts.
- **Aligned** with `docs/tech-design-doc.md` §2.1 — `BudgetsView` is a View + Services screen (no ViewModel), reading via `@Query`, calling `BudgetLifecycleService` directly from `.task` and `.onChange(of: scenePhase)`. None of the §2.1 escalation triggers apply.
- **Aligned** with `docs/tech-design-doc.md` §2.2 — `Router` is `@Observable`, owned by `RootView`, exposed via `@Environment`, `path: [AppRoute]`, `sheet: SheetRoute?`.
- **Aligned** with `docs/tech-design-doc.md` §5.1 — placeholder `Text` views in `RootView` for sheet and push destinations are explicitly exempt from the "no hard-coded English" rule.
- **Aligned** with `docs/tech-design-doc.md` §5.2 — Dynamic Type via `@ScaledMetric` and semantic font styles; VoiceOver labels with currency context; Dark Mode via system semantic colors.
- **Aligned** with `docs/product-features-planning.md` F-2.01 acceptance criteria for the parts implemented (name, remaining, carry-over, top-level placement). The two outstanding F-2.01 acceptance items (swipe-to-delete with confirmation) and F-2.06 (first-run empty state) are explicitly **deferred** and tracked for a follow-up change.

**No `docs/*.md` updates are required** for this retroactive change. The follow-up change for the deferred gaps will revisit doc alignment when those acceptance criteria are addressed.
