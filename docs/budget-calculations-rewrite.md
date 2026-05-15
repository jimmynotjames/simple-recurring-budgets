# Budget calculations rewrite

This briefing describes the new desired end state for the budget carry-over / remaining algorithm. It captures the requirements, conflicts with prior feature descriptions, and edge cases the new behavior must handle. **It does not prescribe a design.** A separate chat will read this and produce the design and implementation.

Sections are numbered (e.g. §2.4, §5.5) so they can be referenced from elsewhere.

## 1. App status: greenfield, no migrations

This app has not been deployed to the App Store. There are no production users. **Do not add or maintain SwiftData schema versions,** `VersionedSchema` **types,** `SchemaMigrationPlan` **stages, or any migration ceremony for this rewrite.** If the model changes, change it. Wipe the simulator. Move on. Update, but do not delete, the `SchemaV1.swift` and `BudgetMigrationPlan.swift` files in the repo.

## 2. Desired end state

A summary of the requirements the rewrite must satisfy. Detailed reasoning, conflicts with prior docs, and edge cases live in the sections further down. Items are tagged **NEW** (introduced by this rewrite), **CHANGED** (replaces existing behavior), **REMOVED** (deleted outright), or **UNCHANGED** (kept intentionally; called out because surrounding context shifts).

### 2.1. Algorithm behavior

- **CHANGED** The carry-over / remaining chip updates **mid-period** in response to any change that affects the value — expense add / edit / delete, allocation edit, start/end-date edit, pause/resume, reset. No more boundary-only `rollCarryOver`.
- **NEW — Carry-over "asymmetric live coupling."** Carry-over and Remaining remain conceptually separate (per main-prd.md §6.7), but Carry-over absorbs the current period's *committed* overflow in real time:
  - When Remaining is inside `[0, Allocation]` (ordinary mid-period state), Carry-over reflects only completed prior active periods — unchanged from the walker sum.
  - When Remaining < 0 (overspend), Carry-over increases by the deficit (i.e., decreases) immediately. Example: prior Carry-over +$5, daily $20 budget, user logs an expense that pushes today to −$1 over → Carry-over updates to +$4 instantly. Undoing the expense snaps it back to +$5.
  - When Remaining > Allocation (the user has added funds for this period via F-6.01 add-funds, making the *net* spend negative), Carry-over increases by the excess immediately. Example: $20/day budget, user adds $30 via Add Funds — Remaining = $50, Carry-over absorbs the +$30 excess.
  - **Why asymmetric.** Overspending and deliberate add-funds are *committed* user actions — they should land in the cumulative position immediately. Ordinary mid-period slack (Remaining > 0 but ≤ Allocation) is *provisional* — the user might still spend more before the period closes, so it stays in "today's envelope" until the period actually completes (at which point the walker folds it in normally). This matches the user's mental model of "today's envelope" (Remaining) feeding the "savings jar" (Carry-over) only when there's a real spill in either direction. Loss-aversion: bad news shows up live; good news waits for the period to close.
  - At the period boundary, the just-closed period's *full* contribution flows into walker sum, and the new period's spillover starts at 0. The asymmetric rule never double-counts: when the period closed with overspend or add-funds excess, the spillover was already reflected, and the walker's fold cancels it cleanly (smooth transition); when the period closed with ordinary slack, the walker folds it in and the chip jumps by that slack at the close.
  - In post-`endDate` (`.postEnd`) state, the rule collapses to symmetric — the entire final-period Remaining is folded into Carry-over, since there is no future period close. This matches the "frozen at final tally" expectation (§2.9, §6.5).
- **NEW** Allocation edits are **forward-only**, effective at `currentPeriodStart` (the boundary of the period that is in progress when the edit happens). They never retroactively rewrite the carry-over contribution of prior completed periods. Allocation edits are **not** a reset.
- **NEW** Allocation edits made **while the budget is paused** take effect at the resume point (i.e., at the period containing the resume action). The chosen storage convention can either record `effectiveFrom = the paused period's start` or `effectiveFrom = the resume-anchored period's start` — both produce the same final carry-over value, because paused periods contribute 0 regardless of allocation. See §5.5 for the underlying pause semantics.
- **NEW** Backdated expenses — including expenses backdated into a *prior active period* of a paused budget — recompute the carry-over of the period they fall in, and that change propagates forward through all subsequent active periods.
- **NEW** Refresh is driven by user actions (expense or budget edits, manual reset, pause/resume) and by app-lifecycle events (app launch, `scenePhase` change to `.active`). There is intentionally **no** timer-driven refresh for clock-driven period-boundary crossings; if the user leaves the app open across midnight on a daily budget, the chip is not forced to update until the next natural trigger. This avoids disrupting an open UI mid-glance and is sufficient for typical usage.
- **UNCHANGED** The value the algorithm returns must equal the value the chip displays, including for the Voice query feature (F-7.03).

### 2.2. `Budget` model

- **NEW** `startDate: Date?` — when the budget begins. May be past, today, or future. **Semantically always populated** for a saved budget: the UI requires a value before save (see §2.4 for per-period-type pre-population rules). The field is stored as `Date?` purely because CloudKit-synced SwiftData fields must be optional. As a safety-net fallback, if the algorithm encounters a nil `startDate` at read time it treats the budget's start as `createdAt`.
- **NEW** `endDate: Date?` — when the budget stops calculating. After `endDate`, the chip is frozen at the final tally; the user may still log expenses dated within `[startDate, endDate]`. Stored as `Date?` because for recurring budgets (non-`specificDates`) it is genuinely optional; for `specificDates` budgets it is required by the UI before save.
- **REMOVED** `carryOverLastProcessedDate` — no longer needed once the algorithm walks live.
- **REMOVED** `resetCadence: String` and the `ResetCadence` enum — Reset Cadences is permanently removed (see §5.4).
- **REMOVED** `BudgetPeriod.defaultResetCadence` mapping.
- **CHANGED** Other carry-over storage fields (`carryOverAmount`, `carryOverLastResetDate`) may change shape depending on how the design represents allocation history, reset history, and pause/resume history. The data-models spec must be updated to match whichever shape the design adopts.
- **UNCHANGED** Edit Mode on the Add/Edit Budget screen continues to allow editing Name, Allocation, Currency, and Carry-Over toggle (per the already-shipped `restrict-edit-budget-period` change). The new `startDate` and `endDate` are also editable in Edit Mode. Period remains locked.

