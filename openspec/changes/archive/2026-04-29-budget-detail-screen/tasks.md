> Tasks 1–7 are **retroactive** — every checkbox describes work that already shipped in commit `3bd83de` ("Created Budget Detail Screen") and is preserved as-is. Tasks 8, 9, and 11 are **new** and represent the behavior, documentation, and test deltas this change proposes (the plural-rule i18n fix; the docs-sync work; the focused automated test suite). Task 10 was the original verify gate; Task 12 is the final verify gate after tests are added.

## 1. Route resolution and shared infrastructure (PR `3bd83de`)

- [x] 1.1 Replace the `Text("Budget Detail")` placeholder in `Views/RootView.swift` for the `AppRoute.budgetDetail(budget)` case with `BudgetDetailView(budget: budget)` and confirm `RootView`'s preview still injects `Router`, `AppSettings`, and a `PreviewContainer` model container.
- [x] 1.2 Extract the `RemainingBar` view from its previous private location in `Views/BudgetsView.swift` into a new `Views/RemainingBar.swift` so the same fuel-gauge component is consumed by both the Budgets row and the new detail header. Confirm `BudgetsView.swift` continues to compile against the extracted component without behavior change.

## 2. `BudgetDetailView` core file (PR `3bd83de`)

- [x] 2.1 Create `Views/BudgetDetailView.swift` declaring `struct BudgetDetailView: View` with `let budget: Budget`, `@Environment(\.modelContext)`, `@Environment(AppSettings.self)`, `@Environment(Router.self)`, `@Environment(\.scenePhase)`, and `@Environment(\.dynamicTypeSize)` injections.
- [x] 2.2 Add `@State` properties `lifecycle: BudgetLifecycleResult?`, `expenseToDelete: ExpenseItem?`, `showDeleteConfirm`, `showResetCarryOverConfirm`, `showResetBudgetConfirm`.
- [x] 2.3 Add `@ScaledMetric` properties for `rowSpacing` (relative to `.headline`), `amountSpacing` (`.callout`), `chipTopSpacing` (`.caption`), and `rowVerticalPadding` (`.body`) to scale layout with Dynamic Type.
- [x] 2.4 Implement computed properties `period`, `remaining`, `carryOverAmount`, `remainingFraction` (clamped to `[0, 1]`, dividing only when `allocation > 0`), `isOverBudget`, and `amountLayout` (`AnyLayout(HStackLayout(...))` below `.xxxLarge`, `AnyLayout(VStackLayout(...))` at `.xxxLarge`+).
- [x] 2.5 Implement `body` as a `List` with `.insetGrouped` style and `scrollContentBackground(.hidden)`, set `navigationTitle(budget.name)`, apply `appBackground()`.
- [x] 2.6 Build the **status header section**: `headerRow` view with the amount + period inside `amountLayout`, the `RemainingBar` below, and the conditional `CarryOverChip` + Reset button row when `budget.isCarryOverEnabled == true`. Wire `accessibilityElement(children: .combine)` and the composed VoiceOver label per spec (header A11y).
- [x] 2.7 Build the **primary action section**: `Section { Button { router.sheet = .addExpense(budget) } label: { Label(...) } }` with `.borderedProminent`, `.controlSize(.large)`, `listRowBackground(Color.clear)`, hidden separator, custom `listRowInsets`. Add `accessibilityLabel` (with budget name) and `accessibilityHint`.
- [x] 2.8 Wire the **toolbar** with a single `topBarTrailing` `Menu { ... } label: { Image(systemName: "ellipsis.circle") }`. Inside the Menu add the `Edit Budget` button (`pencil`, sets `router.sheet = .editBudget(budget)`), a `Divider()`, and the destructive `Reset Budget…` button (`trash`, sets `showResetBudgetConfirm = true`). Add a localized accessibility label on the Menu.
- [x] 2.9 Wire the **Reset Budget** `confirmationDialog` with destructive confirm (calls `resetBudget()`) and cancel; body uses key `budgetDetail.resetBudget.dialog.message` (in **2.9** the body still hand-rolled the plural — fixed in §8 below).
- [x] 2.10 Wire the **Delete Expense** `confirmationDialog` keyed on `$showDeleteConfirm`, branching the body on `expenseToDelete?.name` (named vs unnamed catalog keys). Confirm calls `deleteExpense(expense)` (defined in the expense-section extension).
- [x] 2.11 Wire the **Reset Carry-Over** `.alert` keyed on `$showResetCarryOverConfirm` with destructive confirm (calls `resetCarryOver()`) and cancel.
- [x] 2.12 Wire the lifecycle refresh triggers: `.task(id: budget.persistentModelID) { refreshLifecycle() }`, `.onChange(of: scenePhase) { _, new in if new == .active { refreshLifecycle() } }`, `.onChange(of: budget.expenseItems.count) { refreshLifecycle() }`.
- [x] 2.13 Implement actions: `refreshLifecycle()` (calls `BudgetLifecycleService.refreshAndSave(budget, settings: settings, context: context)` and assigns `lifecycle`), `resetCarryOver()` (zero `carryOverAmount`, set timestamps, single save, refresh), `resetBudget()` (within `withAnimation`: iterate `Array(budget.expenseItems)` calling `context.delete(_)`, zero `carryOverAmount`, set timestamps, single save; refresh).
- [x] 2.14 Implement the on-budget vs over-budget composed VoiceOver label (`headerA11yLabel`) using `period.inlineLabel` and the `(-remaining).formatted(...)` positive overage for the over-budget branch.
- [x] 2.15 Add six `#if DEBUG` `#Preview` declarations using `BudgetDetailPreview`-style hosting that injects `InMemoryModelContainer.makeEmpty()`, `Router()`, `AppSettings()`, and seeds via `DebugData.insertDetail(_:into:)`. Cover Current-only, Current-and-Past (long), Past-only, Empty, Carry-Over Disabled, Dark + Over Budget.

