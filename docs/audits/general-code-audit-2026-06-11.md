# General Code Audit (pre-launch)

| Field        | Value |
|--------------|-------|
| **Date**     | 2026-06-11 |
| **Trigger**  | Final review before packaging the first App Store release |
| **Scope**    | All app-target Swift source (`simple-recurring-budgets/`, ~100 files / ~11.6k lines), read in full. Test targets, scripts, fastlane, and docs reviewed only where needed to confirm behavior. |
| **Stack**    | SwiftUI + SwiftData + CloudKit + Mixpanel, Swift 6 (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) |

## Audit parameters (as requested)

Because the app is pre-launch, this audit looks for **user-facing bugs, possible
data corruption, crashes, or anything else that might affect the user's
experience**. It deliberately does **not** cover long-term architectural
issues, code-style nits, or documentation drift — with one exception: **code
comments that are egregiously out of sync with what the code actually does**
are flagged (see §3).

## 1. Executive summary

The codebase is in good shape for a first release. Money math is `Decimal`
end-to-end, period math is calendar-based and DST-aware, every production save
routes through a typed error helper with a retry alert, CloudKit modeling rules
(optional relationships, defaulted attributes, single pinned store URL,
`lastModified` tiebreaks, `recomputeToken` for cross-transaction merges) are
followed carefully, and analytics is consent-gated with a strict PII
allow-list.

**No high-severity findings.** Two medium findings are worth fixing before
submission — one latent crash on a corrupt-data shape the code itself
anticipates elsewhere, and one failure-path gap where a cancelled save leaves
the context dirty. The rest are low-severity UX/consistency items, plus two
stale comments that now assert the opposite of what the code does.

| # | Severity | Finding |
|---|----------|---------|
| M1 | Medium | Inverted Specific Dates window traps (`start ..< end`) in `specificDatesDisplayLabel` — reachable from the Budgets list |
| M2 | Medium | No `rollback()` after a failed save is cancelled — context stays dirty; default main-context autosave can commit "abandoned" changes later |
| L1 | Low | Settings iCloud row stays "Paused" after a successful container-failure Retry that recovered CloudKit backing |
| L2 | Low | Future-dated expenses inflate the "Current" section total but are excluded from Remaining — visible disagreement |
| L3 | Low | Lifecycle snapshots don't refresh on period rollover while the app stays foregrounded |
| L4 | Low | Backdating an expense into a historical paused gap silently makes it count toward nothing |
| L5 | Low | Stale "Budgets" brand in the user-visible feedback email subject (app is now "Wren") |
| L6 | Low | Combined allocation + start-date edit anchors the new `AllocationChange` to the *old* period start |
| C1/C2 | Comment drift | `BudgetSnapshot.carryOver` / `BudgetLifecycleResult.carryOverAmount` doc comments claim the specific-dates carry-over chip "is not hidden by any code" — it is |
| C3 | Comment drift (minor) | `BudgetLifecycleResult` header still says `effectiveAllocation` "will be plumbed when F-7.05/F-7.07 ships" — those features shipped |

---

## 2. Findings

### M1 — Crash: inverted Specific Dates window traps in `specificDatesDisplayLabel`

`simple-recurring-budgets/Models/Budget+Display.swift:32-39`

```swift
static func specificDatesDisplayLabel(start: Date, end: Date) -> String {
  if start == end { return start.formatted(...) }
  return (start ..< end).formatted(...)   // ⚠️ traps when start > end
}
```

`Range` construction traps with *"Can't form Range with upperBound <
lowerBound"* when `endDate < startDate`. The codebase explicitly anticipates
this exact data shape: `Budget.isWindowValid`
(`Models/Budget.swift:107-114`) calls an inverted window "a data-integrity
violation — typically from a partial CloudKit sync — and callers building date
ranges should assert before constructing a ClosedRange that would trap", and
`AddEditExpenseViewModel.dateRange`
(`Views/ExpenseForm/AddEditExpenseViewModel.swift:185-190`) defends in release
with `max(lower, upper)`. This call site has no such guard.

