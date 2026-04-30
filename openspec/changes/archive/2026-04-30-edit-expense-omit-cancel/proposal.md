## Why

When `AddEditExpenseView` is presented in Edit mode via push navigation (`AppRoute.expenseDetail`), the leading Cancel toolbar button is redundant: tapping it calls `dismiss()`, which pops the view — the same action as the system back chevron. Showing a Cancel button alongside the native back button creates visual clutter and implies a "two-way exit" choice that doesn't exist in practice. Removing it matches the iOS convention for pushed edit screens (e.g., Calendar event editing) and reduces the per-screen tap target count without sacrificing any escape path. The Save button is retained: it provides the explicit commit point that prevents accidental overwrites when the user changes a field and then navigates back without meaning to save.

## What Changes

- **`AddEditExpenseView` Cancel button** — the leading `ToolbarItem(placement: .cancellationAction)` is gated on `!viewModel.isEditing`. In Edit mode (`isEditing == true`) the Cancel button is **not rendered**; in Add mode (`isEditing == false`) it remains as-is.
- **No change to Save** — Save behavior, enablement rules, and VoiceOver labels are unchanged in both modes.
- **No change to Add mode** — the sheet-presented Add flow retains Cancel + Save exactly as specified by F-2.04.
- **No change to Delete** — the Delete Expense button remains Edit-mode-only, unchanged.
- **Spec delta** — `add-edit-expense-screen` requirement "The sheet SHALL expose two toolbar items" is updated to reflect that Cancel is Add-mode-only; Edit mode exposes only Save (plus the system back button).
- **Test** — add a unit assertion that `viewModel.isEditing == true` for an edit-mode VM (confirming the condition that gates the Cancel button) and update/add scenarios to the `add-edit-expense-screen` spec.

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `add-edit-expense-screen`: The requirement "The sheet SHALL expose two toolbar items: a leading Cancel button and a trailing Save button" is refined — Cancel is shown only in Add mode; Edit mode shows Save only (system back chevron is the discard path).

## Impact

- **`simple-recurring-budgets/Views/AddEditExpenseView.swift`** — one-line conditional gate on the Cancel `ToolbarItem`.
- **`openspec/specs/add-edit-expense-screen/spec.md`** (via delta) — toolbar requirement and scenarios updated.
- **`docs/product-features-planning.md`** — F-2.04 acceptance criteria note updated.
- No schema, data model, CloudKit, navigation, or i18n changes.

## Doc alignment

- `docs/product-features-planning.md` F-2.04 lists "Same screen is used for add, edit, and view" and "No Edit Mode" — no conflict; this change doesn't introduce an edit/view mode split, just hides a redundant button.
- `docs/main-prd.md` — no relevant constraints affected.
- `docs/tech-design-doc.md` — no navigation or architecture changes.
- `docs/product-features-planning.md` F-2.04 will need a minor note that Cancel is Add-mode-only. Added as a doc task.
