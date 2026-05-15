# Budget calculations rewrite — migration prompt

| Field            | Value                                                                  |
| ---------------- | ---------------------------------------------------------------------- |
| **Author**       | Jimmy Ho                                                               |
| **Status**       | Active. To be consumed by `/opsx:propose`.                             |
| **Purpose**      | Migrate the app to the new budget-calculations algorithm while preserving the current UI feature surface. New algorithm-enabled features are deferred to future changes. |

> **Read this first.** This document is the **primary directive** for the change. If it conflicts
> with anything inside [`budget-calculations-rewrite-algorithm.md`](budget-calculations-rewrite-algorithm.md)
> (including any "Tasks for Agent" headings or §A.8 service-deletion recommendations), this
> document wins. The algorithm doc is the design spec for the math; this doc tells you which
> parts to wire up *now*.

---

## 1. What you are doing

Migrating the live codebase from the current boundary-only `rollCarryOver` algorithm to the new
live-walker + asymmetric-coupling algorithm. Schema changes, helper rewrites, and the minimum
mechanical UI adaptations required to keep the app compiling, running, and behaviorally
equivalent at the user-facing-feature level.

**You are not building new user-facing features.** The new algorithm enables several
(Pause/Resume, Start/End Date inputs, Specific Dates period type, lifecycle overlays). Those are
each their own separate future change. See §4 below for the explicit out-of-scope list.

---

## 2. Required reading (the canon)

Read these before designing. Where they conflict with each other, the precedence is:

**This doc** → [`budget-calculations-rewrite-algorithm.md`](budget-calculations-rewrite-algorithm.md) → [`budget-calculations-rewrite.md`](budget-calculations-rewrite.md) → other docs.

| Doc | Role |
| --- | --- |
| **This doc** | Migration scope, what's in/out, the compatibility seam. |
| [`budget-calculations-rewrite-algorithm.md`](budget-calculations-rewrite-algorithm.md) | The algorithm design — schema, `BudgetCalculator.snapshot(...)`, helpers (`allocationInEffect`, `walkCarryOver`, `isActive`, `currentPeriodSpillover`), write-site rules, edge cases, test plan. **This is your math source of truth.** |
| [`budget-calculations-rewrite.md`](budget-calculations-rewrite.md) | Briefing — requirements and edge cases the algorithm satisfies. Background reading; do not re-design from it. |
| [`main-prd.md`](main-prd.md) | Product PRD. §6.7 has been updated for the new carry-over behavior (live walker + asymmetric coupling). |
| [`product-features-planning.md`](product-features-planning.md) | Feature backlog. F-2.01, F-2.02, F-2.07 already reflect the new chip refresh rules. F-2.08, F-7.05, F-7.06, F-7.07 stay **Open** after this change. |
| [`tech-design-doc.md`](tech-design-doc.md) | Tech reference. §3 (data model), §4.3 (CloudKit constraints), §5.4 (service layer) — read carefully; you'll be reshaping all three. |

---

## 3. What this change DOES (in scope)

### 3.1. Schema rewrite (per algorithm doc §A.2)

- Reshape the `Budget` entity:
  - **Add**: `startDate: Date?`, `endDate: Date?`, `lastResetDate: Date?` (renamed from
    `carryOverLastResetDate`), `allocationChangesStorage: [AllocationChange]?`,
    `lifecycleEventsStorage: [LifecycleEvent]?` (per the CloudKit optionality pattern in §A.2's
    `[!IMPORTANT]` callout). Provide non-optional computed accessors `allocationChanges` and
    `lifecycleEvents`.
  - **Remove**: `allocation: Decimal`, `carryOverAmount: Decimal`,
    `carryOverLastProcessedDate: Date`, `resetCadence: String`. Also remove the corresponding
    `init` parameters.
- Add two new `@Model` entities exactly as specified in algorithm doc §A.2.2 and §A.2.3:
  `AllocationChange` and `LifecycleEvent`. Include `lastModified: Date` for cross-device
  tiebreaks. `LifecycleEvent.kind` is `LifecycleEventKind` (the enum directly — SwiftData
  serializes `String, Codable` enums automatically; do **not** make it `String` with a separate
  accessor).
- Delete `ResetCadence` enum, `BudgetPeriod.defaultResetCadence`, and the `Budget.resetCadence`
  initializer parameter (the Reset Cadences feature is permanently removed — see briefing §5.4).
