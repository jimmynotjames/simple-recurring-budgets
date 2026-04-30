## Context

The app's primary navigation is a `NavigationStack` driven by an `@Observable Router` (`path: [AppRoute]`, `sheet: SheetRoute?`). `RootView` is the sole sheet host. Two sheet routes cover the expense screen — `SheetRoute.addExpense(Budget)` and `SheetRoute.expense(ExpenseItem)` (the latter was originally named `viewExpense`; renamed for F-2.04 single-surface alignment) — both previously rendering bare `Text("Add Expense")` / `Text("View Expense")` placeholders. The Budgets list (`BudgetsView`) already fires `router.sheet = .addExpense(budget)` from a per-row Add button; the in-progress Budget detail screen (F-2.02) is expected to fire `router.sheet = .expense(expense)` from each row of its expense list.

**A first cut of the production screen has already landed on this branch as uncommitted changes** (see `git status`):

- `simple-recurring-budgets/Views/AddEditExpenseView.swift` — a 380-line file containing both `AddEditExpenseViewModel` (`@Observable @MainActor final class`) and `AddEditExpenseView` (the sheet body) plus a private `OptionalDecimalFormatStyle` and a preview matrix.
- `simple-recurring-budgets/Views/RootView.swift` — the `.addExpense` and `.expense` `.sheet(item:)` arms now resolve to real `AddEditExpenseView` instances instead of placeholder text. The file's doc comment was also updated.
- `simple-recurring-budgets/Resources/Localizable.xcstrings` — 17 new `addEditExpense.*` keys for the screen's nav titles, toolbar items, section labels, placeholders, accessibility labels, the date label, and the Delete confirmation dialog.

The design choices for **layout, formatting, and English copy are already finalized** by the user; this change does NOT propose any redesign. The remaining work is:

1. Codify the existing implementation as the F-2.04 spec (so future regressions are caught).
2. Ship tests for `AddEditExpenseViewModel` and the `OptionalDecimalFormatStyle` parser.
3. Fix two latent issues in the staged code that the spec then guards against: (a) Edit-mode auto-focus is too eager, and (b) Edit-mode Save loses the sign of `ExpenseItem.amount` for `isAddFunds` rows.
4. Update the modified `app-navigation` placeholder requirement and the F-2.04 status in `docs/product-features-planning.md`.

The `ExpenseItem` model (`Models/ExpenseItem.swift`) is fixed for this change: `id`, `amount: Decimal` (signed; positive = expense, negative = add-funds per F-6.01), `name: String?`, `date: Date`, `createdAt`, `lastModified`, `expenseType: String?`, `budget: Budget?`. The model exposes `isAddFunds` (`amount < 0`) and `displayAmount` (`abs(amount)`) helpers. There is no parent `Budget → ExpenseItem` cascade question to resolve here — we are deleting the leaf node, not its parent.

`AppSettings.currencyDisplay` is already plumbed into the screen for the Amount card's currency prefix via `settings.currencyDisplay.prefix(for: viewModel.currencyCode)` (matches the precedent set by `AddEditBudgetView` and `BudgetsView`). `Locale.current.currency?.identifier ?? "USD"` is the canonical fallback for currency code resolution; the implementation pulls the currency code from `expense.budget?.currencyCode` first, falling back to the locale on a stale/orphan expense — this is defensive code paths that match `AddEditBudgetViewModel`'s decoding strategy.

Constraints in play:

- `docs/main-prd.md` §6.4 / `docs/tech-design-doc.md` §5.1–§5.2 — Dynamic Type and VoiceOver are baseline. All new strings live in `Localizable.xcstrings` with `comment:`.
- `docs/tech-design-doc.md` §2.1 — "View + Services, ViewModels on demand". Escalation criterion #1 (form draft state not persisted until the user commits) applies. Reusing the same VM-shape established by `AddEditBudgetViewModel` (no stored `ModelContext`, methods take context at the call site) is a strong consistency win.
- `docs/tech-design-doc.md` §3 / §4 — schema is fixed; all writes go through the existing CloudKit pipeline; last-writer-wins is acceptable.
- `docs/ux-design-brief.md` — "calm, tidy, quietly warm." No exclamation marks. SF Symbols only. The Add/Edit Expense screen is explicitly listed as a high-frequency capture surface.
- `docs/product-features-planning.md` F-2.04 — explicit acceptance criteria: editable name (optional), editable amount (required), date and time (prefilled), same screen for add/edit/view, no Edit Mode toggle.
- `docs/product-features-planning.md` F-6.01 — Add Funds (negative `amount`) is **paused** at the UI layer. The screen does NOT surface an Add Funds toggle. But the screen IS the future editing surface for those rows once F-6.01 ships, so the spec must require sign preservation in Edit mode.

## Goals / Non-Goals

**Goals:**

