## Context

The `2026-05-15-rewrite-budget-calculations` change rewrote the carry-over algorithm around a live walker and three event tables: `ExpenseItem`, `AllocationChange`, and `LifecycleEvent`. The `LifecycleEvent` table — with `kind: pause | resume`, `effectiveDate: Date`, and a one-to-many to `Budget` — already exists, is wired into `BudgetCalculator.snapshot(...)` via `LifecycleClassification.isActive(period:lifecycleEvents:)`, and is exercised by unit tests that cover the algorithm's pause/resume semantics (paused periods contribute 0, the pause-action period is fully active, the resume-action period is fully active, backdated edits to prior active periods recompute correctly).

What the rewrite deliberately did **not** ship (`design.md` "Out of scope"):

- `BudgetLifecycleService.pauseBudget(...)` / `resumeBudget(...)` — no write site exists today for `LifecycleEvent` rows.
- Budget detail toolbar action, prominent Resume button, paused chip presentation and "Paused since X" caption.
- Budgets-screen row paused chip presentation.
- Add/Edit Expense date-picker bounds for the paused state.
- `budget_paused` / `budget_resumed` Mixpanel events.

All four are the contents of this change. The algorithm layer and the data model layer are unchanged; this is a thin service + UI + analytics layer on top.

`docs/product-features-planning.md` F-7.06 already specifies the end state in full detail (toolbar action, primary-slot swap, paused chip, period-granular semantics, allocation-edits-while-paused, backdated edits, pause-before-`startDate`, `endDate` terminal, hidden for Specific Dates). `docs/budget-calculations-rewrite-reqs.md` §5.5 / §6.7 spells out the algorithmic edge cases. This design follows both verbatim; there are no open product questions.

## Goals / Non-Goals

**Goals:**

- Ship F-7.06 end-to-end: user can Pause a budget from the Budget detail toolbar, the chip and primary slot reflect the paused state immediately, and Resume returns the budget to its active behavior. Multiple pause/resume cycles work.
- Service methods are the **single write site** for `LifecycleEvent` rows. Views never insert `LifecycleEvent` directly. This mirrors the `applyAllocationEdit` / `resetCarryOver` / `resetBudget` pattern already used in `BudgetLifecycleService`.
- The service methods enforce the eligibility rules (not Specific Dates; not past `endDate`; not redundant) at the boundary so the UI doesn't have to duplicate that logic in two places — UI only needs to *show* or *hide* the action.
- The Add/Edit Expense date picker respects the union-of-active-periods constraint when the budget is currently paused. Out-of-range dates are unselectable in the picker; the Save path also rejects out-of-range dates as a defense in depth.
- Analytics: `budget_paused` and `budget_resumed` fire from the action sites (sibling-pattern, per the OSLog / Mixpanel boundary already established in F-8.01 / F-8.02).
- All four cross-cutting concerns from `docs/main-prd.md` §6.8 are addressed in the same change: accessibility, localized strings, translations, Mixpanel.

**Non-Goals:**

- No data-model changes. `LifecycleEvent`, `LifecycleEventKind`, and `Budget.lifecycleEvents` already exist from the rewrite.
- No new algorithm logic. `BudgetCalculator.snapshot(...)` and `LifecycleClassification.isActive(...)` already handle pause/resume correctly.
- No `startDate` / `endDate` UI input — that ships with F-7.05 and F-7.07 separately. This change *reads* `endDate` to gate the action and *reads* `startDate` to handle the pause-before-`startDate` clamp, but it does not introduce inputs for either field.
- No Specific Dates UI work beyond hiding the toolbar item. F-2.08 (Specific Dates) is a separate change.
- No `BudgetLifecycleResult` refactor into a sum type. The existing structure remains; we add two optional fields (`lifecycleState` and `pausedSince`) the way `lifecycleState` and `effectiveAllocation` were originally deferred per `budget-lifecycle/spec.md` "Additional snapshot fields … SHALL NOT be exposed through `BudgetLifecycleResult` in this change; they will be plumbed when the new lifecycle UI features ship."
- No Phase 2 analytics (funnel events, feature-flag-gated UI). The two new events fit cleanly into Phase 1's event surface.
- No tests for the underlying algorithm — those shipped with the rewrite. Tests here cover the new service methods and the new UI behavior.

## Decisions

### D1. `BudgetLifecycleService.pauseBudget(_:context:now:)` / `resumeBudget(_:context:now:)`

Two new static methods on `BudgetLifecycleService`, mirroring the existing service surface (`resetCarryOver`, `resetBudget`, `applyAllocationEdit`).

