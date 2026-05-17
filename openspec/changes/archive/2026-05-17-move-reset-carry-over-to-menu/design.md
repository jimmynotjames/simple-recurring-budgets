## Context

Today, `BudgetDetailView` renders a small bordered "Reset" button in the header's `StatusChipRow` trailing slot whenever `Budget.isCarryOverEnabled == true`. The button presents a SwiftUI `.alert` and, on confirm, calls `BudgetLifecycleService.resetCarryOver(_:context:)`, which sets `Budget.lastResetDate = now` so the live carry-over walker (per `docs/main-prd.md` §6.7) excludes all prior periods. No `ExpenseItem`s are touched.

The screen's other destructive action, Reset Budget, lives in the toolbar overflow Menu (a single `topBarTrailing` `Menu` labeled `ellipsis.circle`), placed below a `Divider` that separates it from Edit Budget and the state-driven Pause/Resume item. Reset Budget recently gained a paused-auto-resume behavior (archived change `2026-05-17-reset-budget-auto-resume`), and that change normalized its presentation: `arrow.counterclockwise` icon, `role: .destructive`, confirmation dialog, accessibility hint describing the irreversible consequence.

This change relocates Reset Carry-Over from the header into that same Menu, paired with Reset Budget under the existing Divider. The relocation is purely a trigger-surface move — no change to the service write path, the alert, analytics, or logging.

Two docs explicitly state the current inline placement and must be updated as part of this change:

- `docs/main-prd.md` §6.7 Reset Carry-Over table row: "Budget detail screen → header inline 'Reset' button".
- `docs/product-features-planning.md` F-2.02 status-header bullet: "an inline `CarryOverChip` and a small **Reset** button".

`docs/tech-design-doc.md` does not pin a trigger surface; it only documents the service method, the logging category, and the destructive-control a11y-hint convention — those remain accurate.

## Goals / Non-Goals

**Goals:**

- Consolidate Reset Budget and Reset Carry-Over into one predictable destructive-action surface (the toolbar overflow Menu).
- Reduce visual weight in the header so the primary content (remaining amount, period, `RemainingBar`, status chips) has more room to breathe at every Dynamic Type size.
- Preserve all existing behavior: gating rules, confirmation alert text, write path through `BudgetLifecycleService.resetCarryOver`, analytics event, OSLog entry.
- Bring the Reset Carry-Over spec text in line with the current `Budget` model (housekeeping drift fix; the same fix the prior change did for Reset Budget).

**Non-Goals:**

- No change to *when* Reset Carry-Over is available — it remains gated by `Budget.isCarryOverEnabled == true`, regardless of carry-over balance sign or magnitude, regardless of lifecycle state. (This matches the user-confirmed scope: always include when carry-over is on; hide only when carry-over is off for that budget.)
- No change to the confirmation alert title or body text (the existing copy describes the effect, not the trigger, so it reads correctly from a Menu item).
- No change to the underlying reset mechanism (`lastResetDate = now` via the service).
- No new analytics event; the existing `carryOverReset` event continues to fire from the same call site.
- No change to `CarryOverChip` or `PausedChip`.
- No change to the `StatusChipRow` component's public API — the trailing `@ViewBuilder` slot stays in place and is simply unused by `BudgetDetailView` after this change. (Removing the API would be premature; `StatusChipRow` is shared with `BudgetRowView` and may need a trailing slot in the future.)

## Decisions

### 1. Menu placement and ordering

**Decision:** Place "Reset Carry-Over…" *above* "Reset Budget…", both below the existing `Divider`. Final Menu order:

1. Edit Budget
2. Pause Budget / Resume Budget (state-driven, hidden for Specific Dates and `.postEnd`)
3. `Divider`
4. **Reset Carry-Over…** (new)
5. Reset Budget…

**Rationale:** Within a destructive-action group, ordering from *least* to *most* destructive lets the user scan downward and stop as soon as they find the action they want. Reset Carry-Over preserves all expenses (no data loss beyond carry-over). Reset Budget deletes every `ExpenseItem`. Putting the heavier action last reduces the chance of accidental selection if the user mis-taps the first destructive item.

**Alternatives considered:**

- *Reset Carry-Over below Reset Budget* — would put the most destructive action mid-list, which is slightly riskier for accidental taps and violates the "anchor heavy items at the bottom" iOS convention for stack-ranked destructive menus.
- *No Divider between Pause/Resume and the resets* — rejected; the existing Divider already separates the non-destructive items from the destructive group, and that separation should be preserved.
- *Second Divider between Reset Carry-Over and Reset Budget* — rejected; both items are destructive and conceptually paired, so a single grouping is clearer than splitting them into two visually distinct sub-groups.

### 2. System image for Reset Carry-Over

