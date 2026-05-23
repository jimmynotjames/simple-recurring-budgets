## 1. Viewmodel wiring

- [x] 1.1 Confirm `AddEditExpenseViewModel.isAddFunds: Bool = false` exists with the `didSet` that seeds `name = "Add funds"` when transitioning false → true with empty/whitespace `name` (already in place from prior session — verify it survived rebases)
- [x] 1.2 Confirm `init(editing:)` assigns `isAddFunds = expense.isAddFunds` (already in place from prior session — verify)
- [x] 1.3 Update Add-mode `save(context:analytics:)` so the inserted `ExpenseItem.amount` is signed per `isAddFunds`: `let signedAmount = isAddFunds ? -amount! : amount!` then `ExpenseItem(amount: signedAmount, ...)`
- [x] 1.4 Update Edit-mode `save(context:analytics:)` to read the **draft** `isAddFunds` (the viewmodel's value) instead of `expense.isAddFunds` when computing the sign on amount change
- [x] 1.5 Extend the Edit-mode change comparator so a standalone `isAddFunds` flip (no amount/name/date change) counts as a change: flips the sign on `expense.amount`, bumps `lastModified`, and triggers exactly one `context.save()` and one `expense_edited` analytics event
- [x] 1.6 Verify the existing `expense_logged` and `expense_edited` analytics call sites correctly read `expense.isAddFunds` from the just-written `ExpenseItem` (no code change expected — just confirm the property reflects the new sign)

## 2. View confirmation

- [x] 2.1 Confirm `addFundsCard` exists as the fourth card in the form (after `whenCard`, before `deleteButton`) with `Toggle` + caption, `.tint(.accentColor)`. Extracted to `AddEditExpenseView+AddFundsCard.swift` for the 600-line cap.
- [x] 2.2 Confirm the Amount card's currency-prefix `Text` and numeric `TextField` apply `.foregroundStyle(Color.moneySurplus)` when `viewModel.isAddFunds == true`
- [x] 2.3 Confirm the navigation title uses the four-key matrix from the spec. Refactored into `AddEditExpenseViewModel.navigationTitle` computed property to stay under the line cap.
- [x] 2.4 Confirm the Amount field's `.accessibilityLabel` flips between the expense and add-funds keys

## 3. Localization (cross-cutting per main-prd.md §6.8)

- [x] 3.1 Added the six new keys to `Localizable.xcstrings` via `add_keys.py` (extraction would happen automatically on an IDE build, but the scripted path is the canonical project workflow).
- [x] 3.2 Updated the value for `budgetDetail.expenseRow.unnamed` via `update_keys.py` (now "Untitled" with a comment noting the shared usage). The 38 non-en locale entries were automatically marked `needs_review`.
- [x] 3.3 Dispatched 38 `translation-locale` subagents in parallel via the `translate-new-strings` skill; all PASS in `validate.py --subset`; merged into the catalog (266 key-locale pairs written).
- [x] 3.4 `check_translations.py` exits 0: "all 215 strings fully translated across source (en) + 38 target locales". `check_source_strings.py` also clean ("68 file(s) clean").

## 4. Accessibility (cross-cutting per main-prd.md §6.8)

- [x] 4.1 Toggle uses SwiftUI's default semantics — the `Text("Add funds")` label inside the `Toggle` is the announced label; no custom `.accessibilityLabel` needed.
- [x] 4.2 Amount field's `.accessibilityLabel` flips between `addEditExpense.field.amount.accessibilityLabel.addFunds` ("Funds amount") and `addEditExpense.field.amount.accessibilityLabel` ("Expense amount") based on `viewModel.isAddFunds`.
- [x] 4.3 Navigation title flip is announced naturally by VoiceOver's standard title-change announcement — no special handling needed. (Live VoiceOver walkthrough on hardware deferred to the human verifier per the F-3.02 audit protocol.)

## 5. Analytics (cross-cutting per main-prd.md §6.8)

- [x] 5.1 No new events or properties. Verified all three call sites (`expense_logged`, `expense_edited` in AddEditExpenseView.swift, `expense_deleted` in BudgetDetailView+ExpenseSection.swift) read `expense.isAddFunds` from the persisted `ExpenseItem`, which now reflects the toggle-driven sign.
- [x] 5.2 No `analytics-spec.md` update required.

## 6. Tests

All new tests are in `simple-recurring-budgetsTests/Views/AddEditExpenseViewModelAddFundsTests.swift` (separate file from the existing `AddEditExpenseViewModelTests.swift` to respect the project's 600-line per-file cap). All 485 tests pass.

- [x] 6.1 Add-mode sign tests: `addMode_save_isAddFundsFalse_insertsPositiveAmount`, `addMode_save_isAddFundsTrue_insertsNegativeAmount`. Both also assert the `expense_logged` analytics event carries the correct `isAddFunds` value.
- [x] 6.2 Edit-mode init seeding tests: `editMode_init_seedsIsAddFundsFromNegativeExpense`, `editMode_init_seedsIsAddFundsFromPositiveExpense`.
- [x] 6.3 `editMode_init_doesNotSeedDefaultDescription` — confirms the `didSet` does NOT fire during init.
- [x] 6.4 `editMode_save_toggleFlipFalseToTrue_flipsSign` — asserts sign flip, `lastModified` bump, single `expense_edited` event with `isAddFunds: true`.
- [x] 6.5 `editMode_save_toggleFlipTrueToFalse_flipsSign` — symmetric.
- [x] 6.6 `editMode_save_flipAndChangeAmount_persistsBothInOneWrite` — single coherent write.
- [x] 6.7 Description seed tests (5 scenarios): `descriptionSeed_emptyName_toggleOn_seedsDefault`, `descriptionSeed_nonEmptyName_toggleOn_doesNotOverwrite`, `descriptionSeed_whitespaceOnlyName_toggleOn_seedsDefault`, `descriptionSeed_toggleOnThenOff_retainsSeededName`, `descriptionSeed_secondToggleOn_doesNotOverwriteNonEmpty`.
- [x] 6.8 Verified the existing positive-expense round-trip tests (`editMode_save_signPreservation_negativeRow_amountChanged`, `editMode_save_signPreservation_negativeRow_amountUnchanged`) still pass — they document the no-regression path for the dominant flow.

## 7. Documentation updates (per AGENTS.md doc maintenance protocol)

- [x] 7.1 F-6.01 in `docs/product-features-planning.md` updated: status → `Implemented`; concrete Acceptance Criteria filled in covering the Toggle card, the title flip matrix, the amount tint, the description seed (incl. its one-way and empty-only gating), the Add-mode sign on save, the Edit-mode draft-`isAddFunds` read and toggle-flip behavior, the tap-to-edit round-trip, and the analytics property reuse. The "Untitled" rename and the single-entry-point decision noted under Edge Cases. Dependencies updated.
- [x] 7.2 F-2.04's Edge Cases / Notes amended: removed the "Add mode unconditionally inserts a non-negative amount; the Add Funds toggle UI is part of F-6.01's future change" line; replaced with language describing toggle-driven sign in both modes.
- [x] 7.3 No `docs/tech-design-doc.md` update needed (no architecture, schema, navigation, or data-model changes).
- [x] 7.4 No `docs/main-prd.md` update needed (no global constraint or glossary changes).

## 8. Build, format, and verify

- [x] 8.1 `make format` — exit 0.
- [x] 8.2 `make lint-fix` — exit 0 after extracting `addFundsCard` to its own file and moving the navigation-title selection onto the viewmodel.
- [x] 8.3 `make build` — exit 0.
- [x] 8.4 `make test` — exit 0; all 485 tests pass (including the 12 new add-funds tests).
- [x] 8.5 Smoke-test in the iOS simulator — user-verified. (Subsequent terminology change: default Description "Adjustment" → "Add funds"; Edit-mode title "Adjustment" → "Add Funds". Code, catalog, translations for all 38 locales, tests, spec, design, proposal, and F-6.01 doc all updated; four-step procedure clean.)