```
@discardableResult
static func pauseBudget(
  _ budget: Budget,
  context: ModelContext,
  now: Date = Date()
) -> Bool

@discardableResult
static func resumeBudget(
  _ budget: Budget,
  context: ModelContext,
  now: Date = Date()
) -> Bool
```

Each method:

1. Validates the action is legal for the budget's current state. If not, returns `false` and makes no changes:
   - **Reject for Specific Dates** — `BudgetPeriod(rawValue: budget.period) == .specificDates`. The toolbar item is hidden in this case (UI defense), but the service still rejects (algorithm-layer / direct-CloudKit-write defense per reqs §6.7 case 14).
   - **Reject `resume` past `endDate`** — if `budget.endDate != nil && now > endDate`. The toolbar item is hidden in this case, but the service still rejects.
   - **Reject redundant action** — if `pauseBudget` is called when the budget's current `lifecycleState` is already `.paused`, return `false`. Same for `resumeBudget` when already `.active`. This is a sibling of the no-op guard inside `applyAllocationEdit` and avoids creating phantom events.
2. Computes the `effectiveDate`:
   - **Default**: `now` clamped into `[budget.startDate ?? .distantPast, budget.endDate ?? .distantFuture]`. The clamp at `startDate` implements reqs §5.5 "Pause while `startDate` is in the future: the pause is recorded as if it occurred on `startDate`." (The matching clamp at `endDate` is for symmetry — `resumeBudget` already rejects past `endDate`, so this branch is unreachable for resume; for pause it makes pause-after-`endDate` a no-op as well.)
3. Inserts `LifecycleEvent(budget: budget, kind: .pause | .resume, effectiveDate: clampedNow)` into the context.
4. Sets `budget.lastModified = now` (per `data-models/spec.md` "Future write sites (pause, resume, start/end date edits) SHALL follow the same rule").
5. Calls `context.save()` exactly once.
6. Returns `true`.

**Why static, not instance-bound?** Mirrors `resetBudget` / `resetCarryOver`. The whole service is intentionally a namespace of static methods that operate on a passed-in `ModelContext`; no actor isolation issues because all calls are `@MainActor` per project default.

**Why a `Bool` return?** Same shape as `applyAllocationEdit`. Lets the call site know whether to fire the analytics event (only on `true`).

**Alternative considered:** Inserting `LifecycleEvent` directly from `BudgetDetailViewModel`. Rejected — `LifecycleEvent` writes belong in the service alongside the other lifecycle writes, and the eligibility rules need to be enforced in one place. The view layer should not know about `endDate` clamping.

### D2. Expose `lifecycleState` and `pausedSince` on `BudgetLifecycleResult`

The current `BudgetLifecycleResult` exposes only `remaining`, `carryOverAmount`, `periodStart`, `periodEnd`. The rewrite deferred `lifecycleState` and `effectiveAllocation`, calling out that they "will be plumbed when the new lifecycle UI features ship."

This change adds:

- `lifecycleState: BudgetLifecycleState` — direct from `BudgetSnapshot.lifecycleState`. Used by views to switch between the active and paused presentations.
- `pausedSince: Date?` — the `effectiveDate` of the most recent `.pause` `LifecycleEvent` if the current `lifecycleState == .paused`, else `nil`. Used for the "Paused since {date}" caption.

`effectiveAllocation` is **not** added in this change — no UI surface in scope needs it. (Will be added with F-7.05 if needed.)

**Why expose `pausedSince` separately?** The view shouldn't filter `budget.lifecycleEvents` to find the latest `.pause`. That's a model-layer query. Computing it inside `BudgetLifecycleService.result(for:)` keeps the view layer thin and uses the same sorted-events traversal the snapshot already walks.

**Alternative considered:** Just `lifecycleState`, and let views compute `pausedSince` from `budget.lifecycleEvents`. Rejected — duplicating the sort-and-scan logic in two view sites is the same anti-pattern that the rewrite removed when it consolidated read paths through `BudgetLifecycleService.result(for:)`.

### D3. Budget detail toolbar item

In `BudgetDetailView`'s toolbar overflow `Menu` (alongside "Edit Budget", "Reset Carry-over…", "Reset Budget…"), a state-driven Pause/Resume item:

- **Visible** when: `BudgetPeriod(rawValue: budget.period) != .specificDates` AND (`budget.endDate == nil || now <= endDate`).
- **Label / icon** driven by current `lifecycleState`:
  - `.active`, `.preStart` → "Pause Budget" (icon: `pause.circle`)
  - `.paused` → "Resume Budget" (icon: `play.circle`)
  - `.postEnd` → item is hidden (gate above).