**Decision:** Use `arrow.counterclockwise.circle` for the new Menu item. Reset Budget uses `arrow.counterclockwise` (after the prior change replaced `trash`).

**Rationale:** The two actions share a "reset" concept and should read as related, but they must be visually distinguishable in a vertical Menu. The `.circle` variant of the same glyph gives clear visual kinship while preventing them from looking identical at a glance. Both render in the destructive-role red foreground.

**Alternatives considered:**

- *Same icon for both* — rejected; would harm scan-ability and accident resistance.
- *`xmark.circle` or `eraser`* — rejected; semantically weaker than counterclockwise (which already reads as "reset" elsewhere in the app and HIG).
- *Custom symbol* — not warranted for a single Menu item.

### 3. Visibility rule

**Decision:** The Reset Carry-Over Menu item is visible iff `Budget.isCarryOverEnabled == true`. No additional gating by lifecycle state (active / paused / preStart / postEnd), no gating by current carry-over magnitude, no gating by period type beyond what `isCarryOverEnabled` already implicitly enforces.

**Rationale:** This is the same rule the header button uses today. `Budget.isCarryOverEnabled` is a user-controlled toggle that captures the per-budget intent for the feature; if it's on, the user has opted into carry-over and may want to reset it. Hiding the item when the live balance is zero would create a discoverability cliff (the action vanishes and reappears as state changes) and would prevent a user from confirming "yes, it's zero — keep it that way" via an explicit reset write. The user has explicitly requested this rule.

For Specific Dates budgets: the existing `isCarryOverEnabled` toggle behavior for that period type is the single source of truth and is not modified here. If a Specific Dates budget reaches `BudgetDetailView` with `isCarryOverEnabled == true`, the Menu item will show — which is the same behavior the header button has today. Any product rule that bans carry-over for SD budgets is enforced upstream at the toggle level, not by this view.

### 4. Confirmation alert: keep as `.alert`, keep the existing copy

**Decision:** Continue using the existing `.alert(...)` modifier with the existing string keys (`budgetDetail.resetCarryOver.alert.title`, `budgetDetail.resetCarryOver.alert.message`, `budgetDetail.resetCarryOver.alert.confirm`). No copy changes.

**Rationale:** The alert title ("Reset carry-over?") and body ("The carry-over balance will be cleared and start fresh from zero.") describe the *effect* of confirming the action, not the trigger's location. They read correctly from the Menu just as they did from the header button. Per the user's instruction: keep as is unless the text feels off — it does not.

Reset Budget uses a `confirmationDialog` (action-sheet style) because Reset Budget is invoked from the Menu and the dialog body is a longer multi-effect description. Reset Carry-Over has a single, short, focused effect and the existing `.alert` is appropriate for that. Keeping the two confirmations stylistically different is acceptable because they have meaningfully different scope and risk.

**Alternatives considered:**

- *Switch Reset Carry-Over to `confirmationDialog` for parity with Reset Budget* — rejected; the alert pattern is correct for a single-focus destructive confirmation, and reworking the modifier would risk regressions for no clear UX win.
- *Add a "no expenses will be deleted" reassurance line to the body* — tempting given the proximity to Reset Budget, but the current copy is already unambiguous and shorter is better for SwiftUI alerts.

### 5. String catalog: remove old keys, add new ones

**Decision:**

- **Remove:** `budgetDetail.resetCarryOver.button`, `budgetDetail.resetCarryOver.button.accessibilityLabel`, `budgetDetail.resetCarryOver.button.accessibilityHint`.
- **Add:** `budgetDetail.menu.resetCarryOver` (en-US: "Reset Carry-Over…"), `budgetDetail.menu.resetCarryOver.accessibilityHint` (en-US: "Clears the carry-over balance to zero. Expenses are not affected.").
- **Unchanged:** alert title/message/confirm keys.

**Rationale:**

- The removed keys are no longer referenced after the header button goes away. The project convention is to delete unused keys rather than leave them as orphan translations (matches the `AGENTS.md` and prior changes pattern).
- The new key uses the `budgetDetail.menu.*` namespace, matching `budgetDetail.menu.editBudget`, `budgetDetail.menu.resetBudget`, `budgetDetail.menu.pauseBudget`, `budgetDetail.menu.resumeBudget`. The trailing ellipsis ("Reset Carry-Over…") matches "Reset Budget…" and signals that a confirmation step follows.
- The new accessibility hint follows the destructive-control hint convention from `docs/main-prd.md` §6.8 and parallels the existing `budgetDetail.menu.resetBudget.accessibilityHint`. The wording "Expenses are not affected" mirrors the prior header-button hint to preserve the carefully chosen reassurance, while dropping the now-redundant "Resets the carry-over balance to zero" prefix in favor of the more direct verb.

**Alternatives considered:**

