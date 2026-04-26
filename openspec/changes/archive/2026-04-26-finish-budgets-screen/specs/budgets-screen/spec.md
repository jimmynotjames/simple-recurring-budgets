<!--
  This delta introduces the `budgets-screen` capability for the first time.
  Scope is intentionally narrow: it codifies only the two F-2.01 / F-2.06
  acceptance criteria added by this change (first-run empty state and
  drag-to-reorder). The remainder of F-2.01 (rows, remaining, carry-over
  chip, toolbar entries, 1-tap add-expense) is implemented in
  `simple-recurring-budgets/Views/BudgetsView.swift` but not yet codified
  here; a follow-up change will retroactively spec that behaviour under
  this same capability.

  Note: an earlier draft of this delta also defined a "Swipe-to-delete with
  confirmation" requirement and a "Pop pushed detail when its Budget is
  deleted from the list" requirement. Those have been removed because the
  swipe-delete acceptance criterion has been removed from F-2.01 in
  `docs/product-features-planning.md`.
-->

## ADDED Requirements

### Requirement: First-run empty state

When `@Query(sort: \Budget.sortOrder)` returns zero `Budget` rows, the Budgets screen SHALL render an empty-state composition in place of the row list. The empty state SHALL contain:

- A title (localized).
- A short description (localized).
- A primary, prominently presented **Create a budget** button (localized).
- A neutral SF Symbol illustrating "no items" (`tray` or equivalent).

Activating the **Create a budget** button SHALL set `Router.sheet = .addBudget`, which is the same code path as the toolbar `+` add-budget button.

The branch condition is `budgets.isEmpty` and is the only condition that selects the empty state. The same empty-state view SHALL therefore be rendered both on first launch (F-2.06) and in any future state in which `@Query` transiently returns zero rows (e.g., during initial CloudKit hydration on a fresh install of an existing iCloud account).

The Settings (gearshape) and Add Budget (`+`) toolbar entries SHALL remain visible in the empty state. The Edit toolbar entry, if present, SHALL be hidden when there are zero rows to reorder.

#### Scenario: First launch with empty store

- **WHEN** the app launches for the first time and the SwiftData store contains zero `Budget` records
- **THEN** the Budgets screen SHALL display the empty-state title, description, SF Symbol, and the **Create a budget** button — NOT a blank list.

#### Scenario: Tapping the empty-state CTA

- **WHEN** the user taps the **Create a budget** button on the empty state
- **THEN** the system SHALL set `Router.sheet = .addBudget`, presenting the Add/Edit Budget sheet exactly as if the user had tapped the toolbar `+` button.

#### Scenario: Empty state hides the Edit toolbar entry

- **WHEN** the empty state is rendered (zero `Budget` rows in the store)
- **THEN** the toolbar SHALL NOT show an Edit / Done entry; the Settings (gearshape) and Add Budget (`+`) entries SHALL remain visible.

#### Scenario: Adding a budget exits the empty state

- **WHEN** the empty state is rendered and the user creates a `Budget` via the Add/Edit Budget sheet (regardless of whether they entered the sheet via the empty-state CTA or the toolbar `+`)
- **THEN** the Budgets screen SHALL re-render as the populated list with that new `Budget` as the only row, and the empty state SHALL no longer be visible.

---

### Requirement: Drag-to-reorder budgets persisted via Budget.sortOrder

The Budgets screen SHALL allow the user to reorder rows via SwiftUI's `.onMove(perform:)` modifier on the row `ForEach`. The reorder gesture SHALL be discoverable through a standard `EditButton` toolbar entry placed on the leading edge of the navigation bar alongside the existing Settings (gearshape) entry. Long-press-drag-to-reorder SHALL also be available wherever the platform's `List` enables it for `.onMove`-bearing `ForEach`s.

When a reorder occurs, the system SHALL rewrite `Budget.sortOrder` densely as `0..<reordered.count` over the new order. The system SHALL also bump `Budget.lastModified = Date()` on every `Budget` whose `sortOrder` value actually changed. All affected writes SHALL be batched into a single `ModelContext.save()` call.

The new order SHALL persist across app relaunches and SHALL sync to the user's other iCloud-paired devices through the existing CloudKit pipeline. No new schema fields SHALL be introduced; the existing `Budget.sortOrder` (`Int`) attribute (specified under the `data-models` capability) is the sole ordering key.

The `EditButton` toolbar entry SHALL be hidden when the list is empty.

#### Scenario: User reorders rows in edit mode

- **WHEN** the user taps the `EditButton`, drags a row from index 2 to index 0, then taps `Done`
- **THEN** the system SHALL rewrite `sortOrder` for the affected `Budget` rows so that the moved row's `sortOrder` becomes `0` and the previously-leading rows' `sortOrder` values shift accordingly, all written in a single `ModelContext.save()`.

#### Scenario: New order persists across launches

- **WHEN** the user reorders rows, terminates the app, and relaunches
- **THEN** the Budgets screen SHALL display the rows in the order set by the most recent reorder, because `@Query(sort: \Budget.sortOrder)` reads the persisted values.

#### Scenario: lastModified bumps only on rows whose sortOrder actually changed

- **WHEN** the user reorders rows such that some row's `sortOrder` value would be unchanged after the dense rewrite (e.g., a row at index 0 stays at index 0)
- **THEN** that row's `lastModified` SHALL NOT be bumped, and only rows whose `sortOrder` actually changed SHALL have their `lastModified` updated to the current `Date()`.

#### Scenario: Edit button hidden when list is empty

- **WHEN** the user has zero `Budget` rows
- **THEN** the toolbar SHALL NOT show the `EditButton` (no rows to reorder); the empty state SHALL be visible per the empty-state requirement.

#### Scenario: Reorder writes a single save

- **WHEN** the user moves a row, triggering the `.onMove` handler
- **THEN** the system SHALL update all affected `Budget.sortOrder` (and `Budget.lastModified`) values and call `ModelContext.save()` exactly once, NOT once per row.

#### Scenario: Long-press drag in non-edit mode

- **WHEN** the platform's `List` enables long-press-drag-to-reorder for an `.onMove`-bearing `ForEach`, and the user long-presses a row outside of edit mode and drags it
- **THEN** the system SHALL apply the same dense `sortOrder` rewrite, the same `lastModified` bump rule, and the same single `ModelContext.save()` call as in edit mode.