- Tapping it calls `BudgetLifecycleService.pauseBudget(...)` or `resumeBudget(...)`, then fires the matching analytics event (D6), then re-invokes `BudgetLifecycleService.result(for:)`.

**Why no confirmation dialog?** Pause/Resume is reversible. None of the other reversible actions (Edit Budget, allocation edits) gate on confirmation. Reset Budget and Delete Budget keep their confirmation dialogs because they're destructive.

### D4. Primary action slot swap (Add Expense ↔ Resume Budget)

The Budget detail primary `.borderedProminent` button currently says "Add Expense" and presents `SheetRoute.addExpense(budget)`. This change makes the button's contents state-driven:

- `.active` / `.preStart` / `.postEnd` → "Add Expense" (existing behavior).
- `.paused` → "Resume Budget"; tapping calls the same `resumeBudget` action as the toolbar item.

Directly below the button, when paused, a caption: `"Paused since {date}. Resume to log expenses."` in `.caption`/`.secondary` styling. The caption is **the only** paused-state explainer on this surface — no separate disabled "Add Expense" affordance.

**Why "replace" and not "disable + add a Resume button below"?** Reqs §5.5 / F-7.06 explicitly call for replacement. Two slots competing for the same prominent position is visually noisy and gives the user two paths where one is correct.

**Why both the toolbar item and the prominent button drive the same action?** F-7.06 AC: "the prominent slot is for discoverability; the menu item remains for consistency with the other lifecycle actions."

### D5. Paused chip presentation