- *Reuse `budgetDetail.resetCarryOver.button` for the Menu item* — rejected; the en-US value differs ("Reset" vs. "Reset Carry-Over…"), and the menu-item label needs the full noun phrase because the surrounding chip context is gone.
- *Keep the old keys around in case we revert* — rejected; OpenSpec assumes forward motion, and reverts would re-add keys via the same translation pipeline.

### 6. Pre-existing spec drift: fix as part of this change

**Decision:** While modifying the Reset Carry-Over requirement to change its trigger surface, also correct the operational steps to match the current `Budget` model.

The current spec says:
> On confirm, the system SHALL set `Budget.carryOverAmount = 0`, set `Budget.carryOverLastResetDate = Date()`, ...

Neither `carryOverAmount` nor `carryOverLastResetDate` exists on `Budget` anymore — they were removed by the budget-calculations rewrite (archived change `2026-05-15-rewrite-budget-calculations`). The actual write is `Budget.lastResetDate = now` through `BudgetLifecycleService.resetCarryOver(_:context:)`.

**Rationale:** This is the same drift fix the `reset-budget-auto-resume` change applied to the Reset Budget requirement. Doing both fixes in their respective placement-touching change is the natural place; carrying the drift forward unchanged would be a missed opportunity. The fix is purely descriptive — no behavior change.

## Risks / Trade-offs

- **[Discoverability regression]** Users who have learned the inline header button may take a moment to find Reset Carry-Over in the Menu. → **Mitigation:** This is a one-time relearning cost. The Menu surface is the same place users already go for Reset Budget, Pause/Resume, and Edit Budget, so the cognitive cost is low. No in-app announcement or onboarding step is justified for a single relocation.
- **[Test breakage]** Any UI test that selects the header Reset button by accessibility label will break. → **Mitigation:** Enumerate affected tests in `tasks.md` and update them to navigate via the Menu. Swift Testing's `confirmation` and `#expect` patterns make this straightforward.
- **[Translation churn]** Two key removals + two key additions create work in the translations queue. → **Mitigation:** The removed keys are short; the new keys reuse vocabulary already present in `budgetDetail.menu.resetBudget` and `budgetDetail.menu.resetBudget.accessibilityHint`. Cost is minimal and the `scripts/translate_catalog/` pipeline handles it in one pass.
- **[Visual parity with Reset Budget]** The two reset confirmations now use different SwiftUI presentation styles (`.alert` vs. `confirmationDialog`). → **Trade-off accepted.** See Decision 4: the difference reflects a meaningful difference in scope. Forcing parity would be a separate, larger UX decision and is out of scope.
- **[Pre-existing drift fix bundled in]** Folding the `carryOverAmount` → `lastResetDate` correction into this change technically expands its surface beyond a pure relocation. → **Mitigation:** The drift fix is purely descriptive (matches current code), is small, and is in the exact requirement being modified anyway. Splitting it into its own OpenSpec change would be ceremony for no benefit. Called out explicitly in proposal and design.

## Migration Plan

No data migration. No phased rollout. The change ships as a single PR per the standard flow:

1. Code change in `BudgetDetailView.swift` (remove trailing slot content; add Menu Button + accessibility hint).
2. String Catalog edits (remove three keys; add two keys; queue translations).
3. Spec delta committed under `openspec/changes/move-reset-carry-over-to-menu/specs/budget-detail-screen/spec.md`.
4. Doc updates in `docs/main-prd.md` §6.7 and `docs/product-features-planning.md` F-2.02.
5. Test updates for any UI test that targeted the header Reset button.
6. Standard four-step verification: `make format` → `make lint-fix` → `make build` → `make test`.

Rollback: revert the PR. No data, schema, or CloudKit implications.

## Open Questions

None at proposal time. All scope questions raised in the original UX discussion are resolved per the user's instructions:

- Option 1 (Menu) chosen.
- Visibility: gate on `isCarryOverEnabled` only; show regardless of balance.
- Confirmation copy: unchanged.

## Doc alignment

- `docs/main-prd.md` §6.7 — **conflicts with this change**; the §6.7 Reset Carry-Over table row explicitly says "Budget detail screen → header inline 'Reset' button" and will be updated as a task in this change.
- `docs/product-features-planning.md` F-2.02 — **conflicts with this change**; the status-header bullet currently lists "an inline `CarryOverChip` and a small **Reset** button" and the Menu bullet currently lists only Edit Budget / Pause/Resume / Reset Budget. Both bullets will be updated as tasks.
- `docs/tech-design-doc.md` — no conflict; the file documents the service method (`BudgetLifecycleService.resetCarryOver(_:context:)`), the OSLog category (`Logger.ui`), and the destructive-control a11y-hint convention. All three remain accurate after this change.