- Replace the `RootView` placeholders for `SheetRoute.addExpense(Budget)` and `SheetRoute.expense(ExpenseItem)` with a single, real `AddEditExpenseView` that satisfies F-2.04 acceptance criteria. (Done as a staged uncommitted edit on this branch; this change codifies it as spec and ships the tests.)
- Lock in the existing layout and field formatting as the F-2.04 spec. The user has explicitly approved them; the spec will require them so future drift is caught. (Nav title for the existing-expense path is intentionally neutral per F-2.04 single-surface alignment.)
- Introduce an `@Observable AddEditExpenseViewModel` per `docs/tech-design-doc.md` §2.1, holding **draft state and pure logic only**. The view owns the VM as `@State`; the VM never stores or fetches via `ModelContext`. Save and Delete methods take the context at the call site. Mirrors the contract of `AddEditBudgetViewModel`.
- Insert a new `ExpenseItem` (attached to the in-flight `Budget`) on Add-mode Save; mutate the passed-in `ExpenseItem` on Edit-mode Save with field-by-field comparison so `lastModified` is bumped only when at least one field actually changed.
- Preserve the sign of `ExpenseItem.amount` in Edit mode so a future F-6.01 add-funds row that the user opens, modifies the amount of, and saves does NOT silently flip from negative to positive. Add-mode unconditionally inserts a positive expense (no Add Funds affordance until F-6.01 ships).
- Fix the auto-focus regression: focus the Amount field only in Add mode (mirrors the Add/Edit Budget pattern; avoids popping the keyboard when the user is just inspecting an existing expense).
- Ship Swift Testing tests for the VM and the `OptionalDecimalFormatStyle` parser. Cover Add/Edit defaults, `canSave`, Save semantics in both modes, the sign-preservation rule, no-op Edit Save, Cancel semantics, and Delete behavior in both modes.
- Update the `app-navigation` modified-capability requirement to drop `.addExpense` / `.expense` from the remaining-placeholder list, and flip F-2.04's `**Status:** Open` → `**Status:** Implemented` in `docs/product-features-planning.md`.

**Non-Goals:**

- **No layout or structural formatting changes.** The user explicitly approved what shipped on this branch. The spec captures what's there. Narrow exception: neutral nav title and `SheetRoute.expense` naming for F-2.04 view+edit single-surface alignment (see implementation). If a future change wants to redesign the screen, it MUST file a new OpenSpec change.
- **No Add Funds toggle (F-6.01) UI.** The Add Funds affordance lives in a future change against F-6.01. This screen will be the editing surface for those rows; the spec only requires that existing negative-amount rows survive an edit without losing their sign.
- **No new `SheetRoute` cases beyond the two expense routes.** The existing-expense case is `expense(ExpenseItem)` (renamed from `viewExpense` for API/product alignment with F-2.04); still paired with `.addExpense(Budget)` only.
- **No schema changes.** `ExpenseItem` is untouched. `expenseType` and any future receipt-image / voice-input fields are not edited by this screen.
- **No Save error UI.** No other screen surfaces save errors today (`AddEditBudgetViewModel.save(...)` and `BudgetsView.move(...)` use `try?`). This screen follows the same pattern.
- **No unrelated new `Localizable.xcstrings` keys.** Strings stay under `addEditExpense.*`; key renames (e.g. `title.existing`) for F-2.04 alignment are allowed.
- **No iPad / Mac split-view layout for the sheet.** The sheet uses the default modal presentation; iPad and Mac inherit standard SwiftUI sheet sizing.
- **No interaction with `BudgetLifecycleService` carry-over math.** Inserting / editing / deleting an `ExpenseItem` does NOT directly trigger a carry-over recompute from this screen — the existing `BudgetLifecycleService` plumbing handles that on the next read of the relevant aggregates per `docs/main-prd.md` §6.7. (The screen's writes still propagate through the same SwiftData → CloudKit pipeline.)
- **No receipt scanning (F-7.01) or voice input (F-7.02).** Those features depend on F-2.04 but are tracked separately.
- **No expense-list / Budget detail (F-2.02) entry-point work.** When F-2.02 lands it will trigger `router.sheet = .expense(expense)`; this change makes that sheet present the real screen, but does NOT add the trigger itself. The Budgets-screen Add Expense entry point is already wired and will work as soon as this change lands.

## Decisions

### Decision 1: Reuse the `AddEditBudgetViewModel` shape for the Expense VM

**Choice:** `Views/AddEditExpenseView.swift` defines `@Observable @MainActor final class AddEditExpenseViewModel` with a private `Mode` enum (`case add(Budget)` / `case edit(ExpenseItem)`) and stored properties `var amount: Decimal?`, `var name: String`, `var date: Date`, `let currencyCode: String`. Two initialisers — `init(adding budget: Budget)` and `init(editing expense: ExpenseItem)` — set up the `Mode` and seed defaults. A pure `var canSave: Bool` computed property returns `(amount ?? 0) > 0`. A `func save(context: ModelContext)` method performs the Add or Edit branch. A `func delete(context: ModelContext)` method performs the Edit-mode delete (or no-ops in Add mode).

The VM does NOT hold `ModelContext`, does NOT hold `AppSettings` (currency-display preference is read view-side from `@Environment(AppSettings.self)`), does NOT fetch, and does NOT call `@Query`. The view owns the VM as `@State`.

**On the `save(...)` / `delete(...)` signatures.** `docs/tech-design-doc.md` §2.1 says: _"Methods that need to write take `(context: ModelContext, ...)` at the call site (and `AppSettings` similarly when relevant)."_ For these methods, `AppSettings` is NOT relevant — neither save body nor delete body reads any `AppSettings` property. Following §2.1's "when relevant" rider, both methods take only `context: ModelContext`.

**On the `currencyCode` field being `let`, not `var`.** The Amount card's currency-prefix label is purely a display concern derived from the budget that owns the expense; the user CANNOT change the per-expense currency on this screen (they would change the budget's currency on the Add/Edit Budget screen instead). Holding it as `let` makes that explicit and prevents accidental future code paths that try to mutate it.

**Alternatives considered:**

