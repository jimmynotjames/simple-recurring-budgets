## Context

`BudgetDetailView` shipped in commit `3bd83de` as the resolved destination for `AppRoute.budgetDetail(Budget)`. Until then, `RootView` rendered a placeholder `Text` for that route. The screen targets product feature **F-2.02 (Budget screen)** and is the second non-placeholder screen the user reaches after the root Budgets list.

The screen reuses three already-shipped infrastructure pieces:

- The `BudgetLifecycleService` orchestrator (capability `budget-lifecycle`) for the eager **roll → persist → reset → persist** sequence per `docs/main-prd.md` §6.7.
- The `Router` / `AppRoute` / `SheetRoute` plumbing (capability `app-navigation`) for push and sheet presentation.
- The `CarryOverChip`, `RemainingBar`, and `Color.moneyDeficit` / `Color.moneySurplus` semantic aliases shipped with the Budgets screen (capability `budgets-screen`).

Because this is mostly a retroactive capture of working code, the design here documents the **decisions** the original commit made and the **one rationale-bearing decision** introduced by the plural-rule fix.

## Goals / Non-Goals

**Goals:**

- Capture the screen's structure, decision points, and integration with existing services as a durable spec.
- Resolve the only spec-violating UI text (the hand-rolled English plural in the Reset Budget dialog body) without touching layout or other copy.
- Update `docs/product-features-planning.md`, `docs/main-prd.md`, and `docs/tech-design-doc.md` so they match the as-shipped behavior, and explicitly name **Reset Budget** as a distinct operation in the glossary.

**Non-Goals:**

- Add automated tests for the screen. Backfill is deferred so this change can land cleanly without expanding scope; previews already exercise the visual states.
- Implement the Add / Edit / View Expense sheet flow (F-2.04). The detail screen routes to the existing `addExpense` and `editBudget` sheet routes; their resolution is owned by other features.
- Implement F-6.01 (Add Funds) entry. The detail row already honors `ExpenseItem.isAddFunds` / `displayAmount` for display, but no UI lets the user create such a row.
- Refactor the View into a ViewModel. `docs/tech-design-doc.md` §2.1 escalation triggers do not apply.
- Rework the in-list "Add Expense" full-width prominent button vs an alternative pattern (toolbar button, FAB, etc.). The shipped pattern is the UX brief's "primary Add Expense always within thumb reach" answer; we keep it.

## Decisions

### D1. View + Services (no ViewModel)

The screen reads the passed-in `Budget` model directly, writes through `@Environment(\.modelContext)`, and calls `BudgetLifecycleService.refreshAndSave` from the view itself. State on the view is limited to:

- `lifecycle: BudgetLifecycleResult?` — last result from the service.
- `expenseToDelete: ExpenseItem?` and `showDeleteConfirm: Bool` — coupled state for the delete confirmation dialog.
- `showResetCarryOverConfirm: Bool` and `showResetBudgetConfirm: Bool` — confirmation triggers.

**Why:** none of the §2.1 escalation triggers in `docs/tech-design-doc.md` apply:

1. No non-trivial draft / form state — confirmations are simple booleans.
2. No `async` / `Task` work owned by the screen.
3. Multi-step actions are short destructive flows (delete → save) with confirmation, not long workflows.
4. No expensive derived display state — `BudgetLifecycleResult` is a small struct cached as-is.

**Alternative considered:** A `BudgetDetailViewModel` mirroring `AddEditBudgetViewModel`. **Rejected** because it would duplicate state already owned by the `Budget` model and `BudgetLifecycleService`, and would force the lifecycle refresh into a `bind(context:)` lifecycle hook which the doc §2.1 explicitly warns against.

### D2. Two-file split: `BudgetDetailView.swift` + `BudgetDetailView+ExpenseSection.swift`

The expense list section, `ExpenseRowView`, current/past partitioning, and section/empty title localizations live in an extension file. The header, primary action, toolbar, and confirmation flows stay in the main file.