## 3. `BudgetDetailView+ExpenseSection` extension file (PR `3bd83de`)

- [x] 3.1 Create `Views/BudgetDetailView+ExpenseSection.swift` declaring `extension BudgetDetailView` and a `@ViewBuilder var expenseSection: some View`.
- [x] 3.2 Branch on `budget.expenseItems.isEmpty`: render the centered `budgetDetail.empty.noExpenses` caption when empty, else partition into `currentPeriodExpenses` / `pastPeriodExpenses` and render the two sections.
- [x] 3.3 Implement `currentPeriodExpenses` / `pastPeriodExpenses` partitioning against `lifecycle?.periodStart` (sorted by `date` descending; empty arrays when `periodStart == nil`).
- [x] 3.4 Render the **Current** section header as an `HStack { Text(currentSectionTitle); Spacer(); Text(currentPeriodTotal.formatted(...)) }` with `monospacedDigit()` and `textCase(nil)` on the trailing total.
- [x] 3.5 When `currentPeriodExpenses.isEmpty` but the budget has past expenses, render the per-period `currentPeriodEmptyText` caption inside the Current section instead of the row list.
- [x] 3.6 Render the **Past** section (when non-empty) with the per-period title and no section total.
- [x] 3.7 Implement `expenseRow(_:)` returning `ExpenseRowView` with `listRowBackground(Color("CellBackground"))` and a non-full-swipe trailing `swipeActions` whose destructive button sets `expenseToDelete` + `showDeleteConfirm`.
- [x] 3.8 Implement `deleteExpense(_:)` (within `withAnimation`: `context.delete(expense)` + single `save()`; then `refreshLifecycle()`).
- [x] 3.9 Implement `currentSectionTitle`, `pastSectionTitle`, `currentPeriodEmptyText` switching on `period` with one dedicated localization key per period (no `.lowercased()`).
- [x] 3.10 Implement the private `ExpenseRowView` rendering name (or italic `budgetDetail.expenseRow.unnamed` placeholder when nil) over `expense.date.formattedForExpenseList()`, plus the trailing `expense.displayAmount` formatted with the budget's currency in `monospacedDigit`. Apply `Color.moneySurplus` to the amount when `expense.isAddFunds`.
- [x] 3.11 Provide the row's combined accessibility label using `budgetDetail.expenseRow.accessibilityLabel` (regular) vs `budgetDetail.expenseRow.accessibilityLabel.addFunds` (when `isAddFunds`).

