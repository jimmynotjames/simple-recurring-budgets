# Budget detail screen

Single-budget screen with remaining/carry-over header, period-aware expense sections, Add Expense, Edit Budget, Reset Carry-Over, Reset Budget, and swipe-to-delete. Synced from change `budget-detail-screen` (2026-04-29).

## Requirements

### Requirement: Budget detail screen is the resolved destination of `AppRoute.budgetDetail`

`RootView` SHALL resolve `AppRoute.budgetDetail(Budget)` to `BudgetDetailView(budget:)` (no longer a placeholder `Text`). The screen SHALL set `navigationTitle(budget.name)` and apply `appBackground()`.

The screen SHALL render its primary content as a SwiftUI `List` with `listStyle(.insetGrouped)` and `scrollContentBackground(.hidden)` so the `appBackground()` color shows through.

#### Scenario: Drill into Budget detail from the Budgets row

- **WHEN** the user taps a `Budget` row's drill-in button on the Budgets screen
- **THEN** `AppRoute.budgetDetail(budget)` is appended to `router.path` and `RootView` pushes `BudgetDetailView(budget: budget)` onto the navigation stack with the budget's name as the navigation title

#### Scenario: AppBackground shows through the list

- **WHEN** the detail screen renders
- **THEN** the named asset color `AppBackground` is visible behind the list (`scrollContentBackground(.hidden)`) and the navigation bar (`appBackground()` modifier)

---

### Requirement: Status header presents remaining, period, RemainingBar, and conditional carry-over chip

The first List section SHALL be a status header showing:

- The current-period **remaining** amount, formatted with the budget's `currencyCode` and `AppSettings.currencyDisplay`, rendered in the system large-title font with `monospacedDigit()`. When remaining is negative, the amount SHALL be tinted with `Color.moneyDeficit`; when zero or positive, the primary text color.
- The period label sourced from `BudgetPeriod.listLabel` ("Daily" / "Weekly" / "Biweekly" / "Monthly") rendered in the system callout font with secondary foreground.
- A `RemainingBar` decorative bar bound to `clamp(remaining / allocation, 0, 1)`, hidden from VoiceOver and following the same on-budget vs over-budget rules as the Budgets row (accent fill when remaining ≥ 0; full deficit fill when remaining < 0; empty when allocation is 0).
- When `Budget.isCarryOverEnabled == true`, a row beneath the bar containing a `CarryOverChip` (passing `lifecycle?.carryOverAmount ?? budget.carryOverAmount`, `currencyCode`, and `AppSettings.currencyDisplay`) and a bordered, small-control "Reset" button. When `isCarryOverEnabled == false`, this row SHALL be omitted entirely.

The header SHALL collapse the amount and period label into a single accessibility element with the composed VoiceOver label specified by the dedicated requirement below.

The header's amount + period container SHALL switch from `HStackLayout` (`.firstTextBaseline` aligned) to `VStackLayout` (`.leading` aligned) when `dynamicTypeSize >= .xxxLarge`. Row spacing, amount-stack spacing, chip top spacing, and row vertical padding SHALL scale via `@ScaledMetric` relative to the relevant text style.

The header section SHALL set `listRowBackground(Color("CellBackground"))` and hide the row separator.

#### Scenario: Positive remaining renders with primary color

- **WHEN** the lifecycle service returns `remaining >= 0` for the budget
- **THEN** the amount text uses the primary text color and the period label uses the secondary text color

#### Scenario: Negative remaining renders in deficit color

- **WHEN** the lifecycle service returns `remaining < 0` for the budget
- **THEN** the amount text uses `Color.moneyDeficit` and the `RemainingBar` fills 100% of its width in `Color.moneyDeficit`

#### Scenario: Carry-over chip omitted when toggle is off

- **WHEN** `Budget.isCarryOverEnabled == false`
- **THEN** the header SHALL NOT render the carry-over chip + Reset button row, regardless of the underlying `carryOverAmount` value