### 2.3. `BudgetPeriod` enum

- **NEW** `.specificDates` case for trip-style / one-shot envelope budgets.
- **UNCHANGED** `.daily`, `.weekly`, `.biweekly`, `.monthly` keep their existing semantics, except that weekly/biweekly anchoring now derives from `startDate` per §2.4.

### 2.4. Period anchoring

- **NEW** For weekly and biweekly budgets, the budget's cycle is anchored to `startDate`: `weekStart` = `startDate.weekday`; `biweeklyAnchor` = `startDate`. The global `AppSettings.weekStartDay` is **not** consulted at math-time for budgets that have a `startDate`.
- **NEW** `startDate` is required by the UI at creation time for every period type. Pre-population rules per period type:
  - **Daily**: today (equivalent to `createdAt` for new budgets).
  - **Weekly / biweekly**: the latest natural anchor implied by `AppSettings.weekStartDay` (i.e., the most recent past or current `weekStartDay`-aligned date).
  - **Monthly**: the start of the current month.
  - **Specific Dates**: left blank. Both `startDate` and `endDate` are required for this period type before the user can save.
  - The user may accept or override the pre-populated value.
- **NEW** Semantically `startDate` is always set on a saved budget. The field is stored as `Date?` only for CloudKit compatibility (see §2.2). If a nil value is somehow encountered at read time (e.g., a malformed sync record), the algorithm falls back to `createdAt`; `AppSettings.weekStartDay` is no longer consulted as a math-time fallback for weekly/biweekly budgets.
- **NEW** No proration of partial first/last periods. The full per-period allocation applies regardless of whether the period is partial at the boundary.

### 2.5. Specific Dates type semantics

- **NEW** One window (`[startDate, endDate]`, both required), one allocation, no recurrence.
- **NEW** The standard **Carry-over** chip is hidden for this period type. The **Remaining** chip (per main-prd.md §6.7) is shown and displays `allocation − sumOfExpensesInWindow`. It freezes after `endDate`.
- **NEW** `isCarryOverEnabled` toggle hidden in UI; algorithm ignores it for this type.
- **NEW** "Reset Carry-Over" action hidden in UI; algorithm ignores it for this type.
- **NEW** Pause / Resume action hidden in UI; not applicable to this type. If a pause or resume event somehow lands on a `specificDates` budget anyway (e.g., direct CloudKit write or a UI bug), the algorithm ignores it — matching the `isCarryOverEnabled` treatment.
- **NEW** Carry-over toggle qualification: F-2.07's universal claim becomes "Every **recurring** budget can have the carry-over calculation turned off."

### 2.6. Reset Cadences (REMOVED outright)

- **REMOVED** The entire feature: enum, stored column, scheduled-reset code path, lifecycle orchestration step, picker UI affordance, `checkScheduledReset` math requirement, all "PAUSED — Reset Cadences" notes across `docs/main-prd.md`, `docs/product-features-planning.md` (F-2.03), `docs/tech-design-doc.md`, `docs/ux-design-brief.md`, the relevant openspec specs, and any cadence-related Mixpanel properties in `docs/analytics-spec.md`.
- **UNCHANGED** Manual Reset Carry-Over (the user-tapped button) stays.
- **UNCHANGED** Reset Budget (delete all expenses + zero carry-over from that moment forward) stays — intent unchanged; storage shape may change.
- **UNCHANGED** Delete Budget stays.

### 2.7. Pause / Resume (NEW — delivers F-7.06)

- **NEW** Per-budget on/off capability. At any moment, each of the budget's periods is either **active** or **paused** — see §5.5 for the period-discrete semantics.
- **NEW** Pause and Resume operate at **period granularity**. The within-period timing of the action does not affect the math:
  - Pause: the period containing the pause action is still calculated normally (full allocation, normal carry-over accrual). The **next** period is the first one where math stops.
  - Resume: the period containing the resume action activates **in full** (no proration). Carry-over from the prior pause carries forward into this period.
- **NEW** While paused: no allocation accrues to any new period; the expense Add CTA on Budget Detail is hidden or disabled; the expense date picker is constrained to the union of active periods.
- **NEW** Backdated expense edits into a *prior active period* are always accepted and always recomputed into that period's carry-over.
- **NEW** Pause is hidden / disabled for `specificDates` budgets (see §2.5 for the algorithm-ignores fallback).
- **UNCHANGED** While paused, Manual Reset Carry-Over, Reset Budget, and the Edit Budget sheet all remain available.
- **NEW** The chip is visible while paused but visually marked paused (e.g., greyed value, "Paused since X" caption). The displayed value can still change while paused if expenses in prior active periods are edited.
- **NEW** `endDate` is terminal — once `endDate` is reached, the budget cannot be resumed. If `endDate` falls inside a paused period, no special handling is required: the chip is already frozen at the most-recent-pause value, and reaching `endDate` simply makes that frozen state terminal.

### 2.8. Expense UI

- **NEW** The Add/Edit Expense screen constrains the date picker to `[startDate, endDate]` ∩ the union of active periods (where "active period" is defined in §5.5), or otherwise rejects out-of-range dates. F-2.04's acceptance criteria gains a date-bounds rule.

### 2.9. Chip semantics across `BudgetsView` and `BudgetDetailView`

