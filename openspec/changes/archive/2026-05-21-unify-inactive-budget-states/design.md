## Context

`BudgetCalculator` already classifies a budget at any instant into one of four `BudgetLifecycleState` values — `.preStart`, `.active`, `.paused`, `.postEnd` — and `BudgetLifecycleService.result(for:)` surfaces that classification on `BudgetLifecycleResult.lifecycleState` for view sites. The model layer treats all four cases consistently.

The view layer does not. Today only `.paused` has a presentation:

| Lifecycle state | Today's presentation on Budgets list / Budget detail |
|---|---|
| `.active` | Normal: `remaining` in primary / deficit color, fraction-filled bar, optional `CarryOverChip`. |
| `.paused` | Dimmed: `remaining` rendered `.secondary`, `RemainingBar` rendered `.secondary` at remaining-fraction width, `CarryOverChip` value dimmed, `PausedChip` shown ("Paused · {date}"). |
| `.preStart` | Default render path: `remaining` is forced to `0` by the calculator (`BudgetCalculator.swift:44`), so the user sees "$0.00" with no chip and no dimming. |
| `.postEnd` | Default render path: `remaining` is whatever the final period closed at, no chip, no dimming. `BudgetDetailView` reads `isPostEnd` only to hide the Pause / Resume menu item. |

Three structural pieces drive the paused presentation today and need generalization:

1. **`BudgetRemainingSummary`** (`Views/BudgetRemainingSummary.swift`) renders the large amount + period label + `RemainingBar`. It takes an `isPaused: Bool` parameter that flips two foreground styles via `dimmedStyle(_:when:)`.
2. **`StatusChipRow`** (`Views/StatusChipRow.swift`) is the chip container — `PausedChip` (when `isPaused && pausedSince != nil`) + `CarryOverChip` (when `isCarryOverEnabled`), with the latter accepting a `dimmed:` parameter.
3. **`PausedChip`** (`Views/PausedChip.swift`) is the only "status" chip — capsule with `pause.circle.fill` + "Paused · {date}" + `.secondary` foreground.

Both call sites (`BudgetsView.BudgetRowView`, `BudgetDetailView.headerRow`) ad-hoc-derive `isPaused` from `lifecycle?.lifecycleState == .paused` and pass it into both views. `BudgetDetailView` independently derives `isPostEnd` for action-gating only.

This proposal generalizes the three pieces above to operate on a single view-layer concept that covers all three inactive lifecycle states. No `Domain/` files are touched.

## Goals / Non-Goals

**Goals:**

- Present every "not currently running" lifecycle state with a consistent visual treatment (dimmed amount, dimmed full-width secondary bar, single status chip identifying the reason + date).
- Keep the dollar amount shown in inactive states meaningful (allocation for preStart / postEnd; remaining for paused — leveraging the existing calculator output without changing it).
- Have one derivation of "is this budget inactive, and if so why?" reused by both the Budgets list row and the Budget detail header.
- Preserve every existing paused-state behavior bit-for-bit (copy, accessibility key, capsule styling, value-update-on-backdated-edit semantics).

**Non-Goals:**

- Any change to `BudgetCalculator`, `BudgetSnapshot`, `BudgetLifecycleService`, `LifecycleClassification`, `CurrentPeriodSpillover`, or the `BudgetLifecycleState` enum. The algorithm is correct; only its presentation is being unified.
- Any change to the `BudgetDetailView` primary-action slot for `.preStart` / `.postEnd`. The slot continues to show "Add Expense" in those states; the paused case still swaps to "Resume Budget". A future change can decide whether preStart / postEnd warrant their own slot variant.
- Any change to action gating (`showPauseResumeItem`, `endDate`-is-terminal rules, etc.). The lifecycle state remains the single source of truth for action gating.
- Any change to `CarryOverChip` visibility (already correctly hidden for `.specificDates` and when `Budget.isCarryOverEnabled == false`).
- Backfilling a "last-known remaining at pause moment" — paused-state amount uses the calculator's `remaining`, which is the correct in-period figure for mid-period pauses (the common case) and `0` for fully-paused subsequent periods (the rare case, where no "last-known" exists anyway).

## Decisions

### 1. View-layer enum vs. extension of `BudgetLifecycleState`

