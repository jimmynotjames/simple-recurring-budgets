## Context

F-6.01 has had its model and display path implemented for some time. `ExpenseItem.amount` is a signed `Decimal`, with `isAddFunds` (`amount < 0`) and `displayAmount` (`abs(amount)`) as derived properties. Budget detail rows already tint add-funds entries with `Color.moneySurplus` and announce them with a distinct VoiceOver label. The analytics surface already carries `isAddFunds` on `expense_logged`, `expense_edited`, and `expense_deleted`.

The user-facing gap has been the **entry path**: today, the Add Expense sheet inserts `ExpenseItem.amount` unconditionally as the positive draft value, with no UI affordance to mark an entry as add-funds. As a result, the F-2.04 spec carries a now-stale clause: *"Add mode unconditionally inserts a non-negative amount; the Add Funds toggle UI is part of F-6.01's future change."*

The UI for closing this gap has already been mocked into `AddEditExpenseView.swift` (Toggle card at the bottom, accent-color tint, navigation-title flip, amount-text tint, description "Add funds" seed, edit-mode init seeding). What remains is the wiring (Add-mode sign on save, Edit-mode toggle-flip honoring the draft instead of the persisted value), tests, the spec deltas, and the doc updates. This design captures the technical choices already made in the prior conversation and the few that remain.

## Goals / Non-Goals

**Goals:**

- Users can create add-funds entries from the Add Expense sheet via a single discrete Toggle.
- Round-trip correctness: tapping a green-tinted add-funds row in the Budget detail list reopens the same form in the same state (toggle on, amount tinted, "Funds" title).
- Editing flexibility: users may flip an existing row's type between Expense and Add Funds in Edit mode without delete-and-recreate workarounds.
- No regression for the dominant flow: an expense added without touching the toggle continues to write a positive amount as it does today.
- Analytics correctness: the existing `isAddFunds` property on `expense_logged` / `expense_edited` accurately reflects the user's intent (toggle state at save time), not the persisted state at edit-open time.

**Non-Goals:**

- A second entry point on the Budget detail screen or the Budgets list (e.g., a toolbar "Add Funds…" menu item). The toggle inside the form is the single discrete affordance — discussed and decided in the prior conversation.
- Renaming the "Add Expense" buttons on the Budget detail primary slot or the Budgets-list per-row plus button. They stay "Add Expense" because the dominant use case is recording an expense.
- New analytics events (e.g., `funds_added`). The existing `isAddFunds` property is sufficient for funnel and frequency reporting.
- Schema changes. `ExpenseItem.amount` already accepts negatives.
- Carry-over math changes. The calculator is already signed-correct; adding an add-funds entry already updates the chip and carry-over correctly.

## Decisions

**1. Place the Toggle in its own card at the end of the form (not at the top, not as a segmented Picker).**

Considered earlier in the conversation: a segmented `Expense | Add Funds` picker at the top of the Amount card, or a second entry-point menu item on the Budget detail screen. Chose the bottom-card Toggle because:
- Frequency matches placement: add-funds is rare relative to logging expenses.
- The strong visual feedback (title flip, amount tint, description seed) compensates for lower discoverability.
- A caption earns its keep under a Toggle, where it would feel preachy under a segmented Picker.
- Keeps the primary three-card rhythm (Amount / Description / When) clean.

**2. Description seed is one-way and gated on empty/whitespace.**

The `didSet` on `isAddFunds` writes "Add funds" into `name` only when toggling from `false` → `true` AND the trimmed `name` is empty. It does not clear or revert when the user toggles back off; it does not overwrite a user-entered description. Rationale: the seed is a helpful default for first-time use, not a coupled state — once the user has committed to a description, the toggle should be a pure type modifier.

**3. Read the draft `isAddFunds` (not the persisted `expense.isAddFunds`) when signing the amount on Edit-mode Save.**

The current Edit-mode save path reads `expense.isAddFunds` (a derived property on the persisted model) to decide whether to flip the sign. With the toggle now editable in Edit mode, this would silently ignore a flipped toggle. Switch the read to the viewmodel's current `isAddFunds`. The Edit-mode comparator for the `changed` flag should also be updated so that flipping the toggle alone — without changing amount, name, or date — marks the entry as changed and triggers a save + analytics event.