**Impact:** `periodDisplayLabel` is rendered for every Specific Dates budget on
both the Budgets list row and the detail header. A single corrupt record
(partial sync, or a future client writing dates differently) would crash the
app **on the root screen, on every launch**, with no way for the user to
recover — the worst possible place for a trap.

**Fix:** mirror the `dateRange` defense — e.g. `if start >= end { return
start.formatted(...) }` or order the bounds with `min`/`max` (plus the same
debug `assert(isWindowValid)` used elsewhere).

### M2 — Failed save + Cancel leaves pending changes in the context (no rollback)

`Views/Shared/SaveErrorAlert.swift:121-127` (Cancel), failure call sites in
`BudgetDetailView+ExpenseSection.swift:102-122`, `AddEditBudgetView.swift:148-161`,
`AddEditExpenseView.swift:69-94`, `BudgetsView.swift:165-180`, etc.

When `context.saveChanges(...)` throws, the mutation that was attempted
(deleted expense, inserted budget + `AllocationChange`, edited fields,
reordered `sortOrder`s) remains **pending in the `ModelContext`**. The
save-error alert's Cancel button only clears the alert state — nothing rolls
the context back. Two consequences:

1. **UI/store divergence.** A swipe-deleted expense disappears from the list
   (relationships reflect pending deletes) even though the store still has it.
   The user is told "Your information is still here" and sees the row gone.
2. **Delayed silent commit.** SwiftData's main-context autosave is enabled by
   default for app containers and is never disabled in this codebase (no
   `autosaveEnabled` writes anywhere). If the original failure was transient
   (e.g. disk-full later relieved), autosave — or the next *unrelated*
   successful save — commits the change the user believes they cancelled.

**Impact:** rare in practice (saves seldom fail), but when they do, the user's
mental model and the store disagree, and "cancelled" destructive actions can
land later without further confirmation. For a budgets app, a phantom-deleted
expense is a data-trust problem.

**Fix:** call `context.rollback()` in the alert's Cancel handler (thread a
closure through `SaveErrorState`, or have each cancel path roll back), keeping
the documented "input stays intact" behavior by re-seeding from the view model
draft (form drafts live in the view models, not the context, so rollback does
not lose typed input on the Add/Edit screens — only the pending model writes).

### L1 — Stale iCloud status after container-failure Retry recovers

`App/simple_recurring_budgetsApp.swift:29-32` seeds `SyncStatus` once at init:
`containerBacking: initialStartup.containerBacking ?? .localFallback`. If
container creation fails at launch and the user's **Retry** in
`ContainerFailureView` then succeeds with CloudKit backing, `SyncStatus` is
never updated — Settings shows "iCloud Sync Paused" with a "restart the app"
footer even though sync is actually active. Self-describing (the footer's
restart advice is harmless and a restart fixes the display), but the row lies
until then. Fix: update `SyncStatus` from `AppStartup.retry()`'s success path,
or derive the row's backing from `AppStartup.containerBacking` live.

### L2 — Future-dated expenses: section total disagrees with Remaining

For a recurring budget with no end date, the Add/Edit Expense date picker's
upper bound is `Date.distantFuture`
(`Views/ExpenseForm/AddEditExpenseViewModel.swift:179-183`), so a user can log
an expense dated next month. The "Current" section partition has **no upper
bound** (`Models/ExpenseItem+Partition.swift:16`, `date >= start`), so that
expense appears under "Current Day/Week/Month" and is included in the section
header total (`BudgetDetailView+ExpenseSection.swift:138`), while
`BudgetCalculator` correctly excludes it from Remaining (`date <
effectivePeriodEnd`). Result: header total and the big Remaining number
visibly disagree until the expense's date arrives.

If future-dating is intended (it appears to be — backdating folds in
automatically by design), consider either capping the picker at the current
period end / end of today, or partitioning "current" as `periodStart ..<
periodEnd` and giving future-dated items their own bucket.

### L3 — No refresh on period rollover while foregrounded