**Decision:** Introduce a new view-layer enum `BudgetInactiveReason` with three cases. Do **not** add view properties to `BudgetLifecycleState` (which lives in `Domain/BudgetSnapshot.swift`) and do **not** make views switch directly on the 4-case lifecycle enum.

```swift
enum BudgetInactiveReason: Equatable {
  case preStart(startDate: Date)
  case paused(since: Date)
  case postEnd(endDate: Date)
}
```

The reason is computed from `BudgetLifecycleResult` + `Budget` via a small static helper:

```swift
extension BudgetInactiveReason {
  static func from(lifecycle: BudgetLifecycleResult, budget: Budget) -> BudgetInactiveReason? {
    switch lifecycle.lifecycleState {
    case .active: return nil
    case .preStart:
      guard let startDate = budget.startDate else { return nil } // defensive
      return .preStart(startDate: startDate)
    case .paused:
      guard let since = lifecycle.pausedSince else { return nil } // defensive
      return .paused(since: since)
    case .postEnd:
      guard let endDate = budget.endDate else { return nil } // defensive
      return .postEnd(endDate: endDate)
    }
  }
}
```

**Why a view-layer enum:**

- Keeps `Domain/` purely about algorithm semantics. The 4-case `BudgetLifecycleState` is the right model for the calculator and service; collapsing it for the view is a presentation choice that doesn't belong in the model.
- Lets the view carry the **payload it actually needs** (the date for the chip label) rather than re-fetching it at every site. The calculator already exposes `pausedSince` on `BudgetLifecycleResult`; for preStart / postEnd the dates live on `Budget` itself.
- Makes the "any inactive reason" boolean (`reason != nil`) a one-liner at the dim-driving sites without violating exhaustive-switch hygiene.

**Alternatives considered:**

- *Extend `BudgetLifecycleState` itself with view affordances (a computed `isInactive` etc.).* Rejected — couples domain to presentation and the date payload still has to be threaded separately.
- *Drop the helper entirely and have each view derive the reason inline.* Rejected — two-call-site duplication is small but real, and the call site that currently derives `isPaused` already shows how easy it is for two surfaces to drift.

### 2. What dollar amount to display in each inactive state

**Decision:**