- `BudgetPeriod.specificDates` is added as a new case to the enum (algorithm doc §A.2.5). The
  case must exist in code because the algorithm handles it correctly; the UI just won't
  expose it yet (see §4 below).
- Per briefing §1: **greenfield, no migrations**. Update (do not delete) `SchemaV1.swift` and
  `BudgetMigrationPlan.swift` to reflect the new shape. Do NOT introduce `SchemaV2` or
  `VersionedSchema` machinery.

### 3.2. Algorithm implementation (per algorithm doc §A.3–§A.6)

Implement, in `Domain/`:

- `BudgetSnapshot` value type (§A.3).
- `BudgetCalculator.snapshot(budget:expenses:now:calendar:) -> BudgetSnapshot` as the single
  pure read entry point (§A.4).
- `PeriodCalculator` stays as-is for the four recurring period types. Introduce the
  `RecurringBudgetPeriod` wrapper as recommended in §A.5.1 so `.specificDates` cannot reach
  `PeriodCalculator` at compile time.
- Helpers: `allocationInEffect`, `walkCarryOver`, `isActive`, `currentPeriodSpillover` (§A.5.2,
  §A.5.3, §A.5.4, §A.5.6).
- Date normalization derived values (`effectiveStartDate`, `effectiveEndInclusive`,
  `effectiveEndExclusive`) per §A.4.0.

**Delete** the old algorithm pieces (from algorithm doc §A.7):

- `BudgetCalculator.rollCarryOver(...)` and `CarryOverRollResult`.
- `BudgetCalculator.checkScheduledReset(...)` and `ResetCheckResult`.
- `BudgetCalculator.advanced(from:by:calendar:)` (private cadence helper).
- All tests for the above.

### 3.3. `BudgetLifecycleService` becomes the compatibility seam

**This is the most important non-obvious part of the migration.** Read carefully.

Algorithm doc §A.8 recommends deleting `BudgetLifecycleService` outright. **This migration
explicitly overrides that recommendation.** The service stays. Its deletion is a future
change.

Rationale: every view in the app currently calls
`BudgetLifecycleService.refreshAndSave(_:settings:context:)` and consumes a `BudgetLifecycleResult
{ remaining, carryOverAmount, periodStart, periodEnd }`. Keeping the service as a thin adapter
means the views need zero changes for the read path. The new algorithm is wired up internally;
the legacy result type is mapped from the new snapshot.

What changes inside the service:

1. **`refreshAndSave(_:settings:context:)` no longer writes anything to `Budget`.** The
   walker is live; there are no fields to persist. The method becomes a pure read that calls
   `BudgetCalculator.snapshot(...)` and maps to `BudgetLifecycleResult`. The name
   `refreshAndSave` is a misnomer at this point but stays for compatibility — renaming is a
   future change.
2. **The mapping is mechanical:**
   - `BudgetLifecycleResult.remaining` ← `snapshot.remaining`
   - `BudgetLifecycleResult.carryOverAmount` ← `snapshot.carryOver ?? 0` (Specific Dates would
     pass `nil`, but `.specificDates` doesn't reach this seam in this migration since no UI
     creates one — see §4. The `?? 0` is defensive.)
   - `BudgetLifecycleResult.periodStart` ← `snapshot.effectivePeriodStart`
   - `BudgetLifecycleResult.periodEnd` ← `snapshot.effectivePeriodEnd`
3. **`snapshot.lifecycleState`, `snapshot.effectiveAllocation` are NOT exposed** through the
   legacy result. They'll be plumbed when the new UI features ship.
4. **New service methods for write paths** that the views need:
   - `applyAllocationEdit(_ budget: Budget, newAmount: Decimal, context: ModelContext)` —
     implements algorithm doc §A.6.2 (insert-or-mutate `AllocationChange` at
     `currentPeriodStart`; bump both row and budget `lastModified`).
   - `resetCarryOver(_ budget: Budget, context: ModelContext)` — sets
     `budget.lastResetDate = now`, bumps `lastModified`. Replaces whatever the old Reset
     Carry-Over write path did.
   - `resetBudget(_ budget: Budget, context: ModelContext)` — deletes all expenses, sets
     `lastResetDate = now`, bumps `lastModified`. Replaces whatever zeroed `carryOverAmount`
     before.
   - Don't add `pauseBudget`, `resumeBudget`, `setStartDate`, `setEndDate` methods — those
     are for the future feature changes.

