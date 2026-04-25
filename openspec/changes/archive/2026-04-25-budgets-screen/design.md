## Context

This document captures the design decisions baked into the Budgets list screen and the navigation infrastructure that shipped together in commits `8839adc` (#24) and `909f86d` (#25). It is a **retroactive** design — the implementation already exists and is the source of truth. The purpose here is to make the rationale durable so future work can build on, refactor, or revisit these decisions intentionally rather than by accident.

Prior context this change leans on:

- `BudgetLifecycleService` (added in `2026-04-17-budget-lifecycle-service`) is the sole orchestrator of the eager carry-over roll → persist → reset → persist → compute-remaining sequence. The Budgets row consumes it; it does not duplicate or re-implement that math.
- `AppSettings` (added in `2026-04-11-app-settings`) is `@Observable` and injected via `@Environment`. The lifecycle service reads `weekStartDay` from it.
- `Budget` and `ExpenseItem` are SwiftData `@Model` types defined in `Models/`. `Budget.expenses` is optional for CloudKit; `Budget.expenseItems` is the canonical non-optional accessor.
- `docs/tech-design-doc.md` §2.1 ("View + Services, ViewModels on demand"), §2.2 (NavigationStack with value-based routing), §5.1 (Localization, with placeholder exemption), and §5.4 (Budget Math Service Layer) are direct inputs to the decisions below.

## Goals / Non-Goals

**Goals:**

- Document the screen and navigation patterns as actually shipped, including the rationales that are not visible in the code itself.
- Establish a baseline contract that future changes (the F-2.01 swipe-to-delete + F-2.06 empty-state follow-up, F-2.02 Budget detail, F-2.03/04 sheets, F-2.05 Settings) can extend without re-deriving design choices.
- Capture intentional deferrals (high-contrast money colors, drag-to-reorder, automated tests) so they don't disappear into tribal knowledge.

**Non-Goals:**

- No code changes. This is a documentation-only retroactive change.
- Not specifying behavior for the deferred F-2.01 swipe-to-delete or F-2.06 empty state. Those are explicitly out of scope and will be addressed by a follow-up change.
- Not specifying the Budget detail, Add/Edit Budget, Add/Edit Expense, or Settings screens. Their navigation entry points exist as `SheetRoute` / `AppRoute` cases and as placeholder destinations in `RootView`; the full screens are downstream features.
- Not introducing a ViewModel for `BudgetsView`. None of `docs/tech-design-doc.md` §2.1's escalation triggers apply, and shipping without one is the documented default.

## Decisions

### 1. `BudgetsView` is a View + Services screen — no ViewModel

**Decision:** `BudgetsView` reads budgets via `@Query(sort: \Budget.sortOrder)` and `BudgetRowView` calls `BudgetLifecycleService.refreshAndSave(_:settings:context:)` directly inside `.task(id:)` and `.onChange(of: scenePhase)`. There is no `BudgetsViewModel`.

**Why:** `docs/tech-design-doc.md` §2.1 documents "View + Services, ViewModels on demand" as the default and lists explicit escalation triggers. None apply here:

- No draft/form state — the screen displays persisted data.
- No `async`/`Task` work beyond `.task` driving a synchronous service call.
- No multi-step actions — each row's two interactions (drill-in, add-expense) are single navigations.
- No expensive derived state — the screen relies on the lifecycle service's already-cached result and computes only `remainingFraction` (a clamped ratio) inline.

A VM here would mostly relay `@Query` results and forward `refreshAndSave`, defeating SwiftUI's automatic invalidation on SwiftData changes. The decision matches §2.1's stated default.

**Alternative considered:** Introduce `BudgetsListViewModel` to own the lifecycle calls. Rejected for the reasons above and because it would have required reimplementing reactive fetching that `@Query` already provides.

### 2. `RemainingBar` is decorative — accessibility hidden

**Decision:** The fuel-gauge bar under the amount is hidden from VoiceOver via `.accessibilityHidden(true)`. The over-budget signal and remaining amount are surfaced in the parent row's `accessibilityLabel` instead.

**Why:** A decorative bar that mirrors information already in the row's label would be redundant noise for VoiceOver users. The over-budget state is also reframed in the label as a positive overage amount ("$5 over budget this daily period") rather than a negative number, which reads more clearly than VoiceOver's literal interpretation of a minus sign.

### 3. Carry-over chip lives **outside** the row's drill-in `Button`

**Decision:** The row's drill-in target is a `Button` wrapping name, amount/period, and the indicator bar. The `CarryOverChip` is a sibling `View` inside the same outer `VStack`, *not* inside the button.

**Why:** VoiceOver collapses non-activatable content nested inside a button into the button's label. Keeping the chip outside lets it be read as a distinct static-text element with its own surplus/deficit/zero-aware label, while still appearing visually inside the row. `.accessibilityAddTraits(.isStaticText)` reinforces the intent.

**Trade-off:** The chip is not part of the tap target for drill-in. Users cannot tap the chip to open the budget detail. Acceptable: users have an obvious large tap target above it, and a non-tappable label is consistent with how the chip reads as a status indicator rather than a control.

### 4. Per-row Add Expense button is a fixed-size sibling, not part of the row's drill-in

**Decision:** Each row contains a separate `Button` displaying `plus.circle.fill` that triggers `router.sheet = .addExpense(budget)`. It is constrained to `frame(minWidth: 60, maxWidth: 60, minHeight: 44)` and has independent VoiceOver label and hint.

**Why:** The UX brief calls one-tap expense logging the **signature element**: "From the main budgets screen, there should be only one tap to open a form to add an Expense Item to a Budget." A fixed-size button keeps the touch target compliant with HIG (44pt minimum) at all Dynamic Type sizes — letting it scale would push the row text into a single-line ellipsis at large sizes. The two button regions also give VoiceOver two distinct, properly-labeled actions per row.

### 5. Adaptive amount layout at `dynamicTypeSize >= .xxxLarge`

**Decision:** `BudgetRowView.amountLayout` swaps an `HStackLayout(alignment: .firstTextBaseline)` for a `VStackLayout(alignment: .leading)` once Dynamic Type reaches `.xxxLarge`. All row spacing/padding are `@ScaledMetric`.

**Why:** The amount uses `.largeTitle` and the period label uses `.callout`. At `.xxLarge` they fit horizontally with `.firstTextBaseline` alignment; at `.xxxLarge` and beyond they need to stack to avoid truncation. Picking the threshold (`.xxxLarge`) by `dynamicTypeSize` rather than width avoids layout thrash from `GeometryReader`. The previews verify both sides of the threshold.

### 6. Money colors are simple aliases (`.orange`, `.green`); high-contrast intentionally deferred

**Decision:** `Color.moneyDeficit = .orange` and `Color.moneySurplus = .green` (system dynamic colors that auto-adapt to light/dark mode). The `CarryOverChip` *does* branch on `colorSchemeContrast` to reduce background-fill opacity (`0.15` → `0.05`) in increased-contrast mode, but the foreground colors themselves are not overridden.

**Why:** System dynamic colors give light/dark adaptation for free and avoid an asset-catalog round-trip during prototyping. High-contrast tuning belongs with the broader theming work (T-4 in `docs/product-features-planning.md`), where colors will move into asset catalog color sets with explicit light / dark / increased-contrast variants. Deferring keeps this change small; the deferral is called out in `Color+Money.swift`.

**Alternative considered:** Define color sets in `Assets.xcassets` with all four variants now. Rejected because the values would change again under T-4, and because the orange/green aliases are visually adequate in the meantime.

### 7. `BudgetPeriod` localization uses **dedicated inline strings**, not `.lowercased()`

**Decision:** `BudgetPeriod.listLabel` ("Daily", "Weekly", ...) and `BudgetPeriod.inlineLabel` ("daily", "weekly", ...) are separate `String(localized:)` keys per case.

**Why:** `.lowercased()` is locale-unsafe — German capitalises nouns, Turkish has dotless-i rules, and translators may need to inflect the inline form differently from the list form. Keys are paired (`period.daily` / `period.daily.inline`) so translators control casing. Comments make the inline-vs-list usage explicit for translator context.

### 8. Carry-over chip rendered only when `budget.isCarryOverEnabled`

**Decision:** `if budget.isCarryOverEnabled { CarryOverChip(...) }` — the chip is omitted when carry-over is off. The `lifecycle?.carryOverAmount ?? budget.carryOverAmount` fallback still flows correct values when the chip *is* shown.

**Why:** PRD §6.7: "When carry-over is turned off for a budget, the carry-over amount is still computed and kept current internally but is **not displayed** in the UI for that budget. This ensures that toggling carry-over back on at any time produces an immediately correct, up-to-date figure." The chip's *display* is the toggle; the underlying math (driven by `BudgetLifecycleService`) runs regardless.

### 9. Lifecycle refresh on `task(id:)` and on `scenePhase == .active`

**Decision:** Each `BudgetRowView` calls `BudgetLifecycleService.refreshAndSave` in `.task(id: budget.persistentModelID)` and again on `scenePhase == .active`.

**Why:** This matches the contract documented in `openspec/specs/budget-lifecycle/spec.md` ("ViewModel calls refreshAndSave on screen appearance" and "on scene activation"). The `id:` parameter ensures the task re-runs if the budget identity changes (e.g., row recycle), and the `scenePhase` hook handles the case where the app is foregrounded after period or reset boundaries elapsed in background. Both are no-ops when nothing crossed a boundary (per the lifecycle service's "no save when nothing changed" rule), so calling them on every appearance is cheap.

**Alternative considered:** Trigger only on `scenePhase`. Rejected because navigating away and back without a scene change (e.g., from a future Budget detail) wouldn't refresh, leaving stale carry-over after a boundary crossed during the visit.

### 10. `Router` is `@Observable @MainActor`, owned by `RootView`, exposed via `@Environment`

**Decision:** `Router` is a final class with `@Observable` and `@MainActor`, holding `path: [AppRoute]` and `sheet: SheetRoute?`. `RootView` declares it nowhere — `simple_recurring_budgetsApp` owns the single instance via `@State` and injects it through `.environment(router)`. Leaf screens read it with `@Environment(Router.self)`.

**Why:** `docs/tech-design-doc.md` §2.2 prescribes exactly this shape. `@MainActor` is correct because routing decisions (push, present sheet) are UI-thread mutations driven by user interaction and observed by SwiftUI. `@Observable` integrates cleanly with SwiftUI's tracking — assigning `router.sheet = .settings` from a button handler causes only the dependent surfaces to re-render. Owning the instance at `simple_recurring_budgetsApp` (rather than at `RootView`) means the router survives `RootView` identity changes (preview, scene rebuild) and lets sheets opened from one scene be restored consistently.

**Alternative considered:** Per-screen `@State` with `NavigationLink(value:)`. Rejected because sheets need a programmatic trigger from non-row contexts (toolbar, future deep links), and sheet presentation is much cleaner driven by an observable `sheet` property than by per-call `.sheet(isPresented:)` plumbing.

### 11. `AppRoute` and `SheetRoute` are separate enums

**Decision:** `AppRoute` covers push destinations only (currently `case budgetDetail(Budget)`). `SheetRoute` covers modal sheets (`.addBudget`, `.editBudget(Budget)`, `.addExpense(Budget)`, `.viewExpense(ExpenseItem)`, `.settings`) and conforms to `Identifiable` (with `var id: Self { self }`) for use with `.sheet(item:)`.

**Why:** Push and sheet have different semantics in `NavigationStack`. Push routes feed `navigationDestination(for:)`; sheets feed `.sheet(item:)`. Splitting them keeps each enum small and prevents `RootView` from `switch`-ing on a single union with mixed presentation logic. `Identifiable` on `SheetRoute` lets `.sheet(item:)` distinguish between sheets and animate the change correctly when, e.g., switching from `.addBudget` to `.settings` (rare but possible) without dismissing first.

**Alternative considered:** A single `Route` enum with a `presentation` discriminator. Rejected as needlessly homogenizing two different navigation primitives.

### 12. `AppRoute.budgetDetail(Budget)` carries the model object directly

**Decision:** The push destination payload is the `Budget` SwiftData object itself, not its `id: UUID` or `persistentModelID`.

**Why:** `Budget` is `Hashable` and Identifiable through SwiftData, and the destination view will need the live model anyway. Carrying the object avoids an unnecessary refetch in the detail VM (when one exists for F-2.02) and keeps the route enum small. SwiftData's reference semantics handle CloudKit-driven updates while the route is on the path.

**Trade-off:** `AppRoute.Hashable` derivation uses object identity. If the model is deleted while pushed, the detail screen will need to handle the resulting `nil`-ish state. Acceptable: the same hazard exists with any "deep link to thing that may be gone" pattern, and the detail screen is a downstream responsibility.

### 13. `RootView` placeholder destinations are intentional and exempt from the i18n rule

**Decision:** `RootView`'s `navigationDestination(for:)` and `.sheet(item:)` switch on the route enums and render `Text(...)` placeholders for every destination except the budget-detail name interpolation. These hard-coded English strings are exempt from the "no hard-coded English in production views" rule.

**Why:** `docs/tech-design-doc.md` §5.1: "Placeholder strings in `Views/RootView.swift` are exempt until the real T-2 screens replace them." Each downstream screen change will replace its placeholder with a real, fully-localized screen.

### 14. Localization registered, translations deferred

**Decision:** Every user-visible string in `BudgetsView.swift`, `CarryOverChip.swift`, `BudgetPeriod+Display.swift`, and the new toolbar items uses `String(localized:defaultValue:comment:)`. The `Localizable.xcstrings` catalog is updated. Translations into other languages are not yet provided; they are F-3.03 work.

**Why:** Registering keys and `comment:` strings now (when context is fresh) is much cheaper than going back to add them. F-3.03 will run translations against an already-keyed catalog. Comments are written for translator context — many keys document their sentence position ("VoiceOver hint…", "Period name used inline in an accessibility sentence…") so translators can choose appropriate forms.

### 15. No automated tests in the original commit

**Decision:** The original implementation ships without `BudgetsViewTests` / UI tests. Verification is via SwiftUI previews (Light, Dark, xxLarge, xxxLarge).

**Why:** The screen's logic delegates to already-tested services (`BudgetLifecycleService`, `BudgetCalculator`, `PeriodCalculator`, `AppSettings`). What remains in the view is presentation arithmetic (`remainingFraction` clamp), accessibility-label composition, and Dynamic Type layout — areas where SwiftUI's preview infrastructure provides tighter feedback than UI tests at this stage. Backfill is acceptable as a follow-up if regressions appear.

**Trade-off / risk:** Accessibility-label composition (`rowAccessibilityLabel` switching on `remaining < 0`) and the `remainingFraction` clamp at `allocation == 0` are untested. Marked as a follow-up for the swipe-to-delete + empty-state change.

## Risks / Trade-offs

**[F-2.01 swipe-to-delete missing]** → Captured explicitly as out of scope in `proposal.md`. A follow-up change will add `.swipeActions` (or equivalent) on `ForEach(budgets)` with a confirmation step, and will update this capability's spec.

**[F-2.06 first-run empty state missing]** → Same: deferred to the follow-up. Today the screen renders an empty `List` when the data store has no budgets; the only path to creating one is the toolbar `+`. The follow-up will define the empty-state copy, primary CTA, and the equivalence with the post-delete-all state.

**[High-contrast money colors are unhandled]** → Accepted; called out in `Color+Money.swift` and tracked under T-4 theming work. Increased-contrast users see correct light/dark variants but not contrast-tuned hues; the chip's increased-contrast background-opacity branch partly mitigates background readability.

**[Drag-to-reorder UI not built]** → `Budget.sortOrder` exists and `@Query` honors it, but there is no UI to mutate it. Not in any current feature spec. Accept as future work; no spec entry in this change.

**[`task(id:)` re-runs on row recycling cause double-saves on cold scroll]** → Not observed in practice because the lifecycle service is a no-op when nothing changed (`spec/budget-lifecycle Requirement: Single save per refreshAndSave, only when state changed`). The cost on a no-op path is one date comparison per row.

**[Sheet placeholders are reachable in production builds]** → True; tapping `+` (Add Budget), the row's `+` (Add Expense), or the toolbar gear (Settings) opens a sheet rendering `Text("Add Budget")` etc. Acceptable for a pre-release app (`docs/main-prd.md` §"Release Status": "greenfield"). Each downstream feature change replaces its placeholder with a real screen.

**[Two newly-unused asset catalog entries removed]** → `BudgetNegative.colorset` and `BudgetPositive.colorset` were removed in the same commit that introduced `Color.moneyDeficit` / `.moneySurplus`. No production code referenced them at the time of removal; verified by build success. Future code wanting an asset-catalog approach (T-4) will introduce new color sets with intentional names.

## Migration Plan

This is a documentation-only retroactive change. There is no code migration, schema change, or data migration. The OpenSpec archive flow (delta specs sync to `openspec/specs/`) will simply add the two new capability specs without modifying existing ones.

**No follow-up tasks gating archive of this change** beyond completing the artifacts and validating them. The deferred F-2.01 / F-2.06 work is a separate, future change.

## Open Questions

- None blocking archive. The next change will revisit:
  - Empty-state copy ("Create your first budget" vs alternatives) and CTA visual treatment.
  - Confirmation copy for swipe-to-delete (must mention cascade deletion of expenses).
  - Whether the chip should be hidden when `carryOverAmount == 0` even if `isCarryOverEnabled` is true (current behavior: shown with no arrow).
  - Whether high-contrast money colors move into asset catalog color sets now or wait for T-4.

## Doc alignment

- **Aligned** with `docs/main-prd.md` §6.7 (remaining and carry-over shown as separate, independent figures; carry-over hidden when off; underlying math always runs).
- **Aligned** with `docs/main-prd.md` §6.4 (Dynamic Type, VoiceOver) and §6.5 (per-budget currency, locale-aware formatting).
- **Aligned** with `docs/ux-design-brief.md` (Budgets as root, no tab bar, Settings via toolbar, one-tap Add Expense, calm carry-over chip, system typography with `monospacedDigit()`).
- **Aligned** with `docs/tech-design-doc.md` §2.1 (no VM by default; `BudgetsView` does not meet escalation triggers), §2.2 (Router/AppRoute/SheetRoute pattern as documented), §5.1 (i18n with placeholder exemption), §5.2 (a11y), and §5.4 (lifecycle service consumption contract).
- **No `docs/*.md` updates required** — this retroactive change captures what is already aligned with the published docs. The follow-up F-2.01 swipe-to-delete + F-2.06 empty-state change will revisit doc alignment when those acceptance criteria are addressed.
