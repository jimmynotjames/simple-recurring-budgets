## Why

The F-7.04 Recents section is currently an Add-only affordance — Edit/View mode never shows it. But a common Edit-mode task is refining a Description that was mistyped or left blank at first entry (and occasionally correcting the amount to match a known prior entry). Surfacing Recents in Edit mode lets the user fix those with a tap instead of re-typing, without turning Edit into a noisy logging surface.

## What Changes

- Surface the existing Recents section in Edit/View mode, **gated on a blank Description with a persist-once-shown latch**:
  - If the sheet opens with a blank/`nil` Description, Recents shows immediately.
  - If the user clears the Description to blank mid-session, Recents appears.
  - Once revealed, it **persists for the rest of the sheet's lifetime** (it does not hide again when the Description becomes non-empty, e.g. after a tile tap or re-typing).
- Once revealed, Edit-mode Recents reuses the Add-mode affordances and UI unchanged: horizontal tile row, filter-as-you-type (Description is the filter query), single tap overwrites Description, double-tap / VoiceOver custom action overwrites Description **and** amount.
- **Amount-overwrite safety in Edit mode:** the existing (real) amount is protected — a single tile tap fills the Description only and leaves the amount untouched; the double-tap full replace (or clearing the amount first) is the explicit path to also take the tile's amount. This reuses the existing amount-provenance smart-apply rule by seeding the edited amount as user-typed.
- **Self-tile quirk left as-is (explicit decision):** the Recents corpus continues to be built from all of the budget's expense items, including the row being edited, so the corpus is unchanged from Add mode. The edited row is not excluded.
- This **reverses** the current documented decision that "Edit mode never shows the Recents section."

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `add-edit-expense-screen`: the "Edit mode never shows the Recents section" requirement is replaced by a blank-Description-gated, persist-once-shown reveal in Edit mode; the section-visibility and tap-semantics requirements are extended to cover Edit mode (including the user-typed seed that protects the existing amount on a single tap).

## Impact

- Code: [`AddEditExpenseViewModel.swift`](../../../simple-recurring-budgets/Views/ExpenseForm/AddEditExpenseViewModel.swift) (reveal latch, blank-Description detection, `amountProvenance = .userTyped` seed in `init(editing:)`); [`AddEditExpenseView+RecentsSection.swift`](../../../simple-recurring-budgets/Views/ExpenseForm/AddEditExpenseView+RecentsSection.swift) (`shouldShowRecentsSection` condition + docstring).
- Tests: [`AddEditExpenseViewModelRecentsTests.swift`](../../../simple-recurring-budgetsTests/Views/ExpenseForm/AddEditExpenseViewModelRecentsTests.swift) (update the Edit-mode-hidden test; add latch + Edit-provenance tests); the "Recents — Edit mode (no section)" preview; UI screen objects if Edit-mode Recents becomes reachable in journeys.
- Analytics: `expense_recent_reused` can now fire from Edit mode; [`docs/analytics-spec.md`](../../../docs/analytics-spec.md) catalog text updated (optionally add a `from_screen` property for add-vs-edit parity with the other `expense_*` events).
- Docs: [`docs/product-features-planning.md`](../../../docs/product-features-planning.md) F-7.04 (Add-only framing extended to the Edit-mode reveal).

## Doc alignment

This change **intentionally conflicts** with two currently-documented decisions and updates them in the same change:

- **`add-edit-expense-screen` spec** — requirement/scenario "Edit mode never shows the Recents section" is replaced (delta spec in this change).
- **`docs/product-features-planning.md` F-7.04** — frames Recents as Add-only ("when adding a new Expense Item"); to be amended with the Edit-mode reveal + Edit tap-semantics.
- **`docs/analytics-spec.md`** — `expense_recent_reused` described as firing "in Add Expense"; to be amended (and a `from_screen` property optionally added, with a Revision-History entry).
- **`docs/tech-design-doc.md`** — verify only; no architecture/schema change expected.

No `Localizable.xcstrings` keys are expected to be added (analytics property values are internal, not user-facing), so the translation pipeline likely no-ops; a verification task is included regardless.
