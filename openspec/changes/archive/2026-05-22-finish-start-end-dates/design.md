## Context

The Schedule disclosure UI for F-7.05 / F-7.07 and the F-2.04 clamped-default caption on Add Expense both shipped on this branch. What remains is non-UI work: test coverage that pins the back-dating contract, analytics property flags called for by F-8.02, the translation pipeline run for the new strings, and the spec / docs hygiene that flips F-7.05 and F-7.07 to **Implemented**.

The single load-bearing technical decision under this change is that the existing `allocationInEffect` fallback in `simple-recurring-budgets/Domain/AllocationInEffect.swift` (the "no eligible row → earliest row's amount" branch) is what makes the back-dating-without-realignment design work for recurring budgets. The `applyDateEdits` view-model helper deliberately leaves recurring `AllocationChange` rows untouched on a recurring `startDate` edit; the calculator absorbs the user's intent at read time. This was originally framed as an open product question, but tracing the code (`AllocationInEffectTests.noEligibleRow_fallsBackToEarliest`, `Domain/AllocationInEffect.swift:25-27`, and `walkCarryOver`'s `boundaryStart` queries) confirmed that back-dated periods receive the earliest row's allocation amount without any data-mutation step. This change codifies that contract via new tests so future maintainers don't second-guess the fallback as a TODO.

## Goals / Non-Goals

**Goals:**
- Land the test coverage that pins back-dating behavior so the load-bearing fallback in `allocationInEffect` cannot be silently regressed.
- Add `start_date_changed` and `end_date_changed` (plus `allocation_changed` for symmetry) property flags to `budget_edited` analytics events, sourced from per-field diffs in `saveEdit`.
- Run translations for the ~14 new `String(localized:)` keys across all 38 storefront locales.
- Update `openspec/specs/add-edit-budget-screen/spec.md` and `openspec/specs/add-edit-expense-screen/spec.md` to match the shipped UI; flip F-7.05 / F-7.07 status to **Implemented** in `docs/product-features-planning.md` and reconcile `docs/analytics-spec.md` to match the new flags.

**Non-Goals:**
- No algorithm or calculator changes. `Domain/BudgetCalculator.swift`, `Domain/CarryOverWalker.swift`, `Domain/AllocationInEffect.swift` are read-only for this change.
- No new view files or visual redesigns. The Schedule disclosure shipped two commits ago and is final.
- The known iPhone-compact-width leading-offset bug on the new pre-start / post-end Add Expense previews is **explicitly punted** — it requires either a custom picker control or a deeper iOS 26 layout investigation, and the user is not blocking on it. If revisited, it's a separate change.
- No schema or CloudKit changes. `Budget.startDate` / `Budget.endDate` already exist as `Date?` fields.
- No multi-row recurring-history `startDate`-edit realignment. The fallback handles single-row history (the common just-created back-dating case); multi-row history is rare and the implicit-fallback path remains correct for any number of rows.

## Decisions

### Decision: No code changes to the budget calculator

The `allocationInEffect` fallback (`Domain/AllocationInEffect.swift:25-27`) already extends the earliest `AllocationChange` row's amount backward to any query whose date precedes its `effectiveFrom`. Combined with `walkCarryOver` iterating from `walkWindowStart = max(effectiveStartDate, lastResetDate ?? .distantPast)`, this means back-dating `Budget.startDate` automatically credits the original allocation to the back-dated window without any data-mutation step. Forward-dating works because the walker simply starts later; the existing `AllocationChange` at the old earlier date still matches any query at the new boundaries via the usual `last(where: effectiveFrom <= date)` rule.

**Alternatives considered:**
- *Realign the earliest `AllocationChange` on every recurring `startDate` edit.* Rejected — works for single-row history but corrupts multi-row history (a back-date past existing allocation edits would either need to push them all or destroy them, neither of which the user expects).
- *Realign only when there's exactly one `AllocationChange` row.* Rejected — the algorithmic fallback already handles this case correctly without a data-mutation step. Adding the realignment would be redundant, would surface a UI/model coupling that doesn't exist today, and would generate a `lastModified` write where none is needed.
- *Reject `startDate` edits when allocation history exists.* Rejected — UX regression with no justification; the algorithm copes fine.

### Decision: Document the contract via a snapshot-level integration test

Unit-level coverage of the fallback already exists (`AllocationInEffectTests.noEligibleRow_fallsBackToEarliest`). What's missing is a snapshot-level test that walks the full path: construct a weekly budget with one `AllocationChange`, back-date `Budget.startDate`, run `BudgetCalculator.snapshot`, assert the carry-over credits the back-dated periods at the original allocation amount. A future refactor that "cleans up" the defensive fallback in `allocationInEffect` will then break a high-signal test instead of silently shipping a regression.

A symmetric forward-date test (walker starts at the new later `effectiveStartDate`; no phantom credit for the orphaned earlier history) covers the other direction.

### Decision: Split `saveEdit`'s single `changed: Bool` into per-field diff flags

Today `saveEdit` tracks a single `changed: Bool` and emits the `budget_edited` event with a fixed property bag if anything changed. F-8.02 calls for per-field flags so analytics can distinguish a name edit from a date edit from an allocation edit (cohort analyses and pricing decisions rely on this). The minimal change is:

- Track `nameChanged`, `allocationChanged`, `currencyChanged`, `carryOverToggleChanged`, `startDateChanged`, `endDateChanged` as locals in `saveEdit`.
- Aggregate `changed` from `nameChanged || allocationChanged || …` for the existing single-write gate.
- Pass the four flags called out by F-8.02 (`allocation_changed`, `start_date_changed`, `end_date_changed`, plus the implicit `carry_over_toggled` if present in the spec — confirm against `docs/analytics-spec.md`) through `budgetEventProperties` **only on the `budget_edited` event path**, not on `budget_created`.

