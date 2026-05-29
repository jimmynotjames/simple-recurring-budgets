## MODIFIED Requirements

### Requirement: Drag-to-reorder budgets persisted via Budget.sortOrder

The Budgets screen SHALL allow the user to reorder rows via SwiftUI's `.onMove(perform:)` modifier on the row `ForEach`. The reorder gesture SHALL be discoverable through a standard `EditButton` toolbar entry placed on the leading edge of the navigation bar alongside the existing Settings (gearshape) entry. Long-press-drag-to-reorder SHALL also be available wherever the platform's `List` enables it for `.onMove`-bearing `ForEach`s.

When a reorder occurs, the system SHALL rewrite `Budget.sortOrder` densely as `0..<reordered.count` over the new order. The system SHALL also bump `Budget.lastModified = Date()` on every `Budget` whose `sortOrder` value actually changed. All affected writes SHALL be batched into a single call to the shared persistence-save helper (operation `reorder`), which throws on failure. If the helper throws, the reorder save failure is surfaced as an *interactive* save failure: the system SHALL present the standard save-error alert (see the `persistence-error-handling` capability) over the Budgets screen, and Retry SHALL re-attempt the same persistence-save. The reorder remains visible in the UI until the user retries or backs out; the in-memory `sortOrder` mutations stand until persistence succeeds (the next launch's `@Query(sort: \Budget.sortOrder)` reads whatever was actually persisted).

The new order SHALL persist across app relaunches and SHALL sync to the user's other iCloud-paired devices through the existing CloudKit pipeline. No new schema fields SHALL be introduced; the existing `Budget.sortOrder` (`Int`) attribute (specified under the `data-models` capability) is the sole ordering key.

The `EditButton` toolbar entry SHALL be hidden when the list is empty.

#### Scenario: User reorders rows in edit mode

- **WHEN** the user taps the `EditButton`, drags a row from index 2 to index 0, then taps `Done`, and the save succeeds
- **THEN** the system SHALL rewrite `sortOrder` for the affected `Budget` rows so that the moved row's `sortOrder` becomes `0` and the previously-leading rows' `sortOrder` values shift accordingly, all written in a single call to the persistence-save helper.

#### Scenario: New order persists across launches

- **WHEN** the user reorders rows, the save succeeds, the user terminates the app and relaunches
- **THEN** the Budgets screen SHALL display the rows in the order set by the most recent reorder, because `@Query(sort: \Budget.sortOrder)` reads the persisted values.

#### Scenario: lastModified bumps only on rows whose sortOrder actually changed

- **WHEN** the user reorders rows such that some row's `sortOrder` value would be unchanged after the dense rewrite (e.g., a row at index 0 stays at index 0)
- **THEN** that row's `lastModified` SHALL NOT be bumped, and only rows whose `sortOrder` actually changed SHALL have their `lastModified` updated to the current `Date()`.

#### Scenario: Edit button hidden when list is empty

- **WHEN** the user has zero `Budget` rows
- **THEN** the toolbar SHALL NOT show the `EditButton` (no rows to reorder); the empty state SHALL be visible per the empty-state requirement.

#### Scenario: Reorder writes a single save

- **WHEN** the user moves a row, triggering the `.onMove` handler
- **THEN** the system SHALL update all affected `Budget.sortOrder` (and `Budget.lastModified`) values and call the persistence-save helper exactly once, NOT once per row.

#### Scenario: Long-press drag in non-edit mode

- **WHEN** the platform's `List` enables long-press-drag-to-reorder for an `.onMove`-bearing `ForEach`, and the user long-presses a row outside of edit mode and drags it
- **THEN** the system SHALL apply the same dense `sortOrder` rewrite, the same `lastModified` bump rule, and the same single persistence-save-helper call as in edit mode.

#### Scenario: Failed reorder surfaces the save-error alert

- **WHEN** the user reorders rows and the persistence-save helper throws
- **THEN** the save-error alert is presented over the Budgets screen and Retry re-attempts the same persistence-save against the in-memory `sortOrder` mutations
