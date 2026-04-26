## Context

`BudgetsView` (in `simple-recurring-budgets/Views/BudgetsView.swift`) renders a `List { ForEach(budgets) { BudgetRowView(budget:) } }` against `@Query(sort: \Budget.sortOrder)`. It already covers most of F-2.01: name, **Remaining for current Budget Period** (via `BudgetLifecycleService.refreshAndSave`), the carry-over chip (gated on `Budget.isCarryOverEnabled`), the toolbar's Settings entry (left) and Add-Budget entry (right), and the 1-tap add-expense `+` per row. Navigation is a `NavigationStack` driven by an `@Observable` `Router` (`path: [AppRoute]`, `sheet: SheetRoute?`); the only `AppRoute` case is `.budgetDetail(Budget)`.

Two things are missing relative to `docs/product-features-planning.md`:

1. **First-run empty state (F-2.06).** `budgets.isEmpty` is not handled — the `List` simply renders nothing. F-2.06 (rewritten under archive `2026-04-24-remove-first-run-seeder`) requires a title, short description, and primary "Create a budget" CTA.
2. **Drag-to-reorder (new acceptance criterion for F-2.01).** `Budget.sortOrder` exists in `data-models` and the `@Query` already sorts by it; no UI writes to it.

> **Scope note (revised):** An earlier revision of this design also covered swipe-to-delete with confirmation (and a related "pop pushed detail when its Budget is deleted" navigation rule). Those decisions have been removed because the swipe-delete acceptance criterion has been removed from F-2.01. If a future change re-introduces an in-app delete UX, those decisions can be lifted back from the change's git history.

Constraints in play:

- `docs/tech-design-doc.md` §2.1 ("View + Services, ViewModels on demand") — none of the four escalation triggers apply (no draft state, no async work, no multi-step chaining, no expensive derived display state). `BudgetsView` stays a plain SwiftUI view; transient state lives in the view.
- `docs/tech-design-doc.md` §4.1 — last-writer-wins CloudKit semantics are acceptable for `sortOrder` rewrites.
- `docs/ux-design-brief.md` — "calm, tidy, quietly warm." Avoid alarm reds and exclamation marks. Use SF Symbols. Iconography in default skin: SF Symbols only.
- `docs/main-prd.md` §6.4 — Dynamic Type and VoiceOver are baseline. Strings live in `Localizable.xcstrings` per `docs/tech-design-doc.md` §5.1 with `comment:` for translators.

## Goals / Non-Goals

**Goals:**

- Render an empty-state composition (SF Symbol + localized title + localized description + primary "Create a budget" CTA) whenever `budgets.isEmpty`. This view is the F-2.06 first-run empty state.
- Add drag-to-reorder using SwiftUI's `.onMove(perform:)` on the `ForEach`, gated by an `EditButton` toolbar entry. Persist new ordering by rewriting `Budget.sortOrder` for affected rows in a single `context.save()`.
- Keep the `Localizable.xcstrings` catalog as the only home for new user-facing strings. Provide explicit `comment:` arguments for all of them.
- Keep `BudgetsView` a plain SwiftUI view (no ViewModel introduced).

**Non-Goals:**

- Retroactively codifying the **rest** of F-2.01 (rows, remaining, carry-over chip, toolbar, 1-tap add-expense) into `openspec/specs/budgets-screen/`. That belongs to a separate "document existing implementation" change called out in the proposal. The capability spec in this change SHALL contain only the two new requirement areas.
- iPad / Mac split-view layout. Introducing `NavigationSplitView` is out of scope.
- Any in-app **delete Budget** UX (swipe, button, menu, etc.). The previously-proposed swipe-to-delete with confirmation has been removed from F-2.01 and is not in scope here. The data model still supports deletion at the SwiftData layer; this change simply does not surface it.
- Any change to `Budget.sortOrder` defaults, allocation, or any other model field.
- Any new `AppRoute` / `SheetRoute` case. The empty-state CTA reuses `.addBudget`.
- Any haptic feedback beyond what `EditButton` provides for free. The UX brief calls for restraint.

## Decisions

### Decision 1: Empty-state branch as a sibling view, not a stub row in the `List`

