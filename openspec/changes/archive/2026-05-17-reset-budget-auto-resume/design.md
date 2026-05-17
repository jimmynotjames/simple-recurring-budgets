## Context

Reset Budget currently deletes all `ExpenseItem`s for a budget and sets `Budget.lastResetDate = now` in a single atomic save via `BudgetLifecycleService.resetBudget(_:context:now:)`. The view layer (`BudgetDetailView.resetBudget()`) is thin: it logs, calls the service inside a `withAnimation` block, fires the `budget_reset` analytics event, and refreshes the lifecycle snapshot. All write logic lives in the service.

If the budget is paused at the time of the reset, today's implementation leaves it paused — producing an empty, unusable budget that requires a separate Resume tap. The fix is to fold the resume into the same service write path: before the existing `try? context.save()`, check the lifecycle state and insert a `.resume` `LifecycleEvent` if paused.

A pre-existing concern surfaced during review: the current `budget-detail-screen` spec for this requirement describes setting `Budget.carryOverAmount = 0` and `Budget.carryOverLastResetDate = Date()`. Neither field exists on the `Budget` model anymore — the budget-calculations rewrite removed stored carry-over in favor of live recomputation keyed off `lastResetDate`. The actual service method only sets `lastResetDate` and `lastModified`. Because OpenSpec `MODIFIED` requirements overwrite at sync time, this delta is the right moment to correct that drift while keeping scope tight.

**Doc alignment:** `docs/main-prd.md` §6.7 and the "Reset Budget" glossary entry already accurately describe `lastResetDate = now`; both need a one-line addition about auto-resume. `docs/product-features-planning.md` F-2.02 needs the same addition. No conflict with `docs/tech-design-doc.md`.

## Goals / Non-Goals

**Goals:**

- When Reset Budget is invoked on a paused budget, the service atomically resets AND resumes the budget in a single `context.save()`.
- Dialog body copy and the menu item's accessibility hint inform the user about the auto-resume behavior.
- The `budget-detail-screen` spec requirement is corrected to match the actual `Budget` model fields and the actual service-delegation flow.
- System image already updated to `arrow.counterclockwise` in code (PR #79); the spec is brought in line.

**Non-Goals:**

- Adding a "Reset and keep paused" option or any UI toggle.
- Changing the public signature of `BudgetLifecycleService.resetBudget(...)`. The behavior change is internal.
- Changes to `BudgetLifecycleService.resumeBudget(...)` itself.
- A new analytics event for the auto-resume. The auto-resume is system-initiated; only the user-initiated `budget_reset` event fires.
- Any behavior change when the budget is not paused at reset time.
- Backfilling spec drift in other requirements within `budget-detail-screen` (only the Reset Budget requirement is in scope).

## Decisions

**D1. Put the auto-resume inside `BudgetLifecycleService.resetBudget(...)`, not the view.**

The view already delegates the entire write path to the service. Putting the conditional resume in the view would re-import lifecycle-event creation into the view layer, which fights the existing "service is the gatekeeper" architecture established for `pauseBudget` / `resumeBudget`. Inside the service, the resume event is inserted into the same `ModelContext` before the existing `try? context.save()`, keeping the operation atomic with no API surface change.

*Alternative considered:* Call `BudgetLifecycleService.resumeBudget(...)` from inside `resetBudget(...)`. Rejected — `resumeBudget` calls `context.save()` internally, which would produce two saves and a brief reset-but-still-paused window. The inline-event approach reuses the same single save.

**D2. Reuse the same `now` timestamp across `lastResetDate`, `lastModified`, and the resume event's `effectiveDate`.**

A single `let now = now` capture (with `now` already a parameter defaulting to `Date()`) drives all three fields. This makes the operation deterministic for tests and avoids minute-granular skew between the reset and the resume event.

**D3. Bypass the eligibility checks normally performed by `resumeBudget`.**

`resumeBudget` rejects when the budget is `.specificDates` (cannot be paused per F-2.08) or `.postEnd` (cannot be resumed per F-7.07). If we're inside `resetBudget` and observe `lifecycleState == .paused`, both of those conditions are by construction false: Specific Dates budgets cannot reach `.paused` (they're never pausable), and a `.postEnd` budget cannot have `.paused` as its current lifecycle state. The inline-event insertion is therefore safe without re-checking.

**D4. Keep the existing `budget_reset` analytics event unchanged.**

The user-visible event is "I reset my budget." The fact that the budget happened to be paused at the time is incidental context; auto-resuming on the user's behalf is not a separate user action. Adding a `budget_resumed` event for system-initiated resumes would dilute the metric meaning. A future need to distinguish resets-that-resumed from resets-that-didn't can be addressed by adding a property to `budget_reset` (e.g., `was_paused: Bool`) — out of scope here.

**D5. Fix the pre-existing `carryOverAmount = 0` drift in the spec as part of this delta.**

The MODIFIED requirement must, per OpenSpec rules, carry the full updated content. Copying the old (drifted) operational steps verbatim would re-publish incorrect behavior. Updating those steps to match today's `Budget` model fields (`lastResetDate`, `lastModified`) is a small scope expansion but produces a correct post-sync spec.

## Risks / Trade-offs

**CloudKit sync receives two logical changes (reset + `.resume` event) in one save batch** → Acceptable. CloudKit processes record changes independently within a batch; the single-save boundary is a local atomicity guarantee, not a CloudKit transaction guarantee. Same shape as today's pause/resume writes.

**Inline `.resume` event creation bypasses `resumeBudget` eligibility guards** → Mitigated by D3's by-construction reasoning. A new explicit scenario in the spec ("Reset Budget on paused budget inserts a single .resume event") locks the behavior in. A unit test covers the active-budget branch to prove no spurious resume event is created when unpaused.

**Spec-drift correction is scope creep** → Acknowledged. The alternative is to copy out-of-date language into the new MODIFIED requirement, which would silently re-publish incorrect behavior at sync time. Fixing it now is the smaller harm.