- **CHANGED** For recurring types: chip is the signed cumulative carry-over per main-prd.md §6.7, updating mid-period per the asymmetric coupling rule in §2.1 (overspend and add-funds excess land live; ordinary mid-period slack waits for the period close).
- **NEW** For `.specificDates`: the standard **Remaining** chip displays `allocation − sumOfExpensesInWindow`; the **Carry-over** chip is hidden. main-prd.md §6.7 needs a Specific Dates carve-out.
- **NEW** Pre-`startDate` state, post-`endDate` state, and paused state each get their own chip presentations:
  - Pre-start: "Starts on X" treatment; algorithm returns 0.
  - Post-end: "Ended on X" treatment; chip frozen at final tally.
  - Paused: "Paused since X" treatment; value can still change due to backdated edits.
- **NEW** These status presentations appear on `BudgetsView`, `BudgetDetailView`, and as appropriate on `AddEditBudgetView`.

### 2.10. Absorbed Open features

- **CHANGED** F-7.05 (Per-budget period start date) is delivered by `startDate` plus per-budget weekly/biweekly anchoring. Mark Implemented when the rewrite ships.
- **CHANGED** F-7.06 (Stop a Budget) is delivered by Pause / Resume. Mark Implemented when the rewrite ships.

### 2.11. Docs and specs that must be updated in the same change

> [!NOTE]
> **Sync status (as of 2026-05-11).** `docs/product-features-planning.md` has been pre-synced with this briefing — its features list already reflects the rewrite's end state (new F-2.08 and F-7.07; updated ACs across F-2.01, F-2.02, F-2.03, F-2.04, F-2.07, F-5.01, F-7.05, F-7.06, F-8.02; F-2.03 Reset Cadence picker removed). F-7.05 and F-7.06 are still flagged Open and should be flipped to Implemented when the rewrite ships. **Every other doc and spec below is NOT yet synced** — they still describe the boundary-only `rollCarryOver` design, the PAUSED Reset Cadences feature, the missing `startDate` / `endDate` fields, etc. Thus, openspec must update them all in the same update.

- `docs/main-prd.md` — §6.7 carry-over rewrite for live-walker semantics + Specific Dates carve-out; remove all Reset Cadences PAUSED notes.
- `docs/product-features-planning.md` — **already synced**; only outstanding action is to flip F-7.05 and F-7.06 to Implemented when the rewrite ships.
- `docs/tech-design-doc.md` — remove Reset Cadences references; reflect any new entity/storage choices the design lands on.
- `docs/ux-design-brief.md` — remove Reset Cadences notes; document pre-start / post-end / paused chip states.
- `docs/analytics-spec.md` — remove cadence-related event properties if any; add the new `budget_edited` property flags (`allocation_changed`, `start_date_changed`, `end_date_changed`) and the new dedicated events `budget_paused` and `budget_resumed`.
- `openspec/specs/budget-math/spec.md` — wholesale rewrite; delete `checkScheduledReset`.
- `openspec/specs/budget-lifecycle/spec.md` — rewrite `refreshAndSave`; delete the scheduled-reset step.
- `openspec/specs/data-models/spec.md` — Budget field changes; delete `ResetCadence`; add whatever new entities the design introduces.
- `openspec/specs/add-edit-budget-screen/spec.md` — new editable `startDate` / `endDate` fields with `startDate` pre-population; delete cadence picker scenarios.
- `openspec/specs/budgets-screen/spec.md` and `openspec/specs/budget-detail-screen/spec.md` — chip semantics for Specific Dates and paused states; pre-start / post-end / paused presentations; refresh-trigger updates.
- `openspec/specs/add-edit-expense-screen/spec.md` — new date-bounds scenario.

## 3. Context (what's already in place before this chat starts)

The branch is starting from `main` with one relevant prior change shipped, and the carry-over bug that motivated this work is **still present**:

1. `**restrict-edit-budget-period`** (shipped, commit `68966b1` on main) — In Edit mode on the Add/Edit Budget screen, **Period** is non-interactive after creation (chips render as static labels with a `lock.fill` caption), and a "no currency conversion" disclaimer appears below the allocation/currency row when the user picks a different Currency. The model layer also excludes `period` from Edit-mode Save. **Name**, **Allocation**, **Currency code**, and **Carry-Over enabled** remain editable. A follow-up to also lock **Currency code** in Edit mode is planned in a separate chat; the rewrite does not depend on that. The new **Start Date / End Date** fields proposed below should also be editable in Edit mode.
2. **The original carry-over bug is unfixed.** `BudgetCalculator.rollCarryOver(...)` (returning a `CarryOverRollResult` of the new amount and `lastProcessedDate`) is the current algorithm and is boundary-only: it folds completed periods into `Budget.carryOverAmount` and advances `Budget.carryOverLastProcessedDate` to the last completed period boundary. When an expense is added, edited, or deleted **within the current in-progress period**, the `CarryOverChip` on `BudgetsView` / `BudgetDetailView` does not update mid-period — it only refreshes when a period boundary is crossed. Fixing this is one motivation for the rewrite.

Stored carry-over fields on `Budget` today: `carryOverAmount: Decimal`, `carryOverLastProcessedDate: Date`, `carryOverLastResetDate: Date`. The `resetCadence: String` column is also present but PAUSED (see §5.4).

## 4. Related shipped features and specs

The new chat should read these before designing. They are the contracts the rewrite is operating against. Where this briefing contradicts any of them, the briefing wins — see §4.4 below.

### 4.1. Implemented features (from `docs/product-features-planning.md`)

