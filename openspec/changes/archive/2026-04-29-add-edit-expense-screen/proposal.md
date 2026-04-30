## Why

`F-2.04` (Add/Edit/View Expense Item screen) is the last placeholder in the primary navigation flow. The `RootView` sheet binding rendered bare `Text("Add Expense")` / `Text("View Expense")` strings for `SheetRoute.addExpense(Budget)` and `SheetRoute.expense(ExpenseItem)` (then named `viewExpense` in early scaffolding). With `BudgetsView` already wired up to push an Add Expense sheet from each row, and the in-progress `BudgetView` (F-2.02) preparing to open the same expense sheet from each row of its expense list, this is the next user-facing gap.

A first cut of `AddEditExpenseView` and `AddEditExpenseViewModel` already exists on this branch as uncommitted changes, with finalized formatting, layout, and English copy (Amount / Description / When cards, optional Description, inline title, Save and Cancel toolbar items, destructive Delete button + confirmation in Edit mode). Localized strings are already registered in `Localizable.xcstrings`. **This change retroactively codifies the implementation as the F-2.04 spec, ships tests, fixes the latent issues that the existing code does not yet handle, and updates the relevant docs and modified-capability entries** — without changing the existing layout, formatting, or copy.

## What Changes

- **Codify the Add/Edit/View Expense screen as a new capability** — `add-edit-expense-screen` — capturing the behavior already written in `simple-recurring-budgets/Views/AddEditExpenseView.swift` (the view + `@Observable AddEditExpenseViewModel`). Requirements cover the single-screen Add/Edit/View use case, the three cards (Amount, Description, When), the Save/Cancel toolbar items and Save validation rule, the destructive Delete button + confirmation dialog in Edit mode, the auto-focus-on-Amount behavior, the `currencyDisplay`-aware currency prefix, the per-mode title, and the `@Observable` VM contract (no stored `ModelContext`, save/delete take context at the call site).
- **Wire `RootView` sheet binding to the real screen** — already done on this branch in `simple-recurring-budgets/Views/RootView.swift`. The change formalises the wiring as a spec scenario: `.addExpense(budget)` resolves to `AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget))`; `.expense(expense)` resolves to `AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))`. The `RootView` doc-comment update is part of the same staged change set.
- **Persist on Save** —
    - **Add mode**: build a new `ExpenseItem` from the drafted `amount`/`name`/`date`, attach the in-flight `Budget` (`expense.budget = budget`), `context.insert(expense)`, `try? context.save()`, dismiss.
    - **Edit mode**: write each draft field back to the passed-in `ExpenseItem` only when the value differs (so `lastModified` only bumps if at least one field changed), `try? context.save()`, dismiss. Date comparison uses `.minute` granularity to match the picker's `.hourAndMinute` resolution.
    - **Cancel**: dismiss without persisting any draft.
    - **Delete (Edit mode only)**: `context.delete(expense)`, `try? context.save()`, dismiss. The cascade story is trivial — `ExpenseItem` has no child relationships; only the row itself is removed.