**Choice:** `BudgetsView.body` switches on `budgets.isEmpty`:

- `false` → the existing `List { ForEach(budgets) { BudgetRowView(budget: $0) } }` plus its toolbar.
- `true` → a `BudgetsEmptyStateView` (private struct in the same file or in `Views/BudgetsEmptyStateView.swift` — file split decided in the implementing PR; no architectural meaning either way) rendered in place of the list. The toolbar SHALL still show the Settings (left) and Add-Budget (right) entries so the user can also reach Settings or open the add-budget sheet from the toolbar from the empty state.

**Alternatives considered:**

- `**ContentUnavailableView`** (iOS 17+). This is the system-canonical empty-state view (icon, title, description, optional action). The app is iOS-26-only (PRD §6.1 — latest major OS), so `ContentUnavailableView` is available. **We adopt it.** The empty-state view delegates to `ContentUnavailableView` with a custom `actions` block containing the primary "Create a budget" `Button`.
- **Custom hand-rolled empty state.** Rejected: re-implementing the system idiom adds visual drift from first-party apps and loses the platform's automatic Dynamic Type / VoiceOver / Dark Mode handling.
- **An empty `List` with a single placeholder row.** Rejected: looks broken; the user could try to tap a fake row.

**Rationale:** `ContentUnavailableView` is exactly what HIG wants for "this screen has nothing to show" (Mail uses it for empty mailboxes, Reminders for empty lists). It naturally adapts to Dynamic Type and Dark Mode, and provides VoiceOver's "no items" hint without manual labelling. The custom action block lets us provide the F-2.06-required "Create a budget" CTA.

**Empty-state copy (verbatim, English source — translated via `Localizable.xcstrings`):**

- Title key `budgets.empty.title`: `"No budgets yet"`.
- Description key `budgets.empty.description`: `"Create your budget to start tracking what you spend daily, weekly, biweekly, or monthly."` — sentence case; no exclamation marks; consistent with the UX brief's "calm, tidy" tone.
- CTA button key `budgets.empty.createBudget`: `"Create a budget"`.
- SF Symbol: `tray` (HIG-aligned "empty container" symbol; same family that Apple uses for empty-state Mail / Reminders contexts).

**CTA wiring:** The CTA button sets `router.sheet = .addBudget` — exactly the same code path as the toolbar `+` button. The same view is rendered whenever `budgets.isEmpty` is true, regardless of how the store reached that state.

### Decision 2: `EditButton` for reorder mode + `.onMove(perform:)` rewriting `sortOrder`

**Choice:** Add a leading-toolbar `EditButton()` (or a trailing-toolbar `ToolbarItem` next to the existing `+`, decided below). The `ForEach(budgets, id: \.persistentModelID)` gets `.onMove(perform: handleMove)`. `handleMove(from:to:)` reorders a local mutable copy of the `budgets` array, then writes `sortOrder = i` for `i in 0..<reordered.count` on each `Budget` (skipping rows where `sortOrder` would be unchanged), bumps each touched `Budget.lastModified = Date()`, and calls `context.save()` once.

**Toolbar placement:** Place the `EditButton` on `.topBarLeading` **next to** the existing Settings gear (using a single `ToolbarItemGroup(placement: .topBarLeading)` containing both). Rationale: the trailing edge is owned by the primary `+` action; pushing `EditButton` there would dilute that primary action and the iOS HIG places `Edit` / `Done` on the leading edge of list screens (Mail, Reminders, Photos). The Settings gear remains the leftmost item; `Edit` is between Settings and the title. When the list is empty, the `EditButton` SHALL be hidden (no rows to reorder) — implemented by gating the toolbar item on `!budgets.isEmpty`.

**Alternatives considered:**