#### Scenario: Carry-over row visible when toggle is on

- **WHEN** `Budget.isCarryOverEnabled == true`
- **THEN** the header renders a `CarryOverChip` followed by a small bordered "Reset" button (key `budgetDetail.resetCarryOver.button`) that activates the manual carry-over reset flow

#### Scenario: Horizontal amount layout below xxxLarge

- **WHEN** `dynamicTypeSize` is `.large`, `.xLarge`, or `.xxLarge`
- **THEN** the amount and period label render side-by-side aligned to the first text baseline

#### Scenario: Vertical amount layout at xxxLarge and above

- **WHEN** `dynamicTypeSize` is `.xxxLarge` or any larger accessibility size
- **THEN** the amount renders above the period label in a vertical stack aligned to the leading edge

---

### Requirement: Header announces composed VoiceOver label distinguishing on-budget vs over-budget

The header SHALL provide a single combined accessibility element (`accessibilityElement(children: .combine)`) with a localized label that describes the current-period state:

- When `remaining >= 0`, the label SHALL use key `budgetDetail.header.accessibilityLabel` and include the formatted remaining amount and the inline period name (e.g. "$12.50 remaining this daily period").
- When `remaining < 0`, the label SHALL use key `budgetDetail.header.accessibilityLabel.overBudget` and include the **positive** overage amount (i.e. `|remaining|`) and the inline period name (e.g. "$5.00 over budget this daily period").

The inline period name SHALL be sourced from `BudgetPeriod.inlineLabel`, which is backed by dedicated per-locale strings rather than `.lowercased()` on the list label.

#### Scenario: On-budget header announces remaining

- **WHEN** VoiceOver focuses the header and `remaining >= 0`
- **THEN** the announced label uses key `budgetDetail.header.accessibilityLabel` and includes the formatted positive remaining amount and the inline period name

#### Scenario: Over-budget header announces positive overage

- **WHEN** VoiceOver focuses the header and `remaining < 0`
- **THEN** the announced label uses key `budgetDetail.header.accessibilityLabel.overBudget` and includes the formatted **positive** overage amount and the inline period name; the negative sign is not announced literally

---

### Requirement: Primary action section presents a full-width Add Expense button

The second List section SHALL be a single full-width primary action button styled `.borderedProminent` at `.controlSize(.large)` with the system headline font. Activating the button SHALL set `router.sheet = .addExpense(budget)` for this specific budget.

The button label SHALL be a `Label` composed of the localized title (key `budgetDetail.action.addExpense`, en-US "Add Expense") and the SF Symbol `plus`. The button SHALL provide:

- A localized accessibility label that includes the budget's name (key `budgetDetail.action.addExpense.accessibilityLabel`).
- A localized accessibility hint (key `budgetDetail.action.addExpense.accessibilityHint`).

The section SHALL use `listRowBackground(Color.clear)`, hide the row separator, and apply `listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))` so the button reads as a free-standing prominent action rather than a List row.

#### Scenario: Tapping Add Expense presents the sheet for this budget

- **WHEN** the user activates the primary Add Expense button
- **THEN** `router.sheet` is set to `SheetRoute.addExpense(budget)` for this specific budget

#### Scenario: Add Expense VoiceOver label includes the budget name

- **WHEN** VoiceOver focuses the primary action button
- **THEN** the announced label uses key `budgetDetail.action.addExpense.accessibilityLabel` and includes the budget's name; the announced hint uses key `budgetDetail.action.addExpense.accessibilityHint`

---

### Requirement: Toolbar overflow Menu hosts Edit Budget and Reset Budget actions

The screen SHALL place a single `topBarTrailing` toolbar item rendered as a `Menu` whose label is the SF Symbol `ellipsis.circle`. The Menu SHALL contain, in order:

1. **Edit Budget** (key `budgetDetail.menu.editBudget`, system image `pencil`) — activating it sets `router.sheet = .editBudget(budget)`.
2. A `Divider`.
3. **Reset Budget…** (key `budgetDetail.menu.resetBudget`, system image `trash`, `role: .destructive`) — activating it triggers the Reset Budget confirmation flow.