## 4. Preview fixtures (PR `3bd83de`)

- [x] 4.1 Create `Previews/BudgetDetailFixtures.swift` extending `DebugData` (gated `#if DEBUG`) with the six factories `detailDailyCurrentOnly`, `detailMonthlyCurrentAndPast`, `detailWeeklyPastOnly`, `detailWeeklyEmpty`, `detailMonthlyCarryOverDisabled`, `detailWeeklyOverBudget`, plus the `insertDetail(_:into:)` helper and the private `attachToDetail(_:to:)` wiring helper.
- [x] 4.2 Each factory accepts `now: Date = Date()` for deterministic snapshots and mints fresh `Budget` / `ExpenseItem` instances per call.

## 5. `Resources/Localizable.xcstrings` registration (PR `3bd83de`)

- [x] 5.1 Add catalog entries with `comment:` for every `budgetDetail.*` key referenced by `BudgetDetailView.swift` and `BudgetDetailView+ExpenseSection.swift` (header A11y on/over-budget; primary action title/A11y label/hint; menu A11y label, edit-budget item, reset-budget item; reset-carry-over alert title/message/confirm and the bordered Reset button + its A11y label; reset-budget dialog title/confirm/message — note: message is fixed in §8; delete-expense swipe action title; delete-expense dialog title/confirm/message/message-unnamed; section titles `budgetDetail.section.current.<period>` and `budgetDetail.section.past.<period>`; current-period empty captions `budgetDetail.currentPeriod.empty.<period>`; expense-row unnamed placeholder; expense-row A11y labels — regular and addFunds; the empty-budget caption `budgetDetail.empty.noExpenses`).
- [x] 5.2 Add the four `period.<period>.inline` keys ("daily" / "weekly" / "biweekly" / "monthly") consumed by `BudgetPeriod.inlineLabel` for the header VoiceOver label, with translator-context comments.
- [x] 5.3 Add `date.today` and `date.yesterday` keys consumed by `Date.formattedForExpenseList()`.

## 6. Linting (PR `3bd83de`)

- [x] 6.1 Apply the SwiftLint rule tweak that landed alongside the screen in `.swiftlint.yml` and confirm `make lint` is clean against the new files.

## 7. Build / preview verification (PR `3bd83de`)

- [x] 7.1 Confirm the six `BudgetDetailView` previews render in Xcode Canvas without runtime errors against fresh `InMemoryModelContainer` instances.
- [x] 7.2 Confirm `make test` passes (no new tests added for the screen; existing unit tests for `BudgetCalculator` / `PeriodCalculator` / `BudgetLifecycleService` continue to pass).

---

> Tasks 8–9 are NEW. They are the only behavior and documentation deltas this change introduces.

## 8. Reset Budget plural-rule i18n fix

- [x] 8.1 In `Resources/Localizable.xcstrings`, edit the entry `budgetDetail.resetBudget.dialog.message` to use Xcode's String Catalog **Plural** variation. Provide en-US `one` and `other` strings:
  - `one`: `"All %lld expense will be permanently deleted and the carry-over balance will be reset to zero."`
  - `other`: `"All %lld expenses will be permanently deleted and the carry-over balance will be reset to zero."`
  Keep the entry's `comment:` updated to: "Body of the reset-budget confirmation dialog; argument is the expense count. Catalog plural variation handles the count-correct form per locale."