- **F-1.02 Data Architecture** — SwiftData models with CloudKit sync. Greenfield — no rows in production.
- **F-2.01 Budgets screen** — list of budgets; each row shows **Remaining for current Budget Period** and a separate signed cumulative **Carry-over** chip per main-prd.md §6.7. Today the chip updates only at period boundaries (boundary-only `rollCarryOver`); fixing the mid-period refresh is one motivation for this rewrite.
- **F-2.02 Budget screen** — single-budget detail. Same Remaining / Carry-over treatment, plus the toolbar **Edit Budget**, **Reset Budget…** (deletes all expenses, zeros `carryOverAmount`), and the inline **Reset Carry-Over** button.
- **F-2.03 Add/Edit Budget screen** — fields: Name, Period (immutable after creation, per `restrict-edit-budget-period`), Allocation, Currency (per-budget, label-only changes), Carry-over toggle. The Reset Cadence picker is currently PAUSED in the codebase (the column persists as `"never"`); this rewrite **permanently removes** it — see §5.4.
- **F-2.04 Add/Edit/View Expense Item screen** — fields: name (optional), amount (required), date/time (prefilled with now). No date-bounds validation today.
- **F-2.07 Carry-over toggle** — per-budget toggle plus a global default in Settings (`AppSettings.defaultCarryOverEnabled`). Syncs via `NSUbiquitousKeyValueStore`.
- **F-3.04 Internationalization of currency** — currency is per-Budget and label-only (no FX). The Add/Edit Budget screen already shows the "no conversion" caption when the user changes currency.
- **F-5.01 Configurable start of week** — `AppSettings.weekStartDay` is a global iCloud-synced setting that cascades to all weekly/biweekly Budgets.
- **F-6.01 Add Funds** *(partial)* — negative-amount `ExpenseItem` rows. The algorithm just sees them as expenses with negative amounts.
- **F-6.02 Expense Type** *(partial)* — `expenseType: String?` on `ExpenseItem`. Doesn't affect math.
- **main-prd.md §6.7 Carry-over behavior** — defines `carryOverAmount` as the signed cumulative value folded in at each period boundary, the **Remaining for current Budget Period** vs **Carry-over** display split, and the three reset actions (Reset Carry-Over, Reset Budget, Delete Budget). The "folded in at each period boundary" wording assumes a boundary-only roll; the rewrite changes this behavior, so §6.7 needs an update in the same change.

### 4.2. Open features whose scope this rewrite touches

- **F-7.05 Per-budget period start date** — currently Open. This rewrite delivers it: the new `startDate` field plus per-budget week/biweekly anchoring covers F-7.05's full description. Mark F-7.05 as Implemented by the rewrite when it ships.
- **F-7.06 Stop a Budget** — currently Open; described as a manual halt-with-resume. This rewrite delivers it as the **Pause / Resume** capability — see §5.5. The `endDate` field is a *terminal* cutoff (no resume); pause/resume is a recurring on/off toggle that partitions the budget's periods into active and paused at period granularity. Mark F-7.06 as Implemented by the rewrite when it ships.
- **F-7.03 Voice query for Budget status** — depends on the chip value. The new algorithm's returned value must equal what the chip displays.
- **F-8.02 Mixpanel** — ongoing concern; new edit fields warrant new property flags on `budget_edited` (`allocation_changed`, `start_date_changed`, `end_date_changed`), and pause/resume each get their own dedicated event (`budget_paused`, `budget_resumed`).

### 4.3. Relevant OpenSpec specs

- `**openspec/specs/budget-math/spec.md`** — pure period and carry-over math (`PeriodCalculator`, `BudgetCalculator`).
- `**openspec/specs/budget-lifecycle/spec.md`** — `BudgetLifecycleService.refreshAndSave` orchestrator.
- `**openspec/specs/data-models/spec.md`** — `Budget`, `ExpenseItem`, `BudgetPeriod`, and the carry-over toggle requirement. Currently also defines the (paused) `ResetCadence` enum and `Budget.resetCadence` column; both are removed by this rewrite — see §5.4.
- `**openspec/specs/add-edit-budget-screen/spec.md`** — Add/Edit Budget UI contract, including the post-`restrict-edit-budget-period` immutability rules.
- `**openspec/specs/budgets-screen/spec.md**` and `**openspec/specs/budget-detail-screen/spec.md**` — chip display, refresh triggers, Reset Budget / Reset Carry-Over actions.
- `**openspec/specs/add-edit-expense-screen/spec.md**` — expense form contract; no date-bounds rule today.

These specs describe the current `rollCarryOver` + `checkScheduledReset` + `carryOverLastProcessedDate` design. The rewrite replaces those requirements wholesale.

### 4.4. Conflicts with prior feature descriptions

Where the briefing contradicts the items above, **the briefing wins**. The new chat must update the affected docs in the same change. The known conflicts:

1. **F-2.01 and F-2.02 carry-over chip semantics for `BudgetPeriod.specificDates`.** Both ACs describe the chip as a "signed cumulative carry-over per main-prd.md §6.7." That definition presupposes recurring periods. For Specific Dates budgets there are no completed prior periods to roll forward; the standard **Carry-over** chip is hidden and the **Remaining** chip shows `allocation − sumOfExpensesInWindow` (and freezes after `endDate`). main-prd.md §6.7 needs a Specific Dates carve-out, and F-2.01/F-2.02 ACs need updating. (Separately, §6.7 and F-2.01/F-2.02 also need wording updates so that the chip reflects mid-period changes, not only boundary rolls — see §5.1 and the §6.7 reference above.)
2. **F-2.07 Carry-over toggle universality.** F-2.07 says "Every budget can have the carry-over calculation turned off." Carry-over is meaningless for Specific Dates budgets, so the toggle is hidden in the Add/Edit Budget UI for that period type and the algorithm ignores `isCarryOverEnabled` for that type. F-2.07 AC should be qualified: "Every recurring budget…".
3. **F-2.03 Allocation editability has no semantics today.** F-2.03 lists Allocation as editable but says nothing about what happens to history when it changes. The briefing pins the semantics to "forward-only, effective at `currentPeriodStart`": prior periods retain whichever allocation was in effect when they occurred. F-2.03 AC needs an "Allocation edit semantics" line.
4. **F-2.02 Reset Budget definition.** F-2.02 says Reset Budget "deletes every `ExpenseItem` for this budget, zeros `carryOverAmount`, and bumps timestamps in a single `ModelContext.save()`." The rewrite changes the carry-over storage shape, so the "zeros `carryOverAmount`" wording may not apply. The required end-state behavior is unchanged: Reset Budget removes all expenses for the budget and resets carry-over to zero from that moment forward. Wording in F-2.02 and main-prd.md §6.7 needs to follow whatever shape the rewrite chooses.
5. **F-2.04 expense date is unbounded today.** F-2.04 places no constraint on the expense date. The briefing requires the UI to reject expense dates outside `[startDate, endDate]` ∩ the union of active periods, or to constrain the user's ability to input such dates. F-2.04 AC needs a date-bounds rule, and the spec for `add-edit-expense-screen` needs the matching scenario.
6. **F-5.01 weekStartDay scope.** F-5.01: the global setting "will cascade to all existing Budgets." Under the briefing, weekly/biweekly Budgets derive their anchor from `startDate`, ignoring the global setting at math-time. `AppSettings.weekStartDay` still seeds the UI's pre-populated `startDate` at creation time (per §2.4). It is no longer consulted as a math-time fallback; if `startDate` is somehow nil at read time, the algorithm falls back to `createdAt`. F-5.01 Edge Cases / Notes should be updated to describe the per-budget override and the pre-population behavior.
7. **F-7.05 and F-7.06 absorbed.** F-7.05 (Open, "Per-budget period start date") and F-7.06 (Open, "Stop a Budget") both describe standalone features. The rewrite delivers F-7.05 via the new `startDate` field and F-7.06 via the new Pause / Resume capability (§5.5). When the rewrite ships, mark both as Implemented by this change, not as separate future changes.
8. `**openspec/specs/data-models` Budget entity table.** The rewrite removes `carryOverLastProcessedDate` (no longer needed once the chip updates mid-period) and gains `startDate: Date?` and `endDate: Date?`. Other stored carry-over fields may change shape depending on how the rewrite chooses to represent allocation history, reset history, and pause/resume history; the data-models spec must be updated to match.
9. `**openspec/specs/budget-math` and `budget-lifecycle`**. These currently describe `rollCarryOver` (boundary-only, returning a `CarryOverRollResult` with `amount` and `lastProcessedDate`), `checkScheduledReset`, and the `refreshAndSave` orchestration that calls them in order. The rewrite replaces these requirements wholesale with whatever the new design produces. The `checkScheduledReset` requirement is deleted outright (§5.4).
10. **Reset Cadences PAUSED notes — permanently removed.** Reset Cadences is currently described as PAUSED in `docs/main-prd.md`, `docs/product-features-planning.md` (F-2.03), `docs/tech-design-doc.md`, `docs/ux-design-brief.md`, `openspec/specs/data-models/spec.md`, `openspec/specs/budget-lifecycle/spec.md`, `openspec/specs/budget-math/spec.md`, and `openspec/specs/add-edit-budget-screen/spec.md`. The rewrite deletes the feature, not pauses it (see §5.4). Every PAUSED note, the `ResetCadence` enum, the `Budget.resetCadence` column, the scheduled-reset code path in `BudgetLifecycleService.refreshAndSave`, the `checkScheduledReset` requirement in `budget-math`, and any remaining cadence-picker UI hooks must be removed in the same change. `docs/analytics-spec.md` should be checked for cadence-related event properties and trimmed if present.

## 5. The open problems

Five independent problems all touch the carry-over algorithm. The rewrite must address them together.

### 5.1. Mid-period refresh without retroactive history rewrites

Two requirements together:

1. The Remaining chip must update **fully live** in response to expense add / edit / delete in the current period. The Carry-over chip must update **asymmetrically live** — instantly absorb the current period's *committed* overflow (overspend or add-funds excess), but hold ordinary mid-period slack until the period closes. (See §2.1 for the full rule.) Today's boundary-only `rollCarryOver` is the root cause of the unfixed chip-stale bug.
2. Editing the budget's allocation must **not retroactively rewrite the carry-over of prior periods**. Prior completed periods retain whichever allocation was in effect when they occurred. Allocation edits are forward-only and take effect starting at `currentPeriodStart` (the boundary of the period that is in progress when the edit happens). Allocation edits are *not* a reset.

