## 1. Confirm and tighten the staged ViewModel and View

The branch already contains `simple-recurring-budgets/Views/AddEditExpenseView.swift` (uncommitted, ~380 lines, defining both `AddEditExpenseViewModel` and `AddEditExpenseView`). These tasks audit, fix the latent issues (Decisions 4–7), and lock in the structure so the spec scenarios pass. **No layout, formatting, or English-copy changes are permitted by this change** — the user has approved what shipped.

- [x] 1.1 Verify `AddEditExpenseViewModel` declares `@Observable @MainActor final class AddEditExpenseViewModel` with stored properties `var amount: Decimal?`, `var name: String`, `var date: Date`, `let currencyCode: String`, plus a private `mode: Mode` enum (`case add(Budget)` / `case edit(ExpenseItem)`) and a computed `var isEditing: Bool`. Confirm the VM has NO stored property of type `ModelContext` and NO stored property of type `AppSettings`.
- [x] 1.2 Verify `init(adding budget: Budget)` seeds: `amount = nil`, `name = ""`, `date = Date()`, `currencyCode = budget.currencyCode`, `mode = .add(budget)`. (The staged code already does this; this task is verification only.)
- [x] 1.3 Verify `init(editing expense: ExpenseItem)` seeds: `amount = expense.displayAmount`, `name = expense.name ?? ""`, `date = expense.date`, `currencyCode = expense.budget?.currencyCode ?? (Locale.current.currency?.identifier ?? "USD")`, `mode = .edit(expense)`. (The staged code already does this; this task is verification only.)
- [x] 1.4 Verify the pure computed property `var canSave: Bool { (amount ?? 0) > 0 }` — exactly the rule from spec "Save is enabled only when amount is strictly positive". (The staged code already does this; verification only.)
- [x] 1.5 **Apply the Edit-mode sign-preservation fix (Decision 4 / spec "Edit-mode Save preserves the sign of ExpenseItem.amount").** Edit `save(context:)` in `AddEditExpenseView.swift` so the Edit branch:
    - Computes `trimmedName` per task 1.6 (whitespace-trimmed, with `nil` when trimmed-empty).
    - Compares amount as `expense.displayAmount != newAmount`, NOT `expense.amount != newAmount`.
    - Writes the model field as `expense.amount = expense.isAddFunds ? -newAmount : newAmount`.
    - Keeps the existing date comparator (`Calendar.current.isDate(_:equalTo:toGranularity: .minute)`) unchanged.
    - Sets `expense.lastModified = Date()` exactly once iff at least one field changed; calls `try? context.save()` exactly once iff at least one field changed.
- [x] 1.6 **Apply the description-trimming fix (Decision 7 / spec "Form fields are Amount, Description (optional), and When").** Replace the staged `let trimmedName: String? = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name` (which stores the *un*trimmed value when non-empty) with `let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines); let trimmedName: String? = trimmed.isEmpty ? nil : trimmed`. Apply this in both Add and Edit branches of `save(context:)`.
- [x] 1.7 Verify Add-mode `save(context:)` persists exactly one `ExpenseItem(amount:name:date:)` with `expense.budget = budget` and `try? context.save()`. Confirm there is a `guard canSave, let amount else { return }` defensive check at the top of the Add branch. (The staged code already does this; verification only — but tighten the comment to cite the spec requirement.)
- [x] 1.8 Verify `delete(context:)`:
    - In Edit mode: calls `context.delete(expense)` and `try? context.save()`.
    - In Add mode: returns immediately with no side effects (use `guard case let .edit(expense) = mode else { return }`). (The staged code already does this; verification only.)
- [x] 1.9 **Apply the Edit-mode auto-focus fix (Decision 5 / spec "Add mode auto-focuses the Amount field; Edit/View mode does not").** Edit the `body`'s `.onAppear` in `AddEditExpenseView.swift` from `.onAppear { isAmountFocused = true }` to:
    ```swift
    .onAppear {
      if !viewModel.isEditing {
        isAmountFocused = true
      }
    }
    ```
