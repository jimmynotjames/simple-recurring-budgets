## Why

The recurring-budget Start Date / End Date UI for F-7.05 and F-7.07 shipped in the last two commits on this branch (collapsed `Schedule` disclosure for recurring period types; pre-start / post-end clamped-default caption on Add Expense). Three follow-up obligations remain before the feature can be marked Implemented and shipped to users:

1. **Test coverage** for the back-dating behavior we now rely on (the calculator's `allocationInEffect` earliest-row fallback) and for the new Schedule / caption surfaces.
2. **Mixpanel analytics** — `budget_edited` events need to ship the `start_date_changed` and `end_date_changed` property flags called for in F-8.02, so analytics can distinguish a date edit from any other budget edit.
3. **Localization, doc, and spec hygiene** — the ~14 new `String(localized:)` keys need to be translated to all 38 App Store storefront locales per §6.8; `docs/product-features-planning.md` F-7.05 and F-7.07 need their status flipped to **Implemented**; the affected spec files in `openspec/specs/` need their requirements updated to match what's now on disk.

No algorithm work is required. The existing `allocationInEffect` fallback in `simple-recurring-budgets/Domain/AllocationInEffect.swift` (the "no eligible row → earliest row's amount" branch, already covered by `AllocationInEffectTests.noEligibleRow_fallsBackToEarliest`) is what makes the back-dating-without-realignment design work — `applyDateEdits` in the view model intentionally leaves recurring allocation history alone and the calculator absorbs the intent. This change documents that contract via tests and prose so future maintainers don't second-guess the fallback as a TODO.

## What Changes

- **Add/Edit Budget Save behavior (recurring)** — Spec update reflecting that recurring period types now use `viewModel.startDate` directly at Save time instead of recomputing per-period anchors inside `saveNew`. The ViewModel pre-fills `startDate` at Add-mode init and re-anchors via `period.didSet`; user overrides (e.g. picking a different `weekStartDay`-anchored Monday for a weekly budget) are honored at Save. `endDate` is optional for recurring, required for `.specificDates`.
- **Add/Edit Budget Schedule disclosure (recurring)** — New requirement codifying the collapsed `Schedule` disclosure row (`"Starts {date} · No end date"` summary, expand-to-edit two `DateColumn` chips, "Clear end date" affordance, leading-aligned summary + chip layout). Specific Dates retains its existing always-visible mandatory `Dates` card unchanged.
- **Add/Edit Budget Edit-mode date edits (recurring)** — Spec update: `applyDateEdits` writes `Budget.startDate` / `Budget.endDate` for any period type, and clears `Budget.endDate` when the user removes it (recurring only — `canSave` continues to require both dates for `.specificDates`). `AllocationChange` realignment is **not** applied for recurring; the calculator's earliest-row fallback covers the back-dating case without data mutation. Specific-dates realignment behavior is unchanged.
- **Add/Edit Expense `dateContextCaption`** — Spec update generalizing the existing paused-caption requirement into a single date-context caption with priority order: paused-out-of-range > paused-since > Add-mode-pre-start (`"Budget starts on {startDate}."`) > Add-mode-post-end (`"Budget ended on {endDate}."`) > none. Add-mode `date` seed for post-end budgets clamps to `endDate`'s end-of-day so the picker opens inside `dateRange`.
- **Analytics — `budget_edited` property flags** — `budgetEventProperties` in `AddEditBudgetViewModel` gains per-field change flags (`start_date_changed`, `end_date_changed`, plus `allocation_changed` for symmetry with what `docs/analytics-spec.md` already declares for F-8.02). `saveEdit` tracks per-field diffs (replacing the existing single `changed: Bool`) and passes them through only on `budgetEdited`. `budgetCreated` properties are unchanged.
- **Translations** — Run the `scripts/translate_catalog/` pipeline against the new keys for all 38 storefront locales (no schema or code change; just the data run + validation).
- **Tests** — New `BudgetCalculatorTests` snapshot-level cases pinning back-dated + forward-dated `startDate` behavior; new `AddEditBudgetViewModelTests` cases for Add-mode startDate pre-fill, `period.didSet` reset semantics, Edit-mode `applyDateEdits` paths (set start, set end, clear end, specific-dates realignment); new `AddEditExpenseViewModelTests` cases for the three caption branches and post-end seed clamp.
- **Documentation** — Flip F-7.05 and F-7.07 status to **Implemented** in `docs/product-features-planning.md` and add a one-sentence note on the back-dating contract. Update `docs/analytics-spec.md` with the new property flags if not already present.

Explicitly **out of scope** (split into its own change if revisited):
- The known compact-DatePicker iPhone leading-offset issue visible only in the new `Add — Pre-start budget` / `Add — Post-end budget` previews. The user is aware and not blocking on it; pursuing it requires either a custom picker control or a deeper iOS 26 layout fix.

## Capabilities

### New Capabilities
<!-- None — all changes modify existing capabilities. -->

### Modified Capabilities
- `add-edit-budget-screen`: Recurring period types now expose Start Date / End Date via a collapsed `Schedule` disclosure; Add-mode `startDate` is pre-filled per period type and re-anchored on period change; Save in Add and Edit modes uses `viewModel.startDate` / `endDate` directly (including the "clear endDate" path for recurring); `budgetEdited` analytics events ship per-field change flags.
- `add-edit-expense-screen`: The existing paused-caption requirement generalizes to a `dateContextCaption` with paused + Add-mode pre-start + Add-mode post-end branches; Add-mode date seeding clamps to `endDate`'s end-of-day for post-end budgets so the picker opens inside its allowed range.

## Impact

- **Code touched** — All previously shipped on this branch; this change ships tests, an analytics expansion in `AddEditBudgetViewModel`, the translation run, and doc/spec updates. No new view files.
- **Specs** — Two modified spec files (`add-edit-budget-screen`, `add-edit-expense-screen`) via delta files under `openspec/changes/finish-start-end-dates/specs/`.
- **Algorithm** — No changes. The load-bearing `allocationInEffect` fallback (`Domain/AllocationInEffect.swift`) is documented via new snapshot-level tests, not modified.
- **Localization** — ~14 new keys under `addEditBudget.schedule.*`, `addEditBudget.field.date.{start,end}.recurring.*`, `addEditExpense.preStart.caption.format`, `addEditExpense.postEnd.caption.format`. Pipeline must run before user-facing ship.
- **Analytics** — Backwards-compatible additive change to `budget_edited` property bag. No new events, no removed properties.
- **Docs** — `docs/product-features-planning.md` (F-7.05, F-7.07 status), `docs/analytics-spec.md` (new property flags if missing).

### Doc alignment
- `docs/main-prd.md` §6.7 (carry-over and back-dating) — already consistent; the back-dating contract is rationalized in `applyDateEdits` docstring and will be reflected in F-7.05 / F-7.07 status notes.
- `docs/product-features-planning.md` F-7.05 and F-7.07 — currently marked **Open**; flip to **Implemented**.
- `docs/tech-design-doc.md` — no change required (no schema or architecture impact beyond what's already on disk).
- `docs/analytics-spec.md` — verify `start_date_changed` / `end_date_changed` are documented for `budget_edited`; add if missing.