### 3.4. View-side mechanical updates (the minimum)

These are the only view-side changes in this migration:

1. **`AddEditBudgetViewModel.save()` (Add mode):**
   - Insert the Budget without the removed fields.
   - **Compute `startDate` per period type** (this is F-2.03's pre-population rule, applied
     in code since the UI doesn't expose a Start Date field yet). Preserving the existing
     behavior of F-5.01 (the user's `AppSettings.weekStartDay`) requires this — if `startDate`
     were just `createdAt`, weekly/biweekly budgets would anchor on `createdAt.weekday` and
     silently ignore the user's Settings preference:
       - **Daily:** `startDate = calendar.startOfDay(for: createdAt)`.
       - **Weekly / biweekly:** `startDate = most recent AppSettings.weekStartDay-aligned date
         at or before startOfDay(createdAt)`. (Reuse `PeriodCalculator.periodStart(containing:
         createdAt, period: .weekly, weekStart: weekStartDay, ...)` if the helper signature
         allows; otherwise compute inline — same formula `PeriodCalculator` already uses.)
       - **Monthly:** `startDate = start of the calendar month containing createdAt`.
       - **Specific Dates:** N/A in this migration (the UI does not expose this period type —
         see §4).
   - Default the other new fields: `endDate = nil`, `lastResetDate = nil`.
   - Insert one initial `AllocationChange(effectiveFrom: startDate, amount: enteredAllocation)`
     in the same `context.save()` — i.e. use the same `startDate` value computed above. All
     four per-period-type computations produce start-of-day-aligned values by construction, so
     the `effectiveFrom` matches the algorithm doc §A.6.1 storage convention exactly (the
     algorithm's defensive `?? sorted.first?.amount` fallback is never triggered in normal
     flow).
2. **`AddEditBudgetViewModel.save()` (Edit mode):**
   - If allocation changed, call `BudgetLifecycleService.applyAllocationEdit(...)` instead of
     writing to `Budget.allocation` directly.
   - All other field edits (`name`, `currencyCode`, `isCarryOverEnabled`) stay one-line writes
     to the `Budget`.
3. **Refresh trigger fix.** Two parts:
   - **At every `ExpenseItem` write site (Add, Edit, AND Delete):** bump
     `budget.lastModified = now` in the same `context.save()`. This is consistent with the
     algorithm doc's project-wide rule (§A.6 preamble + §A.2.7) that every user-initiated
     write bumps the parent `Budget.lastModified` so chip refresh has a single reliable
     signal. The old code may have relied on `expenseItems.count` for Add/Delete refresh and
     left Edit unhandled (the bug); after this migration, all three cases bump
     `budget.lastModified` uniformly.
   - **At view sites (`BudgetDetailView` and anywhere else observing the chip):** add
     `.onChange(of: budget.lastModified)` as a refresh trigger, alongside the existing
     `.task(id: budget.persistentModelID)` and `.onChange(of: scenePhase)`. The existing
     `.onChange(of: budget.expenseItems.count)` may be **removed** (it becomes redundant once
     `lastModified` covers all three write cases), but doing so is optional in this
     migration — leaving both is harmless. Keep whichever is simpler.
4. **Reset Budget call site:** change from "zero `carryOverAmount`" to "call
   `BudgetLifecycleService.resetBudget(...)`".
5. **Reset Carry-Over call site:** change from "zero `carryOverAmount`, bump
   `carryOverLastResetDate`" to "call `BudgetLifecycleService.resetCarryOver(...)`".

**Nothing else in the view layer changes.** No new fields, no new toolbar actions, no new chip
overlays, no new screens, no new chip copy.

---

## 4. What this change DOES NOT do (out of scope — explicit)

Do **not** implement, even partially, even as scaffolding, even "while you're already in there":

### Out-of-scope UI work

- **Start Date / End Date fields** on the Add/Edit Budget screen. Defaults wire in code (§3.4
  item 1); no UI input controls.
- **`.specificDates` option** in the period chip group on the Add/Edit Budget screen. The
  enum case must exist in code; the chip group must continue to render only `.daily`,
  `.weekly`, `.biweekly`, `.monthly`.
- **Pause / Resume toolbar action** on the Budget Detail screen toolbar overflow menu.
- **Pre-start chip overlay** ("Starts on X"). Algorithm returns `.preStart` correctly; no UI
  renders it.
- **Post-end chip overlay** ("Ended on X"). Algorithm returns `.postEnd` correctly; no UI
  renders it.
- **Paused chip overlay** ("Paused since X") — including the greyed-value treatment.
- **Date bounds on Add/Edit Expense date picker.** The picker stays unconstrained except for
  whatever it does today.
- **Add Funds toggle** on the Add Expense screen (F-6.01 partial). Not in this change.
- **Chip copy** changes for surplus/deficit, overspend, etc. Keep current copy.

### Out-of-scope analytics

- `budget_paused`, `budget_resumed` events.
- The new `budget_edited` property flags (`allocation_changed`, `start_date_changed`,
  `end_date_changed`).
- Any Mixpanel changes related to the rewrite. Existing events keep firing as they do today.

### Out-of-scope service refactors

- **Do not delete `BudgetLifecycleService`** (overrides algorithm doc §A.8 Option 1
  recommendation; see §3.3 above).
- Do not rename `BudgetLifecycleResult` fields or change its shape.

### Out-of-scope spec updates

The briefing's §2.11 lists every doc and spec that *eventually* updates for the rewrite. For
this migration, only update the specs that describe the now-changed algorithm and data layer:

- **DO update:** `openspec/specs/budget-math/spec.md`,
  `openspec/specs/budget-lifecycle/spec.md`, `openspec/specs/data-models/spec.md`. Wholesale
  rewrites of these per the algorithm doc.
- **DO update:** `docs/main-prd.md` §6.7 carry-over wording (already partially synced) — verify
  it matches the new behavior end-to-end and remove any remaining PAUSED-Reset-Cadences notes.
- **DO update:** `docs/tech-design-doc.md` — remove Reset Cadences references, update §3
  (data model) and §5.4 (service layer) to reflect the new shape, add the new SwiftData
  entities.
- **DO update:** `docs/product-features-planning.md` — only the F-2.03 entry needs the Reset
  Cadence picker removal confirmed; F-7.05 and F-7.06 **stay Open** (not Implemented) since
  no UI is shipping in this change. Already mostly synced per its 0.8 revision.
- **DO NOT update:** `openspec/specs/add-edit-budget-screen/spec.md` (no new fields shipping),
  `openspec/specs/budgets-screen/spec.md` (chip surface unchanged from user POV except for
  refresh-trigger language), `openspec/specs/budget-detail-screen/spec.md` (no new toolbar
  actions), `openspec/specs/add-edit-expense-screen/spec.md` (no date bounds shipping).
  Exception: if any of these specs currently describe the *old* boundary-only `rollCarryOver`
  refresh trigger or mention the PAUSED Reset Cadences feature, those specific phrases need
  updating to match the new algorithm. But no new scenarios are added.
- **DO NOT update:** `docs/ux-design-brief.md` for the new lifecycle states — the UI for
  those states isn't shipping in this change.
- **DO NOT update:** `docs/analytics-spec.md` for the new events — not shipping.

If you're unsure whether a doc update is in scope, the test is: **does the user see anything
new in the app because of this change?** If no (the algorithm changed but the UI didn't), skip
the doc update.

---

## 5. Defaults for new fields

Because the UI doesn't expose these yet, the code sets them programmatically. The `startDate`
default varies by period type to preserve the existing F-5.01 (`AppSettings.weekStartDay`)
behavior for weekly/biweekly budgets — see §3.4 item 1 for the rationale.

| Field                 | Default at Add time                                                                                                                                                                                                            | Safety-net fallback at read time                |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------- |
| `startDate`           | Per period type (all start-of-day-aligned): daily → `startOfDay(createdAt)`; weekly/biweekly → most recent `AppSettings.weekStartDay`-aligned date at-or-before `startOfDay(createdAt)`; monthly → start of month containing `createdAt` | `createdAt` (per algorithm doc §A.4.1 step 1)   |
| `endDate`             | `nil`                                                                                                                                                                                                                          | n/a — genuinely optional for recurring          |
| `lastResetDate`       | `nil`                                                                                                                                                                                                                          | n/a — `nil` means "no manual reset has occurred" |
| `allocationChanges`   | one initial row, `effectiveFrom = startDate` (the computed value above), `amount = enteredAllocation`                                                                                                                          | n/a                                             |
| `lifecycleEvents`     | empty                                                                                                                                                                                                                          | n/a                                             |

---

## 6. Behavior changes that ride along (acceptable)

These are user-visible behavioral changes that are intrinsic to the algorithm rewrite and ride
along with this migration even though no UI was changed:

1. **Carry-over chip updates mid-period** — the bug fix that motivated the rewrite. Expected.
2. **Asymmetric live coupling (§A.5.6)** — overspending the current period now immediately
   shows in the carry-over chip (chip drops by the overshoot amount). Adding negative-amount
   expenses (F-6.01 add-funds, possible today via the model layer even without UI) immediately
   raises carry-over by the excess above allocation. This is the §A.5.6 rule landing live.
   Acceptable.

No other user-visible behavior changes. The Reset Carry-Over button, Reset Budget action, Delete
Budget action, currency editing, name editing, expense add/edit/delete, period selection (for
the four recurring types), and Settings continue to behave exactly as today.

---

## 7. Tests

- **Delete:** all tests for `rollCarryOver`, `checkScheduledReset`, `defaultResetCadence`, and
  any cadence-related lifecycle scenarios. (Algorithm doc §A.7 removal checklist.)
- **Update:** existing tests that assert on `carryOverAmount` / `carryOverLastProcessedDate`
  fields, since those fields no longer exist. Most will move to asserting on the
  `BudgetSnapshot` (or the mapped `BudgetLifecycleResult`).
- **Add (algorithm-side):** the full test plan in algorithm doc §A.10 — unit tests for the
  snapshot per lifecycle state, helper tests for `allocationInEffect` /
  `currentPeriodSpillover` / `isActive`, walker tests, SwiftData round-trip integration tests,
  CloudKit-divergence simulation tests. Test cases marked **★** in §A.10 are the high-risk
  edge cases — do not skip them.
- **Add (migration-side):** tests that verify the `BudgetLifecycleService` adapter correctly
  maps `BudgetSnapshot` to `BudgetLifecycleResult` for each lifecycle state the legacy result
  exposes.
- **Do NOT add:** tests for Pause/Resume UI flows, Start/End Date UI flows, Specific Dates
  budget creation flows, lifecycle chip overlays. The algorithm's tests for these states are
  in §A.10; UI tests for them ship with the respective future features.

---

## 8. Open implementation questions (resolved for this migration)

Algorithm doc §A.11 lists three open questions. For this migration:

1. **`AllocationChange` / `LifecycleEvent` storage shape.** Use SwiftData `@Model` (algorithm
   doc's recommendation). Do not use the Codable-blob alternative.
2. **`BudgetLifecycleService` keep-or-delete.** **Keep** (overrides §A.8 Option 1). Adapter
   role per §3.3.
3. **Specific Dates `effectiveAllocation` rule.** Latest entry by `(effectiveFrom,
   lastModified)`. Per §A.4.2 step 2 — already specified, no decision left to make. In this
   migration no Specific Dates budget can be created, so this is dead code path until the UI
   ships, but the algorithm must still handle it correctly.

---

## 9. After this change ships

- The app compiles, runs, and all current features work as today (with the two ride-along
  behavior changes above).
- The new algorithm is fully in place. No `rollCarryOver`, no `checkScheduledReset`, no
  `ResetCadence`.
- F-7.05 (per-budget start date), F-7.06 (Pause/Resume), F-7.07 (per-budget end date), and
  F-2.08 (Specific Dates) **stay Open**. They each become their own future change.
- `BudgetLifecycleService` exists as an adapter. Its eventual deletion is a future change.
- The algorithm correctly handles all states the new UI features will eventually expose, but
  no UI can currently reach them.

---

## 10. Quick reference: the change at a glance

| Layer              | Changes                                                                                        |
| ------------------ | ---------------------------------------------------------------------------------------------- |
| Schema             | Big — drop fields from `Budget`, add new fields, add two new entities, delete `ResetCadence`. |
| `BudgetCalculator` | Wholesale rewrite per algorithm doc §A.4–§A.5.                                                 |
| `PeriodCalculator` | Untouched (kept as-is for the four recurring period types).                                    |
| `BudgetLifecycleService` | Becomes an adapter — same public method `refreshAndSave`, new internals; plus 3 new write-path methods. |
| Views              | 5 mechanical changes (see §3.4). No new screens, no new fields, no new actions, no new copy.   |
| Tests              | Delete old, update existing, add per §A.10. No new UI tests.                                   |
| Docs               | Update 3 openspec capability specs and 3 markdown docs (see §4 "Out-of-scope spec updates").   |