The Menu SHALL provide a localized accessibility label (key `budgetDetail.menu.accessibilityLabel`).

#### Scenario: Edit Budget opens the edit sheet

- **WHEN** the user taps the ellipsis Menu and selects Edit Budget
- **THEN** `router.sheet` is set to `SheetRoute.editBudget(budget)` and the Add/Edit Budget sheet opens in Edit mode for this budget

#### Scenario: Reset Budget opens the destructive confirmation

- **WHEN** the user taps the ellipsis Menu and selects Reset Budget…
- **THEN** the Reset Budget confirmation dialog is presented (specified below)

#### Scenario: Menu exposes a VoiceOver label

- **WHEN** VoiceOver focuses the toolbar Menu
- **THEN** the announced label uses key `budgetDetail.menu.accessibilityLabel`

---

### Requirement: Reset Carry-Over presents a confirmation alert and zeros only carry-over

The header's "Reset" button next to the `CarryOverChip` SHALL present a SwiftUI `.alert` titled with key `budgetDetail.resetCarryOver.alert.title` and bodied with key `budgetDetail.resetCarryOver.alert.message`. The alert SHALL include:

- A destructive confirm button (key `budgetDetail.resetCarryOver.alert.confirm`).
- A standard `role: .cancel` Cancel button.

On confirm, the system SHALL set `Budget.carryOverAmount = 0`, set `Budget.carryOverLastResetDate = Date()`, set `Budget.lastModified = Date()`, persist via a single `ModelContext.save()`, and re-invoke `BudgetLifecycleService.refreshAndSave(_:settings:context:)` so the header updates. The system SHALL NOT delete any `ExpenseItem`s.

The reset button SHALL provide a localized VoiceOver label (key `budgetDetail.resetCarryOver.button.accessibilityLabel`).

#### Scenario: Confirming Reset Carry-Over zeros only carry-over

- **WHEN** the user activates the header Reset button and confirms the alert
- **THEN** the budget's `carryOverAmount` becomes `0`, `carryOverLastResetDate` and `lastModified` become the current date, and **no** `ExpenseItem` rows are deleted

#### Scenario: Cancelling the alert preserves carry-over

- **WHEN** the user activates the header Reset button and selects Cancel
- **THEN** the budget's `carryOverAmount`, `carryOverLastResetDate`, and `lastModified` SHALL NOT be modified

---

### Requirement: Reset Budget presents a confirmation dialog and atomically wipes expenses + zeros carry-over

The Menu's "Reset Budget…" item SHALL present a SwiftUI `confirmationDialog` titled with key `budgetDetail.resetBudget.dialog.title` and bodied with key `budgetDetail.resetBudget.dialog.message`. The dialog SHALL include:

- A destructive confirm button (key `budgetDetail.resetBudget.dialog.confirm`).
- A standard `role: .cancel` Cancel button.

The dialog body SHALL be a single static localized string under key `budgetDetail.resetBudget.dialog.message` (en-US: "All expenses will be permanently deleted and the carry-over balance will be reset to zero.") with no runtime arguments and no expense count in the copy.

On confirm, within a single `withAnimation` block, the system SHALL:

1. Iterate `Array(budget.expenseItems)` and call `context.delete(_)` on each `ExpenseItem`.
2. Set `Budget.carryOverAmount = 0`.
3. Set `Budget.carryOverLastResetDate = Date()`.
4. Set `Budget.lastModified = Date()`.
5. Persist via exactly one `ModelContext.save()` call.

After the save, the system SHALL re-invoke `BudgetLifecycleService.refreshAndSave(_:settings:context:)` so the header and lists re-render. The Budget itself SHALL NOT be deleted.

