## Why

Reset Cadences (the feature that automatically clears a Budget's carry-over on a weekly/biweekly/monthly/quarterly schedule) are being paused as a user-facing feature while we evaluate whether they meet a real user need. The intent is to **stop offering automatic carry-over resets to users today**, but to preserve the existing design, specs, and implementation so the feature can be unpaused later without rework. We also want to make the pause **agent-safe**: future agents (and humans) reading the docs or code must not accidentally re-introduce Reset Cadences into UIs, plans, or new specs while it is paused.

## What Changes

- **Mark Reset Cadences as PAUSED across all `docs/*.md`** — `main-prd.md`, `product-features-planning.md`, `ux-design-brief.md`, and `tech-design-doc.md`. Existing prose stays intact (so we keep the design knowledge), but each section that mentions Reset Cadences gets a clearly visible "PAUSED — not in scope" callout instructing agents and contributors not to surface, plan against, or implement Reset Cadences UI/flows.
  - On `main-prd.md` §6.7 (Carry-over behavior), explicitly state that **Scheduled** resets are paused; **Manual** carry-over reset remains supported.
  - On `product-features-planning.md`, annotate the Add/Edit Budget feature so the "carry-over reset cadence" sub-feature is marked PAUSED and excluded from acceptance criteria for now.
  - On `ux-design-brief.md`, drop "reset cadence" from the active set of fields described for the Add/Edit Budget sheet (keep the historical mention with a PAUSED callout).
  - On `tech-design-doc.md`, annotate the validation example (Budget Period → Reset Cadence) and the scheduled-reset paragraph as PAUSED for product, while noting the type and code remain.
- **Default `ResetCadence` to `.never` for all newly created Budgets**, regardless of `BudgetPeriod`. The `BudgetPeriod.defaultResetCadence` mapping (`daily → .weekly`, `weekly → .monthly`, `biweekly → .quarterly`, `monthly → .quarterly`) is preserved in code and specs but is **no longer consumed** by the `Budget` initializer while the feature is paused.
- **Annotate the Reset Cadence code surface as PAUSED**, in a way that is easy to grep and easy to revert:
  - `ResetCadence.swift`, the `defaultResetCadence` computed property on `BudgetPeriod`, the `resetCadence` stored property on `Budget`, and the scheduled-reset path in `BudgetLifecycleService` / `BudgetCalculator.checkScheduledReset(...)` each get a leading `// PAUSED (Reset Cadences)` doc comment explaining: feature is paused, do not surface in UI, do not plan new behavior on top of it, may return later.
  - `DebugData` and tests that already use `.never` are fine; tests that exercise the type-level behavior of `ResetCadence`, `defaultResetCadence`, `validResetCadences(for:)`, and `checkScheduledReset(...)` stay as-is so we keep coverage of the underlying mechanism.
- **Update the `Budget` initializer test fixture expectations** so a Budget created without an explicit `resetCadence` ends up with `ResetCadence.never.rawValue`, regardless of period.
- **Do NOT** remove or rename the `ResetCadence` enum, `BudgetPeriod.defaultResetCadence`, the `Budget.resetCadence` stored property, the scheduled-reset code path, or any existing CloudKit-visible field. SwiftData/CloudKit schema is unchanged.

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

- `data-models`: change the requirement for the **default reset cadence applied to a new Budget**. The `BudgetPeriod.defaultResetCadence` mapping requirement is retained (and tagged PAUSED), but the Budget creation requirement now mandates `.never` as the persisted default while the feature is paused.
- `budget-lifecycle`: tag the **scheduled reset** requirements as PAUSED — the code path remains and remains tested at the unit level, but no user-facing flow schedules anything other than `.never`, so scheduled resets are not expected to fire in practice.

## Impact

- **Code (annotations + small behavior change)**: `simple-recurring-budgets/Domain/ResetCadence.swift`, `simple-recurring-budgets/Domain/BudgetPeriod.swift`, `simple-recurring-budgets/Models/Budget.swift` (initializer default change), `simple-recurring-budgets/Domain/BudgetLifecycleService.swift`, `simple-recurring-budgets/Domain/BudgetCalculator.swift`. Tests under `simple-recurring-budgetsTests/Models/ModelTests.swift` need expectation updates for the new initializer default.
- **Docs**: `docs/main-prd.md`, `docs/product-features-planning.md`, `docs/ux-design-brief.md`, `docs/tech-design-doc.md` — each gets PAUSED callouts.
- **Specs**: `openspec/specs/data-models/spec.md`, `openspec/specs/budget-lifecycle/spec.md` — delta specs in this change.
- **Schema / CloudKit**: no changes. `Budget.resetCadence` stays a `String`, default-encoded property; existing records retain their values. New records created on devices running this change persist `"never"`.
- **UI**: no immediate UI change is required because no shipping UI currently exposes Reset Cadence; the pause guarantees future Add/Edit Budget UI work will *not* surface it until the feature is explicitly unpaused.
- **Future un-pause**: reverting is straightforward — flip the `Budget` initializer default back to `period.defaultResetCadence`, drop the PAUSED annotations, and restore the spec/doc language.

## Doc alignment

- `docs/main-prd.md` §6.7 — will be updated to mark **Scheduled** resets as PAUSED while keeping the description for future reference. Manual reset remains supported as documented.
- `docs/product-features-planning.md` — F-x.xx entries that include "carry-over reset cadence" sub-bullets will be annotated PAUSED; acceptance criteria for current work must not require Reset Cadences UI.
- `docs/ux-design-brief.md` — the Add/Edit Budget sheet description will no longer include "reset cadence" as an active field; a PAUSED note retains the historical context.
- `docs/tech-design-doc.md` — the example of cross-field validation (Budget Period → Reset Cadence) and the "Scheduled reset" paragraph will be annotated PAUSED, with explicit guidance that the type and code are retained.

No conflicts identified with PRD, tech-design, or feature IDs — this change pauses behavior and updates the docs in lockstep, rather than overriding them silently.