- **Long-press-to-reorder without `EditButton`.** SwiftUI `List` supports long-press drag in non-edit-mode on iOS 16+, but discoverability is low and there is no consistent VoiceOver path. Rejected as the **sole** affordance, but it remains naturally available because `.onMove` enables it.
- **Custom drag handle column.** Rejected: out-of-style for the rest of the row; `EditButton` is the platform idiom and ships with localized "Edit" / "Done" labels for free.
- **Reorder via a separate "Reorder" sheet.** Rejected: extra screen; adds complexity for a behaviour that fits in the existing `List`.
- **Recompute `sortOrder` only for moved rows (sparse rewrite).** Rejected: adding a row that moves "1 → 5" forces every intermediate row to compact too. Rewriting `0..<count` densely is O(n) and avoids drift / collisions across CloudKit sync (especially given last-writer-wins). Skipping `lastModified` bumps for rows whose `sortOrder` value is unchanged keeps the audit footprint small.
- **Use a fractional float for sort key (gap-based ordering).** Rejected: floats are forbidden for monetary fields and not a fit for ordering keys either; integer rewrites are simpler and CloudKit-friendly. The schema specifies `Int` (`data-models` spec).

**Rationale:** The dense integer rewrite is the simplest, most predictable approach and it composes cleanly with the existing `@Query(sort: \Budget.sortOrder)`. CloudKit sync inherits the same last-writer-wins guarantees as any other field (`docs/tech-design-doc.md` §4.4); a concurrent reorder from two devices simply converges to whichever batch saved later, which is acceptable for personal-device sync. Bumping `lastModified` only on rows whose `sortOrder` actually changed keeps audit semantics consistent.

**Idle-state correctness:** `Budget.sortOrder` already gets a unique, monotonically increasing value at insert time per `data-models` ("Budget sortOrder assignment"). Today the values may have gaps if rows have been deleted; that is fine for `@Query` purposes (the sort is by integer, ties broken by SwiftData internals). After the first reorder, the rewrite densifies the values to `0..<count`, which is also fine.

### Decision 3: No new ViewModel; transient state stays in `BudgetsView`

**Choice:** No new `@State` properties beyond what SwiftUI already provides for the system idioms in use:

- The SwiftUI `EditMode` environment value is consumed by `EditButton` automatically; no explicit `@State` for it.
- The empty-state branch is a pure function of `budgets.isEmpty` (a `@Query` value); no transient state needed.

**Alternatives considered:**

- **Introduce `BudgetsViewModel`.** Rejected against `docs/tech-design-doc.md` §2.1: none of the four escalation triggers apply (no draft state, no async work, no multi-step chaining, no expensive derived display state). The grey-area protocol explicitly lists "more than 3 mutable form fields" — we have none.
- **Wrap reorder in a `BudgetReorderingService` in `Domain/`.** Rejected: there is no math, no orchestration across multiple types, and no second caller. The reorder handler is a small private method on `BudgetsView` (`func move(from: IndexSet, to: Int)`).

**Rationale:** Following §2.1 keeps the screen declarative and avoids speculative abstraction.

### Decision 4: Localization comment style and reuse

**Choice:** Every new key in `Localizable.xcstrings` follows the existing pattern in `BudgetsView.swift` — `String(localized: "key", defaultValue: "…", comment: "translator context")`. The translator comment SHALL note any context that would otherwise be ambiguous to a translator.

**Alternatives considered:**

- **Reuse the existing toolbar add-budget label for the empty-state CTA.** Rejected: the contexts differ (toolbar Add Budget is a noun-form `Image` button; the empty-state CTA is a verb-form sentence button "Create a budget"). Different keys give translators flexibility.

**Rationale:** Keeping per-context strings distinct in the catalog is cheap and avoids bad translations down the line.

### Decision 5: Tech-design doc edit scope

**Choice:** **No edit** to `docs/tech-design-doc.md` for this change. None of the architectural sections (§2 architecture, §3 data model, §4 persistence, §5 i18n/a11y/testing) materially change. The biggest behavioural addition (drag-to-reorder using `Budget.sortOrder`) is already covered by §3 (data model) and the existing `data-models` spec ("Budget sortOrder assignment").

**Alternatives considered:**

- **Add a §X.Y note about reorder.** Rejected: `Budget.sortOrder` is already documented; how the screen consumes it is screen-level detail, not architectural. Adding a note would set a precedent for over-documenting view code.
- **Bump version-history row anyway.** Rejected: the version history records architectural changes, not screen-level features. The last version-history entry (0.7) was a meaningful architectural removal (FirstRunSeeder); padding the table with non-architectural rows dilutes its signal.

