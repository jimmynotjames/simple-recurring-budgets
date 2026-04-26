## 1. Wire transient view state in `BudgetsView`

- [x] 1.1 Add a private `move(from: IndexSet, to: Int)` instance method on `BudgetsView` that performs the dense `sortOrder` rewrite described in design.md → Decision 2. It SHALL: (a) construct a local mutable array of budgets in the new order from `IndexSet` + destination; (b) iterate `0..<reordered.count` and only mutate `reordered[i].sortOrder` and `reordered[i].lastModified` when the value changes; (c) call `try? context.save()` exactly once at the end.
- [x] 1.2 Confirm via grep that no new `@Observable` ViewModel file is added; the screen stays View+Services per `docs/tech-design-doc.md` §2.1 (verified against design Decision 3).

## 2. Empty-state composition

- [x] 2.1 Implement the empty-state UI using `ContentUnavailableView` (iOS 17+, available on the project's iOS 26 target). Decide between an inline private struct in `BudgetsView.swift` or a new file `simple-recurring-budgets/Views/BudgetsEmptyStateView.swift`; either is acceptable per design Decision 1.
- [x] 2.2 The empty state SHALL contain: SF Symbol `tray`; localized title `budgets.empty.title` (`"No budgets yet"`); localized description `budgets.empty.description`; primary `Button` labeled with `budgets.empty.createBudget` (`"Create a budget"`).
- [x] 2.3 The CTA button SHALL set `router.sheet = .addBudget` (no new `SheetRoute` cases). Confirm by reading `simple-recurring-budgets/App/SheetRoute.swift`.
- [x] 2.4 Branch `BudgetsView.body` on `budgets.isEmpty`: render the empty state in place of the `List` when empty; render the existing `List { ForEach ... }` otherwise. Toolbar items for Settings (gearshape) and Add Budget (`+`) SHALL remain visible in BOTH branches; only the `EditButton` SHALL be hidden when empty (see §3 below).

## 3. Drag-to-reorder via `EditButton` + `.onMove`

- [x] 3.1 Add `.onMove(perform: move)` to the `ForEach(budgets) { ... }` in `BudgetsView`. `id` is `\Budget.persistentModelID` (the default for `@Model` types under SwiftData and consistent with `\.persistentModelID` references elsewhere in the file).
- [x] 3.2 Add a new toolbar item: place an `EditButton()` at `.topBarLeading` adjacent to the existing Settings button. Recommended approach: change the existing single `ToolbarItem(placement: .topBarLeading)` for Settings into a `ToolbarItemGroup(placement: .topBarLeading)` containing both the Settings `Button` and a `if !budgets.isEmpty { EditButton() }` clause. Keep the current Settings button content (label, accessibility hint) verbatim.
- [x] 3.3 Verify in previews that long-press-drag-to-reorder also works outside of edit mode (SwiftUI `List` enables this automatically when `.onMove` is present). No additional code is required for this; it just needs to work.
- [x] 3.4 Verify that `lastModified` is bumped only on `Budget` rows whose `sortOrder` actually changed (design Decision 2; spec scenario "lastModified bumps only on rows whose sortOrder actually changed").

## 4. Localization strings

- [x] 4.1 Add the following keys to `simple-recurring-budgets/Resources/Localizable.xcstrings`, each via `String(localized: "key", defaultValue: "...", comment: "translator context")` at the call site:
  - `budgets.empty.title` — `"No budgets yet"`. Comment: empty-state title shown on the Budgets screen when no budgets exist.
  - `budgets.empty.description` — `"Create your first recurring budget to start tracking what you spend each day, week, biweek, or month."`. Comment: empty-state description on the Budgets screen.
  - `budgets.empty.createBudget` — `"Create a budget"`. Comment: primary CTA on the empty-state of the Budgets screen.
- [x] 4.2 Confirm `EditButton` does not need a localized override; the system supplies localized "Edit" / "Done" labels for free. (Only add a custom string here if a manual `Button` is used instead of `EditButton` — which we are not doing per design Decision 2.)
- [x] 4.3 Build the app once and confirm `Localizable.xcstrings` picks up the new keys automatically (the catalog is connected via the `PBXFileSystemSynchronizedRootGroup`; no `project.pbxproj` edits are needed per `docs/tech-design-doc.md` §5.1).

## 5. Tests (Swift Testing)

- [x] 5.1 In `simple-recurring-budgetsTests/Views/BudgetsViewTests.swift` (new file; create the `Views` test directory if it does not exist) using `@MainActor` and an in-memory `ModelContainer` from `simple-recurring-budgetsTests/Helpers/TestModelContainer.swift`, write tests using Swift Testing (`@Test`, `#expect`):
  - **5.1.a** A `move(from:to:)` test: insert three budgets with `sortOrder` `[0, 1, 2]`; invoke the move handler to move index `2 → 0`; assert resulting `sortOrder` values reflect the new dense order — that `@Query(sort: \Budget.sortOrder)` returns the rows in the user-intended order. Assert `lastModified` was bumped only on rows whose `sortOrder` actually changed.
  - **5.1.b** An empty-state branch test: with zero `Budget` rows, instantiate `BudgetsView` in a host hierarchy and inspect that the rendered view contains `ContentUnavailableView` rather than `List` content. (If the SwiftUI runtime under test makes this brittle, fall back to a thin `bodyForBudgets(_:)`-style helper that can be unit-asserted; document the fallback in the commit message.)
- [x] 5.2 Confirm none of the existing tests in `simple-recurring-budgetsTests/Domain/`, `simple-recurring-budgetsTests/Models/`, `simple-recurring-budgetsTests/Settings/`, or `simple-recurring-budgetsTests/Formatting/` need to change. Only the new `Views/` test file is added in this change.

## 6. Update `docs/product-features-planning.md`

- [x] 6.1 In F-2.01 ("Budgets screen") **Acceptance Criteria** list, add a new bullet: `- **Drag-to-reorder budgets** — user can reorder the list via standard iOS edit-mode drag (and long-press drag where the platform supports it); the order is persisted via Budget.sortOrder so it survives app relaunch and syncs across the user's iCloud-paired devices.`
- [x] 6.2 In the same F-2.01 acceptance-criteria list, **remove** the bullet `- **Delete Budget** — swipe-to-delete on a row with confirmation` (it is no longer in scope for the Budgets screen). Do NOT touch the corresponding bullet in F-2.02 (Budget detail / Expense Items), which is a separate feature.
- [x] 6.3 Confirm F-2.06 ("First-run empty state") wording is unchanged; cross-reference design Decision 1 to verify the empty-state copy matches the F-2.06 acceptance criteria ("title, short description, and a primary 'Create a budget' CTA — NOT a blank or unlabeled screen"). No edit needed if it matches.
- [x] 6.4 Grep `docs/product-features-planning.md` for any remaining cross-reference to "swipe-to-delete" on Budgets, "delete a budget" UX, or "blank list" framing that this change makes obsolete; update for consistency.

## 7. Confirm no other docs need editing

- [x] 7.1 Confirm `docs/tech-design-doc.md` needs no edit. Per design Decision 5, the architectural sections (§2 architecture, §3 data model, §4 persistence, §5 i18n/a11y/testing) are unchanged. No version-history bump for this change. If implementation surfaces a genuinely new architectural rule (it should not), add a follow-up task before archive.
- [x] 7.2 Confirm `docs/main-prd.md` needs no edit. Grep for "delete", "empty", "reorder", "sortOrder" — no global constraint discusses these at PRD altitude. PRD §6.7 (carry-over) is unaffected.
- [x] 7.3 Confirm `docs/ux-design-brief.md` needs no edit. The brief already establishes "calm, tidy, quietly warm" and "no exclamation marks", which the empty-state copy follows.

## 8. Build, test, and smoke-check

- [x] 8.1 Run `make test` (or `bash scripts/test.sh`) per `AGENTS.md` and `.cursor/rules/ios-build-test.mdc`. All existing tests SHALL pass; the new `Views/BudgetsViewTests.swift` SHALL pass.
- [x] 8.2 Smoke test on a clean iPhone simulator (matrix from design.md → Migration Plan §4):
  - **8.2.a** Fresh install with no budgets → empty state renders with title, description, SF Symbol, and CTA.
  - **8.2.b** Tap the empty-state CTA → add-budget sheet opens (toolbar `+` does the same).
  - **8.2.c** Add a budget → list view renders; empty state is gone.
  - **8.2.d** Tap `Edit` → drag handles appear; reorder rows; tap `Done` → terminate the app and relaunch → new order persists.
  - **8.2.e** Long-press a row outside of edit mode → drag-to-reorder also works without entering edit mode.

## 9. Archive this change

- [ ] 9.1 After all sections 1–8 are complete and `make test` passes, run `openspec archive finish-budgets-screen` (or follow the `openspec-archive-change` skill). Because this change introduces a new capability (`budgets-screen`), expect a new `openspec/specs/budgets-screen/spec.md` to be created from the delta on archive.
- [ ] 9.2 After archive, confirm: (a) `openspec/specs/budgets-screen/spec.md` exists with the two requirements introduced here; (b) `openspec/changes/` no longer contains `finish-budgets-screen/`; (c) `openspec/changes/archive/` contains a date-prefixed `finish-budgets-screen/` directory with the proposal, design, tasks, and original delta spec preserved.
