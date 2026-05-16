## 1. Schema reshape (data-models)

- [x] 1.1 Add `Models/AllocationChange.swift` — `@Model` class with `id`, `effectiveFrom`, `amount`, `lastModified`, optional `budget` back-reference (inverse of `Budget.allocationChangesStorage`); cascade delete from `Budget`.
- [x] 1.2 Add `Models/LifecycleEventKind.swift` — `String, Codable, CaseIterable` enum with `pause`, `resume` cases (raw values `"pause"`, `"resume"`).
- [x] 1.3 Add `Models/LifecycleEvent.swift` — `@Model` class with `id`, `kind: LifecycleEventKind`, `effectiveDate`, `lastModified`, optional `budget` back-reference (inverse of `Budget.lifecycleEventsStorage`); cascade delete from `Budget`. Store `kind` directly (do NOT use a `String` raw + computed accessor; SwiftData serializes `String, Codable` enums automatically).
- [x] 1.4 Update `Models/Budget.swift` — remove the `allocation: Decimal`, `carryOverAmount: Decimal`, `carryOverLastProcessedDate: Date`, and `resetCadence: String` stored properties and their `init` parameters. Add `startDate: Date?`, `endDate: Date?`, `lastResetDate: Date?` (renamed from `carryOverLastResetDate`), `allocationChangesStorage: [AllocationChange]?`, `lifecycleEventsStorage: [LifecycleEvent]?`. Add non-optional computed accessors `allocationChanges` and `lifecycleEvents` (return `?? []`). Keep `expenseItems` computed accessor.
- [x] 1.5 Update `Models/BudgetPeriod.swift` — add `.specificDates` case (raw value `"specificDates"`) at the end of the order so `Comparable` ordering becomes `.daily < .weekly < .biweekly < .monthly < .specificDates`. Remove the `defaultResetCadence` computed property.
- [x] 1.6 Delete `Models/ResetCadence.swift` entirely. Verify no other source file imports or references it.
- [x] 1.7 Update `Models/SchemaV1.swift` — extend `SchemaV1.models` to include `AllocationChange.self` and `LifecycleEvent.self`. Keep `versionIdentifier` at `(1, 0, 0)`. Do NOT introduce `SchemaV2` or any `VersionedSchema` machinery beyond the existing baseline.
- [x] 1.8 Update `Models/BudgetMigrationPlan.swift` — verify `schemas == [SchemaV1.self]` and `stages == []`. Do not add stages.
- [x] 1.9 Wipe the simulator data store at this point to clear any stale on-disk schema.

## 2. Domain layer — new pure algorithm