- [x] 8.2 In `Views/BudgetDetailView.swift`, replace the existing dialog `message` closure (currently computing `expenseWord` and calling `String(localized:defaultValue:comment:)`) with a single `Text("budgetDetail.resetBudget.dialog.message \(budget.expenseItems.count)", comment: "Body of the reset-budget confirmation dialog; argument is the expense count.")` (or the equivalent `LocalizedStringKey` form that resolves the catalog's plural variation). Remove the now-unused `count` and `expenseWord` locals.
- [x] 8.3 Manually verify in Xcode Canvas that the "Empty" preview shows the `other` form (count = 0 → "All 0 expenses…") and that the "Past Periods Only" preview (which has 4 expenses, count > 1) also shows the `other` form. Verify the case where count = 1 by temporarily seeding a single-expense fixture or by inspection of the catalog editor.
- [x] 8.4 Run `make lint` and `make test` to confirm the catalog and code change build cleanly and pass the test suite.

## 9. Documentation sync (`docs/*.md`)

- [x] 9.1 **`docs/product-features-planning.md` — F-2.02.** Flip `Status:` from `Open` to `Implemented (excluding F-2.04 entry/edit and F-6.01)`. Extend the Acceptance Criteria list to add:
  - "Toolbar overflow Menu (`ellipsis.circle`) hosting **Edit Budget** (opens the Add/Edit Budget sheet in Edit mode) and **Reset Budget…** (destructive)."
  - "**Reset Budget** destructive flow — confirmation dialog body lists the count of expenses to be deleted (locale-aware plural). Confirming deletes every `ExpenseItem` for this Budget, zeros `carryOverAmount`, and bumps `carryOverLastResetDate` and `lastModified` in a single `ModelContext.save()`. The `Budget` itself stays."
  - "Status header shows large monospaced **remaining**, period label, fuel-gauge `RemainingBar`, and (when `isCarryOverEnabled == true`) an inline `CarryOverChip` + small Reset button for the manual carry-over reset (clears only this budget's carry-over)."
  - "Primary in-list **Add Expense** prominent button presents `SheetRoute.addExpense(budget)` (the actual sheet ships under F-2.04)."
  - "Period-aware **Current ⟨period⟩** and **Past ⟨period⟩** sections; the Current header shows the section total in `monospacedDigit`. When the budget has expenses but the current period is empty, the Current section shows a per-period 'Nothing logged …' caption; when the budget has no expenses at all, a single 'No expenses logged yet.' caption replaces both sections."
  - "Adaptive header layout: amount + period side-by-side below `.xxxLarge`, stacked at `.xxxLarge` and above; row spacing scales via `@ScaledMetric`."
  - "Composed VoiceOver labels for the header (on-budget / over-budget) and for each expense row (regular / add-funds variant for F-6.01 forward-compatibility)."
  - "Lifecycle refresh on `.task(id: budget.persistentModelID)`, `scenePhase == .active`, and `onChange(of: budget.expenseItems.count)` so any insert/delete made on this screen re-rolls boundaries before the next render."
  Append a brief implementation note below the bullets: "Implemented by change `budget-detail-screen`. Add Expense entry-point sheet target (F-2.04) and Add Funds entry-point (F-6.01, PAUSED) are intentionally out of scope of F-2.02."

- [x] 9.2 **`docs/main-prd.md` — §6.7 and §10.1.** In §6.7, immediately after the existing **Resetting carry-over** subsection, add a short **Reset Budget** subsection naming three distinct destructive operations on a Budget and contrasting their effects:
  - **Manual carry-over reset** — zeros `carryOverAmount`; keeps every `ExpenseItem`. Surfaced on the Budget detail screen.
  - **Reset Budget** — deletes every `ExpenseItem` for this Budget and zeros `carryOverAmount`; the Budget itself remains. Surfaced on the Budget detail screen's overflow Menu, gated by a confirmation dialog.
  - **Delete Budget** — removes the `Budget` entity (cascades to its expenses). Surfaced on the Add/Edit Budget sheet in Edit mode (per F-2.03 / change `delete-budget-button`).
  In §10.1 (Glossary), add an entry for **Reset Budget** matching the §6.7 wording above and reference `docs/product-features-planning.md` F-2.02 for the screen-level acceptance.
- [x] 9.3 **`docs/tech-design-doc.md` — §2.1, §5.1, and revision history.**
  - §2.1: append `BudgetDetailView` to the View + Services examples and note that lifecycle refresh is invoked from the view body via `.task(id:)`, `onChange(of: scenePhase)`, and `onChange(of: budget.expenseItems.count)` — no escalation triggers apply.
  - §5.1: add a one-line note that the Reset Budget dialog body uses an Xcode String Catalog plural variation rather than Swift-side word substitution, and that `BudgetPeriod.inlineLabel` continues to use dedicated `period.*.inline` keys.
  - Bump version to `0.10`, update **Last Updated** to today, and add a row to the revision history table summarizing the addition.
- [x] 9.4 Skim each of the three `docs/*.md` files end-to-end after the edits and confirm no orphaned references to the prior placeholder behavior, the prior hand-rolled plural rule, or the absence of `BudgetDetailView`.

## 10. Smoke-verify after the i18n + docs deltas

- [x] 10.1 Run `openspec validate budget-detail-screen` after Tasks 8 and 9 land; confirm valid.
- [x] 10.2 Run `make test` after Tasks 8 and 9; confirm the existing suite still passes (no regressions).
- [x] 10.3 Re-open the six `BudgetDetailView` previews in Xcode Canvas and confirm the visual matrix still renders (header on/over-budget, empty / past-only / current+past / dark over-budget, carry-over chip on/off).

## 11. Automated test coverage (NEW)

Mirrors `simple-recurring-budgetsTests/Views/BudgetsViewTests.swift` style: in-memory `ModelContainer` via `TestModelContainer.make()`, Swift Testing (`@Test` / `#expect`), inline-the-algorithm for view actions where the actual call site reads `@Environment(\.modelContext)`. Snapshot / rendering tests are intentionally out of scope — the six previews remain the visual contract.

### 11.1 Refactor partitioning into a testable helper

- [x] 11.1.1 Add a small extension or free helper (e.g. `extension Array where Element == ExpenseItem { func partitioned(byPeriodStart start: Date?) -> (current: [ExpenseItem], past: [ExpenseItem]) }`). Pure logic, no SwiftData dependency, sorts each side by `date` descending, returns `([], [])` when `start == nil`. Place it next to the other expense helpers (e.g. extend `Models/ExpenseItem.swift` with a sibling extension file, or in `Domain/`).
- [x] 11.1.2 Replace `BudgetDetailView+ExpenseSection.swift`'s `currentPeriodExpenses`, `pastPeriodExpenses`, and `currentPeriodTotal` computed properties so they call into the helper rather than duplicating the filter/sort. `currentPeriodTotal` stays as a one-liner sum over the current array. Behavior must remain identical (verify by re-opening every preview).
- [x] 11.1.3 Confirm `make lint` is clean and the previews still render after the refactor.

### 11.2 `BudgetDetailViewActionsTests` — destructive action algorithms

Create a new file at `simple-recurring-budgetsTests/Views/BudgetDetailViewActionsTests.swift`. Top-of-file comment matches the convention in `BudgetsViewTests.swift` (note that tests inline the algorithm rather than calling the view methods, and document the trade-off).

- [x] 11.2.1 **`resetBudget` — happy path.** Seed a Budget with 3 expenses and `carryOverAmount = 12.50`. Run the algorithm: iterate `Array(budget.expenseItems)` → `context.delete(_)`, set `carryOverAmount = 0`, set `carryOverLastResetDate = now`, set `lastModified = now`, `try context.save()`. `#expect`: `budget.expenseItems.isEmpty`, `budget.carryOverAmount == 0`, `budget.carryOverLastResetDate == now`, `budget.lastModified == now`. Refetch the Budget from a fresh `ModelContext` against the same container and verify the count of `ExpenseItem` for that budget is zero (atomicity).
- [x] 11.2.2 **`resetBudget` — Budget itself is preserved.** After running the algorithm, the `Budget` is still present in the store (refetch by `Budget.id` from a fresh `ModelContext` and verify the row exists with its original `name`, `allocation`, `period`, and `currencyCode`).
- [x] 11.2.3 **`resetBudget` — empty starting state.** Seed a Budget with zero expenses and `carryOverAmount = 0`. Run the algorithm. Verify it succeeds (no division by zero, no mutation of expenses), `carryOverAmount` stays `0`, timestamps still set to `now`.
- [x] 11.2.4 **`resetBudget` — does not affect other budgets.** Seed two Budgets, each with 2 expenses. Run the algorithm against the first only. Verify the second Budget's expense count and `carryOverAmount` are unchanged.
- [x] 11.2.5 **`resetCarryOver` — happy path.** Seed a Budget with 2 expenses and `carryOverAmount = -7.25`. Run the algorithm: set `carryOverAmount = 0`, set `carryOverLastResetDate = now`, set `lastModified = now`, save. `#expect`: `budget.expenseItems.count == 2` (unchanged), `budget.carryOverAmount == 0`, timestamps set. Refetch and confirm both expenses still exist.
- [x] 11.2.6 **`deleteExpense` — only the targeted expense is removed.** Seed a Budget with 3 expenses (capture references). Run the algorithm: `context.delete(target)`, save. Refetch from a fresh context: `#expect` exactly the other two expenses remain, the Budget is unchanged, and the Budget's `lastModified` is unchanged (the action does not bump the Budget's lastModified — only the lifecycle service does on its own writes).
- [x] 11.2.7 **Single save persistence.** Mirror `BudgetsViewMoveTests.move_persistsNewOrderAcrossContextRefetch`: after each destructive algorithm runs, refetch through a brand-new `ModelContext` against the same container and verify the post-state is fully persisted (proves `try context.save()` was invoked exactly once and the writes landed atomically).

