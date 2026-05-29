## Why

The Budget **detail** screen renders the budget icon + name with SwiftUI's string-based `navigationTitle(budget.iconPrefixedName)`. A `String` title has three limitations that all point to rendering the title as scroll-aware **content** rather than a nav-bar string: (1) a leading bidi-neutral emoji before strong text gets pinned to the **left** in RTL (Arabic) instead of the leading/right edge; (2) nav-bar titles **truncate** to one line, so long budget names can't display in full; (3) we can't keep the large-title look while controlling the large→inline collapse. The Budgets **list row** already fixed RTL by rendering the icon as a leading `HStack` view; this brings the detail title to parity (issue #117).

## What Changes

- Replace `.navigationTitle(budget.iconPrefixedName)` on the Budget detail screen with a **content-area large title** rendered as the first row of the screen's `List`.
- The content title renders the budget **icon as a leading `HStack` view** (decorative) followed by the **name**, so the icon sits on the leading edge and **mirrors correctly in RTL**, matching the list row and the Add/Edit picker chip.
- Long names **wrap to multiple lines** (full display) in the expanded state instead of truncating.
- The expanded large title **collapses/merges into a custom inline nav-bar title on scroll**: the screen uses `.navigationBarTitleDisplayMode(.inline)` and a `.principal` toolbar item (icon + single-line truncated name) that fades in once the content title scrolls under the bar, preserving large-title font size/weight semantics.
- VoiceOver announces the **name only** (icon decorative), consistent with the Budgets list row; the content title carries the `.isHeader` trait.
- The expanded title's typography matches the standard Apple/SwiftUI screen-title look (large-title size/bold weight, Dynamic Type) — it just wraps instead of truncating.

No data-model, persistence, or sync changes. No new user-facing strings (the title renders existing `budget.name` / `budget.icon`).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `budget-detail-screen`: the screen no longer sets `navigationTitle(budget.name)`; it sets `navigationBarTitleDisplayMode(.inline)` and renders a scroll-aware content large title (icon-leading, wrapping, collapsing into a principal toolbar title) with name-only VoiceOver and the `.isHeader` trait.
- `budget-icon`: the "Icon display on the Budget detail screen" requirement changes from "navigation title SHALL be prefixed with the budget's icon (a String)" to "the content-area large title SHALL render the icon as a **leading view** (not a string prefix) so it mirrors in RTL"; name-only is unchanged.

## Impact

- **Code**: `simple-recurring-budgets/Views/BudgetDetailView.swift` (title rendering, `List` structure, scroll tracking, toolbar). Possibly a small new title-header subview/file. `Budget.iconPrefixedName` (`Models/Budget+Display.swift`) loses its only production caller (the list row already uses a leading-view `nameText`); evaluate removing it or retaining for tests.
- **APIs**: introduces the first use of `onScrollGeometryChange` / `onGeometryChange` and a `.principal` toolbar item in this codebase (deployment target iOS 26.5).
- **Cross-cutting**: Accessibility (header trait, name-only VoiceOver, Dynamic Type wrapping) addressed. No new localized strings, so the translations pipeline is a no-op. No new user-initiated state-changing action, so no new Mixpanel event.
- **Docs**: F-4.03 acceptance criterion ("display the chosen icon … as a **prefix** of the budget name") wording should note the detail title now renders the icon as a leading **view** (RTL-correct), not a string prefix — update `docs/product-features-planning.md` as part of the change.

## Doc alignment

- `docs/main-prd.md` — no conflict; HIG, Dynamic Type, and i18n/RTL constraints are reinforced by this change.
- `docs/tech-design-doc.md` — no conflict; the detail screen stays a View with `@Query`/services and no ViewModel (the scroll-collapse state is trivial local `@State`, below the VM-escalation bar in §2.1).
- `docs/product-features-planning.md` (F-4.03) — minor wording update needed (icon as leading view vs. string prefix on the detail title); tracked as a task.