- [x] 2.1 Add `Domain/RecurringBudgetPeriod.swift` — wrapper enum with cases `daily`, `weekly`, `biweekly`, `monthly` and an initializer from `BudgetPeriod` that returns `nil` for `.specificDates`. Make this the only type `PeriodCalculator`'s public surface accepts.
- [x] 2.2 Update `Domain/PeriodCalculator.swift` — change the period parameter type from `BudgetPeriod` to `RecurringBudgetPeriod`. The four scenarios for each existing case stay computationally identical. Update weekly/biweekly anchoring to take the anchor date from `Budget.startDate` rather than `AppSettings.weekStartDay`.
- [x] 2.3 Add `Domain/BudgetSnapshot.swift` — value type with `remaining: Decimal`, `carryOver: Decimal?`, `effectivePeriodStart: Date`, `effectivePeriodEnd: Date`, `effectiveAllocation: Decimal`, `lifecycleState: BudgetLifecycleState`. Add the `BudgetLifecycleState` enum with cases `preStart`, `active`, `paused`, `postEnd` (algorithm doc §A.3).
- [x] 2.4 Add date-normalization helpers in `Domain/BudgetCalculator.swift` (or a private file): `effectiveStartDate(budget:) -> Date` (returns `startDate ?? createdAt`), `effectiveEndInclusive(budget:) -> Date?`, `effectiveEndExclusive(budget:) -> Date?` per algorithm doc §A.4.0.
- [x] 2.5 Add `Domain/AllocationInEffect.swift` — `allocationInEffect(at date: Date, history: [AllocationChange]) -> Decimal` per algorithm doc §A.5.2. Latest applicable `effectiveFrom <= date`, tiebreak by `lastModified` later wins, defensive fallback to earliest row's amount.
- [x] 2.6 Add `Domain/LifecycleClassification.swift` — `isActive(period: DateInterval, lifecycleEvents: [LifecycleEvent]) -> Bool` per algorithm doc §A.5.4. Pause-action period itself is active; subsequent periods paused until Resume; Resume-action period is fully active.
- [x] 2.7 Add `Domain/CarryOverWalker.swift` — `walkCarryOver(...)` per algorithm doc §A.5.3. Walk window `max(effectiveStartDate, lastResetDate ?? .distantPast)` to current-period start; per period: active → `allocationInEffect − sum(expenses)`, paused → 0.
- [x] 2.8 Add `Domain/CurrentPeriodSpillover.swift` — `currentPeriodSpillover(remaining: Decimal, effectiveAllocation: Decimal) -> Decimal` per algorithm doc §A.5.6. Returns 0 when `0 ≤ remaining ≤ effectiveAllocation`, otherwise the signed overshoot. PostEnd state collapses to symmetric — handled by caller passing through whole-period remaining.
- [x] 2.9 Rewrite `Domain/BudgetCalculator.swift` — add `static func snapshot(budget: Budget, expenses: [ExpenseItem], now: Date, calendar: Calendar) -> BudgetSnapshot` per algorithm doc §A.4.1 and §A.4.2. Pure function: no mutations, no `context.save()`. Includes the `.specificDates` branch (returns `carryOver: nil`).
- [x] 2.10 Delete from `Domain/BudgetCalculator.swift`: `rollCarryOver(...)`, `CarryOverRollResult`, `checkScheduledReset(...)`, `ResetCheckResult`, and the private `advanced(from:by:calendar:)` cadence helper (per algorithm doc §A.7).

## 3. Service layer — `BudgetLifecycleService` adapter + write paths

- [x] 3.1 Rewrite `Services/BudgetLifecycleService.refreshAndSave(_:settings:context:now:calendar:)` — call `BudgetCalculator.snapshot(...)` and map the result to `BudgetLifecycleResult { remaining, carryOverAmount, periodStart, periodEnd }` with `carryOverAmount ← snapshot.carryOver ?? 0`, `periodStart ← snapshot.effectivePeriodStart`, `periodEnd ← snapshot.effectivePeriodEnd`. No mutations. No `context.save()`. Drop the old roll/reset/save logic entirely.
- [x] 3.2 Add `Services/BudgetLifecycleService.applyAllocationEdit(_ budget: Budget, newAmount: Decimal, context: ModelContext, now: Date, calendar: Calendar)` — compute `currentPeriodStart`; if an existing `AllocationChange` row has `effectiveFrom == currentPeriodStart`, mutate its `amount` and bump `lastModified`; else insert a new row. Bump `budget.lastModified = now`. Call `context.save()` once.
- [x] 3.3 Add `Services/BudgetLifecycleService.resetCarryOver(_ budget: Budget, context: ModelContext, now: Date)` — set `budget.lastResetDate = now`; bump `budget.lastModified = now`; call `context.save()` once.
- [x] 3.4 Add `Services/BudgetLifecycleService.resetBudget(_ budget: Budget, context: ModelContext, now: Date)` — iterate `budget.expenseItems` and call `context.delete(_:)` on each; set `budget.lastResetDate = now`; bump `budget.lastModified = now`; call `context.save()` once. Preserve `allocationChanges` and `lifecycleEvents`.
- [x] 3.5 Do NOT add `pauseBudget`, `resumeBudget`, `setStartDate`, or `setEndDate` methods — those belong to future UI changes.

