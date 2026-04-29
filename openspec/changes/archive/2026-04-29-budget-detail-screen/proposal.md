## Why

The Budget detail screen (F-2.02) shipped in commit `3bd83de` ("Created Budget Detail Screen") but was not paired with an OpenSpec change, so there is no `budget-detail-screen` capability under `openspec/specs/` and the `docs/*.md` files do not reflect what landed. This change captures the as-shipped contract so future work (F-2.04 Add/Edit/View Expense, F-6.01 Add Funds, theming) has a documented baseline to build on, and updates `docs/product-features-planning.md`, `docs/main-prd.md`, and `docs/tech-design-doc.md` to remove drift.

It is also an opportunity to **plug a small but clear i18n violation** introduced by the new screen: the Reset Budget confirmation dialog hand-rolls an English plural ("expense" vs "expenses"). This is a direct conflict with F-3.03 / PRD §6.5 (translations for all Apple-supported languages, locale-correct copy) and is the only UI / text change proposed by this otherwise-retroactive change.

## What Changes

This change is **mostly retroactive** — it documents the screen as-shipped. The only behavior delta is fixing the plural-rule i18n violation; the visual layout, copy, and IA are otherwise preserved exactly as the commit shipped them.

### New behavior (in code) being captured under spec

- **`Views/BudgetDetailView.swift`** — Detail screen presented via `AppRoute.budgetDetail(Budget)`.
  - **Status header section**: large monospaced remaining amount (deficit-tinted when negative), period label (`BudgetPeriod.listLabel`), reusable `RemainingBar` fuel gauge, and an inline `CarryOverChip` + Reset button row when `Budget.isCarryOverEnabled == true`.
  - **Primary action section**: a full-width `borderedProminent` "Add Expense" button (label + `plus` icon) that sets `router.sheet = .addExpense(budget)`. Per-row tap-to-add from the budgets list still routes to the same sheet; the detail screen surfaces the action again, prominently, within thumb reach.
  - **Expense sections**: when the budget has expenses, the list groups them into "Current ⟨period⟩" (section total formatted with `monospacedDigit`) and "Past ⟨period⟩" (no section total). When the current period is empty but past expenses exist, the "Current" section renders a contextual empty caption ("Nothing logged today" / "this week" / etc.). When the budget has zero expenses, a single centered "No expenses logged yet." caption replaces both sections.
  - **Expense rows** (`ExpenseRowView`): name (or italicized "Untitled expense" placeholder), `Date.formattedForExpenseList()` ("Today / Yesterday / locale-aware") under it, and the formatted amount on the trailing edge with `monospacedDigit`. Rows for `ExpenseItem.isAddFunds == true` (F-6.01 surface) render the amount in `Color.moneySurplus`. Each row exposes a single composed VoiceOver label and a non-full-swipe trailing destructive swipe action.
  - **Toolbar overflow Menu** (`ellipsis.circle`): "Edit Budget" (sets `router.sheet = .editBudget(budget)`) and "Reset Budget…" (destructive).
  - **Reset Budget destructive flow**: confirmation dialog body lists the affected expense count; on confirm, all `ExpenseItem`s for the budget are deleted, `carryOverAmount` is zeroed, `carryOverLastResetDate` and `lastModified` are bumped, all in a single `ModelContext.save()`.
  - **Reset Carry-Over flow**: header-inline Reset button presents a confirmation alert; on confirm, only `carryOverAmount` is zeroed and the relevant timestamps bumped.
  - **Delete expense flow**: trailing swipe sets `expenseToDelete` and presents a confirmation dialog (using the expense name when present, generic copy when nil); on confirm, the expense is deleted in a single save and the lifecycle is refreshed.
  - **Lifecycle refresh**: `BudgetLifecycleService.refreshAndSave(_:settings:context:)` is invoked in `.task(id: budget.persistentModelID)`, on `scenePhase == .active`, and on `onChange(of: budget.expenseItems.count)` so adds/deletes immediately re-roll any crossed boundaries.
  - **Adaptive layout**: amount + period label use `HStackLayout` below `.xxxLarge` and `VStackLayout` at `.xxxLarge` and above; `@ScaledMetric` drives row spacing, amount-stack spacing, chip top spacing, and row vertical padding.
  - **Localized strings**: every user-visible string uses `String(localized:defaultValue:comment:)` and is registered in `Resources/Localizable.xcstrings`. The `comment:` arguments are present.