- **`@State` properties on the view (no VM)** — rejected because: (a) §2.1 escalation criterion #1 applies (form draft state not persisted until commit); (b) parity with `AddEditBudgetViewModel` is a strong consistency win for testers and reviewers; (c) testing the `save(...)` / `delete(...)` orchestration without a host SwiftUI view is much easier with a VM than with `@State`-only logic.
- **Drop `Mode` and store `editingExpense: ExpenseItem?` directly** — rejected because the `Mode` enum is type-safer (the editing-`Budget` reference for Add mode and the editing-`ExpenseItem` reference for Edit mode are mutually exclusive; an enum captures that exactly).
- **Store `amount` as `Decimal` (not `Decimal?`)** — rejected because the Amount field needs to render empty for first-launch Add mode (so the user types into a blank field, not a `0`). The optional plus an `OptionalDecimalFormatStyle` parse strategy is the canonical SwiftUI path for "blank means nil" numeric entry. The same pattern was considered for `AddEditBudgetViewModel.allocation` and was adopted there in change `2026-04-28-add-edit-budget-screen` (Decision 4).
- **Use `expense.amount` directly as the source of truth instead of a local `var amount`** — rejected because the user can type and discard mid-edit (`Cancel`); the local `var` is the draft, and the model is mutated only on Save.

**Rationale:** Mirrors the contract already established by `AddEditBudgetViewModel`. Same shape, same testability, same review patterns. Escalation criterion #1 is sufficient justification on its own; the mode enum cleanly captures the Add-vs-Edit fork.

### Decision 2: Add and Edit modes share one screen, distinguished by the VM initialiser

**Choice:** `AddEditExpenseViewModel.Mode` is one of:

- `.add(Budget)` — the Add path. The VM is created via `init(adding budget: Budget)` and seeds defaults: `amount = nil` (blank field), `name = ""` (placeholder shown), `date = Date()` (current wall-clock time), `currencyCode = budget.currencyCode` (so the Amount card's currency prefix is in the right currency for the parent budget). The VM stores a reference to the `Budget` so `save(context:)` can set `expense.budget = budget`.
- `.edit(ExpenseItem)` — the Edit path. The VM is created via `init(editing expense: ExpenseItem)` and seeds each field from the existing expense: `amount = expense.displayAmount` (absolute value — the field shows a positive number even for `isAddFunds` rows; the underlying sign is restored on Save per Decision 4), `name = expense.name ?? ""`, `date = expense.date`, `currencyCode = expense.budget?.currencyCode ?? (Locale.current.currency?.identifier ?? "USD")`. The VM stores a reference to the `ExpenseItem` so `save(context:)` can mutate it and `delete(context:)` can remove it.

The view chooses navigation title based on mode: `"Add Expense"` for Add mode, `"Edit Expense"` for Edit mode. The Save button label stays `"Save"`.

The view exposes `var isEditing: Bool` (computed from the mode) so the Delete button can be conditionally rendered. Add mode SHALL NOT render the Delete button (a draft `ExpenseItem` is not yet inserted, so there is nothing to delete).

**Alternatives considered:**

- **Two separate views (`AddExpenseView`, `EditExpenseView`)** — rejected because F-2.04 explicitly requires "Same screen is used for add, edit, and view use cases."
- **Pass an optional `ExpenseItem?` directly into the view** — rejected because Add mode needs the parent `Budget` reference (to attach the new expense), so a single optional cannot capture both modes' inputs. A `Mode` enum with two associated values is the cleanest representation.
- **Store the mode in the view, not the VM** — rejected because the Save/Delete branches and the Edit-mode seeding logic all live in the VM; pushing the mode to the view would split the logic awkwardly.

**Rationale:** F-2.04 mandates a single screen. The `Mode` enum is the simplest internal representation of Add vs Edit and keeps the seeding/saving/deleting logic in the VM rather than the view. Mirrors the Add/Edit Budget pattern.

### Decision 3: `canSave` requires a strictly positive amount; description is optional

**Choice:** `canSave` SHALL evaluate to `true` if and only if `(amount ?? 0) > 0`. Specifically:

- `amount == nil` (blank field) → `canSave = false`.
- `amount == 0` → `canSave = false` (a zero-amount expense is degenerate; F-2.04 says amount is required).
- `amount < 0` → `canSave = false` (not reachable from `.decimalPad`, but the guard is canonical).
- `amount > 0` → `canSave = true` regardless of `name` (the description is optional per F-2.04 AC).

This matches the `(allocation ?? 0) > 0` rule on `AddEditBudgetViewModel.canSave`, just without the trimmed-name requirement (because description is optional here, unlike budget name).

**Alternatives considered:**

- **Allow `amount == 0`** — rejected; "saved a zero-amount expense" is indistinguishable from "forgot to enter the amount". The consistency with `AddEditBudgetViewModel.canSave` is also valuable.
- **Require non-empty trimmed description** — rejected; F-2.04 says description is optional. Forcing it would be a UX regression and a spec violation.
- **Disable Save unless date is in the past** — rejected; allowing future-dated expenses lets the user pre-record an upcoming charge. Out of scope to constrain here.

**Rationale:** Aligned with F-2.04 (amount required, description optional). Mirrors the simpler half of `AddEditBudgetViewModel.canSave`.

### Decision 4: Edit-mode Save preserves the sign of `ExpenseItem.amount`

**Choice:** In Edit mode, when the draft `amount` differs from `expense.displayAmount` (i.e. the user changed the value), the model write SHALL be:

```swift
expense.amount = expense.isAddFunds ? -newAmount : newAmount
```

The Edit-mode change-detection comparison SHALL also be done against `expense.displayAmount`, NOT against `expense.amount` (otherwise comparing a non-negative draft against a negative model value would always return "changed" even when the user did nothing).

Concretely the Save block becomes:

```swift
case .edit(let expense):
  var changed = false
  if let newAmount = amount, expense.displayAmount != newAmount {
    expense.amount = expense.isAddFunds ? -newAmount : newAmount
    changed = true
  }
  if expense.name != trimmedName {
    expense.name = trimmedName
    changed = true
  }
  if !Calendar.current.isDate(expense.date, equalTo: date, toGranularity: .minute) {
    expense.date = date
    changed = true
  }
  if changed {
    expense.lastModified = Date()
    try? context.save()
  }
```

Add-mode Save unconditionally writes a positive `amount` (the field's draft value). The Add Funds affordance is out of scope here; F-6.01's future change will introduce that toggle.

The current uncommitted code uses `expense.amount = newAmount` (no sign restoration) and compares `expense.amount != newAmount` (asymmetric types — `Decimal` vs `Decimal`, but values mismatched for negative rows). This change fixes both halves.

**Why pre-emptively, given F-6.01 isn't shipping in this change?** Because:

- The screen IS the editing surface for `ExpenseItem` rows whose underlying `amount` is negative. Once F-6.01 ships (or once a CloudKit-synced row from an unreleased build arrives, or once a future change introduces a side path that creates negative rows), the `displayAmount`-driven seeding will silently flip the sign on Save without this guard.
- The fix is small (one ternary, one comparator change) and the spec requirement nails it down so the next reviewer catches a regression.
- Adding a test now (against an in-memory `ExpenseItem` with `amount = -10`) gives us a regression net before F-6.01 ever lands.

**Alternatives considered:**

- **Defer the fix to F-6.01's change** — rejected because F-6.01 has no scheduled date and the latent bug exists today against any negative `amount` row (e.g. one created by `DebugData.weeklyDefaultEUR`'s "Added funds from reimbursement" seed that is currently a positive amount; a future seed change could introduce a negative one without anyone noticing).
- **Hold draft as a signed `Decimal?`** — rejected because the visible field always shows a positive number (the user types `5.00` for both expense and add-funds; the sign is encoded by the action that created the row, not by the field). Holding signed-only makes Add/Edit asymmetric and breaks the intended UX.
- **Refactor `ExpenseItem` to split sign and magnitude into two fields** — out of scope; would require a schema migration.

**Rationale:** Cheap, future-proof, fully testable. Adds a single guard at the model write call site and an equally simple fix to the change-detection comparator. The cost of *not* fixing this is a silent data-corruption bug the moment F-6.01 lands.

### Decision 5: Add-mode auto-focuses the Amount field; Edit mode does not

**Choice:** The view sets `isAmountFocused = true` in `.onAppear` only when `viewModel.isEditing == false`. Edit mode SHALL NOT auto-focus any field. Concretely:

```swift
.onAppear {
  if !viewModel.isEditing {
    isAmountFocused = true
  }
}
```

**Why:** The current uncommitted code sets `isAmountFocused = true` unconditionally, which pops the keyboard the moment the user opens an existing expense to inspect it — a UX regression compared to the Add/Edit Budget pattern (which only auto-focuses the Name field in Add mode).

**Alternatives considered:**

- **Always auto-focus** — rejected; the Edit-mode user often opens the screen to look, not type.
- **Never auto-focus** — rejected; Add mode benefits enormously from auto-focus because the user just tapped an Add button intending to immediately enter an amount. Skipping focus would force a second tap.
- **Add a `presentationDetents([.medium, .large])` and auto-focus only at `.large`** — out of scope; iPad / Mac sheet sizing is non-goal.

**Rationale:** Matches the Add/Edit Budget pattern precisely. UX-correct in both modes.

### Decision 6: Edit-mode Date comparison uses `.minute` granularity to match the picker

**Choice:** The change-detection comparator for `date` uses `Calendar.current.isDate(expense.date, equalTo: date, toGranularity: .minute)`. The picker is configured `displayedComponents: [.date, .hourAndMinute]`, so `.minute` is the smallest unit the user can manipulate. Sub-minute differences are not user-visible and SHALL NOT trip the change detector.

**Alternatives considered:**

- **Compare `Date == Date` directly** — rejected because the `Date()` initialiser and the picker round to slightly different sub-second values; comparing `==` would always trigger a change in a "no-op Save" scenario where the user opened and closed the sheet without touching the picker.
- **Compare `.second` granularity** — rejected; the picker has no second component.
- **Compare `.day` granularity** — rejected; the picker DOES have a time component, so a same-day, different-time edit IS a real change.

**Rationale:** Matches the picker's effective resolution. A no-op Edit save leaves `lastModified` untouched.

### Decision 7: Trimmed-but-stored description; empty trimmed description maps to `nil`

**Choice:** When persisting `name` to the model:

```swift
let trimmedName: String? = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines)
```

Note: the local variable name is misleading in the current uncommitted code (it stores the *un*trimmed `name` for non-empty values). This change tightens the implementation to store the *trimmed* value when non-empty, so leading/trailing whitespace is not silently persisted.

The Edit-mode change comparator compares `expense.name != trimmedName`. (`String?` vs `String?` equality works as expected — `nil == nil`, `"foo" == "foo"`, `nil != "foo"`.)

**Alternatives considered:**

- **Persist user-entered whitespace verbatim** — rejected; "  Coffee  " and "Coffee" are the same expense to a human reader, and silently persisting the whitespace produces noisy CloudKit sync output and ugly list rows.
- **Reject submission of whitespace-only descriptions with an inline validation error** — rejected; description is optional per F-2.04. Falling back to `nil` for trimmed-empty is the right default.

**Rationale:** Consistent with how `AddEditBudgetViewModel` treats name trimming. Matches user intent. Tests make this concrete.

### Decision 8: Save and Delete persistence flow

**Choice:** `func save(context: ModelContext)` performs:

#### Add mode (`.add(let budget)`)

0. **Guard:** If `!canSave`, return without inserting.
1. Compute `trimmedName` per Decision 7.
2. Construct `ExpenseItem(amount: amount!, name: trimmedName, date: date)` — `amount!` is safe because `canSave` guarantees non-nil.
3. Set `expense.budget = budget`.
4. `context.insert(expense)`.
5. `try? context.save()`.

#### Edit mode (`.edit(let expense)`)

For each editable field, compare draft to current; only mutate when different per Decisions 4–7. On any mutation, set `expense.lastModified = Date()` once at the end. Then `try? context.save()`.

**`func delete(context: ModelContext)` performs:**

#### Edit mode

1. `context.delete(expense)`.
2. `try? context.save()`.

#### Add mode

No-op: SHALL NOT call `context.delete`, SHALL NOT call `context.save`, SHALL NOT mutate any state. The Delete button is not rendered in Add mode (Decision 9), so this branch is defence-in-depth.

#### Cancel

The view dismisses via `@Environment(\.dismiss)`. The VM is deallocated. No `ExpenseItem` is inserted, mutated, or deleted.

**Alternatives considered:**

- **Always rewrite all fields on Edit-mode Save** — rejected; would bump `lastModified` on every Save even for a no-op. Same rationale as `AddEditBudgetViewModel.save(...)`.
- **Throwing `save(...)` / `delete(...)` with an error sheet** — out of scope; not a pattern this app surfaces today.
- **Push to a background `ModelContext` for the write** — unnecessary for a single-row insert/update/delete at the scale this app expects (`docs/tech-design-doc.md` §6 only mentions backgrounding for multi-period rolls).

**Rationale:** Field-level comparison gives clean `lastModified` semantics. The `try?` save matches the project pattern. Minimal risk for synchronous, small writes.

### Decision 9: Delete button is rendered only in Edit mode; confirmation dialog matches Add/Edit Budget pattern

**Choice:** A destructive **Delete Expense** button is rendered beneath the three cards (Amount / Description / When) when, and only when, `viewModel.isEditing == true`. In Add mode the button SHALL NOT be rendered.

The button uses `.buttonStyle(.bordered)`, `.tint(.red)`, `role: .destructive`, with `.frame(maxWidth: .infinity)` for full width. Label key: `addEditExpense.action.delete` ("Delete Expense"). VoiceOver hint: `addEditExpense.action.delete.accessibilityHint` ("Permanently deletes this expense.").

Activating the button presents a `confirmationDialog` with `titleVisibility: .visible`. The dialog has exactly one explicit destructive button — SwiftUI's implicit Cancel covers the cancel path. Dialog strings:

- Title: `addEditExpense.deleteConfirmation.title` ("Delete Expense?").
- Body: `addEditExpense.deleteConfirmation.message` ("This action cannot be undone.").
- Confirm button: `addEditExpense.deleteConfirmation.confirm` ("Delete Expense"), `role: .destructive`.

Confirming invokes `viewModel.delete(context:)` and dismisses the sheet. Cancelling dismisses the dialog only and leaves the sheet, the editing `ExpenseItem`, and all draft state intact.

This mirrors Decisions 11–14 of the `add-edit-budget-screen` design.md exactly, except the strings are namespaced under `addEditExpense.*`.

**Alternatives considered:**

- **Trash-can toolbar item instead of a destructive button under the cards** — rejected; the user has approved the layout, which puts the destructive action below the form.
- **Skip the confirmation dialog** — rejected; `ExpenseItem` rows are user-typed records and accidental delete is irrecoverable. Confirmation is mandatory.
- **Long-press to delete** — rejected; not a discoverable pattern for a destructive action.

**Rationale:** Matches the Add/Edit Budget pattern. Confirmation dialog protects against accidental deletes. Localized strings already in the catalog.

### Decision 10: Wire Add and View/Edit branches through `RootView`

**Choice:** `RootView`'s `.sheet(item: $router.sheet) { route in switch route { ... } }` block resolves:

```swift
case let .addExpense(budget):
  AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget))
case let .expense(expense):
  AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))
```

This is already in place on this branch as a staged uncommitted edit. `RootView`'s doc-comment header was also updated to reflect that `.addExpense` / `.expense` now resolve to `AddEditExpenseView` (F-2.04). The Budget detail (`AppRoute.budgetDetail`) push case remains a placeholder until F-2.02 ships.

`AppSettings` is NOT passed to `AddEditExpenseViewModel` because the VM does not consume it. The view itself reads `@Environment(AppSettings.self)` for the Amount card's currency-prefix display.

**Alternatives considered:**

- **Have `AddEditExpenseView` infer the mode from a single `Either<Budget, ExpenseItem>` parameter** — rejected; the explicit `Mode` enum on the VM is clearer and SwiftUI's call-site is already a `switch` on `SheetRoute`, so passing the right initialiser arg is direct.

**Rationale:** Keeps the route-to-screen wiring explicit, mirrors the Add/Edit Budget pattern, and satisfies the `app-navigation` modified requirement.

### Decision 11: Currency prefix on Amount card honors `AppSettings.currencyDisplay`

**Choice:** The Amount card displays a leading currency prefix derived from `settings.currencyDisplay.prefix(for: viewModel.currencyCode)`. The view reads `@Environment(AppSettings.self) private var settings` so the prefix updates live when the user changes the global preference (e.g. via the Settings sheet) while the Add/Edit Expense sheet is open.

The visible Amount `TextField` itself remains a numeric editor — it shows the typed `Decimal` (formatted with `.number.precision(.fractionLength(0...2))`), NOT a fully formatted currency string. The prefix sits adjacent in the same `HStack`. This matches the Add/Edit Budget Allocation card's pattern.

The pulled-from-budget `currencyCode` is a `let` on the VM — the user can NOT change the per-expense currency on this screen (currency is a per-budget property, edited on Add/Edit Budget). The prefix's *content* (symbol vs code vs codeAndSymbol) IS reactive to `settings.currencyDisplay`; the *currency code itself* is static for the lifetime of the sheet.

**Alternatives considered:**

- **Format the visible Amount field as full currency (e.g. `$25.00`)** — rejected; the user is in a numeric editing context. Mixing currency formatting with a separate currency prefix produces redundancy. Same rationale as Decision 4 of the Add/Edit Budget design.
- **Hard-code `display: .symbol`** — rejected; would break the app-wide preference contract documented in `app-settings`'s `currencyDisplay setting` requirement.
- **Plumb `currencyDisplay` through the VM as a stored field** — rejected; the preference is a view-side concern, the VM has no business knowing about it. The §2.1 rule "VM holds draft state and pure logic only" applies.

**Rationale:** Mirrors `AddEditBudgetView` exactly. Consistent with how `BudgetsView` and `CarryOverChip` already render money under the user's preference.

### Decision 12: Tests — Swift Testing on the VM and the parser

**Choice:** All deterministic logic lives in `AddEditExpenseViewModel` and the file-private `OptionalDecimalFormatStyle`. Tests target both with Swift Testing (`@Test`, `#expect`) in `simple-recurring-budgetsTests/Views/AddEditExpenseViewModelTests.swift`.

Coverage:

1. Add-mode defaults: `init(adding:)` produces a VM with `amount == nil`, `name == ""`, `date` ≈ current `Date()` (within a 5-second tolerance), `currencyCode == budget.currencyCode`, and `isEditing == false`.
2. Edit-mode seeding (positive amount): `init(editing:)` produces a VM whose fields match an existing `ExpenseItem` with `amount > 0`. `currencyCode` matches `budget.currencyCode`.
3. Edit-mode seeding (negative amount, `isAddFunds`): `init(editing:)` produces a VM whose `amount` field equals `expense.displayAmount` (i.e. `-expense.amount`). The seed does NOT carry the sign.
4. Edit-mode seeding (orphan expense — `expense.budget == nil`): `currencyCode` falls back to `Locale.current.currency?.identifier ?? "USD"`. (This path is reachable for an `ExpenseItem` whose budget was deleted while the row stayed in the store on a foreign device — defensive code.)
5. `canSave` enumeration: `nil` → false; `0` → false; `< 0` → false (set via direct `vm.amount = -1` assignment to bypass keyboard); `> 0` → true regardless of `name`.
6. Add-mode `save(context:)`: inserts exactly one `ExpenseItem` whose fields match the drafted values, with `expense.budget` pointing to the in-flight `Budget`. `expense.amount > 0` (no sign flipping). Verified against an in-memory `ModelContainer` from `simple-recurring-budgetsTests/Helpers/TestModelContainer.swift`.
7. Edit-mode `save(context:)` no-op: open the VM with no field changes, call `save`; `expense.lastModified` is unchanged. Verify by capturing the pre-save value and asserting strict `==` post-save.
8. Edit-mode `save(context:)` single-field change (positive expense): change only `name`; assert `expense.name` is updated, `expense.lastModified` is set to a value `>=` a pre-call `Date()`, and other fields (`amount`, `date`, `expenseType`, `createdAt`) are untouched.
9. Edit-mode `save(context:)` sign preservation (negative `isAddFunds` row): build an `ExpenseItem` with `amount = -10`, edit the VM's `amount` to `15`, call `save`; assert `expense.amount == -15` (sign restored). This is the regression net for Decision 4.
10. Edit-mode `save(context:)` sign preservation when amount unchanged: build an `ExpenseItem` with `amount = -10`, leave the VM's `amount` at its seeded `displayAmount` value (`10`), call `save`; assert `expense.amount` remains `-10` (no spurious change). This catches the comparator-asymmetry bug in the staged code.
11. Edit-mode `save(context:)` multi-field change: change name and amount; assert both fields are written and `lastModified` is updated exactly once.
12. Edit-mode `save(context:)` description trimming: set the VM's `name` to `"  Coffee  "`, save; assert `expense.name == "Coffee"` (whitespace trimmed). Set the VM's `name` to `"   "` (whitespace-only), save; assert `expense.name == nil`.
13. Edit-mode `save(context:)` date no-op tolerance: edit the VM's `date` by `< 60s` from the seeded value; the change comparator (Decision 6) treats it as a no-op; `lastModified` is unchanged.
14. Cancel semantics: construct a VM, mutate its fields, do NOT call `save`; assert the underlying `ExpenseItem` rows in the store retain their original values.
15. Delete in Edit mode: construct a VM in Edit mode for an existing `ExpenseItem`, call `delete(context:)`; assert the expense is removed from the store, and `context.save()` was invoked exactly once.
16. Delete in Add mode is a no-op: construct a VM in Add mode, call `delete(context:)` against an in-memory store with one or more pre-existing expenses; assert the store contents are unchanged.

`OptionalDecimalFormatStyle` parsing tests (in the same file or a sibling — implementer's choice):

17. Empty / whitespace-only string parses to `nil`.
18. Valid locale-current decimal string parses to the corresponding `Decimal` (e.g. `"25.50"` in `en_US` locale → `Decimal(25.50)`). Test against an explicit `Locale(identifier: "en_US")` to keep the assertion deterministic, by injecting the locale through whatever seam the parse strategy exposes; if the parse strategy has no locale seam, document that as a follow-up.
19. Malformed string (e.g. `"abc"`) throws `CocoaError(.formatting)`.

VoiceOver / Dynamic Type / Dark Mode coverage stays in `#Preview` blocks (no snapshot tests, per `docs/tech-design-doc.md` §5.3 / Decision 13 of the Add/Edit Budget design).

**Alternatives considered:**

- **UI snapshot tests** — out of scope per `docs/tech-design-doc.md` §5.3.
- **Test the full sheet via SwiftUI's `inspect` or hosting controllers** — brittle; the VM contract is the unit-test target.

**Rationale:** Aligns with `docs/tech-design-doc.md` §5.3. Every requirement scenario in the spec maps to at least one VM test, and the latent sign / focus / trimming bugs each get a dedicated regression test.

### Decision 13: Doc updates required by this change

**Choice:** One `docs/*.md` file SHALL be updated **in this change** (not deferred):

1. `docs/product-features-planning.md` —
    - **F-2.04 (Add/Edit/View Expense Item screen)**: flip `**Status:** Open` → `**Status:** Implemented`. Add a brief implementation note pointing at this change name. Add a sentence in Edge Cases / Notes clarifying that the screen treats Edit and View as the same mode (per the AC's "No Edit Mode") and that the Edit-mode Save preserves the sign of `ExpenseItem.amount` so F-6.01 (Add Funds) rows survive an edit.
    - **F-6.01 (Add Funds)**: optional. If the file already has a note about the F-2.04 dependency, leave the F-6.01 entry untouched. If a one-line clarifying note ("the F-2.04 screen will be the editing surface; sign preservation is in place") fits naturally, add it. Otherwise defer to F-6.01's own change.

`docs/tech-design-doc.md`, `docs/main-prd.md`, and `docs/ux-design-brief.md` are unchanged. The VM pattern matches §2.1's existing rule; no architectural shift.

**Alternatives considered:**

- **Defer the F-2.04 status flip until verify** — rejected; the proposal already establishes the flip is the right doc state, and pushing it to verify introduces drift between the change and the docs at archive time.
- **Bump tech-design-doc version-history** — rejected; no architectural change.

**Rationale:** Matches the workspace's `Doc maintenance protocol` ("update the corresponding `docs/` file(s) in the same effort") and the OpenSpec config's `apply` rule.

## Risks / Trade-offs

- **[Sign-preservation logic is too clever for a future contributor]** → Mitigation: the spec scenario explicitly requires it, the test enumeration in §7 covers it, and the comment block on the relevant VM line cites Decision 4 by anchor. A future contributor who removes the guard breaks tests.
- **[Test for sign preservation requires constructing a negative-amount `ExpenseItem`]** → Mitigation: trivial to do (`ExpenseItem(amount: -10, ...)`); the in-memory `ModelContainer` from `TestModelContainer` accepts it. No fixtures change.
- **[Auto-focus regression in Edit mode is invisible until you test on device]** → Mitigation: a SwiftUI focus-state test would require a host view; instead, we ship the documented `if !viewModel.isEditing` guard, capture the requirement in the spec, and call it out in the smoke-test matrix (§4 of Migration Plan).
- **[Delete cascade on `ExpenseItem` is a no-op (no children), so we don't get a dedicated test for cascade behavior]** → Acceptable: the model has no child relationship to verify. The Delete test in §7 (Decision 12) verifies the row is removed and `context.save()` was called.
- **[`AppSettings.currencyDisplay` change while the sheet is open]** → The currency prefix on the Amount card updates reactively (verified by the existing `AddEditBudgetView` precedent); no in-flight draft state is affected because the prefix is a pure view-side derivation.
- **[Concurrent edit of the same `ExpenseItem` from two devices via CloudKit]** → Standard last-writer-wins per `docs/tech-design-doc.md` §4.4. Acceptable.
- **[Save errors from `try? context.save()` are swallowed]** → No user-visible feedback when saving fails. Mitigation: matches existing app pattern (`AddEditBudgetViewModel.save(...)` and `BudgetsView.move(...)`). Save-error UX is a future cross-cutting concern, not scoped here.
- **[`OptionalDecimalFormatStyle` is file-private to `AddEditExpenseView.swift`]** → The parsing tests want to call into it. Mitigation options: (a) make the type and its `parse(_:)` method `internal` and `@testable import simple_recurring_budgets`; (b) extract the type to its own file under `simple-recurring-budgets/Formatting/` and make it `internal`. The implementation task picks one; the spec stays agnostic. The simplest path is `@testable import` plus widening the access modifier to `internal`.
- **[Edit-mode comparison against `expense.displayAmount` rather than `expense.amount` is subtle]** → Mitigation: Decision 4 documents it; the test in §7 (case 10, "amount unchanged on a negative row") guards it.

## Migration Plan

1. **Land this change as a single PR.** The PR body includes:
    - Edits to `simple-recurring-budgets/Views/AddEditExpenseView.swift` (already staged): apply Decision 4 (sign-preserving edit save + symmetric comparator), Decision 5 (auto-focus only in Add mode), Decision 7 (trimmed name persisted).
    - The already-staged edits to `simple-recurring-budgets/Views/RootView.swift` and `simple-recurring-budgets/Resources/Localizable.xcstrings` ride along unchanged.
    - New file: `simple-recurring-budgetsTests/Views/AddEditExpenseViewModelTests.swift` per Decision 12.
    - Optional new file: `simple-recurring-budgets/Formatting/OptionalDecimalFormatStyle.swift` (if the implementer extracts the format-style type per the access-modifier decision in Risks). Otherwise, widen the file-private type to `internal` in place.
    - Edits to `docs/product-features-planning.md` per Decision 13.
    - The OpenSpec change folder `openspec/changes/add-edit-expense-screen/` (proposal, design, specs, tasks).
2. **No data migration.** Schema is untouched. CloudKit is untouched.
3. **Rollback strategy.** Revert the single PR. `RootView` reverts to the placeholder texts. `Localizable.xcstrings` retains the auto-extracted entries (harmless — they would be marked stale on next build). No data loss.
4. **Smoke test matrix on a clean iPhone simulator** (per `docs/tech-design-doc.md` §5.3):
    - Open a budget → tap row Add → Add Expense sheet opens with empty Amount, empty Description, current Date/Time, currency prefix matching the budget's currency in the user's `currencyDisplay` mode. Amount field is auto-focused (keyboard pops).
    - Add sheet → leave Amount blank → Save disabled. Type `0` → Save still disabled. Type `5.00` → Save enabled. Tap Save → expense appears in the budget's expense list with the typed values.
    - Add sheet → type a description with leading/trailing spaces → Save → the persisted description has whitespace trimmed.
    - Edit sheet (via the F-2.02 entry point or a temporary preview hook): opens pre-filled with the expense's values; Amount field is NOT auto-focused (no keyboard pop); Delete button is rendered below the cards.
    - Edit sheet → change nothing → Save → `lastModified` unchanged (verified via debug print or test).
    - Edit sheet → change the date by less than a minute (e.g. nudge seconds) → Save → `lastModified` unchanged (Decision 6).
    - Edit sheet → tap Delete → confirmation dialog appears with title, message, destructive button, and SwiftUI's implicit Cancel. Tap Cancel → dialog dismisses, sheet remains, expense is intact. Tap Delete Expense → dialog dismisses, sheet dismisses, expense is removed from the store.
    - Edit sheet on a *negative-amount* `ExpenseItem` (constructed via debug seed): the Amount field shows the absolute value; change the value, Save → the persisted `expense.amount` retains its negative sign. (This is the F-6.01 forward-compat scenario; until F-6.01 ships, the seed has to be an ad-hoc `ExpenseItem(amount: -10)` insertion, e.g. via a temporary preview helper.)
    - Cancel from any state → no `ExpenseItem` is inserted, modified, or deleted.
    - Toggle `AppSettings.currencyDisplay` in Settings → reopen Add Expense sheet → currency prefix on the Amount card reflects the new preference.
    - VoiceOver enabled → focus the Delete Expense button → hear the destructive hint.
    - Dynamic Type at `xxxLarge` → cards reflow without clipping; the date picker remains usable.
    - Dark Mode → no surface reads as a hard-coded white card; backgrounds use `appBackground()` / `Color("CellBackground")`.

## Open Questions

_(none — every implementation-shape choice is settled in Decisions 1–13. Below are deliberate non-questions:)_

- **VM vs `@State`-only**: settled (Decision 1) — a VM, per §2.1.
- **Amount type**: settled (Decision 1) — `Decimal?` with `OptionalDecimalFormatStyle`.
- **`Mode` shape**: settled (Decision 2) — enum with `.add(Budget)` / `.edit(ExpenseItem)`.
- **`canSave` rule**: settled (Decision 3) — `(amount ?? 0) > 0`.
- **F-6.01 sign preservation**: settled (Decision 4) — preserve sign on Edit-mode Save; spec requires it; tests cover it.
- **Auto-focus rule**: settled (Decision 5) — Add mode only.
- **Date comparator granularity**: settled (Decision 6) — `.minute`.
- **Description trim semantics**: settled (Decision 7) — persist trimmed value, `nil` when trimmed-empty.
- **Persistence flow**: settled (Decision 8) — field-by-field comparison in Edit, single `try? context.save()` per call.
- **Delete affordance**: settled (Decision 9) — Edit mode only, with confirmation dialog matching Add/Edit Budget.
- **`AppSettings.currencyDisplay` plumbing**: settled (Decision 11) — view-side, not VM-side.
- **`OptionalDecimalFormatStyle` access modifier**: implementer's choice between `@testable import` + `internal`, or extracting to its own file. Both are acceptable; both are testable.