The Reset Budget operation is distinct from the Reset Carry-Over operation (which only zeros carry-over) and from the Delete Budget operation owned by the Add/Edit Budget sheet (which removes the Budget and cascades expenses). The capability `budget-detail-screen` SHALL NOT introduce a Delete Budget entry point on this screen.

#### Scenario: Reset Budget dialog body is static and localized

- **WHEN** the user opens the Reset Budget dialog (any number of expenses, including zero)
- **THEN** the dialog body is rendered from key `budgetDetail.resetBudget.dialog.message` as a single String Catalog entry (en-US: "All expenses will be permanently deleted and the carry-over balance will be reset to zero.") with no count interpolation

#### Scenario: Confirming Reset Budget deletes expenses and zeros carry-over in one save

- **WHEN** the user activates Reset Budget… from the Menu and confirms the dialog
- **THEN** every `ExpenseItem` whose `budget == budget` is removed from the store, `Budget.carryOverAmount` becomes `0`, `Budget.carryOverLastResetDate` and `Budget.lastModified` become the current date, and `ModelContext.save()` is called exactly once for the entire operation

#### Scenario: Reset Budget does NOT delete the Budget entity

- **WHEN** the user confirms the Reset Budget dialog
- **THEN** the `Budget` entity SHALL remain in the store (no `context.delete(budget)` call), the screen stays on the same `BudgetDetailView`, and the navigation stack does not pop

#### Scenario: Cancelling the dialog preserves the budget's data

- **WHEN** the user activates Reset Budget… and selects Cancel
- **THEN** no `ExpenseItem` is deleted and the budget's `carryOverAmount`, `carryOverLastResetDate`, and `lastModified` are unchanged

---

### Requirement: Expense list partitions into Current and Past sections with localized headers

When `budget.expenseItems` is non-empty, the screen SHALL render the expense list as up to two adjacent List sections:

- A **Current** section containing every `ExpenseItem` whose `date >= lifecycle?.periodStart`, sorted by `date` descending. Its header SHALL be the period-aware string under `budgetDetail.section.current.<period>` ("Current Day" / "Current Week" / "Current Period" / "Current Month") and SHALL also display, on the trailing edge of the header row, the section total formatted with the budget's `currencyCode`, `AppSettings.currencyDisplay`, and `monospacedDigit`. The section header SHALL apply `textCase(nil)` to the trailing total so the digits are not uppercased.
- A **Past** section containing every `ExpenseItem` whose `date < lifecycle?.periodStart`, sorted by `date` descending. Its header SHALL be the period-aware string under `budgetDetail.section.past.<period>` ("Past Days" / "Past Weeks" / "Past Periods" / "Past Months"). The Past section SHALL NOT display a section total.

When `lifecycle?.periodStart` is `nil` (the lifecycle has not yet returned), the Current and Past partitions both evaluate as empty arrays; the screen SHALL render the empty-budget caption (per the next requirement) until the lifecycle resolves.

Each row SHALL set `listRowBackground(Color("CellBackground"))`.

#### Scenario: Current section shows period-aware title and total

- **WHEN** the budget has at least one expense within the current period
- **THEN** the Current section header reads the localized title for that budget's period and the trailing label shows the sum of the section's expense `amount`s formatted with the budget's currency

#### Scenario: Past section omits the section total

- **WHEN** the budget has at least one expense before the current period
- **THEN** the Past section header reads the localized title for that budget's period and does **not** show a trailing total

#### Scenario: Sort order is most-recent first within each section

- **WHEN** either section renders
- **THEN** its rows are ordered by `ExpenseItem.date` descending (most recent at the top)

---

### Requirement: Empty states differentiate "no expenses at all" from "nothing in current period"

When `budget.expenseItems.isEmpty`, the screen SHALL render a single Section containing a centered, body-font, secondary-foreground, vertically-padded caption with key `budgetDetail.empty.noExpenses` (en-US "No expenses logged yet."). The caption SHALL use a clear list row background and hide the row separator.

