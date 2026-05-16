## Why

F-7.06 (Pause / Resume a Budget) is still Open. The `2026-05-15-rewrite-budget-calculations` change already shipped the algorithm-layer plumbing for pause — `LifecycleEvent`, `LifecycleEventKind { pause, resume }`, `Budget.lifecycleEvents`, `LifecycleClassification.isActive(period:lifecycleEvents:)`, and `BudgetSnapshot.lifecycleState = .paused` — but explicitly deferred the service methods, the UI, and the analytics events to a follow-up change (rewrite `design.md` "Out of scope: Pause / Resume UI, `pauseBudget` / `resumeBudget` service methods", and "New analytics events / properties (`budget_paused`, `budget_resumed`) — not shipping"). This change is that follow-up: it adds the user-facing on/off capability on top of the existing model and math.

## What Changes

- Add `BudgetLifecycleService.pauseBudget(_:context:now:)` and `BudgetLifecycleService.resumeBudget(_:context:now:)`. Each inserts a `LifecycleEvent`, bumps `Budget.lastModified`, persists, and is rejected when the action is invalid for the budget's current state (Specific Dates, past `endDate`, or already-in-target-state).
- Surface `lifecycleState` on `BudgetLifecycleResult` so screens can render paused presentations without recomputing the snapshot. Add a `pausedSince: Date?` accessor for caption rendering.
- Budget detail screen:
  - Toolbar overflow menu gains a state-driven **Pause Budget** / **Resume Budget** item (hidden for Specific Dates; hidden once `now > endDate`).
  - When the budget is paused, the prominent **Add Expense** slot is replaced by a **Resume Budget** button with a short caption directly below (e.g., "Paused since {date}. Resume to log expenses.").
  - Header chip(s) render with a paused presentation (greyed value + "Paused since {date}" caption); value remains live for backdated edits to prior active periods.
- Budgets screen: each row's chip renders the same paused presentation when its budget is paused.
- Add/Edit Expense screen: while the bound budget is paused, the date picker is constrained to the union of the budget's active periods (per algorithm doc §A.5.4 / reqs §5.5). Out-of-range dates are either unselectable or rejected on Save.
- Analytics: fire `budget_paused` and `budget_resumed` dedicated Mixpanel events via `AnalyticsClient` on each action (per analytics-spec § events; cross-cutting concern per `docs/main-prd.md` §6.8). No PII.
- Docs:
  - Flip F-7.06 in `docs/product-features-planning.md` to **Implemented**.
  - Add the two new events to `docs/analytics-spec.md`.
  - Add the Pause/Resume entry to `docs/tech-design-doc.md` §4.5 (service surface) if not already covered.

## Capabilities

### New Capabilities

None. All work modifies existing capabilities.

### Modified Capabilities

- `budget-lifecycle`: new `pauseBudget` / `resumeBudget` service methods, plus `BudgetLifecycleResult` exposes `lifecycleState` and `pausedSince` for the screens.
- `budget-detail-screen`: new toolbar Pause/Resume item, state-driven primary action slot (Add Expense ↔ Resume Budget), paused chip presentation and caption.
- `budgets-screen`: paused chip presentation on each row.
- `add-edit-expense-screen`: date-picker bounds restricted to the union of active periods when the bound budget is paused.
- `data-models`: add a scenario asserting that `pauseBudget` / `resumeBudget` insert exactly one `LifecycleEvent` and bump `Budget.lastModified` (existing requirement § "Future write sites … SHALL follow the same rule" is now exercised by a concrete write site).

## Impact

- **Code:** `BudgetLifecycleService` (new methods), `BudgetLifecycleResult` (new fields), `BudgetDetailView` and its ViewModel (toolbar, primary slot, caption), `BudgetRowView` (paused chip), `AddEditExpenseView` and its ViewModel (date range), `AnalyticsClient` call sites in the service methods (or in the views, per the existing analytics pattern), localized strings catalog.
- **Data:** No schema changes — `LifecycleEvent` already ships from the rewrite. No migration.
- **Docs:** `docs/product-features-planning.md` (F-7.06 status flip), `docs/analytics-spec.md` (new events), `docs/tech-design-doc.md` (service-surface row), and possibly `docs/ux-design-brief.md` if it tracks the paused chip presentation.
- **Cross-cutting concerns (`docs/main-prd.md` §6.8):** Accessibility (new VoiceOver labels on toolbar item, prominent Resume button, paused chip), localized source strings (every new label/caption keyed in the catalog), translations queue (re-run `scripts/translate_catalog/`), Mixpanel events (the two new events above).

## Doc alignment

- `docs/product-features-planning.md` F-7.06 already describes the end state targeted by this change (toolbar action, prominent Resume button, paused chip, period-granular semantics, allocation-edits-while-paused, backdated edits, pause-before-`startDate`, `endDate` terminal, hidden for Specific Dates). No conflicts.
- `docs/budget-calculations-rewrite-reqs.md` §5.5 / §6.7 / §6.9 — same end state; algorithmic edge cases (Pause/Resume #1–#16) are already covered by the shipped algorithm and `LifecycleClassification`. This change adds the service entry points and UI that produce the `LifecycleEvent` rows the algorithm already consumes correctly.
- `docs/main-prd.md` §6.7 — Pause/Resume is named as one of the triggers that refresh the chip; this change does not alter §6.7.
- `docs/analytics-spec.md` — currently does not enumerate `budget_paused` / `budget_resumed`; the rewrite reqs §2.11 / §6.9 call for adding them. Tasks include the doc update.

No conflicts identified.