- **`.preStart`, `.postEnd`** → `allocation` (the `currentAllocation: Decimal` prop already passed into `BudgetRemainingSummary`).
- **`.paused`** → `remaining` (today's behavior — `lifecycle.remaining`).
- **`.active`** → `remaining` (unchanged).

**Why:**

- For preStart, `remaining` is currently hard-zeroed by `BudgetCalculator.swift:44`. Showing `$0` for a budget that *hasn't started yet* misrepresents the state — there's no spending against the budget yet, so "remaining" is undefined. Showing the **allocation** answers "this budget will cover $X per period" which is exactly what the user planned.
- For postEnd, `remaining` is the residual of the final period, which is an arbitrary in-flight figure rather than a meaningful summary of a finished budget. Showing the allocation lets the user remember what they had set up.
- For paused, the calculator's `remaining` is **already correct for the common case**: when a user pauses mid-period, `isCurrentPaused` (period-granular) is `false`, so `BudgetCalculator.swift:147–150` computes `remaining = allocation − period_expenses` as usual. The UI just sees the right number. For periods *after* the pause-action period that are fully paused, `remaining` collapses to `0` — fine, because no "in-progress" state exists there to preserve.
- This means **no algorithm work is required** for the paused case to do the right thing. The view simply picks between `allocation` (preStart / postEnd) and `remaining` (paused / active).

**Alternatives considered:**

- *Always show `remaining` (today's behavior generalized).* Rejected because preStart shows "$0" — the user's stated complaint.
- *Always show `allocation` for any inactive state.* Rejected because it loses the useful "mid-period $7.50 left" information the paused presentation currently gives — and gives no transition path from healthy → low → over for users who pause partway through.
- *Preserve a "last-known remaining at pause moment" on the budget model.* Rejected as out of scope (algorithm change) and unnecessary given the paragraph above.

### 3. `RemainingBar` behavior in inactive states

**Decision:** When `dimmed` is true, `RemainingBar` fills **100% width** in `.secondary` (replacing the current "fraction-driven width in `.secondary`" behavior).

**Why:**

- For `.preStart`, fraction is undefined (no spending yet); 100% reads as "full budget, untouched".
- For `.postEnd`, the bar's fraction is whatever the final period closed at, which is meaningless after-the-fact.
- For `.paused`, the bar's current "remaining-fraction in secondary" reads as "draining mid-pause" which is misleading — the user is paused, not still spending.
- A single full-width secondary bar reads as "status indicator: inactive" across all three cases without needing per-case logic.

**Alternatives considered:**

- *Keep fraction for paused, only switch the new states.* Rejected — splits the presentation across two visual languages for the same underlying concept.
- *Hide the bar entirely when inactive.* Rejected because the row's vertical layout would shift between active and inactive states, causing visible jumps as a budget crosses period or pause boundaries while on screen.

### 4. `PausedChip` → `InactiveStatusChip(reason:)`

**Decision:** Rename and refactor `Views/PausedChip.swift` → `Views/InactiveStatusChip.swift`. The new chip takes `reason: BudgetInactiveReason` and dispatches on the case for icon + localized text.

```swift
struct InactiveStatusChip: View {
  let reason: BudgetInactiveReason
  // …same capsule styling, same .secondary foreground, same chipBackground rules
}
```

**Why:**

- One capsule, three label variants is the minimum-friction generalization.
- The `.paused` variant uses the existing `chip.paused.label.format` / `chip.paused.accessibilityLabel.format` keys verbatim — no translator churn.
- The new variants add four keys: `chip.inactive.preStart.label.format`, `chip.inactive.preStart.accessibilityLabel.format`, `chip.inactive.postEnd.label.format`, `chip.inactive.postEnd.accessibilityLabel.format`.

**Icons (rationale):**

- `.preStart` → `calendar.badge.clock` — pending / not-yet-started.
- `.paused` → `pause.circle.fill` — unchanged.
- `.postEnd` → `checkmark.circle` — completed, terminal. (Alternative `flag.checkered` rejected as too "victorious"; `xmark.circle` rejected as feeling like an error.)

**Alternatives considered:**

- *Keep `PausedChip` and add a separate `PreStartChip` / `PostEndChip`.* Rejected — three near-identical files that all need to stay aligned on capsule styling, dynamic-type metrics, and increased-contrast handling.
- *Make the chip take a `(systemImage:String, label:String)` pair and have the caller localize.* Rejected — invariants ("the label format uses an abbreviated date") are easier to enforce inside the chip.

### 5. `StatusChipRow` parameter shape

**Decision:** Replace `isPaused: Bool` + `pausedSince: Date?` with a single `inactiveReason: BudgetInactiveReason?`. Drop the explicit `pausedSince` param entirely — the reason carries it.

```swift
struct StatusChipRow<Trailing: View>: View {
  let inactiveReason: BudgetInactiveReason?
  let isCarryOverEnabled: Bool
  let carryOverAmount: Decimal
  // …
}
```

Render rules:

- When `inactiveReason != nil` → render `InactiveStatusChip(reason: inactiveReason!)` (first slot).
- When `isCarryOverEnabled` → render `CarryOverChip(... dimmed: inactiveReason != nil)` (second slot).
- `showsRow` is `inactiveReason != nil || isCarryOverEnabled` (same shape as today).

**Why:** Two parameters → one parameter, and the boolean-plus-optional-date pair becomes impossible to inconsistent (you can't get `isPaused: true` with `pausedSince: nil` anymore).

### 6. `BudgetRemainingSummary` parameter shape

**Decision:** Replace `isPaused: Bool` with `inactiveReason: BudgetInactiveReason?`. The body chooses between `allocation` and `remaining` for the amount text and passes `dimmed: inactiveReason != nil` to `RemainingBar`.

```swift
private var displayedAmount: Decimal {
  switch inactiveReason {
  case .preStart, .postEnd: return allocation
  case .paused, .none:      return remaining
  }
}
```

`isOverBudget` continues to read off the *displayed* amount — when allocation is shown, `isOverBudget` is `false` (allocation ≥ 0 by invariant) so the deficit-color path is correctly skipped.

### 7. Accessibility labels

**Decision:** Extend `BudgetRemainingSummary.accessibilityLabel(...)` to take `inactiveReason: BudgetInactiveReason?` and add three new localized keys (one per inactive case). The existing `budget.summary.accessibilityLabel*` keys handle the active cases.

Keys added (en-US examples):

- `budget.summary.accessibilityLabel.preStart` → "{amount} {periodInlineLabel}, not yet started, begins {startDate}" (and a name-prefixed variant)
- `budget.summary.accessibilityLabel.paused` → "{amount} remaining {periodInlineLabel}, paused since {pausedSince}" (covers the existing on/over budget paused announcement — currently both rolled into one "paused" key on `budgets-screen` / `budget-detail-screen`; we preserve that)
- `budget.summary.accessibilityLabel.postEnd` → "{amount} {periodInlineLabel}, ended {endDate}"

The chip itself remains a sibling element with its own announcement (`chip.inactive.*.accessibilityLabel.format`), preserving today's pattern of "summary first, then chip" reading order.

### 8. Specific Dates

**Decision:** No special-casing. A Specific Dates budget viewed before `startDate` enters `.preStart` and viewed after `endDate` enters `.postEnd` — same as recurring budgets, so the same `InactiveStatusChip` variants and the same allocation-as-amount choice apply. Specific Dates budgets cannot be `.paused` (F-2.08), so the `.paused` chip simply never fires for them.

The `CarryOverChip` continues to be hidden for Specific Dates (already enforced in both surfaces' wiring code) — that's an orthogonal rule.

### 9. Action gating unchanged

**Decision:** `BudgetDetailView.showPauseResumeItem` and any other code that reads `lifecycle.lifecycleState` for **action gating** continues to use the 4-case enum directly. Only **presentation** consumes `BudgetInactiveReason`.

`isPostEnd` on `BudgetDetailView` stays for that one purpose; `isPaused` derivations used only for the summary / chip presentation are removed in favor of `inactiveReason`.

## Risks / Trade-offs

- **Risk:** Translator churn on the four new keys. **Mitigation:** keys are added to the standard pipeline; `translate-new-strings` runs as part of this change and covers all 38 storefront locales.
- **Risk:** Subtle visual regression on the paused case if `RemainingBar` switches from fraction-driven secondary to full-width secondary. **Mitigation:** explicit "paused-presentation" preview in `BudgetRemainingSummary` and `StatusChipRow` is updated; QA includes a side-by-side check of a mid-period-pause budget before/after the change.
- **Risk:** Users may interpret the postEnd allocation as "this much still available" rather than "this is what it was". **Mitigation:** the InactiveStatusChip's "Ended {date}" label and the dimming together make the terminal state unambiguous; copy can be tuned post-ship if user testing surfaces confusion.
- **Risk:** A budget with no `startDate` / `endDate` reaches `.preStart` or `.postEnd` (currently impossible per the data model — `startDate` is non-optional once F-7.05 ships, and `.postEnd` requires `endDate != nil`). **Mitigation:** the `BudgetInactiveReason.from(...)` helper defends with `guard let` and returns `nil`, which collapses to active rendering — failing safe rather than crashing. An `assertionFailure` in debug catches the unexpected case.
- **Trade-off:** Showing `allocation` instead of `remaining` for postEnd loses the "ended at $X over budget" affordance some users might find useful. Accepted because the chip carries the "Ended {date}" status and the `BudgetLifecycleResult` is still available via the carry-over chip path for users who want the closing carry-over.

## Migration Plan

This is a UI-only refactor of view types that live inside the app target. No persisted data is touched. No CloudKit schema is touched. No analytics events are added or renamed. The change ships in a single PR with no feature flag.

Rollback: revert the PR. Because `BudgetCalculator` / `BudgetSnapshot` / `BudgetLifecycleService` are untouched, there's no lingering data state.

## Open Questions

None at design time. The three open questions surfaced before the design (amount displayed per state, bar behavior, Specific Dates treatment) were answered by the user and folded into Decisions §2, §3, and §8 respectively.

## Doc alignment

- `docs/main-prd.md` — no changes required. The unified treatment is consistent with §6.7 (presentation only) and §6.8 (cross-cutting concerns checklist is followed via the localized strings, accessibility labels, and "no analytics" determination).
- `docs/product-features-planning.md` F-2.01 ("Budgets screen") and F-2.02 ("Budget detail screen") acceptance criteria currently describe paused presentation in detail and only briefly mention preStart / postEnd. After this change ships, the acceptance criteria in both features SHOULD be edited to describe a single "Inactive presentation" rule covering all three states. A docs-update task is included in tasks.md.
- `docs/tech-design-doc.md` — no changes required. No architecture, data-model, or sync changes.
- No conflicts with docs identified.