### 11.3 `ExpenseItemPartitionTests` — partitioning helper

Create `simple-recurring-budgetsTests/Models/ExpenseItemPartitionTests.swift` (or co-locate next to `ModelTests.swift`). Pure logic; no SwiftData container needed if the helper is pure (build `ExpenseItem` directly without persisting).

- [x] 11.3.1 **`periodStart == nil` returns empty arrays.** Given any number of expenses, the helper returns `(current: [], past: [])`.
- [x] 11.3.2 **Boundary inclusivity.** An expense whose `date == periodStart` SHALL fall in the **current** array (matches the implementation's `>=` semantic). An expense one second before SHALL fall in the **past** array.
- [x] 11.3.3 **Sort order is descending by date in both arrays.** Verify with mixed timestamps.
- [x] 11.3.4 **All-current and all-past edge cases.** Confirm correct partitioning when every expense is on one side.
- [x] 11.3.5 **Section total convenience.** Optional: assert that summing the `current` array's `amount` matches the value `BudgetDetailView+ExpenseSection.swift` displays in the section header.

### 11.4 Plural-rule smoke-check (optional)

- [x] 11.4.1 Skipped — bundle + locale resolution in unit tests is too fragile; plural forms verified via the six BudgetDetailView Xcode Canvas previews. (Was: Add a single `@Test` (or skip if Apple's String Catalog plural resolution feels untestable in unit tests) that resolves `String(localized: "budgetDetail.resetBudget.dialog.message", defaultValue: ..., comment: ...)` (or its `Text(_:_:)`-equivalent representation) for `count = 1` and `count = 2` with `Locale(identifier: "en_US")` and `#expect` the resolved string contains `"1 expense "` for the singular and `"2 expenses "` for the plural. **Only land this if it works without fragile string-format gymnastics**; if it requires brittle `Text._resolveText`-style hacks, drop this task and rely on the visual previews to verify the rule.

### 11.5 Run the new suite

- [x] 11.5.1 Run `make test` and confirm the new suite passes alongside the existing tests.
- [x] 11.5.2 Confirm `make lint` is clean against the new test files.

## 12. Final verify before archive

- [x] 12.1 Run `openspec validate budget-detail-screen`; confirm valid.
- [x] 12.2 Run `make test` end-to-end; confirm full suite (existing + new) passes.
- [x] 12.3 Cross-read `proposal.md`, `design.md`, and `specs/budget-detail-screen/spec.md` against the post-edit `docs/*.md` files; confirm zero drift remains. If drift is found, fix the docs (per the project doc-maintenance protocol) before invoking `archive`.