**Why both at once.** The naive way to satisfy (1) is to re-walk every period from some anchor through the in-progress period using a single scalar `allocation`. That walker re-applies the *current* allocation to every prior period, which violates (2). The chosen design (allocation history with forward-only `effectiveFrom` keys, walker iterating completed prior periods only, current period's spillover added separately) satisfies both.

**Worked example (allocation edit propagation).** Daily budget, $20 allocation, $15/day spend, 60 days running. A naive live walker that re-applies current allocation: 60 × $5 + (today: $20 − $0) = $320. User edits allocation $20 → $25. Next refresh: 60 × $10 + (today: $25 − $0) = $625. User expected ~$325 (the change should only affect today and going forward). The chosen design's walker uses per-period allocation lookup, so prior periods continue contributing $5 each → +$300, plus today's spillover (none, since $25 − $0 = $25 is inside `[0, $25]`) = +$300 carry-over after the edit. Today's Remaining shows $25.

**Worked example (asymmetric live coupling).** Daily $20 budget, +$5 carry-over from prior days, $10 spent today so far. Remaining = $10, Carry-over = +$5. User logs an $11 expense. Remaining = −$1 (overspent by $1), Carry-over updates instantly to +$4 (because the −$1 is *committed* overspend). User then deletes that $11 expense. Remaining = $10, Carry-over snaps back to +$5. User adds $30 via F-6.01 Add Funds. Remaining = $40, Carry-over jumps to +$25 (the +$20 excess above the $20 allocation lands live). User then spends $30. Remaining = $10, Carry-over returns to +$5. The chip mirrors what the user has *committed* at every moment.

### 5.2. New Start Date and End Date fields on `Budget`

Two new fields, both stored as `Date?` for CloudKit compatibility:

- `**startDate: Date`** (stored `Date?`) — when the budget begins. May be in the past, today, or the future. Carry-over does not accumulate before `startDate`. Expenses dated before `startDate` should be rejected by the UI. The UI **requires** a value before save and pre-populates it according to the per-period-type rules in §2.4 (daily = today; weekly/biweekly = latest `AppSettings.weekStartDay`-aligned date; monthly = start of current month; specific dates = blank, user must fill in). If a nil value is ever encountered at read time, the algorithm falls back to `createdAt`.
- `**endDate: Date?`** — when the budget stops calculating. Genuinely optional for recurring budgets; required by the UI for `specificDates` budgets. After `endDate`, the chip is frozen at the final tally. The user may still add expenses dated within `[startDate, endDate]` after `endDate` has passed (e.g., logging trip expenses after returning home). Expenses dated outside `[startDate, endDate]` should be rejected by the UI.

For weekly and biweekly periods, the budget's `startDate` becomes the per-budget anchor for the week/biweekly cycle. That is, `weekStart` is derived from `startDate.weekday` and `biweeklyAnchor` is `startDate` itself, *for that budget*. The global `AppSettings.weekStartDay` is no longer consulted at math-time for individual budgets that have a `startDate`; it only seeds the pre-populated value at creation time.

No proration of partial first/last periods. The full per-period allocation applies regardless of whether the period is partial at the boundaries.

### 5.3. New "Specific Dates" period type

A new `BudgetPeriod.specificDates` case for one-shot / trip-style budgets. Semantics:

- **One window**: `[startDate, endDate]` defines the entire budget lifetime. That is, there is only one instance of the Period and that Period is from `startDate` to `endDate` inclusive. Both dates are required for this type.
- **One allocation**: a single number for the whole window, not per-day.
- **No recurrence**: there are no repeating periods.
- **Carry-over has no meaning**: there's no "completed prior period" to roll forward from. Carry-over is effectively turned off and the **Carry-over** chip is never displayed for this period type. The standard **Remaining** chip displays `allocation − sumOfExpensesInWindow` and freezes after `endDate`.
- `**isCarryOverEnabled` and "Reset Carry-Over"** are meaningless for this type. Hide both in the UI.

A "$50/day for 7 days" trip budget is **not** a `specificDates` budget — it's a `daily` budget with `startDate` and `endDate` set. The `specificDates` type is for the "$350 total for the trip" envelope semantics.

### 5.4. Permanently remove Reset Cadences

Reset Cadences (the user-configurable "every N period boundaries, automatically zero the carry-over" feature, with options weekly / biweekly / monthly / quarterly / never) was paused on 2026-04-28. The picker is hidden, new rows persist `resetCadence = "never"`, and the scheduled-reset code path is a runtime no-op for any budget created during the pause. This rewrite **deletes the feature outright** — it is not coming back.

What goes away:

- `ResetCadence` enum, `Budget.resetCadence` stored property, and `BudgetPeriod.defaultResetCadence` mapping.
- `BudgetCalculator.checkScheduledReset` (or whatever the current scheduled-reset entry point is named) and the corresponding requirement in `openspec/specs/budget-math/spec.md`.
- The "check for a scheduled reset" step inside `BudgetLifecycleService.refreshAndSave` and the corresponding requirement in `openspec/specs/budget-lifecycle/spec.md`.
- The cadence-picker UI affordance in `openspec/specs/add-edit-budget-screen/spec.md`.
- All "PAUSED — Reset Cadences" `[!NOTE]` callouts and prose in `docs/main-prd.md`, `docs/product-features-planning.md` (F-2.03), `docs/tech-design-doc.md`, `docs/ux-design-brief.md`, and the openspec specs above. Replace each with either deletion or a one-line "Reset Cadences was removed in " note where context demands it.
- Tests for `checkScheduledReset` and any "default-cadence budget never schedules a reset" scenarios.

What stays:

- **Manual Reset Carry-Over** (the user-initiated button on Budget Detail). Unchanged.
- **Reset Budget** (delete all expenses + reset carry-over to zero from that moment forward). Unchanged in intent; storage shape may change.
- **Delete Budget**. Unchanged.

### 5.5. Pause and Resume a Budget

A user can **Pause** a budget and later **Resume** it. A budget can cycle through pause/resume any number of times.

**Distinction from `endDate` and `specificDates`.** `endDate` is *terminal* — no resume, walker stops permanently. `specificDates` is a single fixed window with no recurrence at all. Pause/Resume is a recurring on/off toggle on a recurring budget. The model is **period-discrete**: at any moment, each of the budget's periods (from `startDate` through `endDate` or `now`) is either **active** or **paused**. The budget's lifetime is partitioned into active periods and paused periods by the budget's pause/resume history.

**Period granularity.** Pause and Resume operate at the granularity of whole periods, not arbitrary timestamps. The within-period timing of a pause/resume action does not affect the math:

- **Pause.** The period containing the pause action is itself **active** — calculated normally with full allocation and normal carry-over accrual. Periods strictly *after* the pause-action period are paused until a resume occurs.
- **Resume.** The period containing the resume action is **active** in full (no proration). Carry-over from the most recent pause carries forward into this period.

**Definition of "paused period".** A paused period is any period whose entire extent falls between the close of the most recent pause-action period and the open of the next resume-action period (or `endDate` / `now` if there has been no resume since the pause).

**Example.** Weekly budget, current date 05 May, week 01–07 May. User taps Resume on 05 May. The week 01–07 May is the resume-action period and is therefore fully active. The whole week counts in full.

**Conceptual link to `startDate` / `endDate`.** Setting `startDate` and `endDate` is conceptually like pre-setting a Resume and Pause respectively. Conversely, a Pause/Resume is like applying an `endDate` or a `startDate` to the budget effective on the day the user invokes the action — but unlike `endDate`, Pause is not terminal. As a corollary, if `endDate` falls inside a paused period, no special algorithmic handling is needed: the chip is already frozen at the most-recent-pause value, and `endDate` simply makes that frozen state terminal.

**The required edge case.** User pauses, then later adds an `ExpenseItem` backdated to a date that falls inside a *prior* active period. On the next refresh — whether the budget is currently paused or has just been resumed — the algorithm must fold that expense into the carry-over for the period it belongs to. Concretely: a daily budget with $20/day, paused after 10 days at +$50 carry-over; user later adds a backdated $30 expense to day 5 (which was active); the algorithm produces +$20 carry-over. When the budget resumes, that +$20 carries over into the new resume-action period just like any other completed-period accumulation.

**Allocation edits while paused.** Allocation edits made during a pause take effect at the resume point — i.e., they apply to the period that contains the resume action and to every subsequent active period. The storage convention may record `effectiveFrom` either at the paused period's start or at the resume-anchored period's start; both produce the same final carry-over, because paused periods contribute 0 regardless of allocation value.

**Pause while `startDate` is in the future.** If the user invokes Pause on a budget whose `startDate` has not yet been reached (UI affordance permitting), the pause is recorded as if it occurred on `startDate` itself. The pre-start chip presentation is preserved until `startDate`; from `startDate` onward the budget is in a paused state until the user resumes.

**What stays the same when paused.** Manual Reset Carry-Over and Reset Budget remain available. The Edit Budget sheet stays open. The chip is visible but visually marked paused.

**What changes when paused.** The expense Add CTA on Budget Detail is hidden or disabled. Backdated expense edits remain available but the date picker is constrained to the union of active periods.

## 6. Edge cases / situations the new algorithm must handle

The new chat should walk every numbered item against whatever design it proposes, before writing code. Items marked **★** are the ones most likely to expose design flaws — verify these explicitly.

### 6.1. Expense lifecycle

1. Add expense in current period.
2. Add expense backdated to a prior period.
3. Edit expense amount in current period.
4. Edit expense amount in a prior period.
5. Edit expense date moving it across a period boundary.
6. Delete expense in current period.
7. Delete expense in a prior period.
8. Sign-flip edits (negative `amount` for add-funds per F-6.01).
9. Add or edit expense dated outside `[startDate, endDate]` — UI must reject or not offer that option; if it slips through, algorithm must clamp.
10. **★ Asymmetric live Carry-over coupling (§2.1).** Adding an expense that pushes the current period from Remaining ≥ 0 into Remaining < 0 must immediately decrease Carry-over by the overshoot amount. Deleting or editing-down that same expense back into Remaining ≥ 0 must immediately restore Carry-over. Add-funds expenses (negative `amount`, F-6.01) that push Remaining above Allocation must immediately increase Carry-over by the excess. Ordinary mid-period expenses that keep Remaining inside `[0, Allocation]` must NOT change Carry-over (the change is provisional until the period closes).

### 6.2. Allocation lifecycle

1. Single allocation edit, current period day 1.
2. Single allocation edit mid-period.
3. Multiple allocation edits in the same current period (must be deterministic; the latest edit overwrites the prior in-period allocation, which is not retrievable).
4. Two allocation edits in different periods.
5. Decreasing allocation.
6. **★** Allocation edit followed by backdated expense to a period BEFORE the most recent allocation change (must use the historical allocation for that period).
7. Allocation edit followed by backdated expense to a period BETWEEN two allocation changes.
8. **★** Allocation edit followed by manual Reset Carry-Over (reset trims the active walk window; allocation history from before the reset is not consulted by the walker).
9. Manual Reset Carry-Over followed by allocation edit.
10. Allocation edit while sitting on negative carry-over.
11. Allocation edit on a budget with zero prior periods.
12. **★** Concurrent allocation edits on two devices via CloudKit (must converge to a consistent value).

### 6.3. Reset / lifecycle

1. Manual Reset Carry-Over (existing behavior). Post-reset rebound: chip immediately shows `(currentAllocation − currentPeriodSpend)` because the algorithm includes the current in-progress period. Documented and intentional.
2. Reset, then allocation edit, then expense add in the post-reset period.
3. Verify there is no surviving scheduled-reset code path, stored field, or requirement after the rewrite (Reset Cadences removal — see §5.4).
4. After a user manually Resets the Carry-over, if the user then modifies expenses in periods *before* the reset took place, the Carry-over should not be affected.

### 6.4. Start Date

1. **★** Budget with `startDate` in the future. `now < startDate`: chip hidden or shows "Starts on X"; algorithm returns 0.
2. Budget with `startDate` in the past (e.g., backfilling a budget for last month). Walk starts at `startDate`, treats prior days normally.
3. Budget read with `startDate = nil` falls back to `createdAt`. The UI requires `startDate` at creation (see §2.4), so this is a safety-net for malformed sync records rather than a normal-flow state.
4. Weekly budget with `startDate = Wednesday`. The budget's "week" runs Wed → Tue, regardless of `AppSettings.weekStartDay`.
5. Biweekly budget with `startDate = some Monday`. Subsequent biweekly cycles align to that Monday.

### 6.5. End Date

1. **★** Budget past its `endDate`. `now > endDate`: algorithm uses `endDate` as its effective "now". Chip frozen at final tally. No further period rolls.
2. User adds an expense dated `endDate − 2 days` after the budget has ended. UI accepts (within window); algorithm folds it in; chip updates to reflect the new final tally.
3. Budget where `endDate` falls mid-period (e.g., monthly budget ending Sept 15). The final period spans `currentPeriodStart` to `endDate`. Full allocation credited (no proration).
4. Specific Dates budget past its `endDate`. Same shape as #1 above but the entire budget is one window.

### 6.6. Specific Dates type

1. **★** Specific Dates budget, in-progress (now between startDate and endDate). The **Remaining** chip displays `allocation − sumOfExpensesInWindow` (the **Carry-over** chip is hidden — see §2.5). Updates live as expenses are added.
2. Specific Dates budget before its startDate.
3. Specific Dates budget past its endDate. Frozen final tally.
4. Specific Dates with a backdated expense edit. Recompute is trivial (entire budget is one period).
5. Specific Dates and `isCarryOverEnabled` toggle: hide in UI; algorithm ignores.
6. Specific Dates and "Reset Carry-Over" action: hide in UI; algorithm ignores.
7. Editing the allocation on a Specific Dates budget. There is only one period (the entire window), so the algorithm cannot preserve per-period allocations the way recurring types do. A mid-window allocation edit uses the most recent allocation for the entire window (latest-wins). Thus, latest-wins overwrites the user's prior figure.
8. Specific Dates and Pause / Resume: not applicable. Specific Dates budgets cannot be paused; the period type already encodes a fixed window. Hide the Pause action in the UI for this type.

### 6.7. Pause / Resume

1. Pausing and Resuming a Budget applies the action in the period it occurred in. The within-period timing of the action does not affect the math.
2. When Pausing, the period containing the pause action still calculates its remaining amount and carry-over normally. It's the *next* period where Budget mathematics are stopped. Allocation is zeroed out and carry-over is frozen in display value (see item 15 for the can-still-be-recomputed nuance).
3. Resume activates the period containing the resume action with its full allocation — no proration, regardless of when in the period the resume occurred.
4. After resuming a budget, carry-over carries forward from the prior pause into the resumed period.
5. **★** Backdated expense to a date inside a *prior* completed active period, while the budget is currently paused. Algorithm folds it into the period it belongs to; carry-over for that prior period is recomputed; the chip reflects the new total. (This is the user's explicitly-called-out edge case.)
6. **★** Backdated expense to a prior active period, then Resume. The resume-action period inherits the recomputed carry-over from all prior active periods.
7. Backdated expense dated inside a paused period (i.e., a period whose entire extent falls between the close of the most recent pause-action period and the open of the next resume-action period — see §5.5). UI rejects or restricts the user somehow, whichever is more convenient; algorithm clamps (returns 0 contribution from that expense).
8. Multiple pause/resume cycles (pause → resume → pause → resume). Algorithm handles arbitrary count; every completed active period contributes to the running total, regardless of which active run it belongs to.
9. **★** Pause → allocation edit → Resume. The allocation edit takes effect at the resume point (i.e., applies to the period containing the resume action and forward). See §2.1 / §5.5 for the convergence note that makes the exact `effectiveFrom` representation a no-op for paused periods.
10. Manual Reset Carry-Over while paused. Allowed. Does not change pause state. On resume, the active walk window starts from the reset point.
11. Reset Budget while paused. Allowed. Deletes all expenses and resets carry-over. Does not change pause state.
12. Pause then set `endDate`. Allowed; budget is terminal once `endDate` is reached even if it was paused at the time. Resume after `endDate` is rejected by the UI. If `endDate` falls inside a paused period, no special algorithmic handling is needed — the chip is already frozen at the most-recent-pause value, and `endDate` simply makes the frozen state terminal (see §5.5 "Conceptual link to `startDate` / `endDate`").
13. Concurrent pause on one device, resume on another, via CloudKit. Must converge cleanly and not produce a "phantom paused period."
14. Pause a `specificDates` budget. Not allowed; pause action hidden for this type (see Specific Dates edge case 8). If a pause or resume event somehow lands on a `specificDates` budget anyway (direct CloudKit write, UI bug), the algorithm ignores it — matching the `isCarryOverEnabled` treatment in §5.3.
15. Pause display: chip is visible but visually marked paused (e.g. greyed value or "Paused since X" caption); chip value is the carry-over at the moment of pause, plus any retroactive adjustments from backdated expense edits. Not "frozen" in the sense `endDate` is — the value can still change while paused if expenses are edited.
16. Pause while `startDate` is in the future. If the user invokes Pause before `startDate` has been reached (UI affordance permitting), the pause is recorded as if it occurred on `startDate` itself. The pre-start chip presentation is preserved until `startDate`; from `startDate` onward the budget is in a paused state until the user resumes.

### 6.8. Display / non-math edits

1. Toggle `isCarryOverEnabled` (recurring types only). Display only; no recompute.
2. Edit `name`. Bumps `lastModified` for refresh trigger; math unchanged.

### 6.9. Future-feature interactions

1. **F-6.01 Add Funds** (negative-amount `ExpenseItem`). Just an expense to the algorithm. Must work in both recurring and Specific Dates types.
2. **F-7.03 Voice query for Budget status**. The value the algorithm returns must match what the chip displays.
3. **F-8.02 analytics**. The `budget_edited` event gains `allocation_changed: bool`, `start_date_changed: bool`, `end_date_changed: bool` flags. Pause and resume each fire their own dedicated event (`budget_paused`, `budget_resumed`).

## 7. Notes on using this briefing

- The edge case list is intentionally exhaustive. The new chat should walk each one against its proposed design. Items marked ★ are the ones most likely to expose design flaws.
- The greenfield status removes the usual reason to add migration ceremony, preserve old field names "for compatibility," or introduce `SchemaV2` / migration-plan stages. The model can change cleanly.
- All product decisions raised during briefing development are resolved and absorbed into §2–§6. There are no open product questions for the next chat to answer before designing.

