## Why

The current `BudgetsView` (shipped in #24, navigation wiring in #25) covers most of F-2.01 — name, remaining, carry-over chip, settings entry, add-budget toolbar, and 1-tap add-expense per row — but a prior gap analysis shows two contracts that are still missing relative to `docs/product-features-planning.md`:

- **F-2.06 — first-run empty state:** with the seeder removed (archive `2026-04-24-remove-first-run-seeder`), an empty store renders a blank list. F-2.06 requires a title, short description, and a primary "Create a budget" CTA on first launch.
- **Drag-to-reorder (new acceptance criterion for F-2.01):** `Budget.sortOrder` already exists in the schema and the view already reads `@Query(sort: \Budget.sortOrder)`, but there is no UI to set it. The user has asked that the Budgets list support drag-to-reorder with persistence so the order syncs through CloudKit.

Closing both gaps in one change keeps the F-2.01 / F-2.06 contracts coherent (both share the same `List` and `ForEach` structure on `BudgetsView`) and avoids a second pass over the file.

> **Scope note (revised):** An earlier draft of this change also added swipe-to-delete with confirmation for Budgets. That requirement has been removed from this proposal and from F-2.01 in `docs/product-features-planning.md`. A future change can re-introduce a delete UX if and when product needs it; this change is now strictly empty-state + drag-to-reorder.

## What Changes

- **Add the F-2.06 first-run empty state to `BudgetsView`.** When `@Query(sort: \Budget.sortOrder) budgets` is empty, the view renders an empty-state composition (SF Symbol, localized title, localized description, and a primary "Create a budget" button) **in place of** the `List`. The CTA invokes `router.sheet = .addBudget` — the same action as the toolbar `+`. The empty-state view is reused for first-run and for any future state in which the store transiently presents zero budgets (e.g., during initial CloudKit hydration on a fresh install of an existing iCloud account).
- **Add drag-to-reorder with persistence.** The `ForEach` gets an `.onMove(perform:)` handler that rewrites `Budget.sortOrder` for every affected row in a single `context.save()`. Since `@Query` already sorts by `sortOrder`, the user sees their new order immediately and CloudKit syncs the new order to the user's other devices. iOS edit-mode entry uses the standard `EditButton` toolbar idiom; long-press drag remains available for non-edit-mode reorder where the platform supports it (List in iOS 16+ supports long-press reorder out of the box). When the list is empty, the empty state is shown instead of an empty edit mode.
- **Update F-2.01 in `docs/product-features-planning.md`** to add a "Drag-to-reorder budgets, persisted via `Budget.sortOrder`" acceptance criterion **and** to remove the "Delete Budget — swipe-to-delete on a row with confirmation" acceptance criterion. F-2.06 wording from the prior change stays as-is.
- **No data-model schema changes.** `Budget.sortOrder` (`Int`, default `0`) already exists per `openspec/specs/data-models/spec.md` ("Budget sortOrder assignment"). No CloudKit record-type changes; no migration.
- **No breaking API changes.** No public type, enum, or service signature changes. `BudgetLifecycleService`, `Router`, `AppRoute`, `SheetRoute`, and `Budget` keep their current shapes.

## Capabilities

### New Capabilities

- `budgets-screen`: Behavior contract for the root **Budgets screen** as it relates to the first-run empty state and drag-to-reorder with persisted ordering. This capability is intentionally scoped to the F-2.01 / F-2.06 acceptance criteria that this change introduces; the rest of F-2.01 (rows, remaining, carry-over chip, toolbar, 1-tap add-expense) is already implemented but not yet codified in `openspec/specs/` and is explicitly **out of scope** for this change. A follow-up change will retroactively spec the existing `BudgetsView` behavior under this same capability so future requirements share one home.

### Modified Capabilities

_(none — `data-models`, `budget-lifecycle`, `budget-math`, `app-settings`, and `schema-versioning` are unaffected. `Budget.sortOrder` is already specified under `data-models`; this change consumes it without changing its requirements.)_

## Impact

- **Modified code:**
  - `simple-recurring-budgets/Views/BudgetsView.swift` — replace the bare `List { ForEach(budgets) … }` with: (a) a top-level branch that switches between the empty state and the populated list based on `budgets.isEmpty`; (b) `.onMove(perform: move)` on the `ForEach`; (c) toolbar additions for `EditButton` (placement TBD in design.md, hidden when the list is empty).
  - `simple-recurring-budgets/Resources/Localizable.xcstrings` — new strings for: empty-state title; empty-state description; "Create a budget" CTA; reorder accessibility hint (or rely on system localizations for `EditButton` if used).
- **New code:**
  - `simple-recurring-budgets/Views/BudgetsEmptyStateView.swift` (or an equivalent private view inside `BudgetsView.swift`) — the empty-state composition. Decision deferred to design.md.
- **New tests:**
  - Swift Testing unit tests covering: (1) `.onMove` correctly rewrites `sortOrder` for affected rows and persists; (2) empty-state branch renders when no budgets exist and the CTA sets `router.sheet = .addBudget`. UI behaviour beyond unit coverage stays in preview / smoke testing per `docs/tech-design-doc.md` §5.3.
- **Localization / Accessibility:**
  - Every new user-facing string lives in `Localizable.xcstrings` with a `comment:` for translators.
  - The empty-state CTA button SHALL be a real `Button` (not a tap-gesture wrapper) so `largeContentViewer`, Dynamic Type, and VoiceOver labels work as expected.
  - Reorder mode SHALL announce its activation through the system `EditButton` (which already supplies localized "Edit" / "Done" labels and VoiceOver hints).
- **Persistence / Sync:** Drag-to-reorder writes only `sortOrder` (and `lastModified`) on affected `Budget` rows, batched in one `context.save()`. CloudKit's last-writer-wins semantics (`docs/tech-design-doc.md` §4.4) are acceptable for ordering — concurrent reorders from two devices will converge to whichever wrote last, which matches user expectation for personal-device sync.
- **No new dependencies.** No SwiftData schema migration. No CloudKit container changes.

## Doc alignment

- **Aligned with `docs/main-prd.md`** — no global constraints touched. PRD §6.7 (carry-over) is unaffected.
- **Aligned with `docs/tech-design-doc.md`** — the screen escalation criteria in §2.1 do **not** trigger a ViewModel here: reorder is a simple in-view interaction with no draft state, no async work, no multi-step chaining, and no expensive derived display state. Per §2.1 ("View + Services, ViewModels on demand"), `BudgetsView` stays a plain SwiftUI view.
- **Conflict with `docs/product-features-planning.md` §F-2.01** — F-2.01 today does not list drag-to-reorder, and (after the scope revision) no longer lists swipe-to-delete. Resolution: **update the doc** to add the new "Drag-to-reorder" acceptance criterion and remove the obsolete "Delete Budget — swipe-to-delete" bullet. F-2.06 wording is already correct (set by archive `2026-04-24-remove-first-run-seeder`); no edit needed there.
- **No conflict with `docs/main-prd.md`** — empty-state UX details are below the PRD's altitude.
- **Doc updates required after implementation:**
  - `docs/product-features-planning.md` (F-2.01 — add reorder acceptance criterion, remove swipe-to-delete acceptance criterion; cross-check F-2.06 wording is unchanged)
  - `docs/tech-design-doc.md` — version-history bump only if any architectural note changes; otherwise no edits expected. Decision deferred to design.md.