When `budget.expenseItems` is non-empty but the Current section's filtered array is empty (i.e. the budget has past-period expenses only), the Current section SHALL render a centered, subheadline-font, tertiary-foreground caption keyed under `budgetDetail.currentPeriod.empty.<period>` ("Nothing logged today" / "Nothing logged this week" / "Nothing logged this period" / "Nothing logged this month"). The caption row SHALL set `listRowBackground(Color("CellBackground"))` and hide the row separator. The Past section SHALL still render with its expense rows.

#### Scenario: Empty budget shows the "no expenses logged yet" caption

- **WHEN** `budget.expenseItems.isEmpty`
- **THEN** the screen renders a single section with the centered "No expenses logged yet." caption, no Current/Past sections, and no swipe targets

#### Scenario: Past-only budget shows period-aware Current empty caption

- **WHEN** the budget has expenses but none are in the current period
- **THEN** the Current section header shows its period-aware title and the section body shows the period-aware "Nothing logged …" caption; the Past section continues to render its expense rows

---

### Requirement: Each expense row displays name, formatted relative date, amount, and Add-Funds visual treatment

The private `ExpenseRowView` SHALL render an `HStack` with:

- A leading `VStack(alignment: .leading)` containing:
  - The expense name in body font (up to 3 lines), or — if `name == nil` — an italicized placeholder body-font caption keyed `budgetDetail.expenseRow.unnamed` (en-US "Untitled expense") in secondary foreground.
  - The expense `date` formatted via `Date.formattedForExpenseList()` (Today / Yesterday / locale-aware date+time) in caption font with secondary foreground.
- A trailing amount label rendering `expense.displayAmount` (the absolute value of `expense.amount`) formatted with the budget's `currencyCode` and `AppSettings.currencyDisplay`, in body font with `monospacedDigit`. When `expense.isAddFunds == true` (i.e. `expense.amount < 0`), the amount foreground SHALL be `Color.moneySurplus`; otherwise the primary text color.

Row vertical padding SHALL scale via `@ScaledMetric` relative to `.body`.

The row SHALL collapse to a single accessibility element via `accessibilityElement(children: .combine)` and provide the composed label specified by the next requirement.

#### Scenario: Named expense row renders name, date, and amount

- **WHEN** an expense has a non-nil `name`
- **THEN** the row shows the name (body font, up to 3 lines), the formatted relative date (caption, secondary), and the formatted absolute amount (body, monospacedDigit, primary color)

#### Scenario: Unnamed expense row uses italic placeholder

- **WHEN** an expense has `name == nil`
- **THEN** the row shows the italicized localized "Untitled expense" placeholder (key `budgetDetail.expenseRow.unnamed`) in secondary foreground in place of the name

#### Scenario: Add-funds row uses surplus color

- **WHEN** an expense has `amount < 0` (i.e. `isAddFunds == true`, F-6.01 display path)
- **THEN** the trailing amount text uses `Color.moneySurplus` and renders the absolute value of the amount

---

### Requirement: Each expense row provides a composed VoiceOver label distinguishing add-funds from expenses

The combined accessibility element SHALL provide a localized label that includes the formatted absolute amount, the expense name (or the localized "Untitled expense" placeholder when nil), and the formatted relative date. The label SHALL use distinct keys for the two semantic cases:

- `budgetDetail.expenseRow.accessibilityLabel` for `isAddFunds == false` (en-US: "%@, %@, %@" — amount, name, date).
- `budgetDetail.expenseRow.accessibilityLabel.addFunds` for `isAddFunds == true` (en-US: "%@ added, %@, %@" — amount, name, date).

#### Scenario: Expense row VoiceOver label

- **WHEN** VoiceOver focuses a row whose `expense.amount > 0`
- **THEN** the announced label uses key `budgetDetail.expenseRow.accessibilityLabel` and contains the formatted absolute amount, the resolved name (or "Untitled expense"), and the formatted relative date

#### Scenario: Add-funds row VoiceOver label