This is backwards-compatible (additive property bag), follows the precedent set by `expense_logged.is_add_funds`, and keeps the property surface predictable for downstream Mixpanel cohorts.

**Alternatives considered:**
- *Add the flags to both `budget_created` and `budget_edited` for symmetry.* Rejected — they're meaningless on creation (everything is "new"), would noise up dashboards, and don't match the F-8.02 wording which scopes them to `budget_edited`.
- *Use a single `fields_changed` array property.* Rejected — Mixpanel works best with flat boolean property flags for cohort filtering; an array property requires custom segmentation queries.

### Decision: Translation pipeline run uses the existing `scripts/translate_catalog/` pipeline

No bespoke tooling. Follow the `translate-new-strings` skill: extract from `Localizable.xcstrings`, translate via the pipeline, merge, validate. Same path every other UI change in this repo has used. All 38 storefront locales must be current before user-facing ship — this is enforced by `docs/main-prd.md` §6.8.

### Decision: Spec deltas only modify what's actually changing

Two affected spec capabilities (`add-edit-budget-screen`, `add-edit-expense-screen`). All other capabilities (`budget-math`, `budget-lifecycle`, etc.) are unchanged. The delta files use `## MODIFIED Requirements` blocks with the full updated content for each touched requirement, and `## ADDED Requirements` blocks for the new Schedule-disclosure and analytics-property-flags requirements. No `## REMOVED Requirements` — the previously specific-dates-only requirements generalize rather than disappear.

### Decision: Punt the iPhone compact-DatePicker leading-offset issue

The two new Add Expense previews (`Add — Pre-start budget`, `Add — Post-end budget`) show a leading inset on iPhone 17e (iOS 26 simulator) that we couldn't eliminate via `.labelsHidden()`, closure-based init with `EmptyView`, `.fixedSize`, or `VStack(alignment: .leading)`. iPad rendering is correct. The user is aware and explicitly OK punting; a future change can pursue either a custom date / time button pair backed by a sheet-presented graphical picker, or a deeper iOS 26 layout investigation. Out of scope here.

## Risks / Trade-offs

- **[Test brittleness — back-dating contract]** → The new `BudgetCalculatorTests` cases rely on the `allocationInEffect` fallback. If a future refactor changes the fallback behavior (e.g., decides to return zero instead of the earliest row's amount), our tests will fail loudly — which is the entire point of adding them. The mitigation is a clear test name (e.g. `snapshot_backDatedStartDate_extendsEarliestAllocationToNewWindow`) and an in-file comment pointing at the `AllocationInEffect.swift` docstring for the rationale.

- **[Analytics property explosion]** → Adding four boolean flags to `budget_edited` (`name_changed`, `allocation_changed`, `currency_changed`, `start_date_changed`, `end_date_changed`, plus existing `period`, `carry_over_enabled`, etc.) makes the event property bag larger. Mitigation: F-8.02 explicitly calls for these flags; Mixpanel charges per event, not per property. The cost is negligible. Limit the per-field flags to the ones F-8.02 calls out; don't speculatively add others.

- **[Translation pipeline failure]** → Running the pipeline for 38 locales is the longest single step in the change. If a locale's translation API call fails mid-run, the catalog could end up with a mix of translated and untranslated strings. Mitigation: the pipeline already supports subset mode and validation; re-running is idempotent. Validate before commit.

- **[Spec delta drift from shipped code]** → The delta files describe state that already exists on disk. There's a real risk the delta wording subtly misstates what `AddEditBudgetView+Schedule.swift` does. Mitigation: every `## MODIFIED` block must be cross-checked against the corresponding code on disk before commit; scenarios should be specific enough that an implementation engineer can reproduce them.

- **[F-7.05 / F-7.07 status flip premature if translations not run]** → Per §6.8, a feature isn't shippable until source-string + translation obligations are met. Mitigation: in `tasks.md`, gate the doc status flip behind the translation pipeline completing.

## Migration Plan

No data migration. All changes are additive (new tests, additive analytics properties, expanded spec scenarios). Rollback is git revert — no schema or CloudKit state to unwind.

## Open Questions

- **`carry_over_toggle_changed` flag?** F-8.02 doesn't explicitly list a `carry_over_toggle_changed` property flag for `budget_edited`. If `docs/analytics-spec.md` has it (or wants it for symmetry), include in the same change. Otherwise leave out — adding analytics flags is cheap, but the value-add for a binary toggle whose new value is already in the existing `carry_over_enabled` property is low.
- **Translation pipeline pre-flight check.** Confirm `scripts/translate_catalog/` is healthy on this branch before scheduling the run (it sometimes drifts when key formats change). The `translate-new-strings` skill handles this end-to-end; mention in tasks.

## Doc alignment

- `docs/main-prd.md` — unchanged. The back-dating contract is consistent with §6.7's "carry-over math operates at period granularity" prose.
- `docs/product-features-planning.md` — F-7.05 and F-7.07 status flips, plus a one-sentence back-dating contract note under F-7.05's edge cases. Required in this change.
- `docs/tech-design-doc.md` — unchanged. No schema, sync, or architecture impact.
- `docs/analytics-spec.md` — confirm `start_date_changed`, `end_date_changed`, `allocation_changed` properties are documented for `budget_edited`; add if missing.
