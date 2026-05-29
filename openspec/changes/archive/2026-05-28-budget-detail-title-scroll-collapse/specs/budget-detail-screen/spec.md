## MODIFIED Requirements

### Requirement: Budget detail screen is the resolved destination of `AppRoute.budgetDetail`

`RootView` SHALL resolve `AppRoute.budgetDetail(Budget)` to `BudgetDetailView(budget:)` (no longer a placeholder `Text`). The screen SHALL set `navigationBarTitleDisplayMode(.inline)` and apply `appBackground()`. The screen SHALL NOT set a string `navigationTitle`; the budget title is rendered as scroll-aware content per the "Scroll-aware content-area budget title" requirement.

The screen SHALL render its primary content as a SwiftUI `List` with `listStyle(.insetGrouped)` and `scrollContentBackground(.hidden)` so the `appBackground()` color shows through.

#### Scenario: Drill into Budget detail from the Budgets row

- **WHEN** the user taps a `Budget` row's drill-in button on the Budgets screen
- **THEN** `AppRoute.budgetDetail(budget)` is appended to `router.path` and `RootView` pushes `BudgetDetailView(budget: budget)` onto the navigation stack, which renders the budget's icon + name as a scroll-aware content title (not a string navigation title)

#### Scenario: AppBackground shows through the list

- **WHEN** the detail screen renders
- **THEN** the named asset color `AppBackground` is visible behind the list (`scrollContentBackground(.hidden)`) and the navigation bar (`appBackground()` modifier)

## ADDED Requirements

### Requirement: Scroll-aware content-area budget title

The Budget detail screen SHALL render the budget's icon + name as a content-area large title rather than a string `navigationTitle`, so the title can place the icon on the leading edge (RTL-correct), wrap long names, and collapse into the inline navigation bar on scroll.

The expanded title SHALL be the first row of the screen's `List`, rendered as a leading-aligned `HStack` in which the budget's `icon` (when set) is a leading **view** (decorative), followed by the budget `name`. It SHALL use large-title font size with bold weight, support Dynamic Type, and wrap to multiple lines (no single-line truncation) so a long name displays in full. When no icon is set, only the name is rendered.

As the user scrolls the list up, once the expanded title has substantially scrolled beneath the navigation bar, an inline navigation-bar title SHALL fade in. The inline title SHALL render the same icon (leading view, decorative) + name in the navigation bar, truncated to a single line. When the user scrolls back to the top, the inline title SHALL fade back out and the expanded content title SHALL be fully visible.

The expanded content title SHALL expose the budget `name` as its VoiceOver label (the icon is decorative and SHALL NOT be announced) and SHALL carry the `.isHeader` trait, consistent with the Budgets list row.

#### Scenario: Title shows icon on the leading edge in LTR and RTL

- **WHEN** the detail screen is shown for a budget that has an icon
- **THEN** the expanded content title renders the icon as a leading view followed by the name — on the left in LTR and on the right (the leading edge) in RTL — mirroring the Budgets list row rather than pinning the emoji to the left

#### Scenario: Long budget name wraps in the expanded title

- **WHEN** the detail screen is shown for a budget whose name is too long for one line
- **THEN** the expanded content title wraps to multiple lines and displays the full name (it does not truncate)

#### Scenario: Expanded title collapses into the inline nav-bar title on scroll

- **WHEN** the user scrolls the list up so the expanded title moves substantially beneath the navigation bar
- **THEN** an inline navigation-bar title (icon as a leading view + single-line truncated name) fades in, preserving the icon's leading-edge placement; scrolling back to the top fades it out again

#### Scenario: Title without an icon

- **WHEN** the detail screen is shown for a budget with no icon
- **THEN** both the expanded content title and the inline nav-bar title render the budget name alone, with no leading icon view

#### Scenario: VoiceOver announces the name only and marks the title as a header

- **WHEN** VoiceOver focuses the expanded content title
- **THEN** it announces the budget `name` alone (the icon is decorative and not announced) and the element carries the `.isHeader` trait