- [x] 1.10 Confirm the staged view structure is intact and unchanged otherwise:
    - `NavigationStack { ScrollView { VStack(spacing: 16) { amountCard; nameCard; whenCard; if viewModel.isEditing { deleteButton } } ... } }`
    - Inline navigation title from `addEditExpense.title.add` / `addEditExpense.title.existing` keyed on `viewModel.isEditing`.
    - Toolbar: leading Cancel from `addEditExpense.action.cancel`, trailing Save from `addEditExpense.action.save` with `.disabled(!viewModel.canSave)` and `.fontWeight(.semibold)`.
    - `.appBackground()` modifier on the `ScrollView`.
    - The destructive `confirmationDialog(...)` is attached at the sheet root (NOT inside the `if viewModel.isEditing` block) so the dialog flag is owned by `AddEditExpenseView` regardless of mode and does not break SwiftUI's modal-presentation tracking.
- [x] 1.11 Verify each card uses the existing keys without alteration:
    - Amount card: `addEditExpense.section.amount`, `addEditExpense.field.amount.placeholder`, `addEditExpense.field.amount.accessibilityLabel`. Currency prefix derived via `settings.currencyDisplay.prefix(for: viewModel.currencyCode)` from `@Environment(AppSettings.self) private var settings`.
    - Description card: `addEditExpense.section.name`, `addEditExpense.field.name.placeholder`, `addEditExpense.field.name.accessibilityLabel`.
    - When card: `addEditExpense.section.when`, `addEditExpense.field.date.label` (used as the `DatePicker`'s underlying label, hidden by `.labelsHidden()`).
- [x] 1.12 Verify the destructive Delete button uses keys `addEditExpense.action.delete` and `addEditExpense.action.delete.accessibilityHint`, and the confirmation dialog uses `addEditExpense.deleteConfirmation.{title,message,confirm}` with `role: .destructive` and `titleVisibility: .visible`. (The staged code already does this; verification only.)

## 2. Decide where `OptionalDecimalFormatStyle` lives (testability)

The staged code declares `OptionalDecimalFormatStyle` and `OptionalDecimalParseStrategy` as file-private types inside `AddEditExpenseView.swift`. Tests need to call into them. Pick one option below and apply it.

- [x] ~~2.1 Pick **option A**~~ (chose option B instead) (`@testable import`-friendly): change `private struct OptionalDecimalFormatStyle` and `private struct OptionalDecimalParseStrategy` to internal (drop `private`) so they are reachable from the test target via `@testable import simple_recurring_budgets`. Leave the file location unchanged. **Superseded by 2.2 — checkbox closed for archive.**
- [x] 2.2 Pick **option B** (extracted helper): move the two structs to a new file `simple-recurring-budgets/Formatting/OptionalDecimalFormatStyle.swift` with `internal` access. Add a brief doc comment ("Used by `AddEditExpenseView`'s Amount field to allow blank input to map to `Decimal?` rather than `0`."). Update `AddEditExpenseView.swift` to import nothing additional (same target).
- [x] 2.3 Whichever option is chosen, the implementer SHALL document the choice in the implementation PR description so reviewers know where to find the type.

## 3. Wire `RootView` (already staged — verify only)

- [x] 3.1 Verify `simple-recurring-budgets/Views/RootView.swift` resolves `case let .addExpense(budget): AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget))` and `case let .expense(expense): AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))` in the `.sheet(item:)` switch. (The staged diff already shows this; verification only.)
- [x] 3.2 Verify `RootView`'s doc-comment header references `AddEditExpenseView` for F-2.04 only (the F-2.03 reference belongs to Add/Edit Budget) so the comment correctly identifies the owning feature.
- [x] 3.3 Confirm `RootView` does NOT need any new `@Environment` injections beyond the existing `Router` and `AppSettings` (which were already added by the Add/Edit Budget change). The expense screen reads its `ModelContext` and `AppSettings` from its own environment scope.
- [x] 3.4 Confirm the existing `RootView` `#Preview` still injects `Router`, `AppSettings`, `SyncStatus`, and `modelContainer`. No new preview injections are required by this change.

## 4. Localization — `Resources/Localizable.xcstrings` (already staged — verify only)

The staged catalog already contains all 17 `addEditExpense.*` keys. These tasks verify that no new keys are needed and that translator comments are in place.

- [x] 4.1 Run `rg "Text\(\""` and `rg "String\(\""` against `simple-recurring-budgets/Views/AddEditExpenseView.swift` (and the optional new `OptionalDecimalFormatStyle.swift`) to confirm no hard-coded English strings remain.
- [x] 4.2 Verify `Localizable.xcstrings` contains entries for each of these keys, each with a non-empty `comment`:
    - `addEditExpense.title.add`, `addEditExpense.title.existing`
    - `addEditExpense.action.cancel`, `addEditExpense.action.save`, `addEditExpense.action.delete`, `addEditExpense.action.delete.accessibilityHint`
    - `addEditExpense.deleteConfirmation.title`, `addEditExpense.deleteConfirmation.message`, `addEditExpense.deleteConfirmation.confirm`
    - `addEditExpense.section.amount`, `addEditExpense.section.name`, `addEditExpense.section.when`
    - `addEditExpense.field.amount.placeholder`, `addEditExpense.field.amount.accessibilityLabel`
    - `addEditExpense.field.name.placeholder`, `addEditExpense.field.name.accessibilityLabel`
    - `addEditExpense.field.date.label`
- [x] 4.3 Confirm none of the `addEditExpense.*` keys reuse `addEditBudget.*` content paths (per the spec requirement that namespaces are not crossed).

## 5. Tests (Swift Testing) — `simple-recurring-budgetsTests/Views/AddEditExpenseViewModelTests.swift`

Create the test file under `simple-recurring-budgetsTests/Views/` (the directory exists; sibling files include `AddEditBudgetViewModelTests.swift`, `BudgetsViewTests.swift`, `CurrencyPickerTests.swift`, `SettingsViewTests.swift`). Use `@MainActor` `@Test` cases against an in-memory `ModelContainer` from `simple-recurring-budgetsTests/Helpers/TestModelContainer.swift`.

- [x] 5.1 **Add-mode defaults** (`init(adding:)`): construct an in-memory `Budget` with `currencyCode = "USD"`. Build the VM. Assert: `amount == nil`, `name == ""`, `date` within ~5 seconds of a fresh `Date()`, `currencyCode == "USD"`, `isEditing == false`, `canSave == false`.
- [x] 5.2 **Edit-mode seeding (positive amount)** (`init(editing:)`): construct a `Budget` with `currencyCode = "USD"` and an `ExpenseItem(amount: 4.50, name: "Morning coffee", date: someFixedDate)` attached to it. Build the VM. Assert: `amount == 4.50`, `name == "Morning coffee"`, `date == someFixedDate`, `currencyCode == "USD"`, `isEditing == true`, `canSave == true`.
- [x] 5.3 **Edit-mode seeding (negative amount, isAddFunds)**: construct a `Budget` and an `ExpenseItem(amount: -10, name: "Reimbursement", date: someFixedDate)`. Build the VM. Assert: `amount == 10` (absolute value), `name == "Reimbursement"`, `isEditing == true`, `canSave == true`. (The seed does NOT carry the sign through.)
- [x] 5.4 **Edit-mode seeding (orphan expense)**: construct an `ExpenseItem` with no `budget` reference (insert standalone, do NOT attach). Build the VM. Assert `currencyCode` falls back to `Locale.current.currency?.identifier ?? "USD"` (use whichever the test env reports) — assertion checks the value matches `Locale.current.currency?.identifier ?? "USD"` via direct comparison.
- [x] 5.5 **`canSave` enumeration**: parameterize a `@Test` (or use multiple `@Test` cases) with the matrix:
    - `amount = nil` → `canSave == false`.
    - `amount = 0` → `canSave == false`.
    - `amount = -1` (set programmatically via `vm.amount = -1`) → `canSave == false`.
    - `amount = 5.00`, `name = ""` → `canSave == true`.
    - `amount = 5.00`, `name = "Coffee"` → `canSave == true`.
- [x] 5.6 **Add-mode `save(context:)` inserts the expense attached to the budget**: build a VM with `init(adding: budget)`, set `amount = 5.00`, `name = "Coffee"`, `date = fixedDate`, then call `save(context:)`. Use a `FetchDescriptor<ExpenseItem>` to read all expenses; assert exactly one row exists with `amount == 5.00 && amount > 0`, `name == "Coffee"`, `date == fixedDate`, `budget == budget`.
- [x] 5.7 **Add-mode `save(context:)` trims and nullifies description**: build a VM with `init(adding: budget)`, set `amount = 5.00`. Test cases:
    - `name = "  Coffee  "` → after `save`, the inserted `ExpenseItem.name == "Coffee"`.
    - `name = "   "` → after `save`, the inserted `ExpenseItem.name == nil`.
    - `name = ""` → after `save`, the inserted `ExpenseItem.name == nil`.
- [x] 5.8 **Add-mode `save(context:)` guards on `!canSave`**: build a VM with `init(adding: budget)`, leave `amount = nil`, call `save(context:)`. Assert no `ExpenseItem` is inserted (`FetchDescriptor<ExpenseItem>.count == 0`).
- [x] 5.9 **Edit-mode no-op `save(context:)` does not bump `lastModified`**: build a VM via `init(editing: expense)`, capture `let original = expense.lastModified`, immediately call `save(context:)`. Assert `expense.lastModified == original`.
- [x] 5.10 **Edit-mode `save(context:)` single-field change (description)**: build a VM via `init(editing: expense)` for a positive-amount expense, capture `let original = expense.lastModified`, set `vm.name = "New name"`, call `save(context:)`. Assert: `expense.name == "New name"`, `expense.lastModified > original`, `expense.amount` is unchanged, `expense.date` is unchanged.
- [x] 5.11 **Edit-mode `save(context:)` sign preservation (negative row, amount changed)**: build an `ExpenseItem(amount: -10)`, build a VM via `init(editing: expense)` (so `vm.amount == 10`), set `vm.amount = 15`, call `save(context:)`. Assert `expense.amount == -15` (sign restored).
- [x] 5.12 **Edit-mode `save(context:)` sign preservation (negative row, amount unchanged)**: build an `ExpenseItem(amount: -10)`, build a VM via `init(editing: expense)` (so `vm.amount == 10`), capture `let original = expense.lastModified`, leave `vm.amount` at `10`, call `save(context:)`. Assert: `expense.amount == -10` (no spurious flip), `expense.lastModified == original` (no change detected). This is the regression net for the comparator-asymmetry bug in the staged code.
- [x] 5.13 **Edit-mode `save(context:)` multi-field change**: build a VM via `init(editing: expense)` for a positive expense, set `vm.name = "New name"` AND `vm.amount = 99.99`, call `save(context:)`. Assert both fields are written, and `expense.lastModified > original`. Verify a single coherent `lastModified` value (not two separate writes) by capturing it once after the call and comparing equality across two reads.
- [x] 5.14 **Edit-mode `save(context:)` description trim/nullify on edit**:
    - Build a VM via `init(editing: expense)` for an expense with `name = "Old"`. Set `vm.name = "  New  "`. Save. Assert `expense.name == "New"`.
    - Build a VM via `init(editing: expense)` for an expense with `name = "Old"`. Set `vm.name = "   "`. Save. Assert `expense.name == nil`.
- [x] 5.15 **Edit-mode `save(context:)` sub-minute date drift is no-op**: build a VM via `init(editing: expense)` for an expense with `date = fixedDate`. Set `vm.date = fixedDate.addingTimeInterval(20)` (20 seconds later). Capture `let original = expense.lastModified`. Save. Assert `expense.lastModified == original` (no change, sub-minute granularity).
- [x] 5.16 **Cancel semantics**: build a VM via `init(editing: expense)`, capture all original fields (`amount`, `name`, `date`, `lastModified`), mutate `vm.amount`, `vm.name`, `vm.date`, do NOT call `save(context:)`, then re-read `expense`. Assert all four fields equal the pre-mutation values.
- [x] 5.17 **Delete in Edit mode**: build a VM via `init(editing: expense)` against an in-memory store with one or more `ExpenseItem`s. Call `delete(context:)`. Assert: a `FetchDescriptor<ExpenseItem>` no longer returns the deleted expense; the count of remaining expenses is `originalCount - 1`.
- [x] 5.18 **Delete in Add mode is a no-op**: build a VM via `init(adding: budget)` against an in-memory store containing pre-existing expenses. Call `delete(context:)`. Assert the store contents are unchanged: `FetchDescriptor<ExpenseItem>.count == originalCount`.
- [x] 5.19 **`OptionalDecimalFormatStyle` parsing**: in the same file (or a sibling `simple-recurring-budgetsTests/Formatting/OptionalDecimalFormatStyleTests.swift`):
    - Empty string parses to `nil`.
    - Whitespace-only string (`"   "`) parses to `nil`.
    - Valid string parses to `Decimal` (use a deterministic `Decimal(string:)` round-trip; if locale matters and the parse strategy has no locale seam, document that as a follow-up — see Decision 12 / Risks).
    - Malformed string (e.g. `"abc"`) throws `CocoaError(.formatting)` (use `#expect(throws:)`).
    The parse strategy access modifier must be `internal` per task 2.1 / 2.2; if it is still `private`, fix that first.
- [x] 5.20 **Save signature negative test (compile-time)**: assert via a compile-time call site that `viewModel.save(context: context)` is the canonical shape and that no overload accepts `AppSettings`. Mirrors `AddEditBudgetViewModelTests.swift` task 7.1.i.
- [x] 5.21 **Delete signature negative test (compile-time)**: assert via a compile-time call site that `viewModel.delete(context: context)` is the canonical shape and that no overload accepts `AppSettings`.

## 6. Documentation updates

- [x] 6.1 Edit `docs/product-features-planning.md` F-2.04 (Add/Edit/View Expense Item screen): change `**Status:** Open` → `**Status:** Implemented`. Add a one-line implementation note pointing at this change name (`add-edit-expense-screen`). In the Edge Cases / Notes section, replace `None` with two short notes:
    1. "The screen treats Edit and View as a single mode (per the AC's 'No Edit Mode' rule); fields are always directly editable. There is no read-only mode toggle."
    2. "Edit-mode Save preserves the sign of `ExpenseItem.amount`, so existing F-6.01 add-funds rows survive an edit without flipping to a positive expense. Add mode unconditionally inserts a non-negative amount; the Add Funds toggle UI is part of F-6.01's future change."
- [x] 6.2 Confirm `docs/tech-design-doc.md` needs no edit. The VM pattern matches §2.1's existing rule established by `AddEditBudgetViewModel`. **No version-history bump for this change.** If implementation surfaces a genuinely new architectural rule (it should not), append a note here describing what changed and why.
- [x] 6.3 Confirm `docs/main-prd.md` needs no edit. Grep for "Add Funds", "Expense", "carry-over", "F-2.04", "F-6.01" — the global constraints (§6.4, §6.5, §6.7) are untouched.
- [x] 6.4 Confirm `docs/ux-design-brief.md` needs no edit. The brief's mention of the high-frequency Add/Edit Expense capture surface already describes this screen.

## 7. Build, test, and smoke-check

- [x] 7.1 Run `make test` (or `bash scripts/test.sh`) per `AGENTS.md` and `.cursor/rules/ios-build-test.mdc`. All existing tests SHALL pass; the new `Views/AddEditExpenseViewModelTests.swift` cases SHALL pass.
- [x] 7.2 Smoke test on a clean iPhone simulator (matrix from design.md → Migration Plan §4):
    - **7.2.a** Open a budget → tap row Add → Add Expense sheet opens with empty Amount, empty Description, current Date/Time, currency prefix matching the budget's currency under the user's `currencyDisplay` mode. Amount field is auto-focused (keyboard pops).
    - **7.2.b** Add sheet → leave Amount blank → Save disabled. Type `0` → Save still disabled. Type `5.00` → Save enabled. Tap Save → expense appears in the budget's expense list with the typed values.
    - **7.2.c** Add sheet → type a description with leading/trailing spaces → Save → the persisted description has whitespace trimmed.
    - **7.2.d** Edit sheet (via the F-2.02 entry point, or a temporary preview hook until F-2.02 ships): opens pre-filled with the expense's values; Amount field is NOT auto-focused (no keyboard pop); Delete button is rendered below the cards.
    - **7.2.e** Edit sheet → change nothing → Save → `lastModified` unchanged (verifiable via debug print or via the unit test in §5.9).
    - **7.2.f** Edit sheet → change the date by less than a minute (nudge seconds) → Save → `lastModified` unchanged.
    - **7.2.g** Edit sheet → tap Delete → confirmation dialog appears with the expected title, message, destructive button, and SwiftUI's implicit Cancel. Tap Cancel → dialog dismisses, sheet remains, expense is intact. Tap Delete Expense → dialog dismisses, sheet dismisses, expense is removed from the store.
    - **7.2.h** Edit sheet on a *negative-amount* `ExpenseItem` (constructed via a temporary `DebugData` seed or an inline insertion against the in-memory container): the Amount field shows the absolute value; change the amount, Save → the persisted `expense.amount` retains its negative sign.
    - **7.2.i** Cancel from any state → no `ExpenseItem` is inserted, modified, or deleted.
    - **7.2.j** Toggle `AppSettings.currencyDisplay` in Settings → reopen Add Expense sheet → currency prefix on the Amount card reflects the new preference.
    - **7.2.k** VoiceOver enabled → focus the Delete Expense button → hear the destructive hint from `addEditExpense.action.delete.accessibilityHint`.
    - **7.2.l** Dynamic Type at `xxxLarge` → cards reflow without clipping; the date picker remains usable.
    - **7.2.m** Dark Mode → no surface reads as a hard-coded white card; backgrounds use `appBackground()` / `Color("CellBackground")`.
- [x] 7.3 Run `rg "Text\(\""` and `rg "String\(\""` over the entire `simple-recurring-budgets/Views/AddEditExpenseView.swift` file (and the optional extracted format-style file) as a final residual check; expect zero hard-coded English strings outside `String(localized:defaultValue:comment:)` / `Text(LocalizedStringKey(...))` call sites.

## 8. Archive this change

- [x] 8.1 After all sections 1–7 are complete (run `/opsx-archive` to complete) and `make test` passes, run `openspec archive add-edit-expense-screen` (or follow the `openspec-archive-change` skill).
- [x] 8.2 Because this change introduces a new capability (`add-edit-expense-screen`) AND modifies an existing one (`app-navigation`), expect the archive to: (a) create `openspec/specs/add-edit-expense-screen/spec.md` from the delta, and (b) update `openspec/specs/app-navigation/spec.md`'s "Placeholder destinations are exempt..." requirement to the new wording.
- [x] 8.3 After archive, confirm: (a) `openspec/specs/add-edit-expense-screen/spec.md` exists with the requirements introduced here; (b) `openspec/specs/app-navigation/spec.md` reflects the modified placeholder requirement (only `AppRoute.budgetDetail(Budget)` remains a placeholder); (c) `openspec/changes/` no longer contains `add-edit-expense-screen/`; (d) `openspec/changes/archive/` contains a date-prefixed `add-edit-expense-screen/` directory with the proposal, design, tasks, and original delta specs preserved.

## Remaining gaps (for change-author awareness — not implementation tasks here)

These items are explicitly **out of scope** for this change but are surfaced to the reviewer so they are not lost:

- **F-2.02 (Budget detail / `AppRoute.budgetDetail`)** — the only remaining placeholder after this change. Until F-2.02 ships, the existing-expense sheet entry point is reachable only from a temporary preview hook or by manually setting `Router.sheet = .expense(expense)` in a debug build. The existing-expense smoke tests in §7.2 acknowledge this.
- **F-6.01 (Add Funds toggle UI)** — the screen handles existing negative-amount rows correctly (sign preservation, Decision 4) but does NOT yet expose an "Add Funds" toggle in Add mode. F-6.01's future change introduces that affordance.
- **F-7.01 (Receipt scanning) / F-7.02 (Voice input)** — both depend on F-2.04 being shipped. Neither is in scope here.
- **Save error UI** — no other screen surfaces save errors today. Adding a dedicated error path is a future cross-cutting concern.
- **iPad / Mac sheet sizing customization** — out of scope; default modal presentation is used.
- **Per-budget icons / emoji / photo on `ExpenseItem`** — F-4.03 / F-4.04 are unrelated future work; `expenseType` and any future receipt-image fields are not edited by this screen.