- **WHEN** VoiceOver focuses a row whose `expense.amount < 0`
- **THEN** the announced label uses key `budgetDetail.expenseRow.accessibilityLabel.addFunds` and contains the formatted absolute amount followed by "added" (per the catalog string), then the resolved name and date

---

### Requirement: Trailing swipe immediately deletes one expense without confirmation

Each expense row SHALL expose a trailing `swipeActions(edge: .trailing, allowsFullSwipe: true)` containing exactly one destructive `Button` whose label is a `Label` composed of the localized title `budgetDetail.deleteExpense.swipeAction` (en-US "Delete") and the SF Symbol `trash`. Activating the swipe button (partial swipe + tap, or full trailing swipe) SHALL immediately call `deleteExpense(_:)` on the tapped expense.

There is no confirmation dialog for swipe-initiated expense deletion. The `@State` properties `expenseToDelete` and `showDeleteConfirm` SHALL NOT exist on `BudgetDetailView`.

On invocation, within a single `withAnimation` block, the system SHALL `context.delete(expense)` and call `ModelContext.save()` exactly once, then re-invoke `BudgetLifecycleService.refreshAndSave(_:settings:context:)`. The Budget itself SHALL NOT be modified except by the lifecycle service's normal roll-and-persist behavior.

The four localization keys that existed solely for the removed confirmation dialog SHALL NOT be present in `Localizable.xcstrings`:
- `budgetDetail.deleteExpense.dialog.title`
- `budgetDetail.deleteExpense.dialog.confirm`
- `budgetDetail.deleteExpense.dialog.message`
- `budgetDetail.deleteExpense.dialog.message.unnamed`

#### Scenario: Full trailing swipe immediately deletes the expense

- **WHEN** the user performs a full trailing swipe on an expense row
- **THEN** the expense is immediately deleted from the store; no confirmation dialog is presented

#### Scenario: Partial swipe button tap immediately deletes the expense

- **WHEN** the user partially swipes a row to reveal the red Delete button and taps it
- **THEN** the expense is immediately deleted from the store; no confirmation dialog is presented

#### Scenario: Deletion removes only the targeted expense

- **WHEN** swipe-delete is invoked on one expense row
- **THEN** that `ExpenseItem` is removed from the store, `ModelContext.save()` is called exactly once, no sibling `ExpenseItem`s are affected, and the lifecycle service is re-invoked so the header re-derives `remaining`

#### Scenario: Localized delete button label is unchanged

- **WHEN** the user trailing-swipes any expense row
- **THEN** the action button label reads the localized string under key `budgetDetail.deleteExpense.swipeAction` (en-US "Delete") and uses the `trash` SF Symbol

---

### Requirement: Eager lifecycle refresh on task, scene-active, and expense-count change

The screen SHALL invoke `BudgetLifecycleService.refreshAndSave(_:settings:context:)` for the bound `Budget` on three triggers:

1. `.task(id: budget.persistentModelID)` — initial load and identity changes.
2. `onChange(of: scenePhase)` when the new phase equals `.active`.
3. `onChange(of: budget.expenseItems.count)` — every insert or delete from the Add Expense sheet, swipe-to-delete, or Reset Budget operation.

The screen SHALL bind the returned `BudgetLifecycleResult` to a `@State` property and use it to drive the header `remaining`, `carryOverAmount`, and `periodStart` (used by the section partitioning). The screen SHALL NOT call `BudgetCalculator.rollCarryOver` or `checkScheduledReset` directly — `BudgetLifecycleService` is the sole entry point for the eager sequence (consistent with `docs/tech-design-doc.md` §5.4).

When the lifecycle result is unavailable (initial state before the first call returns), the screen MAY fall back to the budget's persisted `carryOverAmount` for chip rendering and SHALL evaluate the section partitions as empty arrays (showing the empty-budget caption) until the result resolves.

#### Scenario: Refresh on screen appearance

