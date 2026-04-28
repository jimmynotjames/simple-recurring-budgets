## Context

Reset Cadences ship in code today (`ResetCadence` enum, `BudgetPeriod.defaultResetCadence`, `Budget.resetCadence` stored property, `BudgetCalculator.checkScheduledReset(...)`, `BudgetLifecycleService` scheduled-reset path) and are described in product/tech docs as a first-class part of the carry-over story (see `docs/main-prd.md` §6.7, `docs/product-features-planning.md`, `docs/ux-design-brief.md`, `docs/tech-design-doc.md`). However:

- No shipping UI currently surfaces Reset Cadence to users (the Add/Edit Budget sheet hasn't been built yet at the level required by `docs/ux-design-brief.md`).
- We want to pause the **product feature** without losing the design or the implementation, and without producing churn on CloudKit-visible schema.
- We want a strong "do not re-introduce" signal so that future agents — when planning new UI, writing new specs, or generating Figma — do not re-include Reset Cadence options.

This change therefore has two surfaces: **annotation** (docs, spec, code) and one **small behavior change** (default a new Budget's persisted `resetCadence` to `.never`).

## Goals / Non-Goals

**Goals:**
- Make Reset Cadences invisible to end users at runtime by ensuring every newly created Budget defaults to `ResetCadence.never` (no scheduled clears).
- Preserve all existing tests of the underlying mechanism (`isBroaderThan`, `validResetCadences(for:)`, `defaultResetCadence`, `checkScheduledReset(...)`).
- Annotate every doc and code location that mentions Reset Cadences with a clearly visible **PAUSED** marker that explains the pause and warns against surfacing the feature in UI/specs/plans.
- Keep the SwiftData schema and CloudKit field set unchanged — `Budget.resetCadence: String` stays a non-optional, default-valued column.
- Make the pause trivially reversible (small diff to flip back).

**Non-Goals:**
- Removing the `ResetCadence` enum, the `defaultResetCadence` mapping, the `resetCadence` stored property, or the scheduled-reset code path.
- Migrating existing Budgets that have a non-`.never` cadence stored. Their persisted value is left as-is; if the scheduled reset code path were to fire on those records it would still behave correctly. (In practice no shipping UI sets non-`.never` values, but we don't sweep them.)
- Building Add/Edit Budget UI. The pause explicitly tells future UI work to omit the field; it does not prescribe new UI.
- Changing `BudgetPeriod` ordering or any monetary/period semantics.

## Decisions

### Decision 1: Default new Budgets to `ResetCadence.never` instead of `period.defaultResetCadence`

- **Choice**: In `Budget.init`, when `resetCadence` is `nil`, persist `ResetCadence.never.rawValue`.
- **Rationale**: This is the smallest possible behavior change that fully removes the user-facing effect of Reset Cadences, because `.never` short-circuits `BudgetCalculator.checkScheduledReset(...)` to a no-reset result. No call sites need to special-case "feature paused"; the existing engine already does the right thing for `.never`.
- **Alternatives considered**:
  - *Hardcode `.never` at every reset checkpoint, ignoring `Budget.resetCadence` entirely.* Rejected: scatters the pause across multiple files, masks the persisted value, and is harder to revert.
  - *Make `Budget.resetCadence` optional and store `nil`.* Rejected: would change the SwiftData/CloudKit schema (CloudKit-visible default-value contract) for a temporary pause.
  - *Remove the `resetCadence` parameter from `Budget.init`.* Rejected: many tests and `DebugData` already pass an explicit cadence; removing it forces unrelated edits and makes the un-pause more invasive.

### Decision 2: Keep `BudgetPeriod.defaultResetCadence` mapping in code and specs, just unused

- **Choice**: Leave the `daily → .weekly`, `weekly → .monthly`, `biweekly → .quarterly`, `monthly → .quarterly` mapping intact, both as the Swift computed property and as a spec requirement, and tag both as **PAUSED**.
- **Rationale**: This is the most expensive piece of design knowledge in the feature. Deleting it now would have to be re-derived later. Keeping it as PAUSED preserves the intent.
- **Alternatives considered**:
  - *Delete `defaultResetCadence`.* Rejected: loss of design intent, and several tests still validate it.
  - *Rename to something obscure to discourage use.* Rejected: makes the un-pause noisier and breaks tests for no benefit.

### Decision 3: Use a consistent, greppable PAUSED marker

- **Choice**: Use the literal string `PAUSED (Reset Cadences)` in code comments and `**PAUSED — Reset Cadences feature is not in scope.**` in markdown callouts. Always include a short rationale and a "do not surface in UI / do not re-introduce in specs" sentence inline.
- **Rationale**: Future agents tend to look for greppable markers; one consistent token across docs, specs, and code makes the pause trivially auditable (`rg 'PAUSED \(Reset Cadences\)'`) and reduces the risk of one location drifting back. Markdown callouts are formatted as a leading `> [!NOTE] **PAUSED — Reset Cadences feature is not in scope.**` so they render distinctly in editors that support GitHub-style alerts and degrade gracefully elsewhere.
- **Alternatives considered**:
  - *Just delete the prose.* Rejected: the user explicitly wants to retain design/implementation knowledge.
  - *A single top-of-file note instead of inline callouts.* Rejected: agents quoting individual sections would miss the marker.

### Decision 4: Pause annotations live in docs, specs, AND code

- **Choice**: Update `docs/`, the affected delta specs (`data-models`, `budget-lifecycle`), and the relevant Swift files (`ResetCadence.swift`, `BudgetPeriod.swift`, `Budget.swift`, `BudgetCalculator.swift`, `BudgetLifecycleService.swift`).
- **Rationale**: Different agents enter the codebase from different surfaces (PRD, feature plan, spec, code). Each entry point must self-describe the pause.
- **Alternatives considered**:
  - *Only annotate docs.* Rejected: agents reading only Swift code would miss the pause and might assume the feature is live.

## Risks / Trade-offs

- **Risk**: A future agent edits `Budget.init` to "fix" the default and re-introduces `period.defaultResetCadence` without realizing the pause. → **Mitigation**: leading `// PAUSED (Reset Cadences)` doc comment on the initializer and on `defaultResetCadence` itself with explicit "do not consume from `Budget.init`" guidance, plus a unit test asserting the new default is `.never` regardless of period.
- **Risk**: PAUSED markdown callouts get stripped by tooling that doesn't understand GitHub alerts. → **Mitigation**: include the literal text **PAUSED — Reset Cadences feature is not in scope.** in the body of the callout so the marker survives any rendering.
- **Risk**: Existing CloudKit records with non-`.never` cadences could trigger a reset on devices that pull those records, even though we no longer create them. → **Mitigation**: this is the *intended* behavior of the existing engine; we are not paving over it. The pause only changes new-record defaults. If the product later decides to forcibly suppress scheduled resets, that's a separate change.
- **Trade-off**: Spec and code keep "dead-on-paper" requirements. We accept this so that un-pausing is a small, mechanical revert rather than a re-design.

## Migration Plan

1. Land the doc/spec/code annotations and the `Budget.init` default change together. No data migration is needed.
2. Update tests in `simple-recurring-budgetsTests/Models/ModelTests.swift` so the "default reset cadence follows period" expectation becomes "default reset cadence is `.never` regardless of period" (the underlying `BudgetPeriod.defaultResetCadence` mapping continues to be tested in `EnumTests.swift`).
3. Run `make test` (single iPhone simulator) per the repo test rule.
4. **Rollback**: revert this change. Because nothing is removed and no schema changes, reverting restores the previous defaults without any data migration.

## Open Questions

- None at this time. If, while paused, we observe scheduled resets firing on imported CloudKit records (created before the pause on another device), we may want a follow-up change to coerce all persisted cadences to `.never`. That is **not** part of this pause.