**4. Navigation title flips four ways: Add Expense / Add Funds / Expense / Add Funds.**

The matrix is `isEditing × isAddFunds`. Add-mode is the expected action-verb pair (Add Expense / Add Funds). Edit mode is asymmetric on purpose: the Expense case uses the noun "Expense" (parallel to "Current Day" / "Past Days" terminology), but the add-funds case uses "Add Funds" — same as the Add-mode title — because "Funds" alone reads as an awkward noun-form title. The asymmetry is accepted in exchange for a title that reads naturally in both modes. Side benefit: "Add Funds" / "Add funds" / "Add funds" appear as the Edit-mode title, the Toggle label, and the seeded Description default, giving consistent terminology across the surface.

**5. Rename `budgetDetail.expenseRow.unnamed` from "Untitled expense" to "Untitled".**

The same key is used for both expense and add-funds rows (and in their VoiceOver labels). With add-funds entries now first-class, "Untitled expense" reads oddly on a green-tinted add-funds row. Keep the localization key; update the value and the translator comment.

**6. No analytics-event additions.**

`AnalyticsProperty.isAddFunds` is already attached to `expense_logged`, `expense_edited`, and `expense_deleted` at all three call sites. The Add-mode call site already reads `expense.isAddFunds` from the just-inserted `ExpenseItem`, so once Add-mode save signs the amount per the toggle, the analytics property will be correct automatically. No new event names, no spec.md changes needed in the analytics doc.

**7. Edit-mode toggle is editable, not disabled.**

Alternative considered: disable the Toggle in Edit mode so existing rows are immutable in type. Rejected because flipping is a cheap, reversible, model-supported operation; denying it forces users into delete-and-recreate for what's likely a fat-finger correction. This is also consistent with the rest of the Edit-mode contract — name, amount, date, all editable.

**8. Doc update happens in-flight, not deferred.**

Per `docs/main-prd.md` §6.8 and AGENTS.md, the F-6.01 status update (Partially implemented → Implemented with concrete ACs) and the F-2.04 amendment (removing the "non-negative amount" line) ship as part of this change's task list, not as a follow-up.

## Risks / Trade-offs

- **[Discoverability of the Toggle]** → The Toggle sits at the bottom of the form. Users who don't scroll on smaller devices, or who don't experiment, may not realize they can add funds. **Mitigation:** the in-form caption explains exactly what it does once discovered; the bottom-of-form placement is justified by frequency (see Decision 1). If post-ship analytics show very low `isAddFunds=true` rates relative to qualitative feedback, revisit with a second entry point in the Budget detail overflow menu.
- **[Sign-flip on Edit lost without test coverage]** → If the Edit-mode `save()` continues to read `expense.isAddFunds` instead of the draft, a user who flips the toggle in Edit mode will see no change after Save. **Mitigation:** explicit test for toggle-flip-only edits, and a test for amount-edit + toggle-flip together.
- **[Description seed surprise]** → If the user types nothing in Description, toggles on, sees "Add funds" auto-fill, then types over it — fine. If they toggle on and off and on again, they'll see "Add funds" the first time only (because by then the field is non-empty). This is intentional but might confuse a first-time tester. **Mitigation:** the gating is one-way and well-defined; ship as-is and only revisit if real feedback shows confusion.
- **[Localization lag]** → Six new keys (and one modified value) go to all 38 storefront locales via `scripts/translate_catalog/`. **Mitigation:** standard cross-cutting concern; run the script as part of the change per `docs/main-prd.md` §6.8 and AGENTS.md.

## Migration Plan

No migration required. The data model already supports signed amounts; no existing data needs rewriting. New rows created post-ship use the same `ExpenseItem.amount` field with sign determined by the toggle. Existing add-funds rows (created via debug paths or direct database manipulation) continue to display and behave the same — only now they round-trip correctly through the editor.

Rollout is a single shipped change. No feature flag is warranted (the surface is small, the rollback path is a code revert, and there's no risky data path).

## Open Questions

None. The UI and copy decisions were finalized in the prior conversation; the wiring decisions in this design were all implicit in that conversation and are recorded here for the record.