- **Preserve the sign of `ExpenseItem.amount` on Edit-mode Save (latent F-6.01 readiness fix)** — the current implementation seeds the form with `expense.displayAmount` (absolute value) and writes `expense.amount = newAmount` on Save, which silently flips a negative `add-funds` row's sign on any Save. F-6.01 ("Add Funds" via negative `amount`) is **not** yet user-reachable, but the screen will be the editing surface for those rows once F-6.01 ships. The fix preserves the original sign in Edit mode (`expense.amount = expense.isAddFunds ? -newAmount : newAmount`) and is captured as a spec requirement so a future regression is caught. Add-mode unconditionally inserts a positive expense (the user has no Add-Funds affordance on this screen yet — `F-6.01` will introduce that toggle).
- **Tighten Edit-mode auto-focus behavior** — current code unconditionally sets `isAmountFocused = true` in `.onAppear`. Match the Add/Edit Budget pattern (Add mode auto-focuses; Edit mode does not) so the keyboard does not auto-pop when the user is just viewing or editing an existing expense. The spec requires Add mode auto-focus the Amount field; Edit mode SHALL NOT auto-focus.
- **Add tests (Swift Testing)** — `simple-recurring-budgetsTests/Views/AddEditExpenseViewModelTests.swift` covers Add-mode defaults; Edit-mode seeding (including a negative-amount/`isAddFunds` row); `canSave` cases (nil amount, zero amount, positive amount); Add-mode save inserts exactly one row attached to the right budget; Edit-mode save mutates only changed fields, bumps `lastModified` once, and preserves `amount` sign for `isAddFunds` rows; Edit-mode no-op save does not bump `lastModified`; Cancel writes nothing; Delete in Edit mode removes the row and saves once; Delete in Add mode is a no-op. A focused parsing test for the screen's `OptionalDecimalFormatStyle` covers empty input → `nil`, valid `Decimal` parse, and a malformed-string `throw`.
- **Update `openspec/specs/app-navigation/spec.md` Placeholder requirement** — drop `.addExpense(Budget)` and `.expense(ExpenseItem)` from the remaining-placeholder list once F-2.04 ships. The remaining placeholder cases after this change are limited to `AppRoute.budgetDetail(Budget)`. The modified-capability delta block contains the FULL updated requirement text per OpenSpec rules.
- **Update `docs/product-features-planning.md` F-2.04** — flip `**Status:** Open` → `**Status:** Implemented`. Add a brief implementation note pointing at this change name, and confirm the AC line "Same screen is used for add, edit, and view use cases" is met (the screen has no read-only "View" mode — Edit mode IS the View mode per the AC's "No Edit Mode" rule).
- **No schema changes.** `ExpenseItem` already carries every persisted field this screen edits (`amount`, `name`, `date`, `lastModified`). `expenseType` and `isAddFunds` are not edited by this screen.
- **No new Localizable.xcstrings keys.** Every user-visible string was already registered in the staged catalog edits on this branch under the `addEditExpense.*` namespace. The change verifies coverage and translator comments per `docs/tech-design-doc.md` §5.1 but does not introduce additional keys.

## Capabilities

### New Capabilities

- `add-edit-expense-screen`: Behavior contract for the F-2.04 sheet — three-card layout (Amount / Description / When) shared between Add, Edit, and View use cases; Save validation (positive amount); destructive Delete + confirmation dialog in Edit mode only; per-mode title and Add-only auto-focus on Amount; reactive `currencyDisplay` prefix on the Amount card from `AppSettings.currencyDisplay`; `@Observable` VM with `init(adding:)` and `init(editing:)` initialisers and `save(context:)` / `delete(context:)` methods that take the `ModelContext` at the call site; sign-preserving Edit-mode write to support `ExpenseItem.amount` rows that are negative (F-6.01 forward-compatibility); Cancel discards all draft state. The capability does NOT cover the F-6.01 "Add Funds" toggle UI (out of scope until F-6.01 ships) or per-budget receipt scanning (F-7.01) / voice input (F-7.02) — those features depend on F-2.04 but are tracked separately.

### Modified Capabilities

- `app-navigation`: The `RootView` placeholder requirement currently lists `SheetRoute.addExpense(Budget)` and `SheetRoute.expense(ExpenseItem)` among the remaining placeholders. After this change, both cases SHALL render the real, fully-localized `AddEditExpenseView` and the i18n exemption SHALL no longer apply to them. `AppRoute.budgetDetail(Budget)` remains a placeholder until F-2.02 ships.

## Impact

- **New code:**
    - `simple-recurring-budgets/Views/AddEditExpenseView.swift` (already present as a staged uncommitted file on this branch). Edits within this change: defer the auto-focus to Add mode only, and apply the Edit-mode sign-preserving Save.
- **Modified code (already staged on this branch):**
    - `simple-recurring-budgets/Views/RootView.swift` — replace the `.addExpense` / `.expense` `Text(...)` placeholders with `AddEditExpenseView` instances, and update the file's doc comment to reference the screen.
    - `simple-recurring-budgets/Resources/Localizable.xcstrings` — adds the 17 `addEditExpense.*` keys for nav titles, toolbar items, section labels, placeholders, accessibility labels, the date label, and the delete confirmation dialog (already auto-extracted by the build).
- **New tests (Swift Testing):**
    - `simple-recurring-budgetsTests/Views/AddEditExpenseViewModelTests.swift` covering Add/Edit defaults, `canSave`, save semantics in both modes, sign preservation for `isAddFunds` rows, no-op save behavior, Cancel semantics, and Delete behavior in both modes.
    - A focused parsing test for `OptionalDecimalFormatStyle` (empty → `nil`, valid → `Decimal`, malformed → `throw`). Either inline within `AddEditExpenseViewModelTests.swift` or in a sibling `OptionalDecimalFormatStyleTests.swift` — the design.md will pick one.
- **No schema changes.** `ExpenseItem` is untouched. No `VersionedSchema` migration.
- **No CloudKit changes.** No new record types, no new fields, no entitlement edits.
- **No new dependencies.** SwiftUI, SwiftData, and Foundation carry the entire surface area.
- **Localization / Accessibility:**
    - All user-visible strings already in `Localizable.xcstrings` with `comment:` translator context (verified — no new keys needed).
    - VoiceOver labels for the Amount field (`addEditExpense.field.amount.accessibilityLabel`), the Description field (`addEditExpense.field.name.accessibilityLabel`), and the destructive Delete button hint (`addEditExpense.action.delete.accessibilityHint`).
    - The When picker uses SwiftUI's `DatePicker` `.compact` style, which inherits system VoiceOver behavior; the section heading ("When") is announced as the field's label.
    - Dynamic Type: the card layout uses system text styles; previews already include an `xxxLarge` matrix.
    - Dark Mode: all surfaces use `.appBackground()` and `Color("CellBackground")` — no hard-coded hex.
- **Persistence / Sync:** Save in Add mode performs `insert` → `save`. Save in Edit mode performs a single batched `context.save()` for all changed fields, with `lastModified = Date()` set once. Delete in Edit mode performs `context.delete` + `context.save`. All flows propagate through the existing CloudKit pipeline.
- **No new runtime risks beyond the standard form-write failures already accepted across the app** (`try?` save matches `BudgetsView.move(...)` and `AddEditBudgetViewModel.save(...)`; user-recoverable error UI is out of scope, consistent with the rest of the app today).

## Doc alignment

- **Aligned with `docs/main-prd.md`** — PRD §6.4 (Dynamic Type, VoiceOver) and §6.5 (i18n, per-budget currency) are explicit goals of the new screen. PRD §6.7 (Over/Under vs remaining for the current Budget Period) is unaffected — this screen does not display Over/Under itself. Currency prefix on Amount honors the user's `AppSettings.currencyDisplay` preference per the app-wide rule.
- **Aligned with `docs/tech-design-doc.md`**:
    - §2.1 (View + Services, ViewModels on demand) — escalation criterion #1 (form draft state not persisted until commit) applies; the grey-area trigger "more than 3 mutable form fields" does NOT apply here (we have 3 fields: amount, name, date) but criterion #1 alone is sufficient justification, and parity with `AddEditBudgetViewModel` is desirable. Per §2.1 VM rules, `AddEditExpenseViewModel` stores **draft state and pure logic only**, does NOT hold `ModelContext`, and its `save(context:)` / `delete(context:)` methods take the context at the call site.
    - §2.2 (Navigation) — the screen is presented via the existing `Router.sheet = .addExpense(Budget)` / `.expense(ExpenseItem)` pipeline. No new `SheetRoute` cases beyond the two expense routes.
    - §3.1 / §3.2 (Data model) — no schema changes; `ExpenseItem.amount` is `Decimal` and storage is unchanged.
    - §5.1 (Localization) — every new user-visible string lives in `Localizable.xcstrings` with a `comment:`.
- **Aligned with `docs/ux-design-brief.md`** — "Add/Edit Expense (sheet): high-frequency capture — amount, optional description, date/time" matches what shipped: amount-first input with auto-focus in Add mode, optional description, compact date picker, single Save / Cancel toolbar.
- **Aligned with `docs/product-features-planning.md` F-2.04 (Open)** — every acceptance criterion is satisfied by the implementation:
    - "Shows editable name of expense (optional)" → Description card with optional empty value.
    - "Shows editable amount of expense (required)" → Amount card with `canSave` gated on `> 0`.
    - "Shows date and time (prefilled with current date and time)" → When card seeded from `Date()` in Add mode, from `expense.date` in Edit mode.
    - "Same screen is used for add, edit, and view use cases" → one `AddEditExpenseView` shared between `init(adding:)` and `init(editing:)`. Per the next AC, "View" is just Edit mode that the user can read without typing — there is no read-only mode toggle.
    - "No Edit Mode. User should be able to edit fields in place without having to toggle modes." → fields are always editable; no edit/done toggle on the screen.
- **Aligned with `docs/product-features-planning.md` F-6.01 (Add Funds)** — F-6.01 is **not** in scope for this change, but the spec requires Edit-mode Save to preserve the sign of `ExpenseItem.amount` so F-6.01 can later add a negative-amount affordance without retroactively breaking historical add-funds rows on first edit. F-6.01's status remains Open.
- **No conflicts with `docs/*.md`.** Every behavior in the implementation is consistent with the four high-level docs; the only doc edits required are status flips and a small note in F-2.04 (see below).
- **Doc updates required after implementation:**
    - `docs/product-features-planning.md` — flip F-2.04 `**Status:** Open` → `**Status:** Implemented`. Add a one-line implementation note pointing at this change name. Add a clarification under Edge Cases / Notes that the screen treats Edit and View as a single mode (per the AC) and that F-6.01 sign handling is plumbed through but not yet user-reachable.
    - `docs/tech-design-doc.md` — **no edit expected.** The VM pattern matches the rule established in `add-edit-budget-screen` and §2.1 covers it. **No version-history bump for this change.**
    - `docs/main-prd.md` — no edit (no global constraint changes).
    - `docs/ux-design-brief.md` — no edit (the brief already describes this screen).