**Rationale:** The only doc edit this change requires is updating F-2.01 in `docs/product-features-planning.md` (add the reorder acceptance criterion; remove the obsolete swipe-to-delete acceptance criterion). F-2.06 wording is already correct.

## Risks / Trade-offs

- **[Concurrent reorder from two devices via CloudKit]** → Last-writer-wins applied to `sortOrder` rewrites means two devices reordering simultaneously will resolve to whichever device's latest sortOrder values landed last. Mitigation: acceptable per `docs/tech-design-doc.md` §4.4 — single-user, personal-device sync, no destructive divergence. We do not introduce custom merge logic.
- **[Empty-state shown briefly during initial CloudKit sync]** → On a fresh install with iCloud-paired data, `@Query` returns `[]` for a moment before CloudKit hydrates rows. The user could see the empty state flicker. Mitigation: the empty state's CTA is benign even if accidentally tapped (it opens the add-budget sheet; the user can dismiss it). A future change can add a "loading" branch if the flicker proves disruptive in TestFlight; not worth pre-engineering.
- **[`EditButton` toolbar collisions with future split-view layout]** → If iPad/Mac later move the Budgets list into a `NavigationSplitView` sidebar, the `EditButton` placement may need to migrate to the sidebar's toolbar. Mitigation: the current placement (`.topBarLeading`) maps cleanly to a sidebar's leading toolbar in split-view; revisiting at that time is a small mechanical edit.
- **[Reorder writes during very large lists]** → A user with N budgets reorders one row → we rewrite up to N `sortOrder` values. Mitigation: N is bounded by user behaviour (a small handful of recurring budgets is the entire product premise). Even at N=100 the write batch is trivial. No optimization needed.

## Migration Plan

1. **Land this change as a single PR.**
  - `BudgetsView.swift` gains: empty-state branch via `ContentUnavailableView`; `EditButton` toolbar item gated on `!budgets.isEmpty`; `.onMove(perform:)` on the `ForEach`; private `move(from:to:)` handler implementing the dense `sortOrder` rewrite.
  - `Localizable.xcstrings` gains the new keys listed in Decisions 1 and 4.
  - `docs/product-features-planning.md` F-2.01 gains the drag-to-reorder acceptance criterion **and** loses the obsolete swipe-to-delete acceptance criterion.
  - Tests added in `simple-recurring-budgetsTests/Views/BudgetsViewTests.swift`: reorder handler `sortOrder` rewrite + `lastModified` bump rule, and empty-state branch decision (assert that the empty-state composition is rendered when `budgets.isEmpty`). UI behaviour (visual drag, edit-mode appearance) is validated by previews and smoke testing per `docs/tech-design-doc.md` §5.3.
2. **No data migration.** No schema change; no CloudKit container change; no `NSUbiquitousKeyValueStore` key added. Existing installs continue to read/write `Budget.sortOrder` exactly as before.
3. **Rollback strategy.** Revert the single PR. No data is lost: any reorder writes are just `Int` field updates. The empty-state view is purely additive UI and disappears with the revert.
4. **Smoke test matrix on a clean iPhone simulator (per `docs/tech-design-doc.md` §5.3):**
  - Fresh install, no budgets → empty state renders; tapping CTA opens add-budget sheet.
  - Add a budget → list view renders with the row; empty state is gone.
  - Tap `Edit` → drag handles appear; reorder rows; tap `Done` → new order persists across app relaunch.
  - Long-press on a row outside of edit mode → drag-to-reorder also works (SwiftUI `List` provides this for free with `.onMove`).
  - VoiceOver: `Edit` toolbar entry announces the localized system label.

## Open Questions

*(none — Decisions 1–5 cover all implementation-shape choices. Anything below is a deliberate non-question:)*

- The exact toolbar placement of `EditButton` is settled in Decision 2 (`.topBarLeading` group with the Settings gear).
- Whether to extract `BudgetsEmptyStateView` to its own file is a stylistic choice deferred to the implementing PR; no architectural significance.
- Long-press-drag-to-reorder outside of edit mode is naturally enabled by `.onMove` on iOS; no explicit gating is needed.
