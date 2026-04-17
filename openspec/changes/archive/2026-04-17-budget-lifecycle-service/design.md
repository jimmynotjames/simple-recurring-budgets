## Context

`BudgetCalculator` (added in `2026-04-13-budget-math-service`) is pure and has no SwiftData dependency: `rollCarryOver` returns a `CarryOverRollResult`, `checkScheduledReset` returns a `ResetCheckResult`, and `remaining` returns a `Decimal`. None of them touch a `Budget` or a `ModelContext`. That purity is intentional and must be preserved — it's what makes the math unit-testable without a container.

The PRD §6.7 and tech-design §3.2 / §5.4 require an eager, ordered, per-budget sequence on access:

1. Roll carry-over across any completed periods since `carryOverLastProcessedDate`.
2. Persist the new `carryOverAmount` and `carryOverLastProcessedDate`.
3. Check whether a scheduled reset boundary has been crossed.
4. If so, zero `carryOverAmount` and stamp `carryOverLastResetDate`, then persist.
5. Compute `remaining` for the current period for display.

Without a dedicated bridge, every ViewModel that surfaces a `Budget` (Budgets list, Budget detail, expense add/edit flows that affect display) will re-implement this sequence. That is the kind of duplicated orchestration that makes the §6.7 contract drift over time — wrong ordering, missing `lastModified` bumps, or saving twice when only display values changed. The calculator is pure; the model is storage; nothing in between owns the contract.

## Goals / Non-Goals

**Goals:**

- Provide a single orchestrator that binds `BudgetCalculator` outputs to `Budget` writes in the §5.4 order.
- Keep `BudgetCalculator` and `PeriodCalculator` completely unchanged — no new SwiftData imports in `Domain/` math files.
- Return a `BudgetLifecycleResult` that carries everything a VM needs for display in one step: `remaining`, `carryOverAmount`, `periodStart`, `periodEnd`.
- Only write to the `ModelContext` when something actually changed — no spurious `lastModified` bumps that would cause needless CloudKit syncs or re-renders.
- Be deterministic and testable: all time-dependent inputs (`now`, `calendar`) are parameters, never read from globals inside the service.
- Reuse the in-memory `ModelContainer` test helper so the service is tested against real SwiftData semantics.

**Non-Goals:**

- No ViewModels, SwiftUI views, or screen wiring in this change (F-2.01 / F-2.02 screens will consume this service later).
- No background-context scheduling. The eager call path is synchronous on the caller's context; tech-design §6 leaves background processing for long-gap catch-up as a future optimization.
- No new persisted fields on `Budget` or `ExpenseItem`.
- No manual-reset action surface here. PRD §6.7 "manual reset" is a user-triggered Budget-screen control; the lifecycle service only implements the eager (automatic) sequence. A separate surface can reuse the service's reset helper if useful, but adding UI for it is out of scope.
- No new public API on `BudgetCalculator`; the service uses only the existing `rollCarryOver`, `checkScheduledReset`, and `remaining` functions.

## Decisions

### 1. Standalone `BudgetLifecycleService` (caseless `enum`), not a `Budget` extension

**Decision:** Add `Domain/BudgetLifecycleService.swift` as a caseless `enum` with a single entry-point static method:

```swift
@discardableResult
static func refreshAndSave(
    _ budget: Budget,
    settings: AppSettings,
    context: ModelContext,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent
) -> BudgetLifecycleResult
```

**Why over `Budget.refresh(now:calendar:settings:context:)`:**

- `Budget` is a SwiftData `@Model` defined in `Models/`. Adding an extension there that imports `AppSettings` and calls `BudgetCalculator` pulls domain orchestration into the storage layer and couples `Budget` to `AppSettings`, which the data model doesn't otherwise know about.
- Tech-design §5.3 / §5.4 place budget math in `Domain/` specifically to keep it out of the `@Model` classes. An extension would blur that boundary; a service file preserves it and lives next to `BudgetCalculator.swift`.
- A namespaced `enum` matches the existing `PeriodCalculator` / `BudgetCalculator` shape — the codebase already reads as "pure namespace services in `Domain/`." Consistency wins here.
- A service is easier to mock at the VM seam (VM holds a function reference or the type) than an extension method, if a future ViewModel test wants to assert "refreshAndSave was called" without exercising the full SwiftData path.