## 4. View / ViewModel mechanical updates

- [x] 4.1 `ViewModels/AddEditBudgetViewModel.save()` (Add mode) — compute `startDate` per period type using `AppSettings.weekStartDay` for weekly/biweekly anchoring per the `data-models` capability "Initial AllocationChange row on Budget creation". Default `endDate = nil`, `lastResetDate = nil`. Insert one initial `AllocationChange(effectiveFrom: startDate, amount: enteredAllocation, lastModified: now)` in the same `context.save()` as the Budget insert.
- [x] 4.2 `ViewModels/AddEditBudgetViewModel.save()` (Edit mode) — if the allocation field changed, call `BudgetLifecycleService.applyAllocationEdit(...)` instead of writing `Budget.allocation` directly. Other field edits (`name`, `currencyCode`, `isCarryOverEnabled`) remain one-line writes.
- [x] 4.3 At every `ExpenseItem` Add call site — bump `expenseItem.budget?.lastModified = now` in the same `context.save()`.
- [x] 4.4 At every `ExpenseItem` Edit call site — bump `expenseItem.budget?.lastModified = now` in the same `context.save()` (the previously unhandled case).
- [x] 4.5 At every `ExpenseItem` Delete call site — bump `expenseItem.budget?.lastModified = now` in the same `context.save()` before delete.
- [x] 4.6 At each chip-observing view (`BudgetDetailView`, `BudgetsView`, and any other view consuming a `BudgetLifecycleResult`) — add `.onChange(of: budget.lastModified)` as a refresh trigger alongside the existing `.task(id: budget.persistentModelID)` and `.onChange(of: scenePhase)`. The existing `.onChange(of: budget.expenseItems.count)` MAY be removed; leaving it is harmless.
- [x] 4.7 At the Reset Budget call site — replace whatever zeroed `carryOverAmount` with a single call to `BudgetLifecycleService.resetBudget(...)`.
- [x] 4.8 At the Reset Carry-Over call site — replace whatever bumped `carryOverLastResetDate` with a single call to `BudgetLifecycleService.resetCarryOver(...)`.
- [x] 4.9 Audit the Add/Edit Budget screen: confirm the period chip group continues to render only `.daily`, `.weekly`, `.biweekly`, `.monthly` (do NOT add `.specificDates` to the chip group). Confirm no Reset Cadence picker is rendered.
- [x] 4.10 Audit all views: confirm no new fields (Start Date, End Date), toolbar actions (Pause/Resume), chip overlays (pre-start, post-end, paused), or copy changes have been introduced.

## 5. Cross-cutting concerns (docs/main-prd.md §6.8)

The cross-cutting concerns checklist applies to UI-touching work. This migration intentionally ships **no new user-facing UI**; the four concerns are addressed as follows:

- [x] 5.1 **Accessibility** — no new UI; existing chip accessibility labels/hints/values remain. Verify no regression in VoiceOver readout for the Carry-over chip after the refactor (read the chip with VoiceOver in the simulator on a budget with a mid-period expense edit, confirm the value updates).
- [x] 5.2 **Localized source strings** — new string keys for `.specificDates` section titles/labels added with `comment:` arguments per convention. No strings require translation queue update for this migration (labels fallback to English defaults and are not user-visible since no UI exposes `.specificDates` in this change).
- [x] 5.3 **Translations queue** — no new strings to queue for this migration.
- [x] 5.4 **Mixpanel user-action events** — no new events. Existing `expense_added`, `expense_deleted`, `budget_edited` continue to fire from their existing call sites with no property changes in this migration (the new property flags ship with future UI work).

## 6. Tests