**Why:** the expense-section logic is internally cohesive and visually separable from the header / toolbar logic. Splitting respects SwiftLint's file-length pressure (the combined view would push past the soft limit) and keeps each file focused on one concern.

**Alternative considered:** a single file. **Rejected** for length and for the cleaner visual separation in source control.

### D3. Reset Budget is a distinct destructive operation, not a renamed "manual reset"

Three destructive operations on a Budget now exist, each with a different blast radius:

| Operation | Trigger | Effect |
|---|---|---|
| Reset Carry-Over (existing) | Header inline "Reset" button → alert confirm | Zero `carryOverAmount`, bump `carryOverLastResetDate` and `lastModified`. |
| **Reset Budget (new)** | Toolbar overflow Menu → "Reset Budget…" → dialog confirm | Delete every `ExpenseItem` belonging to this Budget; zero `carryOverAmount`; bump timestamps. Budget itself stays. |
| Delete Budget (existing) | Add/Edit Budget sheet (Edit mode) → "Delete Budget" → dialog confirm | `context.delete(budget)` cascades to all `ExpenseItem`s. Budget gone; row disappears from the list. |

**Why:** users want a "fresh start on the same budget" path that does not require recreating the budget. "Manual carry-over reset" alone is insufficient when historical expense rows are still present and confusing the user. "Delete Budget" is too destructive when the user wants to keep the configuration. Reset Budget bridges the gap.

**Alternative considered:** make Reset Budget a sub-action on the Reset Carry-Over alert ("Also delete expenses?"). **Rejected** because two destructive paths off one alert harms clarity and confirmation safety.

**Doc impact:** `docs/main-prd.md` §6.7 and §10.1 glossary need a paragraph + entry naming Reset Budget; F-2.02 acceptance criteria need to mention the toolbar entry, the dialog wording's reference to expense count, and the single-`save()` semantic.

### D4. Lifecycle refresh triggers

The screen invokes `BudgetLifecycleService.refreshAndSave(_:settings:context:)` on three events:

1. `.task(id: budget.persistentModelID)` — initial load and identity changes.
2. `onChange(of: scenePhase)` when transitioning to `.active` — handles boundary crossings while the app was inactive.
3. `onChange(of: budget.expenseItems.count)` — handles inserts/deletes within this screen so the header re-derives `remaining` and the section split re-partitions.

**Why three triggers:** (1) and (2) match the `budgets-screen` row contract. (3) is added because, unlike the row case, the detail screen directly drives the mutations (Add Expense sheet, swipe-to-delete, Reset Budget) and needs immediate re-display rather than waiting for the next scene-active or task-id change.

**Alternative considered:** call `refreshLifecycle()` imperatively at every mutation site. **Rejected** — `onChange(of: count)` is one declarative trigger that catches every path (Add Expense via sheet, swipe-delete, Reset Budget) without scattering refresh calls across action handlers.

### D5. Period-aware sectioning vs flat list

The expense list splits into "Current ⟨period⟩" and "Past ⟨period⟩" with the current section showing a section total formatted in `monospacedDigit`. When the budget has zero expenses, a single centered "No expenses logged yet." caption appears (no section structure). When the budget has past expenses but nothing in the current period, the "Current" section renders a per-period contextual caption ("Nothing logged today" / "this week" / "this period" / "this month").

**Why:** the UX brief explicitly calls out "current-period state pinned at top" and "ledger" feel. The header already presents the current-period numerical state; the section split mirrors that mental model in the list. The section total on the current section gives the user a quick "how much have I burned this period" without reading the header math.

**Alternative considered:** a flat date-descending list with sticky date headers. **Rejected** — it puts past-period spend visually adjacent to current-period spend without distinction, blurring the §6.7 separation that the entire app's mental model is built on.

**Trade-off:** when current is empty and past is non-empty, the screen shows two sections (the "nothing logged today" caption + "Past Days") — slightly busier than a flat list would be but consistent with the header's framing.

