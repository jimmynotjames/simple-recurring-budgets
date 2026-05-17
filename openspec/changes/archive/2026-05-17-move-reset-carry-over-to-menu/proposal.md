## Why

The Reset Carry-Over control currently lives inline in the Budget Detail screen header, immediately to the right of the `CarryOverChip`. This placement creates two ongoing problems:

1. **Asymmetric destructive surface.** The closely related Reset Budget action lives in the toolbar overflow Menu (alongside Edit Budget and Pause/Resume), while Reset Carry-Over sits inline. Users who learn the Menu path for one would reasonably expect the other to be there too, and discovering "Reset Carry-Over lives in a different place" is a small but persistent friction.
2. **Header weight.** The header already carries the largest, most-read content on the screen (remaining amount, period, `RemainingBar`, and up to two chips). Adding a persistent action button to that row competes with the visual hierarchy of an infrequent destructive action that does not need permanent header real estate.

Moving Reset Carry-Over into the toolbar overflow Menu — paired with Reset Budget under the existing Divider — consolidates destructive actions in one predictable surface, declutters the header, and aligns with the iOS HIG pattern of grouping infrequent/destructive actions in an ellipsis Menu.

## What Changes

- **Remove** the inline "Reset" button from the header's `StatusChipRow` trailing slot on `BudgetDetailView`. The `CarryOverChip` continues to render in the header on the same row as the existing `PausedChip` (when present), without a trailing action.
- **Add** a "Reset Carry-Over…" item to the toolbar overflow Menu, placed below the existing Divider and above "Reset Budget…" (least-destructive-first ordering within the destructive group). System image: `arrow.counterclockwise.circle` (distinct from Reset Budget's `arrow.counterclockwise`), `role: .destructive`.
- **Visibility rule (preserved):** the Reset Carry-Over Menu item SHALL be visible whenever `Budget.isCarryOverEnabled == true`, regardless of whether the live carry-over balance is zero or non-zero. When `isCarryOverEnabled == false`, the item SHALL be omitted entirely. This matches the prior header-button gating rule; no new visibility logic is introduced.
- **Confirmation dialog text:** unchanged. The existing alert title (`budgetDetail.resetCarryOver.alert.title` — "Reset carry-over?") and message (`budgetDetail.resetCarryOver.alert.message` — "The carry-over balance will be cleared and start fresh from zero.") read correctly from the Menu trigger because they describe the action's effect rather than the trigger's location. No copy change required.
- **Rename or repurpose strings:** the `budgetDetail.resetCarryOver.button` ("Reset") header-button label is no longer used and SHALL be removed from `Localizable.xcstrings`. A new key `budgetDetail.menu.resetCarryOver` ("Reset Carry-Over…") is introduced for the Menu item, with the trailing ellipsis matching the "Reset Budget…" menu item convention.
- **Accessibility:** the existing button-level accessibility label/hint keys (`budgetDetail.resetCarryOver.button.accessibilityLabel`, `budgetDetail.resetCarryOver.button.accessibilityHint`) are no longer needed for the header. A Menu-item accessibility hint key (`budgetDetail.menu.resetCarryOver.accessibilityHint`) is added, mirroring the existing pattern for `budgetDetail.menu.resetBudget.accessibilityHint`, with en-US value "Clears the carry-over balance to zero. Expenses are not affected."
- **Pre-existing spec drift fix (housekeeping):** the existing Reset Carry-Over requirement still references the removed `Budget.carryOverAmount` / `Budget.carryOverLastResetDate` fields. The modified requirement updates the operational steps to match the current model (`Budget.lastResetDate = now`, `Budget.lastModified = now`, service-delegated write via `BudgetLifecycleService.resetCarryOver(_:context:)`), matching the same drift correction performed in the archived `reset-budget-auto-resume` change.

Not in scope: changing the underlying reset mechanism, changing analytics (`carryOverReset` event continues to fire from the same call site, just triggered from the Menu now), changing the `CarryOverChip` itself, or any change to Specific Dates / paused / postEnd visibility logic (the existing `isCarryOverEnabled` gate already handles those cases, since SD budgets cannot have carry-over enabled per F-2.08-adjacent product rules and the toggle remains user-controlled in other states).

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `budget-detail-screen`: Status header carry-over row no longer renders a trailing Reset button; Toolbar overflow Menu gains a "Reset Carry-Over…" item; Reset Carry-Over trigger surface and operational steps updated (with pre-existing field-name drift corrected).

## Impact

- **Code:**
  - `simple-recurring-budgets/Views/BudgetDetailView.swift` — remove the `if budget.isCarryOverEnabled { Button("Reset")... }` trailing-slot content passed to `StatusChipRow`, leaving an `EmptyView` (or omitting the trailing closure to use the no-trailing convenience initializer); add a "Reset Carry-Over…" `Button` to the toolbar Menu beneath the Divider and above "Reset Budget…"; keep the `.alert(...)` and `resetCarryOver()` action wiring unchanged. The `@State private var showResetCarryOverConfirm` remains.
  - `simple-recurring-budgets/Views/StatusChipRow.swift` — no source change; the trailing `@ViewBuilder` slot remains generic and continues to be used by callers that need it (none after this change, but the API stays for future use).
- **Strings (`Localizable.xcstrings`):**
  - Remove: `budgetDetail.resetCarryOver.button`, `budgetDetail.resetCarryOver.button.accessibilityLabel`, `budgetDetail.resetCarryOver.button.accessibilityHint`.
  - Add: `budgetDetail.menu.resetCarryOver` (en-US: "Reset Carry-Over…"), `budgetDetail.menu.resetCarryOver.accessibilityHint` (en-US: "Clears the carry-over balance to zero. Expenses are not affected.").
  - Unchanged: `budgetDetail.resetCarryOver.alert.title`, `budgetDetail.resetCarryOver.alert.message`, `budgetDetail.resetCarryOver.alert.confirm`.
  - Translations queue: re-run `scripts/translate_catalog/` pipeline for added keys; removed keys are dropped naturally.
- **Analytics:** no change. `AnalyticsEvent.carryOverReset` continues to fire from `resetCarryOver()` with the same property shape (`period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount`).
- **Logging:** no change. The existing `Logger.ui.debug("ui.action: resetCarryOver budget=...")` line stays.
- **Specs (`openspec/specs/budget-detail-screen/spec.md`):**
  - Modified: "Status header presents remaining, period, RemainingBar, and conditional carry-over chip" — remove the trailing Reset button from the carry-over row text and scenarios.
  - Modified: "Toolbar overflow Menu hosts Edit Budget and Reset Budget actions" — rename to include Reset Carry-Over; add the new item between Divider and Reset Budget; add scenarios for visibility and selection.
  - Modified: "Reset Carry-Over presents a confirmation alert and zeros only carry-over" — change the trigger from the header button to the Menu item; correct operational steps to match current model (`lastResetDate`, service-delegated write).
- **Docs (must be updated in lockstep — these explicitly specify the current inline placement):**
  - `docs/main-prd.md` §6.7 Reset Carry-Over table row (currently: "Budget detail screen → header inline 'Reset' button") → "Budget detail screen → toolbar overflow Menu → 'Reset Carry-Over…'".
  - `docs/product-features-planning.md` F-2.02 status-header bullet (currently lists "inline `CarryOverChip` and a small **Reset** button") → remove the Reset button mention; the F-2.02 Menu bullet adds "Reset Carry-Over…" alongside "Reset Budget…".
  - `docs/tech-design-doc.md` — no schema or service change; the only existing references to Reset Carry-Over are at the service / logging / a11y level and remain accurate.
- **Cross-cutting concerns (`docs/main-prd.md` §6.8):**
  - **Accessibility:** new Menu item gets a localized accessibility hint (key noted above) matching the destructive-hint convention for `resetBudget`.
  - **Localized source strings:** all new strings keyed with `comment:` in `Localizable.xcstrings`.
  - **Translations queue:** re-run via `scripts/translate_catalog/` for new keys after en-US is in place.
  - **Mixpanel user-action analytics:** unchanged; existing `carryOverReset` event continues to fire from the same code path.
- **Data model / CloudKit / sync:** no change.
- **Risk / migration:** none. This is a UI relocation; no persisted data, schema, or analytics taxonomy changes. Existing automated tests that target the header Reset button will need their selectors updated (or be replaced with Menu-based tests); to be enumerated in `tasks.md`.

## Doc alignment

Skimmed `docs/main-prd.md` (§6.7 Reset Carry-Over table, glossary entries for Reset Budget / Reset Carry-Over), `docs/product-features-planning.md` (F-2.02 status header and overflow Menu bullets), and `docs/tech-design-doc.md` (BudgetDetailView destructive-action notes, `BudgetLifecycleService.resetCarryOver`, Logger.ui category, a11y hints for destructive controls).

Two docs explicitly state the current inline placement and must be updated as part of this change: `docs/main-prd.md` §6.7 table row, and `docs/product-features-planning.md` F-2.02. Both updates are listed under Impact above and will appear in `tasks.md`. No silent override of PRD/feature IDs.