- [x] 6.1 Delete every test that asserts on `BudgetCalculator.rollCarryOver`, `CarryOverRollResult`, `BudgetCalculator.checkScheduledReset`, `ResetCheckResult`, `BudgetCalculator.advanced(...)`, or `defaultResetCadence`.
- [x] 6.2 Delete every test that asserts on `Budget.carryOverAmount`, `Budget.carryOverLastProcessedDate`, or `Budget.resetCadence` (those fields no longer exist). Where the test's intent is still valid, port it to assert on `BudgetSnapshot` or the mapped `BudgetLifecycleResult`.
- [x] 6.3 Add unit tests on `BudgetCalculator.snapshot(...)` per lifecycle state — `.preStart`, `.active`, `.paused`, `.postEnd` — covering all algorithm doc §A.10.1 cases.
- [x] 6.4 Add unit tests on `allocationInEffect(at:history:)` covering latest-applicable, tiebreak-by-lastModified, and defensive-fallback paths (algorithm doc §A.10.2).
- [x] 6.5 Add unit tests on `isActive(period:lifecycleEvents:)` covering pause-action period, subsequent paused period, resume-action period, and no-events default-active behavior.
- [x] 6.6 Add unit tests on `currentPeriodSpillover(remaining:effectiveAllocation:)` covering all four branches (0 ≤ remaining ≤ allocation, remaining < 0, remaining > allocation, and the post-end symmetric collapse).
- [x] 6.7 Add walker tests — multi-period catch-up, walker honoring `lastResetDate`, backdated-expense recomputation, paused-period contribution of 0. Cover algorithm doc §A.10.1's **★** high-risk edge cases.
- [x] 6.8 Add `RecurringBudgetPeriod` wrapper test — `RecurringBudgetPeriod(.specificDates)` returns `nil`; the four other cases round-trip cleanly.
- [x] 6.9 Add SwiftData round-trip integration tests for `AllocationChange` and `LifecycleEvent` per algorithm doc §A.10.3 — insert, fetch, mutate, cascade delete from `Budget`.
- [x] 6.10 Add CloudKit-divergence simulation tests per algorithm doc §A.10.4 — two AllocationChange rows with the same `effectiveFrom` differing in `lastModified` resolve deterministically; two LifecycleEvent rows on different devices converge.
- [x] 6.11 Add `BudgetLifecycleService` adapter mapping tests — for each lifecycle state the legacy result exposes (mainly `.active`), verify `BudgetLifecycleResult.{remaining, carryOverAmount, periodStart, periodEnd}` equals the underlying `BudgetSnapshot` field per the mapping table.
- [x] 6.12 Add `BudgetLifecycleService` write-path tests — `applyAllocationEdit` insert-and-mutate, `resetCarryOver` writes `lastResetDate` and bumps `lastModified`, `resetBudget` deletes all expenses and preserves AllocationChange/LifecycleEvent rows.
- [x] 6.13 Add view-side refresh-trigger tests where feasible — assert that an expense Edit bumps `Budget.lastModified` (the previously unhandled case).
- [x] 6.14 Do NOT add tests for Pause/Resume UI, Start/End Date UI, Specific Dates creation flows, or lifecycle chip overlays — those ship with their respective future changes.

## 7. Doc updates (in-scope)

- [x] 7.1 Update `docs/main-prd.md` §6.7 — replace any remaining boundary-only `rollCarryOver` wording with the live-walker + asymmetric coupling rule from briefing §2.1. Remove every "PAUSED — Reset Cadences" callout in the doc. Verify the §6.7 wording end-to-end matches the new behavior (this section has been partially synced per briefing §2.11).
- [x] 7.2 Update `docs/tech-design-doc.md` §3 (data model) — reflect the new `Budget` shape (drop `allocation`, `carryOverAmount`, `carryOverLastProcessedDate`, `resetCadence`; add `startDate`, `endDate`, `lastResetDate`, `allocationChangesStorage`, `lifecycleEventsStorage`). Add the new `AllocationChange` and `LifecycleEvent` entities. Remove every Reset Cadences reference.
- [x] 7.3 Update `docs/tech-design-doc.md` §5.4 (service layer) — replace the previous orchestration sequence description with the adapter-plus-three-write-paths shape from this change's `budget-lifecycle` delta.
- [x] 7.4 Update `docs/product-features-planning.md` — confirm F-2.03's Reset Cadence picker removal is finalized. Verify F-7.05, F-7.06, F-7.07, F-2.08 are still flagged Open (they ship with future changes, not this one). Verify F-2.01, F-2.02, F-2.07 reflect the new chip refresh rules (per the briefing's 2026-05-11 sync status, these are already updated).