- **`Views/BudgetDetailView+ExpenseSection.swift`** — Extension hosting the expense `Section` builders, the `ExpenseRowView` private view, current/past partitioning helpers, period-aware section titles, and the period-aware empty caption.
- **`Views/RemainingBar.swift`** — The fuel-gauge bar previously inlined in `BudgetsView` is extracted to a shared file so the detail header reuses the same component.
- **`Previews/BudgetDetailFixtures.swift`** — Six `DebugData` factories (`detailDailyCurrentOnly`, `detailMonthlyCurrentAndPast`, `detailWeeklyPastOnly`, `detailWeeklyEmpty`, `detailMonthlyCarryOverDisabled`, `detailWeeklyOverBudget`) and an `insertDetail(_:into:)` helper, used by six SwiftUI previews on `BudgetDetailView`.
- **`Resources/Localizable.xcstrings`** — Adds the full set of `budgetDetail.*`, `period.*.inline` (consumed by the header VoiceOver label), and `date.today` / `date.yesterday` keys.
- **`Views/RootView.swift`** — Wires `AppRoute.budgetDetail(budget)` to `BudgetDetailView(budget: budget)` (replacing the prior placeholder).

### Behavior delta (in scope for this change)

- **Fix the hand-rolled plural in the Reset Budget dialog body.** Replace the English-only `"All \(count) \(expenseWord) will be permanently…"` string (where `expenseWord` is conditionally `"expense"` or `"expenses"` based on `count`) with the proper SwiftUI / Foundation plural form so translators control the rule per locale (e.g. `Text("budgetDetail.resetBudget.dialog.message \(count)")` whose String Catalog entry uses Xcode's `Plural` variation, or an explicit `.stringsdict`-equivalent encoded in the catalog). User-visible English copy in en-US SHALL stay equivalent ("All N expense(s) will be permanently deleted and the carry-over balance will be reset to zero.") so the layout/voice does not change.

### Behavior explicitly NOT changed

- All other UI layout, copy, sectioning, button placement, ellipsis menu items, toolbar trailing placement, dialog titles, alert wording, swipe-action label, and accessibility wording stay exactly as shipped in `3bd83de`.
- The Reset Budget action and per-period sectioning are **kept** even though they were not previously specified — they are documented (see "Doc alignment", below).

### Out of scope (deferred to other features / changes)

- The Add Expense sheet (`SheetRoute.addExpense(budget)`) and the View/Edit Expense flow (`SheetRoute.viewExpense(item)`) — both still render `Text("Add Expense")` / `Text("View Expense")` placeholders in `RootView`. These ship under **F-2.04**.
- Tap-to-edit / tap-to-view on an expense row (F-2.04 same-screen-for-all paradigm). The row currently has no tap action; only swipe-to-delete is wired. Adding the tap target will land with F-2.04.
- The full Add Funds entry-point (F-6.01 — PAUSED). The detail row's display path already honors `ExpenseItem.isAddFunds` / `displayAmount`, but no UI lets the user create an add-funds entry yet.
- High-contrast / theming variants of `Color.moneyDeficit` / `Color.moneySurplus` (T-4 follow-up).
- Reset Cadence configuration — **PAUSED** project-wide; explicitly absent from this screen and not surfaced.

## Capabilities

### New Capabilities

- `budget-detail-screen`: The Budget detail screen — status header (remaining + RemainingBar + period + carry-over chip with manual reset), primary Add Expense action, period-aware Current / Past expense sections with section totals and contextual empty states, swipe-to-delete with confirmation, ellipsis Menu with Edit Budget and Reset Budget destructive actions, eager `BudgetLifecycleService.refreshAndSave` on task / scene-active / expense-count change, Dynamic Type adaptive amount layout, composed VoiceOver labels for header and rows including a dedicated add-funds variant, localized period-aware strings, and locale-correct plural copy in the Reset Budget dialog.

### Modified Capabilities

- _None._ The `app-navigation` enum already declares `AppRoute.budgetDetail(Budget)` and `SheetRoute.editBudget(Budget)` / `SheetRoute.addExpense(Budget)`; no new cases are added. `data-models` is not touched. `budget-lifecycle` is consumed unchanged. The `budgets-screen` requirements that drill into the detail screen are unaffected (the row's drill-in still appends `AppRoute.budgetDetail(budget)`; `BudgetDetailView` is now the resolved destination instead of a placeholder, but no `budgets-screen` requirement statement changes).

## Impact

- **New files (UI):** `Views/BudgetDetailView.swift`, `Views/BudgetDetailView+ExpenseSection.swift`, `Views/RemainingBar.swift`.
- **New files (previews / fixtures):** `Previews/BudgetDetailFixtures.swift`.
- **Modified files:**
  - `Views/RootView.swift` — `AppRoute.budgetDetail` resolves to `BudgetDetailView` (no longer a placeholder).
  - `Views/BudgetsView.swift` — the inline `RemainingBar` definition is removed (the view now consumes the shared `RemainingBar`).
  - `Resources/Localizable.xcstrings` — new keys under `budgetDetail.*`, `period.*.inline`, and `date.today` / `date.yesterday`. The plural-rule fix introduces a `Plural` variation on the existing `budgetDetail.resetBudget.dialog.message` entry; no key rename.
  - `.swiftlint.yml` — minor rule tweak that landed alongside the screen.
- **Dependencies:** none added. Uses SwiftUI, SwiftData, the existing `Router` / `AppRoute` / `SheetRoute` (capability `app-navigation`), and `BudgetLifecycleService` (capability `budget-lifecycle`).
- **Tests:** the original commit shipped previews-only verification (six `BudgetDetailView` previews exercising current-only, mixed, past-only, empty, carry-over-disabled, dark + over-budget). This change **adds a focused Swift Testing suite** for the destructive action algorithms (Reset Budget, Reset Carry-Over, Delete Expense) and the period-partitioning helper, mirroring the established `BudgetsViewMoveTests` pattern (inline the action algorithm in the test against an in-memory `ModelContainer` from `TestModelContainer.make()`). Snapshot / SwiftUI rendering tests are intentionally out of scope; the six previews continue to be the visual contract. See task §11 for scope.
- **Doc updates (in scope of this change — see `tasks.md`):**
  - `docs/product-features-planning.md` — flip **F-2.02** to "Implemented (excluding F-2.04 entry/edit and F-6.01)" and extend the acceptance criteria to cover (a) Edit Budget toolbar entry, (b) Reset Budget destructive action and confirmation, (c) period-aware Current / Past sectioning with section totals and contextual empty states, (d) header status presentation (large remaining + RemainingBar + period label + carry-over chip with manual reset), (e) Dynamic Type adaptive amount layout, (f) VoiceOver labels including the add-funds variant for F-6.01 forward compatibility.
  - `docs/main-prd.md` §6.7 — document **Reset Budget** as a per-budget destructive operation distinct from the carry-over manual reset (Reset Budget = delete all this budget's expenses + zero its carry-over; Delete Budget remains the operation that removes the budget itself). No new global rules; this is a clarifying paragraph + glossary entry.
  - `docs/tech-design-doc.md` §2.1 — add a one-line note that `BudgetDetailView` follows the View + Services pattern (no VM) and that lifecycle refresh is invoked from the view body via `.task(id:)`, `onChange(of: scenePhase)`, and `onChange(of: budget.expenseItems.count)`. §5.1 — note the `period.*.inline` keys and the plural-variation usage on the Reset Budget dialog body.

## Doc alignment

- **Aligned with `docs/main-prd.md` §6.7** — the header shows **remaining for current Budget Period** (computed by `BudgetLifecycleService` for that period only, not offset by carry-over) and **carry-over** as a separate, signed chip. Carry-over is hidden when `isCarryOverEnabled == false`. The header **Reset** button performs the per-budget manual carry-over reset to zero. **Reset Budget** is a new, broader destructive operation not previously named in §6.7; the doc-update task adds a paragraph and a glossary entry to disambiguate it from "manual carry-over reset" and from "delete budget".
- **Aligned with `docs/main-prd.md` §6.4** — Dynamic Type via `@ScaledMetric` and adaptive `HStack ↔ VStack` switch at `.xxxLarge`; VoiceOver labels on header, rows, chip, menu, and primary action; Dark Mode via semantic colors and asset-catalog appearances.
- **Aligned with `docs/main-prd.md` §6.5** — locale-aware currency formatting via `Decimal.formatted(currencyCode:display:)` honoring `AppSettings.currencyDisplay`. **Conflict to resolve:** the Reset Budget dialog body's English plural ("expense" / "expenses") violates §6.5 / F-3.03 — the only behavior delta this change proposes (see "What Changes / Behavior delta").
- **Aligned with `docs/ux-design-brief.md`** — "current-period state pinned at top" → status header section renders first; "primary Add Expense action always within thumb reach" → full-width prominent button is the second section, before the lists; "carry-over (surplus / deficit) is a small, clearly labeled chip — no streaks, trophies, or alarm reds" → reuses `CarryOverChip`; "no celebratory animations over routine logs" → no animations on add/delete beyond SwiftUI's default `withAnimation` for the destructive paths.
- **Aligned with `docs/tech-design-doc.md` §2.1** — `BudgetDetailView` is a View + Services screen (no VM): reads via `@Bindable`-free direct binding on the passed `Budget`, writes through `@Environment(\.modelContext)`, calls `BudgetLifecycleService` directly. None of the §2.1 escalation triggers apply (no draft form state, no async/Task work, multi-step user actions are simple destructive flows with confirmation, no expensive derived state).
- **Aligned with `docs/tech-design-doc.md` §2.2** — push destination is `AppRoute.budgetDetail(Budget)`; sheet routes invoked are existing `.editBudget(Budget)` and `.addExpense(Budget)`.
- **Aligned with `docs/tech-design-doc.md` §3** — no SwiftData schema changes. `Budget.carryOverAmount`, `carryOverLastResetDate`, `lastModified`, and `ExpenseItem` are written via existing fields. The PAUSED `ResetCadence` field is untouched. The `ExpenseItem.isAddFunds` / `displayAmount` consumption simply uses fields already on the model.
- **Aligned with `docs/tech-design-doc.md` §5.1 / §5.2 / §5.5** — i18n via String Catalog with `comment:` on every key (after the plural fix, the Reset Budget dialog body uses Xcode's plural variation in the catalog); a11y via composed labels and explicit `.accessibilityHidden(true)` on the bar; color via `AppBackground` / `CellBackground` / `AccentColor` named assets and the semantic `Color.moneyDeficit` / `Color.moneySurplus` aliases — no hard-coded color literals in the new files.
- **Aligned with `docs/product-features-planning.md` F-2.02** — every original acceptance criterion in F-2.02 is implemented:
  - "Vertical scrolling list of transactions, most-recent to least-recent" ✓ (sorted by `date` descending within each section).
  - "Shows the Budget's name at top of the screen" ✓ (`navigationTitle(budget.name)`).
  - "Shows Remaining for current Budget Period and Carry-over consistent with §6.7 and F-2.01" ✓.
  - "Reset Carry-over control with confirmation; clears only this budget's carry-over" ✓.
  - "Delete Expense Item — swipe-to-delete on a row with confirmation" ✓.
  - "For each Expense Item, shows Date and time, Amount of expense, Name of expense" ✓.
  - The doc-update task extends F-2.02 to cover the additional behaviors that shipped (Reset Budget, Edit Budget toolbar entry, sectioning + section totals, contextual empty states, adaptive amount layout) so the spec and code stop drifting.

## Conflicts with docs

- **Resolved by behavior change** — the Reset Budget dialog body's English-only plural rule violates F-3.03 / PRD §6.5. This change fixes the catalog entry (no UI re-layout, no copy reword in en-US).
- **Resolved by doc update** — F-2.02 in `docs/product-features-planning.md` does not currently mention Reset Budget, the Edit Budget menu entry, the Current / Past sectioning + section totals, or the per-period contextual empty captions. The spec-update tasks add these explicitly.
- **Resolved by doc update** — `docs/main-prd.md` §6.7 + §10.1 glossary do not currently name **Reset Budget** as a distinct operation. The spec-update tasks add a clarifying paragraph + glossary entry distinguishing "Reset Budget" (destructive: deletes all expenses, zeros carry-over) from "Manual carry-over reset" (zeros carry-over only) and from "Delete Budget" (removes the Budget entity, cascades expenses).
- **Resolved by doc update** — `docs/tech-design-doc.md` §2.1 does not currently list `BudgetDetailView` among the View + Services examples. A one-liner is added.
