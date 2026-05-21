## Why

The view layer treats each inactive lifecycle state (`.preStart`, `.paused`, `.postEnd`) inconsistently today. Paused alone gets a dimmed amount, dimmed bar, dimmed CarryOverChip, and a `PausedChip`. `.preStart` is silently shown as `$0` with no chip and no dimming. `.postEnd` shows the final period's `remaining` with no visual treatment at all. As `docs/product-features-planning.md` F-7.05 / F-7.07 (per-budget start/end date) reach the UI, this gap will become visible to users: a paused budget will read as "paused since …" while a budget that hasn't started yet will read as "$0 today" — same conceptual state ("the budget isn't running right now"), different presentation, no caption to explain it.

This change unifies the **presentation** of all three "not currently running" states under a single view-layer concept (`BudgetInactiveReason`) — a dimmed amount + bar plus a single status chip (`InactiveStatusChip`) carrying the reason ("Starts Jan 1", "Paused · May 1, 2026", "Ended Apr 10"). The unification is UI-only: `BudgetCalculator`, `BudgetSnapshot`, `BudgetLifecycleService`, and the four-way `BudgetLifecycleState` enum stay exactly as they are.

## What Changes

- Introduce `BudgetInactiveReason` in the view layer with three cases (`.preStart(startDate:)`, `.paused(since:)`, `.postEnd(endDate:)`) and a derivation helper from `BudgetLifecycleResult` + `Budget`.
- Replace `BudgetRemainingSummary`'s `isPaused: Bool` parameter with `inactiveReason: BudgetInactiveReason?`.
  - **`.preStart` / `.postEnd`** → display the **allocation amount** (using `Budget.currentAllocation`, already passed in) instead of `remaining`, dimmed via `dimmedStyle(...)`.
  - **`.paused`** → display `remaining` (today's behavior — works out of the box because the calculator only zeros remaining for *fully* paused periods, not the mid-period pause case), dimmed.
  - **`nil` (active)** → unchanged.
- Replace `RemainingBar`'s fraction-driven render when `dimmed` is true with a **full-width `.secondary` fill** (representing "full allocation, not running").
- Generalize `PausedChip` → `InactiveStatusChip(reason:)` with three label variants:
  - `.preStart` → `calendar.badge.clock` + "Starts {date}"
  - `.paused` → `pause.circle.fill` + "Paused · {date}" *(unchanged copy)*
  - `.postEnd` → `checkmark.circle` + "Ended {date}"
- Update `StatusChipRow` to consume `inactiveReason` (replacing `isPaused` / `pausedSince`) and render `InactiveStatusChip` in any inactive state. `CarryOverChip` keeps its existing visibility rules and dims when any inactive reason is set.
- Wire `BudgetsView.BudgetRowView` and `BudgetDetailView` to derive `inactiveReason` once and pass it through to both `BudgetRemainingSummary` and `StatusChipRow`. Delete the per-site `isPaused` / `isPostEnd` derivations used only for presentation. `BudgetDetailView.showPauseResumeItem` continues reading `lifecycle.lifecycleState` because that's action gating, not presentation.
- Apply the same treatment to Specific Dates budgets viewed before `startDate` or after `endDate`: the same `InactiveStatusChip` is rendered with the same copy (one chip, both period types).
- Add localized strings (`chip.inactive.preStart.label.format`, `chip.inactive.postEnd.label.format`, plus matching accessibility-label keys); keep the existing paused chip keys.
- Update VoiceOver labels for `BudgetRemainingSummary` so each inactive reason has its own announcement variant.

Explicitly **out of scope** (called out so reviewers don't expect it):

- The `BudgetDetailView` primary action slot for `.preStart` / `.postEnd`. Currently only `.paused` swaps to a Resume Budget button + caption; `.preStart` / `.postEnd` continue to show "Add Expense". The primary-slot behavior for those states is a functional question (does Add Expense stay tappable? Is there a "Budget starts on …" caption?) outside this presentation-only change.
- Any algorithm change. `BudgetCalculator`, `BudgetSnapshot`, `BudgetLifecycleService`, the `BudgetLifecycleState` enum, the `remaining = 0` short-circuits — none of these move.

## Capabilities

### New Capabilities

*(none — the new `BudgetInactiveReason` type is a view-layer presentation helper, not a capability with its own spec)*

### Modified Capabilities

- `budgets-screen`: the existing "Row renders paused presentation when budget lifecycle state is paused" requirement is generalized to cover all inactive lifecycle states (preStart, paused, postEnd) and dims allocation rather than zeroing it. New `InactiveStatusChip` requirements added; per-state copy and accessibility labels updated.
- `budget-detail-screen`: the existing "Status header renders paused presentation when lifecycle state is paused" requirement is generalized to cover all inactive lifecycle states. The primary-action-slot requirement is **not** changed by this proposal (preStart/postEnd primary-slot behavior remains out of scope).

## Impact

**Affected views**
- `simple-recurring-budgets/Views/BudgetsView.swift` (`BudgetRowView`)
- `simple-recurring-budgets/Views/BudgetDetailView.swift` (`headerRow`)
- `simple-recurring-budgets/Views/BudgetRemainingSummary.swift` (parameter + render logic)
- `simple-recurring-budgets/Views/StatusChipRow.swift` (parameter shape)
- `simple-recurring-budgets/Views/PausedChip.swift` → renamed/refactored to `InactiveStatusChip.swift`
- `simple-recurring-budgets/Views/RemainingBar.swift` (dimmed render)

**New view-layer file**
- `simple-recurring-budgets/Views/BudgetInactiveReason.swift` (enum + derivation helper)

**Unaffected**
- `simple-recurring-budgets/Domain/BudgetCalculator.swift`, `BudgetSnapshot.swift`, `BudgetLifecycleService.swift`, `LifecycleClassification.swift`, `CurrentPeriodSpillover.swift` — no algorithm or service changes.

**Localization**
- New keys: `chip.inactive.preStart.label.format`, `chip.inactive.preStart.accessibilityLabel.format`, `chip.inactive.postEnd.label.format`, `chip.inactive.postEnd.accessibilityLabel.format`, plus new inactive-state variants of `budget.summary.accessibilityLabel*` for the detail header and row.
- Existing paused-chip keys (`chip.paused.label.format`, `chip.paused.accessibilityLabel.format`) are reused.
- `translate-new-strings` runs to populate the 38 storefront locales.

**Analytics** — none. This is presentation-only.

**Tests** — new unit / preview coverage for the derivation helper, the chip variants, the summary render in each inactive state, and the status header on both screens.

## Doc alignment

- `docs/product-features-planning.md` F-2.01 ("Budgets screen") and F-2.02 ("Budget detail screen") currently describe per-state chip presentations in prose (preStart / postEnd / paused). The text is consistent with the unified treatment proposed here, so no PRD edits are required for the spec to be coherent — but the F-2.01 / F-2.02 acceptance criteria SHOULD be updated to spell out the unified "Inactive presentation" rather than just the paused case. A docs-update task ships with this change.
- `docs/main-prd.md` §6.7 / §6.8 are unaffected (math and cross-cutting concerns unchanged).
- `docs/tech-design-doc.md` is unaffected (no architecture or data-model changes).
- No conflicts with docs identified.