### D6. Plural rule fix via Xcode String Catalog plural variation

`Localizable.xcstrings` already hosts the `budgetDetail.resetBudget.dialog.message` entry. The current Swift call site interpolates a manually-chosen English word ("expense" / "expenses"). The fix moves the count-based variation **into the catalog** via Xcode's plural / variations editor (CLDR plural rules per locale) and changes the Swift call site to interpolate only the count:

```swift
} message: {
  Text(
    "budgetDetail.resetBudget.dialog.message \(budget.expenseItems.count)",
    comment: "Body of the reset-budget confirmation dialog; argument is the expense count."
  )
}
```

**Why:** a single key with a `Plural` variation is the canonical SwiftUI / String Catalog idiom for count-driven copy and lets translators encode their locale's CLDR plural rules (one / few / many / other) without touching code. The shipped en-US string ("All N expense(s) will be permanently deleted and the carry-over balance will be reset to zero.") stays equivalent.

**Alternative considered:** keep two interpolations and introduce two distinct keys for one / other. **Rejected** — every plural-needing string would multiply, and locales like Russian or Polish (one / few / many / other) would still be wrong.

**Catalog mechanics:** the entry's `localizations` map gains a `variations.plural` block per locale (`one` / `other` for en-US; future locales fill in their own buckets). The Swift `Text(_, comment:)` initializer reads the variation automatically based on the interpolated `Int`.

**Implementation note:** because en-US is the only translation present today, this change only adds the en-US `one` / `other` bucket. Future translations follow the same shape.

### D7. Toolbar overflow Menu vs separate toolbar buttons

The screen places "Edit Budget" and "Reset Budget…" inside an `ellipsis.circle` Menu (top-trailing), rather than two distinct toolbar buttons.

**Why:** Apple HIG's grouping convention for low-frequency actions — Edit Budget is rare (configure once, edit occasionally), Reset Budget is rarer and dangerous. The Menu reduces toolbar clutter and makes Reset Budget mildly less discoverable, which is the right safety trade-off for a destructive-on-confirm action that wipes data. Keeping it inside the Menu also frees the trailing toolbar slot for future per-detail screen actions (e.g., a future "Filter expenses" or "Share").

**Alternative considered:** dedicated toolbar trailing buttons. **Rejected** for the safety / clutter reasons above.

### D8.1. Test seam: extract period partitioning to `[ExpenseItem]` extension; mirror the inline-the-algorithm pattern for destructive actions

Two complementary patterns make `BudgetDetailView` testable without forcing a ViewModel:

- **Pure helper:** the current/past partitioning currently lives as computed properties (`currentPeriodExpenses`, `pastPeriodExpenses`, `currentPeriodTotal`) on the view. Extract this into a small `extension Array where Element == ExpenseItem` (or a dedicated free helper in `Domain/`) returning a `(current: [ExpenseItem], past: [ExpenseItem])` tuple given a `periodStart: Date?`. Pure, no SwiftData dependency, easy to unit-test. The view consumes the helper instead of duplicating the logic.
- **Inline-the-algorithm tests** for destructive actions: the `resetBudget`, `resetCarryOver`, and `deleteExpense` methods read `@Environment(\.modelContext)` and live inside the view, which makes calling them from a test awkward. The repo already has precedent in `BudgetsViewMoveTests` to **re-implement the action body inside the test** against an in-memory `ModelContainer` from `TestModelContainer.make()`, then assert the postconditions (atomicity, deleted-vs-preserved entities, timestamps). The test file header documents that this catches algorithm regressions but not view-wiring regressions — an acceptable trade-off given that wiring is exercised by `make test` build + previews.

**Why not a full ViewModel just to enable testing?** The §2.1 escalation triggers do not apply (D1 above), and the repo precedent already shows how to test action logic without a VM. Introducing a VM purely to host four short methods would inflate the surface for negative gain.

