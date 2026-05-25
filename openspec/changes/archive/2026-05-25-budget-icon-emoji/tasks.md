## 1. Review existing implementation against the specs

- [x] 1.1 Verify `Budget.icon: String?` (default `nil`) and the `Budget.init(icon:)` param match the `data-models` delta
- [x] 1.2 Verify `AddEditBudgetViewModel` loads `icon` on edit, passes `icon` on create, and gates Save on the icon diff (`iconChanged`)
- [x] 1.3 Verify `AddEditBudgetView` icon chip presents `BudgetIconPicker` bound to `viewModel.icon` (set / change / remove)
- [x] 1.4 Verify `BudgetIconPicker` is the sole curated-set source, entries are unique, and selection writes back + dismisses; "Remove" clears
- [x] 1.5 Verify `BudgetsView`/`BudgetRowView` render the icon as a single-space name prefix (name-only when unset) and keep the icon decorative
- [x] 1.6 Verify `BudgetDetailView` nav title is icon-prefixed when set, name-only otherwise
- [x] 1.7 Confirm no new analytics event/property was added for icon changes

## 2. Accessibility

- [x] 2.1 Confirm the row's composed `.accessibilityLabel` (name + status) excludes the decorative icon; add/adjust if needed
- [x] 2.2 Confirm the icon chip exposes localized label, value (current icon or "None"), and hint
- [x] 2.3 Confirm picker emoji are accessible controls labeled by emoji, with the selected item carrying `.isSelected`
- [x] 2.4 Spot-check legibility of the chip, list prefix, and picker at xxxLarge Dynamic Type and in Dark Mode (preview-level)

## 3. Localization

- [x] 3.1 Confirm all icon UI strings are keyed (`addEditBudget.field.icon.*`, `addEditBudget.iconPicker.*`) with translator comments; no hard-coded literals
- [x] 3.2 Run the `scripts/translate_catalog/` pipeline for the new keys (extract → translate → merge → validate)
- [x] 3.3 Reconcile orphaned former keys (`addEditBudget.field.emoji.*`, `addEditBudget.emojiPicker.*`) in `Localizable.xcstrings`
- [x] 3.4 Run the translation check (`check_translations.py`) and confirm no missing/stale keys for this feature

## 4. Tests (Swift Testing)

- [x] 4.1 Model: a `Budget` created without an `icon` reads `nil`; created with `icon` round-trips through SwiftData (insert → fetch)
- [x] 4.2 View model (create): saving a new budget with a chosen icon persists `Budget.icon`; saving with none leaves it `nil`
- [x] 4.3 View model (edit): changing the icon updates `Budget.icon` and bumps `lastModified`
- [x] 4.4 View model (edit): removing the icon sets `Budget.icon` to `nil`
- [x] 4.5 View model (edit): an icon-only change still satisfies the Save-needed gate (persists)
- [x] 4.6 Picker: `BudgetIconPicker` set has no duplicate entries; selecting writes the binding; Remove clears it

## 5. Build, verify, and doc alignment

- [x] 5.1 Run the four-step procedure: `make format` → `make lint-fix` → `make build` → `make test`
- [x] 5.2 Verify implementation matches the `budget-icon` and `data-models` deltas (run `openspec` verify)
- [x] 5.3 Confirm `docs/product-features-planning.md` (F-4.03/F-4.04) and `docs/tech-design-doc.md` §9 reflect the shipped scope; update if any drift remains
- [x] 5.4 Update F-4.03 Status to Implemented once tests/translations/a11y are complete