`BudgetDetailView` and `BudgetRowView` recompute the lifecycle snapshot on
`.task(id:)`, `scenePhase == .active`, and `budget.recomputeToken` change
(`Views/BudgetDetail/BudgetDetailView.swift:347-359`,
`Views/BudgetList/BudgetsView.swift:318-330`). None of those fire when a
period boundary passes with the app open — a daily budget left on screen past
midnight keeps showing yesterday's Remaining/carry-over until the user
backgrounds the app or touches data. Cheap fix: also observe
`NSNotification.Name.NSCalendarDayChanged` (or schedule a refresh at
`lifecycle.periodEnd`).

### L4 — Expenses backdated into a paused gap count toward nothing

Save-time validation only restricts the date **while the budget is currently
paused** (`AddEditExpenseViewModel.isDateValid:86-92` guards on
`cachedBudgetSnapshot?.lifecycleState == .paused`). For a currently-active
budget with a historical pause/resume gap, the user can date an expense inside
that gap. The carry-over walker skips paused periods entirely — `guard
isActive(...) else { continue }` runs **before** expenses are summed
(`Domain/CarryOverWalker.swift:61-71`) — and the expense is outside the
current period, so it never affects Remaining or carry-over. It just sits in
the "Past" list. This is arguably consistent with §A.5.4 pause semantics
(paused periods contribute 0), but money that silently affects no number is
surprising; the paused-state flow blocks the equivalent entry. Consider
applying the same active-period validation in all states, or accept and ship.

### L5 — Stale brand in feedback email subject

`Domain/FeedbackMailto.swift:23` — `defaultValue: "Budgets app feedback"`. The
app is now **Wren**; this subject line is user-visible in the Mail compose
sheet from Settings → Send Feedback and from both error-escalation surfaces
(it's the shared `defaultSubject`). Update the en source (and run the
translation pipeline) before launch. This was the only stale user-facing brand
string found in the app target.

### L6 — Combined allocation + start-date edit anchors the new amount to the old period grid

In `AddEditBudgetViewModel.saveEdit`
(`Views/BudgetForm/AddEditBudgetViewModel.swift:271-288`),
`applyAllocationEdit` runs **before** `applyDateEdits`, so for a recurring
budget the new `AllocationChange.effectiveFrom` is computed from the *pre-edit*
`startDate`'s period grid. If the user changes the start date (which re-anchors
weekly/biweekly boundaries) and the allocation in the same save, the new row
can land mid-period under the new anchoring. Because `allocationInEffect` is
latest-wins from `effectiveFrom` onward, the *current* period still resolves to
the new amount, so the visible outcome is right; the subtlety only shows up in
walker history around the boundary period. Listed for awareness — swapping the
order (dates first, then allocation) would make the row land on the new grid.

---

## 3. Egregiously out-of-sync comments (explicitly in scope)

### C1 — `BudgetSnapshot.carryOver` claims no code hides the specific-dates carry-over chip

`Domain/BudgetSnapshot.swift:27-32`:

> "`nil` for `.specificDates` budgets — F-2.08 specifies that the carry-over
> chip is hidden for that type, but **no code currently hides it**. The F-2.08
> UI work must add explicit chip-hiding in `BudgetDetailView` and
> `BudgetRowView`; today `BudgetLifecycleResult.carryOverAmount` flattens
> `nil` → `0`, so an out-of-flow specificDates budget would render `$0.00`
> rather than no chip."

This is now the opposite of reality. Both surfaces hide the chip:
`BudgetDetailView.headerRow` (`Views/BudgetDetail/BudgetDetailView.swift:389`)
and `BudgetRowView` (`Views/BudgetList/BudgetsView.swift:280`) pass
`isCarryOverEnabled: budget.isCarryOverEnabled && !isSpecificDates` into
`StatusChipRow`, which renders `CarryOverChip` only when that flag is true. A
specificDates budget never shows a `$0.00` chip.

### C2 — `BudgetLifecycleResult.carryOverAmount` repeats the same stale story

`Domain/BudgetLifecycleService.swift:14-21`:

> "…the chip-hiding work lives in `BudgetDetailView` and `BudgetRowView` and
> ships with the F-2.08 UI. **Until then this fallback is unreachable in
> normal flow**; the F-2.08 work should either stop calling this entry point
> for specificDates budgets or replace `BudgetLifecycleResult` with a sum type…"

The chip-hiding shipped, and the `?? 0` fallback **is** exercised on every
specificDates render (the calculator returns `carryOver: nil` for that branch
on every snapshot). The "unreachable until F-2.08 ships" framing would send a
future agent down the wrong path. Rewrite both comments to describe the
shipped behavior: snapshot returns `nil`, the adapter flattens to `0`, and the
views hide the chip via `!isSpecificDates`.

### C3 (minor) — `BudgetLifecycleResult` header predicts plumbing that never happened

`Domain/BudgetLifecycleService.swift:8-9`: "`effectiveAllocation` from
`BudgetSnapshot` is intentionally not exposed here — it will be plumbed when
the start-date / end-date input UI ships (F-7.05 / F-7.07)." That UI shipped
(Schedule disclosure / Dates card); the field was never plumbed — views read
`budget.currentAllocation` instead, which is equivalent in practice because
`applyAllocationEdit` always writes the current-period row. Not harmful, but
the stated reason no longer holds.

---

## 4. Areas reviewed and found sound

- **Money math** — `Decimal` everywhere in models and domain; `Double`
  appears only at the analytics boundary for the allow-listed
  `budget_allocation_amount`. Division guarded (`allocation > 0` before the
  remaining-fraction ratio). Input capping (`DecimalInputField.isAcceptable`)
  applies to typing *and* paste; negative/garbage paste is rejected by the
  `canSave` (> 0) gates in both forms.
- **Period math** — all boundary arithmetic is `Calendar`-based
  (`startOfDay`, `date(byAdding:)`); biweekly uses day-count floor-division
  from a day-aligned anchor; dedicated DST test suites exist. The force-unwraps
  on `calendar.date(byAdding:)` calls cannot realistically fail for Gregorian
  inputs.
- **Carry-over algorithm** — walker + current-period spillover reviewed for
  double-counting and end-clamping (`effectiveNow = min(now, endInclusive)`);
  postEnd folds the final period exactly once; reset semantics
  (`lastResetDate` window, full-allocation/no-proration on the reset period)
  match the documented design. Pause math (period-granular) vs pause UI
  (moment-granular) are reconciled deliberately, including the
  `pausedSince`/`isPausedAtMoment` consistency filter.
- **CloudKit modeling** — all relationships optional with non-optional
  accessors; every attribute has a default; no unique constraints; both
  container configs pinned to one explicit store URL (split-brain guard);
  `Budget.recomputeToken` covers child-row merges arriving in separate
  transactions; concurrent-edit convergence tiebreaks on
  `(effectiveFrom/effectiveDate, lastModified)` are applied consistently
  across calculator, service, and view-model write paths.
- **Persistence failure handling** — single `saveChanges(operation:)`
  helper; typed `PersistenceError`; every interactive save site presents the
  standard retry alert and fires analytics only on success; container-creation
  failure shows a recovery surface instead of crashing (subject to M2/L1
  above).
- **Navigation robustness** — routes carry UUIDs, are resolved at the
  destination, and silently pop/dismiss when the model was deleted (e.g. on
  another device).
- **Privacy/analytics** — lazy Mixpanel init (no SDK/network when opted
  out), conservative jurisdiction defaults (unknown region → consent
  required), no `ExpenseItem` field ever transmitted, consent toggle-off
  ordering (track → reset → flag) per spec. The two hardcoded Mixpanel tokens
  are client-side-by-design and deliberately `gitleaks:allow`ed.
- **Test/dev escape hatches** — `IS_TESTING`, screenshot flags, debug launch
  modes, and `TestDynamicTypeOverride` are all either `#if DEBUG`-gated or
  unreachable in a sealed App Store process; the marketing
  `screenshotForcesAvailableState` override is compiled out of Release.