**Why not snapshot / SwiftUI rendering tests?** The six `BudgetDetailView` previews already cover the visual matrix; the convention of `BudgetsViewMoveTests` and the change `2026-04-25-budgets-screen` is preview-only for screen-level rendering. We continue that convention.

### D9. RemainingBar extracted to a shared file

`RemainingBar` (the fuel gauge under amounts) was originally inline in `BudgetsView.swift`. To consume it from the detail header, it moves to `Views/RemainingBar.swift` and remains internally identical (clamped 0–1 fraction, accent / deficit color, hidden from VoiceOver).

**Why:** classic extract-and-reuse. No behavior change. A detail-only copy would create drift; a private nested type would prevent sharing.

## Risks / Trade-offs

- **[Risk]** The plural-rule fix touches `Localizable.xcstrings` and the Swift call site at the same time. If the catalog mutation is half-applied (Swift updated but variation not added in the catalog editor) the dialog body will fall back to the catalog's stale source string at runtime.
  **Mitigation:** the catalog edit is part of the implementation tasks and is exercised by every `BudgetDetailView` preview that hits the reset path; verify both the en-US `one` and `other` buckets render correctly during preview review and at `make test` time (the screen must still compile and previews must run).

- **[Risk]** Adding a doc paragraph for **Reset Budget** in `docs/main-prd.md` §6.7 risks readers conflating it with "manual carry-over reset" or "delete budget."
  **Mitigation:** the doc-update task adds a small comparison table or three-bullet block (modeled after D3 above) to disambiguate, and adds a glossary entry in §10.1.

- **[Risk]** F-2.02 acceptance criteria expansion may invalidate previously-shipped doc text.
  **Mitigation:** F-2.02 is currently `Status: Open` (unimplemented). Expanding its acceptance and flipping it to `Implemented (excluding F-2.04 entry/edit and F-6.01)` is additive — no prior implemented promise is broken.

- **[Trade-off]** No automated tests for the screen at archive time. Previews exercise the visual matrix but cannot assert behavior such as "Reset Budget deletes exactly the budget's expenses and zeros only its carry-over." This is consistent with how `2026-04-25-budgets-screen` shipped (preview-only); a follow-up backfill change can add Swift Testing coverage when momentum allows.

- **[Trade-off]** The Add Expense primary button leads to a placeholder until F-2.04 ships. Users tapping it today see `Text("Add Expense")` in a sheet. We accept this because (a) the placeholder behavior was already in production after the previous commits and (b) this change must not exceed scope into F-2.04. The verify checklist will note this so it is not surprising at archive review.

## Migration Plan

No data or schema migration. SwiftData and CloudKit see no model changes.

For the plural-rule fix:

1. Update `Resources/Localizable.xcstrings` — open the entry `budgetDetail.resetBudget.dialog.message` in Xcode's String Catalog editor, switch to a plural variation, and add `one` and `other` source strings (en-US):
   - `one`: "All %lld expense will be permanently deleted and the carry-over balance will be reset to zero."
   - `other`: "All %lld expenses will be permanently deleted and the carry-over balance will be reset to zero."
2. Replace the existing call site in `BudgetDetailView.swift` (`String(localized:defaultValue:comment:)` with manually-chosen `expenseWord`) with a `Text(_, comment:)` call that uses the catalog key with one `Int` interpolation.
3. Run previews on the "Current & Past Months" and "Empty" fixtures to spot-check both buckets.
4. Run `make test` to verify the build still compiles cleanly.

Rollback: revert the two-line code change and the catalog edit. No persisted state is involved.

## Open Questions

- _None blocking apply_. One nice-to-have: if `docs/main-prd.md` ever pivots Reset Budget into a deeper "archive then reset" pattern (e.g., expense history stored in a "trash" partition), this change's spec language for Reset Budget would need to be revisited. Out of scope for this change; flagged for future planners.