- **WHEN** `BudgetDetailView` first appears for a budget
- **THEN** `BudgetLifecycleService.refreshAndSave` is called once within `.task(id: budget.persistentModelID)` and the returned `remaining`, `carryOverAmount`, and `periodStart` are bound to the view's state

#### Scenario: Refresh on scene activation

- **WHEN** the app transitions from `.inactive` or `.background` to `.active` while `BudgetDetailView` is visible
- **THEN** `BudgetLifecycleService.refreshAndSave` is invoked again so any boundaries crossed while the app was inactive are applied before the next render

#### Scenario: Refresh on expense count change

- **WHEN** `budget.expenseItems.count` changes (via Add Expense sheet, swipe-to-delete, or Reset Budget confirmation)
- **THEN** `BudgetLifecycleService.refreshAndSave` is invoked so the header re-derives `remaining` and the section partitioning re-evaluates against the latest set

#### Scenario: Refresh keyed by persistentModelID for row recycling

- **WHEN** the bound `Budget` value changes identity (e.g. navigating away and back to a different budget that recycles the view)
- **THEN** the `.task(id:)` is re-run so the lifecycle is computed for the new budget

---

### Requirement: All user-visible strings are registered for localization with translator context

Every user-visible string introduced by `BudgetDetailView`, `BudgetDetailView+ExpenseSection.swift`, and the supporting `Date.formattedForExpenseList()` helper SHALL use `String(localized:defaultValue:comment:)` (or the equivalent `Text(_, comment:)` initializer that reads a String Catalog entry) with a stable kebab/dot-cased key, an en-US default value, and a non-empty `comment:`. All keys SHALL be present in `Resources/Localizable.xcstrings`.

The Reset Budget dialog body (`budgetDetail.resetBudget.dialog.message`) SHALL be a single `stringUnit` entry in the catalog (no plural buckets, no format placeholders). The Swift call site SHALL use `Text("budgetDetail.resetBudget.dialog.message", comment: …)` with no string interpolation.

When copy genuinely varies by count in other features, count-driven plurals MAY use Xcode String Catalog plural variations (CLDR `one` / `other` per locale) per `docs/tech-design-doc.md` §5.1; this screen's Reset Budget message intentionally avoids a count to keep catalog and call sites simple.

The keys for the period-aware section titles, section empty captions, and the inline period name in the header VoiceOver label SHALL use **dedicated** per-period keys (`budgetDetail.section.current.<period>`, `budgetDetail.section.past.<period>`, `budgetDetail.currentPeriod.empty.<period>`, `period.<period>.inline`). Inline forms SHALL NOT be derived from list-label forms via `.lowercased()`.

#### Scenario: Reset Budget dialog message is a plain catalog string

- **WHEN** the catalog editor inspects key `budgetDetail.resetBudget.dialog.message` for a locale
- **THEN** the entry is a single localized `stringUnit` with translator `comment:` and no `%lld` or plural-variation structure

#### Scenario: All keys present in the catalog

- **WHEN** the app is built
- **THEN** `Resources/Localizable.xcstrings` contains entries with `comment:` text for every key referenced by `BudgetDetailView`, `BudgetDetailView+ExpenseSection.swift`, and the new `date.today` / `date.yesterday` helpers

#### Scenario: Reset Budget dialog call site has no count branch

- **WHEN** auditing `BudgetDetailView.swift` for the Reset Budget confirmation `message` closure
- **THEN** the body uses only `Text("budgetDetail.resetBudget.dialog.message", comment: …)` with no `budget.expenseItems.count` interpolation and no Swift-side plural branching for that dialog

---

### Requirement: Six SwiftUI previews exercise the visual matrix in DEBUG builds

`BudgetDetailView.swift` SHALL provide, gated by `#if DEBUG`, six `#Preview` declarations exercising:

1. Daily budget with current-period-only expenses (`detailDailyCurrentOnly`).
2. Monthly budget with mixed current-and-past expenses across two prior months (`detailMonthlyCurrentAndPast`).
3. Weekly budget with past-period-only expenses (`detailWeeklyPastOnly`).
4. Empty weekly budget (`detailWeeklyEmpty`).
5. Monthly budget with `isCarryOverEnabled == false` (`detailMonthlyCarryOverDisabled`).
6. Weekly over-budget budget rendered in dark mode (`detailWeeklyOverBudget`).

Each preview SHALL host the view inside a `NavigationStack`, install an `InMemoryModelContainer.makeEmpty()` model container, inject a `Router()` and `AppSettings()` into the environment, and seed the container via `DebugData.insertDetail(_:into:)`.

The preview fixtures SHALL live in `Previews/BudgetDetailFixtures.swift` as `DebugData` extension methods, each accepting an optional `now: Date = Date()` anchor for deterministic snapshots.

#### Scenario: Previews compile and render the visual matrix

- **WHEN** the developer opens `BudgetDetailView.swift` in Xcode's Canvas
- **THEN** all six previews render without runtime errors and exercise: header on-budget, header over-budget, empty state, current-empty + past-only state, current+past with section total, carry-over chip on, carry-over chip off, dark mode

#### Scenario: Fixtures isolated to DEBUG builds

- **WHEN** building for Release
- **THEN** the contents of `Previews/BudgetDetailFixtures.swift` are excluded by the `#if DEBUG` gate and contribute no code to the shipping binary

---

### Requirement: Tapping an expense row pushes AddEditExpenseView in Edit mode

Each expense row rendered in `BudgetDetailView` SHALL be wrapped in a tappable affordance (a `Button` with `.buttonStyle(.plain)`) whose action appends `AppRoute.expenseDetail(expense)` to `router.path`. `RootView` SHALL resolve that route to `AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))`, presenting the screen as a push within the `NavigationStack`.

The row's visual appearance SHALL be unchanged from the non-tappable state — `.buttonStyle(.plain)` ensures no system button highlighting is applied. Swipe actions (trailing swipe-to-delete) SHALL continue to function because SwiftUI's swipe gesture takes priority over the tap gesture on list rows, and the `.swipeActions` modifier is applied outside the `Button` wrapper.

In Edit mode, `AddEditExpenseView` provides a trailing Save toolbar button only (no Cancel button — see the `add-edit-expense-screen` spec); the system back button serves as the discard path.

#### Scenario: Tapping a current-period expense row pushes the edit view

- **WHEN** the user taps an expense row in the Current section of `BudgetDetailView`
- **THEN** `AppRoute.expenseDetail(expense)` is appended to `router.path` and `RootView` pushes `AddEditExpenseView` seeded with that `ExpenseItem`

#### Scenario: Tapping a past-period expense row pushes the edit view

- **WHEN** the user taps an expense row in the Past section of `BudgetDetailView`
- **THEN** `AppRoute.expenseDetail(expense)` is appended to `router.path` and `RootView` pushes `AddEditExpenseView` seeded with that `ExpenseItem`

#### Scenario: Swipe-to-delete still works on tappable rows

- **WHEN** the user trailing-swipes an expense row (which is now wrapped in a tap `Button`)
- **THEN** the swipe delete action is presented (not the tap navigation); the expense is not navigated to

#### Scenario: Expense row visual appearance is unchanged

- **WHEN** the expense list renders in `BudgetDetailView`
- **THEN** each expense row retains its existing layout (name, relative date, amount, add-funds tint) with no visible button highlight, chevron disclosure indicator, or other affordance added by the tap wrapper

#### Scenario: Save from pushed edit view returns to Budget Detail with changes persisted

- **WHEN** the user taps an expense row, edits a field, and taps Save
- **THEN** the edit is persisted, the pushed view is popped, and the user is returned to `BudgetDetailView` where the expense row reflects the updated values

#### Scenario: VoiceOver treats each expense row as a button

- **WHEN** VoiceOver focuses an expense row
- **THEN** it announces the button trait (because the row is wrapped in a `Button`) in addition to the existing combined accessibility label (amount, name, date)