**Alternative considered:** `Budget.refresh(...)` extension. Rejected because it reverses the dependency direction between `Models/` and `Domain/` and would require `Budget.swift` to either import `AppSettings` or accept a grab-bag of primitives at the call site.

### 2. Single save per `refreshAndSave` call, and only when something changed

**Decision:** The service accumulates all mutations on the `Budget` in memory, then calls `try? context.save()` exactly once at the end — and only if at least one field was actually modified.

**Rationale:**

- Two saves (one after roll, one after reset) would generate two CloudKit mutations for what the user experiences as one screen load. SwiftData + CloudKit last-writer-wins (§4.4) is fine, but needless writes cost bandwidth and battery, and can trigger noisy `@Query` invalidations in the UI.
- The `lastModified` bump is gated on a `didChange` flag. If `rollCarryOver` returns unchanged values (no boundary crossed) and `checkScheduledReset` returns `shouldReset == false`, the service writes nothing and does not call `save()`. This is the common case on repeated accesses within the same period.
- Errors from `save()` are logged (not thrown) because the caller (a VM on `scenePhase == .active` or on budget-access) has no meaningful recovery path mid-render. The in-memory `Budget` state is still correct for display; the next `refreshAndSave` will re-attempt the save if the store becomes writable again. This matches how the rest of the app treats SwiftData saves (fire-and-forget with optional logging).

**Alternative considered:** Save after each step (roll save, then reset save). Rejected because of double-write cost and because intermediate states (rolled but not yet reset) are not useful to persist — the eager sequence is atomic from the user's point of view.

### 3. Ordering: roll before reset, strictly

**Decision:** The service calls `rollCarryOver` first, applies its result to the budget, then calls `checkScheduledReset`. This matches the existing `budget-math` spec requirement ("Carry-over roll processes before reset check") and the tech-design §5.4 wording ("roll before reset, so completed-period carry-over is folded in before any reset fires").

**Why:** Reversing the order would zero out a surplus/deficit that the user *earned* in the just-completed period. The roll-then-reset test scenario in `budget-math/spec.md` asserts this ordering; the service is the place that enforces it at the composition level.

### 4. Biweekly anchor derived inline from `createdAt` + `weekStart`

**Decision:** The service computes the biweekly anchor on each call as: the most recent `weekStart` day at or before `budget.createdAt`. This mirrors tech-design §5.4 and the `2026-04-13-budget-math-service` design decision #2 — no new stored field.

**Why:** Consistency with the existing pure-math layer. If `AppSettings.weekStartDay` changes (F-5.01), the anchor shifts naturally on the next `refreshAndSave`; carry-over is still folded correctly from `carryOverLastProcessedDate` forward because the roll walks period boundaries from that date, not from the anchor.

### 5. `BudgetLifecycleResult` carries the display-ready window

**Decision:** The return type is:

```swift
struct BudgetLifecycleResult {
    let remaining: Decimal
    let carryOverAmount: Decimal
    let periodStart: Date
    let periodEnd: Date
}
```

**Why include the window?** The Budgets/Budget screens already need `periodStart`/`periodEnd` for any period-scoped `@Query` predicate on `ExpenseItem`, and they need the label ("Today", "This week", the biweekly range, the month). Returning them from the service avoids re-running `PeriodCalculator.periodStart` / `periodEnd` at the call site with the same inputs. `carryOverAmount` is returned even though it's also on the `Budget` so VMs have a single result object to bind to.

**Why not include `isCarryOverEnabled` or a "did reset" flag?** `isCarryOverEnabled` is a trivial read from the `Budget` directly. A "did reset this call" flag has no identified consumer yet; adding it speculatively violates YAGNI. If a future toast/undo surface needs it, we can extend the struct (additive, non-breaking).

### 6. `now` and `calendar` are injected parameters with production defaults

**Decision:** `now: Date = Date()` and `calendar: Calendar = .autoupdatingCurrent` as parameters on the entry point.

**Why:** Matches the `BudgetCalculator` injection convention (calendar is already a parameter there). Tests pass a fixed `Date` and a UTC `Calendar` for deterministic results. Production callers usually accept the defaults. Future code that wants to test "what will the display look like tomorrow?" can pass a future `now`.