The chip(s) on the Budgets list (`BudgetRowView`) and on Budget detail (`BudgetDetailView`'s header) render with a paused presentation when `lifecycleState == .paused`:

- Numeric value rendered with `.foregroundStyle(.secondary)` (the "greyed value").
- Below the value, a `.caption` line: `"Paused since {date}"`, using `formatted(date: .abbreviated, time: .omitted)` for the date.
- Value remains live — backdated edits to prior active periods still update it, per reqs §5.5 "Pause display … not 'frozen'."

**Why not freeze the value entirely?** Backdated edits to active periods change the cumulative carry-over for those periods, which propagates forward through subsequent active periods. The current paused value at the moment of pause is the carry-over rolled up to that point; if the user later edits an expense in an active period, the algorithm must recompute and the chip must reflect the new value. (Reqs §6.7 case 5 and case 15.)

### D6. Analytics events `budget_paused` and `budget_resumed`

Two new event-name constants in `AnalyticsEvent`:

```
nonisolated static let budgetPaused = "budget_paused"
nonisolated static let budgetResumed = "budget_resumed"
```

Properties: `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount` — same shape as `budget_reset` and `carry_over_reset`, so dashboards can group cleanly.

Call sites are the view sites (in `BudgetDetailView`), not the service. This matches the existing pattern (D6 in the rewrite design doc): `Logger.ui.debug` and `analytics.track` are independent siblings; both fire from the view; neither call is derived from the other.

The analytics event fires **only** when the service method returns `true`. If pause/resume is rejected (already in target state, or for Specific Dates / past endDate), no event fires.

`docs/analytics-spec.md` § events table gains two new rows. The cross-cutting-concern obligation from `docs/main-prd.md` §6.8 is what motivates adding these events at the same time as the UI, not later.

### D7. Add/Edit Expense date-picker bounds (paused state)

Currently, `AddEditExpenseView`'s date picker uses `Date.distantPast...Date()` (or similar — exact closed-range constraint lives in the view).

This change introduces a `validDateRange(for: Budget, now: Date) -> [DateInterval]` helper (location: `Views/AddEditExpenseView.swift` or a small companion file; depends on what reads cleanest in the codebase as it stands at apply time). The helper returns the active-period intervals — the union of `[startDate, endDate]` (or `[startDate, now]` if `endDate == nil`) intersected with the set of active-period intervals derived from `LifecycleClassification`.

For SwiftUI's `DatePicker` which takes a single `ClosedRange<Date>`, we use the **bounding closed range** of the union (i.e., `[firstActiveStart, lastActiveEnd]`) for the picker constraint and then validate against the full union on Save:

- **Picker constraint** = `firstActiveStart...lastActiveEnd`. This blocks dates outside the budget's lifetime entirely, and blocks dates after the most recent pause (or after `endDate` if past `endDate`). It does NOT visually block intermediate paused gaps (e.g., a date inside a previously-paused interval between two active intervals).
- **Save validation** = check the picked date lies inside one of the active intervals. If not, surface an inline error in the same `.caption`/`.secondary` styling as the clamped-default caption (per F-2.04) and disable Save.

**Why two-stage (picker + save)?** SwiftUI's `DatePicker` does not support a disjoint set of valid intervals. The bounding range is the closest single-range approximation, and the Save-time check covers the remaining gap. In normal usage (one active interval, then a pause that extends to `now`), the bounding range *is* the full valid range and there's no gap to worry about. The Save-time check matters only when the user has cycled pause/resume multiple times *and* tries to pick a date inside a historical paused gap.

**Alternative considered:** A custom date picker that visually blocks paused gaps. Rejected — building a custom picker for an edge case that's nearly impossible to trigger in normal usage is disproportionate scope. The Save-time check is sufficient.

### D8. Localized strings

New strings added to the catalog:

- `budgetDetail.toolbar.pause` → "Pause Budget"
- `budgetDetail.toolbar.resume` → "Resume Budget"
- `budgetDetail.action.resume.button` → "Resume Budget"
- `budgetDetail.action.resume.caption.format` → "Paused since %@. Resume to log expenses." (uses positional `%1$@` if more positions are added later)
- `chip.paused.caption.format` → "Paused since %@" (used by both `CarryOverChip` and the Budgets list row, where %@ is the localized abbreviated date)
- `addEditExpense.date.outOfRange.caption` → "Pick a date within an active period of the budget." (used when Save validation rejects)

Every new string carries a translator-friendly `comment:`. Translations queue work runs via `scripts/translate_catalog/` after the strings are added.

## Risks / Trade-offs

- **[Risk] Picker bounding range hides historical paused gaps.** → Mitigated by Save-time validation. In normal usage the bounding range = full valid range, so this is invisible. If telemetry shows users hitting the Save-time error, we can revisit with a custom picker.
- **[Risk] CloudKit convergence: concurrent Pause on device A and Resume on device B.** → Both events are insert-only `LifecycleEvent` rows; CloudKit merges them in `effectiveDate` order with the algorithm honoring whichever lands last. The algorithm's period-granular semantics mean a same-period pause-then-resume collapses to "fully active" (the pause-action period is active anyway). No "phantom paused period" can occur because periods strictly between events are paused only if pause < resume in `effectiveDate` order, which is data-determined and deterministic across devices. Reqs §6.7 case 13.
- **[Risk] Redundant pause/resume races.** → The "reject redundant action" guard (D1 step 1) uses the current snapshot to decide; if two devices both decide to pause at the same instant, both `LifecycleEvent` rows land in CloudKit. The algorithm folds duplicate pauses (`isActive` checks the most recent event before a period, not the count of events). No user-visible artifact. The same applies to duplicate resumes.
- **[Trade-off] Service rejection is silent (returns `false`).** No toast, no error. The UI prevents the rejected case from being reachable via the hidden-item rules, so users won't hit it organically. Direct CloudKit writes by a misbehaving sync record fall through to the algorithm's `specificDates`-ignores-events safety net.
- **[Trade-off] `pausedSince` is computed every `result(for:)` call.** Negligible — `lifecycleEvents` is small (single-digit rows for a typical budget) and the scan is O(n). Could be cached on `Budget` if it ever shows up in performance traces.
- **[Risk] Localization for "Paused since {date}" — date format varies by locale.** → Use `Date.formatted(date: .abbreviated, time: .omitted)` which is locale-aware. Caption template uses `String.localizedStringWithFormat` so the substitution itself is locale-safe.

## Migration Plan

No schema or data migration needed — `LifecycleEvent` already exists from the rewrite and is `[]` for every existing budget. The first time a user pauses, the first event is inserted normally.

Rollback: revert the change. Existing budgets that have been paused/resumed in the meantime will have `LifecycleEvent` rows the reverted UI can't see, but the rewrite-era algorithm still consumes them correctly (the algorithm ignores `LifecycleEvent` for nobody — there's no special handling needed for rolled-back UI). Users would silently lose the ability to act on a paused budget; not data-loss.

## Open Questions

None. F-7.06's UX and the algorithm semantics are fully specified between `docs/product-features-planning.md`, `docs/budget-calculations-rewrite-reqs.md` §5.5 / §6.7, and the already-shipped algorithm specs.

## Doc alignment

- `docs/product-features-planning.md` F-7.06 — full match; F-7.06 flips to **Implemented** as a task.
- `docs/budget-calculations-rewrite-reqs.md` §5.5 — full match.
- `docs/tech-design-doc.md` §4.5 (service surface) — gains rows for `pauseBudget` / `resumeBudget` (task).
- `docs/analytics-spec.md` — gains `budget_paused` and `budget_resumed` event rows (task).
- `docs/main-prd.md` §6.7 — Pause/Resume is already listed as a refresh trigger; no edits needed.

No conflicts.