## 8. Doc updates (out-of-scope — verify)

- [x] 8.1 Confirm NO update is made to `openspec/specs/add-edit-budget-screen/spec.md`, `openspec/specs/budgets-screen/spec.md`, `openspec/specs/budget-detail-screen/spec.md`, or `openspec/specs/add-edit-expense-screen/spec.md` beyond replacing any sentence that describes the *old* boundary-only `rollCarryOver` refresh trigger or the PAUSED Reset Cadences feature. No new scenarios.
- [x] 8.2 Confirm NO update is made to `docs/ux-design-brief.md` or `docs/analytics-spec.md` — the new lifecycle UI and the new analytics events ship with their respective future changes.

## 9. Build / test / verify

- [x] 9.1 Run `make format` (per AGENTS.md).
- [x] 9.2 Run `make lint-fix`. Address any new lints.
- [x] 9.3 Run `make build`. The project SHALL build clean with no warnings introduced by this change.
- [x] 9.4 Run `make test`. All tests added in §6 SHALL pass; no test deleted in §6 SHALL reappear.
- [x] 9.5 Manual smoke test in the simulator (wiped first per §1.9):
  - Create a daily budget. Add expenses. Verify the Carry-over chip refreshes after Add, Edit, and Delete without leaving the screen.
  - Create a weekly budget; verify it anchors to `AppSettings.weekStartDay` and that subsequent period boundaries advance correctly across `scenePhase` changes.
  - Tap Reset Carry-Over; verify the chip drops to the current period's spillover only.
  - Tap Reset Budget; verify all expenses are deleted and the chip reads `effectiveAllocation`.
  - Edit a budget's allocation mid-period; verify the chip reflects the new value for the current period and the prior periods retain their historical allocation contributions (assert via a debug build's logging or a dedicated test).
  - Overspend the current day (recurring budget): verify the Carry-over chip drops by the overshoot amount immediately.
  - Insert a negative-amount expense (via the model layer or `DebugData` if exposed): verify the Carry-over chip absorbs the excess immediately.
- [x] 9.6 Re-run `openspec validate rewrite-budget-calculations --strict` to verify all artifacts parse cleanly.

## 10. Archive prep

- [x] 10.1 Compare the implemented change against `docs/main-prd.md`, `docs/product-features-planning.md`, and `docs/tech-design-doc.md` — flag any docs drift before archive. (No drift: all three docs updated in tasks 7.1–7.4.)
- [x] 10.2 Confirm `SchemaV1.swift` and `BudgetMigrationPlan.swift` are updated in place; no `SchemaV2` exists; `BudgetMigrationPlan.stages == []`.
- [x] 10.3 Confirm no out-of-scope UI affordances have leaked in (Start Date / End Date inputs, Pause/Resume action, Specific Dates chip, lifecycle chip overlays, date-bounds picker, Add Funds toggle). The user-visible diff is exactly the two ride-along behaviors (mid-period refresh, asymmetric live coupling) plus permanent removal of any UI surface that referenced Reset Cadences.
- [x] 10.4 Confirm `BudgetLifecycleService` still exists with the public `refreshAndSave` signature (algorithm doc §A.8 Option 1 deletion is deferred to a future change).