### 7. `AppSettings` is passed by reference, not copied

**Decision:** The service takes `AppSettings` (the `@Observable` reference type) directly and reads `weekStartDay` at the top of the method.

**Why:** `AppSettings` is already a shared, observed reference used throughout the app. Passing it in keeps the call site tidy (`BudgetLifecycleService.refreshAndSave(budget, settings: appSettings, context: context)`) and allows the service to read whatever additional settings it may need in the future (e.g., a future "default reset cadence" or per-user locale override) without widening the parameter list.

**Alternative considered:** Passing `weekStartDay: Weekday` directly. Rejected because the service is likely to need more settings over time; taking the whole observable keeps evolution non-breaking.

### 8. Service is called from ViewModels, not from `@Model` or `@Query`

**Decision:** The contract is: ViewModels call `BudgetLifecycleService.refreshAndSave` eagerly on budget access (screen appearance, `scenePhase == .active`, and after an expense is added/edited/deleted if the mutation could cross a boundary). Views do not call the service directly; `Budget` does not call it from initializers or property getters.

**Why:** Tech-design §5.4 assigns this responsibility to ViewModels. Calling from `Budget` property getters would couple storage to `AppSettings` and `ModelContext` and could trigger writes from SwiftUI render passes (a footgun). Calling from views makes timing non-deterministic during view identity changes. ViewModels have lifecycle, can schedule the call, and can test the effect in isolation.

## Risks / Trade-offs

**[Repeated `refreshAndSave` calls within a single period do nothing, by design]** → Good. Mitigation: the "nothing changed" path has no `save()` and no `lastModified` bump, so repeated `scenePhase` transitions don't thrash CloudKit.

**[A very long-gap catch-up (app unopened for months on a daily budget) runs on the caller's context]** → The inner loop is trivial arithmetic per period (see `budget-math` design §Risks). If profiling surfaces an issue, we move the call to a background `ModelContext` and marshal results back. Out of scope here; tech-design §6 already flags this.

**[`try? context.save()` swallows errors]** → Acceptable and consistent with the rest of the app's eager-write paths. The next `refreshAndSave` re-attempts, and the in-memory `Budget` values remain correct for display. If an operational reason to surface errors appears (e.g., telemetry), we can widen the return type — but not speculatively.

**[CloudKit last-writer-wins on concurrent edits from two devices]** → Unchanged from `docs/tech-design-doc.md` §4.4. The lifecycle service does not introduce new concurrency hazards; both devices would independently roll and reset to identical values given identical inputs, and the eventual-consistency merge is fine.

**[VM must remember to call `refreshAndSave`]** → Enforced by convention and tests at the VM layer (future change). The lifecycle service cannot force its own invocation; the trade-off is accepting a small discipline cost at the VM seam in exchange for keeping `Budget` unaware of orchestration.

**[Biweekly anchor shifts when `weekStartDay` changes]** → Same as in the `budget-math` change. Acknowledged by F-5.01; no new risk introduced here.

## Migration Plan

No data migration. The service reads and writes existing fields on `Budget`. First call after deploy that crosses any boundary will roll and/or reset as normal.

## Open Questions

- None blocking. A follow-up change for the Budgets/Budget ViewModels will decide whether to expose a debounced `refreshIfStale(...)` convenience (e.g., skip when `now − lastModified < 1s`), or whether the "nothing changed" fast path is enough. Deferred.

## Doc alignment

- **Aligned** with `docs/main-prd.md` §6.7 (roll at period boundaries; scheduled reset aligned to period boundaries; per-budget; no display rule changes).
- **Aligned** with `docs/tech-design-doc.md` §3.2 (eager roll + scheduled reset on access), §5.3 (pure math stays in `Domain/`; this service is the narrow, tested seam that binds math to storage), §5.4 (roll-then-reset ordering; remaining for display).
- **Update needed after implementation**: `docs/tech-design-doc.md` §5.4 — add `BudgetLifecycleService` as the sole orchestrator of the eager sequence and clarify that ViewModels call the service rather than `BudgetCalculator` directly for the roll+reset flow.
