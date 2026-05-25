## Why

Budgets are currently distinguished only by their text name, which is slow to scan in a list and misses the brief's "quietly warm, low-key delightful" personality. F-4.03 calls for an optional per-budget icon. We scope that icon to a single emoji chosen from a curated, in-app set — the simplest, most delightful option that needs no extra data infrastructure (one optional `String`, no asset storage, CloudKit-safe).

## What Changes

- Add an optional **icon** (a single emoji) to each Budget, chosen from a curated set the app provides.
- **Add/Edit Budget screen**: an icon chip beside the name field that opens a curated emoji picker sheet; choosing is optional, and an existing icon can be removed.
- **Budgets screen** and **Budget detail screen**: display the chosen icon as a prefix of the budget name (name-only when unset).
- Persist the icon on the `Budget` entity (`Budget.icon: String?`), synced via CloudKit.
- The curated emoji set lives in code (the picker component is the master source); it is not enumerated in specs or docs.
- Close the cross-cutting gaps for the feature: **tests** (model persistence + round-trip, picker selection/removal, name-prefix rendering), **translations** for the new source strings, and **accessibility** (decorative icon hidden from VoiceOver on list rows; labeled icon chip + picker; nav-title behavior on detail).
- Explicitly **out of scope (canceled, not deferred)** per the updated F-4.03: SF Symbols as an icon source, Genmoji/custom-generated icons, LLM-guessed defaults, and photo upload (former F-4.04).

## Capabilities

### New Capabilities
- `budget-icon`: Selecting an optional per-budget icon (a single emoji from a curated in-app set) on the Add/Edit Budget screen, and displaying it as a name prefix on the Budgets list and Budget detail screen. Covers optionality, removal, the picker behavior, accessibility, and localization of the picker/chip strings.

### Modified Capabilities
- `data-models`: The `Budget` entity gains an optional `icon: String?` attribute (single emoji by convention; `nil` when unset), and `Budget.init` gains a defaulted `icon` parameter.

## Impact

- **Code (already implemented; this change reviews and gap-fills):**
  - `simple-recurring-budgets/Models/Budget.swift` — `icon: String?` attribute + init param.
  - `simple-recurring-budgets/Views/AddEditBudgetViewModel.swift` — `icon` draft, load on edit, persist on create/edit (gate-only diff flag).
  - `simple-recurring-budgets/Views/AddEditBudgetView.swift` — icon chip in the name card, presents the picker.
  - `simple-recurring-budgets/Views/BudgetIconPicker.swift` — curated emoji grid picker (master source for the set).
  - `simple-recurring-budgets/Views/BudgetsView.swift` — row renders icon as name prefix (decorative).
  - `simple-recurring-budgets/Views/BudgetDetailView.swift` — nav title prefixed with icon.
  - `simple-recurring-budgets/Models/DebugData.swift` — preview fixtures seeded with sample icons.
- **Persistence / sync:** additive optional SwiftData attribute; in-place `SchemaV1` (greenfield, unreleased), CloudKit-safe — no migration plan required.
- **Localization:** new source strings (`addEditBudget.field.icon.*`, `addEditBudget.iconPicker.*`) need the `scripts/translate_catalog/` pipeline run; orphaned former `emoji`-named keys should be reconciled in the catalog.
- **Accessibility:** icon is decorative on list rows (name read without it); icon chip + picker carry labels/hints; detail nav title currently includes the emoji in its announcement.
- **Analytics:** no new event/property — icon edits are cosmetic and feed only the existing `budget_edited` aggregate change gate (consistent with F-8.02 scope).

## Doc alignment

Skimmed `docs/product-features-planning.md`, `docs/main-prd.md`, and `docs/tech-design-doc.md`. This proposal matches the recently-updated **F-4.03** (icon scoped to a curated emoji set; SF Symbols/Genmoji/LLM-default/photo descoped) and the canceled **F-4.04**, and `tech-design-doc.md` §9's updated F-4.03 row. No conflicts with the docs. No further doc updates required by this change beyond keeping those entries current.
