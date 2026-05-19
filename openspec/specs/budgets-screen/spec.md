# Budgets screen

Root screen of the app presenting a list of recurring budgets with current-period remaining, carry-over chip, and one-tap Add Expense per row. Synced from change `budgets-screen` (2026-04-25). Updated from change `pause-resume-budget` (2026-05-16). Updated from change `specific-dates-period` (2026-05-18).

## Requirements

### Requirement: Budgets screen is the app's root navigation destination

The Budgets screen SHALL be the root destination of the app's primary `NavigationStack`. It SHALL display a vertical list of `Budget` rows ordered by `Budget.sortOrder` ascending, fetched reactively so that inserts, updates, and deletes from any source (user action, CloudKit sync) appear without manual refresh.

The screen SHALL provide a navigation title that reads "Budgets" in en-US (key `budgets.navigationTitle`) and is registered for localization.

#### Scenario: Root screen renders the list of budgets

- **WHEN** the app launches with one or more `Budget` records in the data store
- **THEN** the Budgets screen is the first screen displayed and shows one row per budget, ordered by `sortOrder` ascending

#### Scenario: List reflects data store changes reactively

- **WHEN** a `Budget` is inserted, updated, or deleted in the data store while the Budgets screen is visible
- **THEN** the list updates to reflect the change without requiring a manual refresh action

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

### Requirement: Toolbar provides Settings and Add Budget entry points

The Budgets screen SHALL expose two toolbar buttons hosted by the `NavigationStack`'s navigation bar:

- A leading button presenting the Settings sheet (`SheetRoute.settings`), shown with the `gearshape` SF Symbol.
- A trailing button presenting the Add Budget sheet (`SheetRoute.addBudget`), shown with the `plus` SF Symbol.

Each button SHALL provide a localized accessibility label and an accessibility hint distinct from the visible label, so VoiceOver users learn the destination ("Opens app settings", "Opens add budget form").

#### Scenario: Settings entry point

- **WHEN** the user activates the leading toolbar button
- **THEN** the Settings sheet is presented (route `SheetRoute.settings`)

#### Scenario: Add Budget entry point

- **WHEN** the user activates the trailing toolbar button
- **THEN** the Add Budget sheet is presented (route `SheetRoute.addBudget`)

#### Scenario: Toolbar buttons expose VoiceOver labels and hints

- **WHEN** VoiceOver focuses either toolbar button
- **THEN** the announced label and hint match the localized keys (`toolbar.settings.label` / `toolbar.settings.accessibilityHint`, `toolbar.addBudget.accessibilityLabel` / `toolbar.addBudget.accessibilityHint`)

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

---

### Requirement: Each row shows name, remaining for current period, and period label

Each `Budget` row SHALL display:

- The budget's `name` rendered with the system body font, allowing up to two lines.
- The current-period **remaining** amount formatted with the budget's `currencyCode` and rendered with the system large-title font using `monospacedDigit()` so amounts align across rows.
- A **period label** rendered in the system callout font, sourced from `Budget.periodDisplayLabel`. For recurring periods, this resolves to "Daily", "Weekly", "Biweekly", or "Monthly" via `BudgetPeriod.listLabel`. For `.specificDates` budgets, it resolves to the formatted date range produced by `Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)` over `Budget.startDate ..< Budget.endDate` (e.g., "May 8 – May 25" for same-year, "Dec 28, 2025 – Jan 5, 2026" for year-crossing). See `data-models` for the `Budget.periodDisplayLabel` definition.

The `remaining` value SHALL be the result of `BudgetLifecycleService.result(for:)` for that budget — i.e. the current period's allocation minus expenses for that period only, **not** offset by carry-over (per `docs/main-prd.md` §6.7). For `.specificDates` budgets, the "current period" is the entire `[startDate, endDate]` window per F-2.08.

When `remaining` is negative, the amount text SHALL be rendered in `Color.moneyDeficit`. When `remaining` is zero or positive, it SHALL be rendered in the primary text color.

#### Scenario: Positive remaining renders with primary color

- **WHEN** a budget's current-period `remaining` is positive
- **THEN** the row displays the formatted amount in the primary text color and the period label in the secondary text color

#### Scenario: Negative remaining renders in deficit color

- **WHEN** a budget's current-period `remaining` is negative
- **THEN** the row displays the formatted amount in `Color.moneyDeficit`

#### Scenario: Remaining is per-period, never offset by carry-over

- **WHEN** a budget has a non-zero carry-over amount and any expenses in the current period
- **THEN** the displayed `remaining` is computed only from this period's allocation and expenses, and is independent of the carry-over value

#### Scenario: Recurring period label uses BudgetPeriod.listLabel

- **WHEN** a budget has period `.weekly`
- **THEN** the period label renders the localized string "Weekly" (key `period.weekly`)

#### Scenario: Specific Dates period label renders as a date range

- **WHEN** a `.specificDates` budget has `startDate = 2026-05-08` and `endDate = 2026-05-25` and the user's locale is en-US
- **THEN** the period label renders "May 8 – May 25" (a single locale-aware interval string with the year omitted because both dates fall in the same year)

#### Scenario: Specific Dates period label across years includes the year

- **WHEN** a `.specificDates` budget has `startDate = 2025-12-28` and `endDate = 2026-01-05` and the user's locale is en-US
- **THEN** the period label renders an interval that includes the year on at least one endpoint (e.g. "Dec 28, 2025 – Jan 5, 2026")

### Requirement: Each row shows a fuel-gauge indicator bar that reflects current-period status

Each row SHALL display a horizontal indicator bar below the amount and period label that visualises the fraction of the current-period allocation still available:

- A 0–1 fraction (`remaining / allocation`, clamped to `[0, 1]`) governs the filled portion of the bar in the app's accent color when `remaining >= 0`.
- When `remaining < 0` the bar SHALL render fully filled in `Color.moneyDeficit` to signal an over-budget state.
- When `Budget.allocation` is `0`, the fraction SHALL collapse to `0` (empty bar) without dividing by zero.

The indicator bar SHALL be hidden from assistive technologies (`accessibilityHidden(true)`); the same information is conveyed in the row's accessibility label.

#### Scenario: Bar reflects 50% remaining

- **WHEN** a budget has `allocation = 100`, `remaining = 50`, and `remaining >= 0`
- **THEN** the bar renders with its filled portion at 50% width in the accent color

#### Scenario: Over-budget bar fills with deficit color

- **WHEN** a budget's current-period `remaining` is negative
- **THEN** the bar fills 100% of its width in `Color.moneyDeficit`

#### Scenario: Zero-allocation budget renders an empty bar

- **WHEN** a budget has `allocation = 0`
- **THEN** the bar renders with no filled portion (no division-by-zero, no over-budget signal triggered solely by the zero allocation)

#### Scenario: Indicator bar is hidden from VoiceOver

- **WHEN** VoiceOver focuses the row
- **THEN** the indicator bar is not announced as a separate element; the row's accessibility label conveys the remaining amount and over-budget state

### Requirement: Carry-over chip is shown only when carry-over is enabled

When `Budget.isCarryOverEnabled` is `true` AND `Budget.period != .specificDates`, the row SHALL display a `CarryOverChip` showing the budget's current `carryOverAmount` formatted with the budget's `currencyCode`. When `Budget.isCarryOverEnabled` is `false` OR `Budget.period == .specificDates`, the row SHALL omit the chip entirely (per F-2.08, the Carry-over chip is hidden for Specific Dates budgets regardless of the stored `isCarryOverEnabled` value).

The underlying `Budget.carryOverAmount` SHALL continue to be computed and persisted by `BudgetLifecycleService` regardless of the toggle (for recurring budgets), so re-enabling carry-over yields an immediately correct, up-to-date value (per `docs/main-prd.md` §6.7).

The chip SHALL render:

- An upward-arrow SF Symbol (`arrow.up`) when `carryOverAmount > 0`, a downward-arrow SF Symbol (`arrow.down`) when `carryOverAmount < 0`, and no arrow when `carryOverAmount == 0`.
- The formatted amount and a fixed localized label "carry-over" (key `carryOver.label`).
- A foreground color of `Color.moneySurplus` when the amount is `> 0` or `0`, and `Color.moneyDeficit` when the amount is `< 0`.
- A capsule background tinted with the same surplus/deficit color at low opacity. When `colorSchemeContrast == .increased`, the background opacity SHALL be reduced (from `0.15` to `0.05`).
- A trailing-label foreground opacity of `0.8` in default contrast and `1.0` in increased contrast.

The chip SHALL be a sibling of (not nested inside) the row's drill-in button, and SHALL carry the static-text accessibility trait.

#### Scenario: Carry-over chip omitted when toggle is off

- **WHEN** a budget has `isCarryOverEnabled == false`
- **THEN** the row does not render a `CarryOverChip`, regardless of the underlying `carryOverAmount` value

#### Scenario: Carry-over chip omitted for Specific Dates regardless of stored toggle

- **WHEN** a budget has `period == .specificDates` AND `isCarryOverEnabled == true` (e.g., a record arriving via CloudKit before this change shipped)
- **THEN** the row does NOT render a `CarryOverChip`; `.specificDates` budgets never display the chip

#### Scenario: Surplus chip renders with up arrow and surplus color

- **WHEN** a budget has `isCarryOverEnabled == true` and `carryOverAmount > 0`
- **THEN** the chip displays `arrow.up`, the formatted amount, the localized "carry-over" label, and uses `Color.moneySurplus` for foreground and tinted background

#### Scenario: Deficit chip renders with down arrow and deficit color

- **WHEN** a budget has `isCarryOverEnabled == true` and `carryOverAmount < 0`
- **THEN** the chip displays `arrow.down`, the formatted amount, the localized "carry-over" label, and uses `Color.moneyDeficit` for foreground and tinted background

#### Scenario: Zero-amount chip renders without an arrow

- **WHEN** a budget has `isCarryOverEnabled == true` and `carryOverAmount == 0`
- **THEN** the chip displays the formatted amount and the localized "carry-over" label, without any directional arrow, using surplus colors

#### Scenario: Increased-contrast tunes background opacity

- **WHEN** `colorSchemeContrast == .increased`
- **THEN** the chip's capsule background opacity is `0.05` (instead of `0.15` in default contrast) and the trailing label foreground opacity is `1.0` (instead of `0.8`)

### Requirement: Carry-over chip provides direction-aware accessibility labels

The `CarryOverChip` SHALL provide a single localized accessibility label that describes the chip's surplus, deficit, or zero state and includes the formatted amount where applicable. The label SHALL use distinct localization keys for each state so translators can render correct grammar and copy:

- `carryOver.accessibilityLabel.surplus` for `amount > 0`.
- `carryOver.accessibilityLabel.deficit` for `amount < 0`.
- `carryOver.accessibilityLabel.zero` for `amount == 0`.

#### Scenario: Surplus chip announces "surplus carry-over"

- **WHEN** VoiceOver focuses a chip with `amount > 0`
- **THEN** it announces the formatted amount followed by "surplus carry-over" (per the `carryOver.accessibilityLabel.surplus` key)

#### Scenario: Deficit chip announces "deficit carry-over"

- **WHEN** VoiceOver focuses a chip with `amount < 0`
- **THEN** it announces the formatted amount followed by "deficit carry-over" (per the `carryOver.accessibilityLabel.deficit` key)

#### Scenario: Zero chip announces "zero carry-over"

- **WHEN** VoiceOver focuses a chip with `amount == 0`
- **THEN** it announces "zero carry-over" (per the `carryOver.accessibilityLabel.zero` key) without a numeric amount

### Requirement: Each row provides a one-tap Add Expense button

Each row SHALL include a per-row Add Expense button that, when activated, presents the Add Expense sheet for that specific budget (`SheetRoute.addExpense(budget)`). The button SHALL:

- Be visually distinct from the row's drill-in target (a `plus.circle.fill` SF Symbol rendered with the tint color).
- Use a fixed minimum width of 60pt and a fixed minimum tap target height of 44pt, *not* scaling with Dynamic Type, so the touch target meets HIG at all text sizes while leaving room for amount text to grow.
- Provide a localized accessibility label that includes the budget's name (key `budget.row.addExpense.accessibilityLabel`) and an accessibility hint (key `budget.row.addExpense.accessibilityHint`).

This delivers the "fast expense logging" signature element from `docs/ux-design-brief.md` — one tap from the root screen to the Add Expense form for a specific budget.

#### Scenario: Tapping the per-row plus opens Add Expense for that budget

- **WHEN** the user taps the per-row `plus.circle.fill` button
- **THEN** the Add Expense sheet is presented for that specific budget (`router.sheet = .addExpense(budget)`)

#### Scenario: Add Expense button keeps a 44pt tap target at all Dynamic Type sizes

- **WHEN** Dynamic Type is set to any supported size, including the largest accessibility sizes
- **THEN** the per-row Add Expense button remains 60pt wide with at least 44pt tall tap target, and the row's text fields wrap or stack instead of crowding the button

### Requirement: Tapping the row drills into Budget detail

The row's name + amount + period + indicator bar region SHALL be wrapped in a single button. Activating that button SHALL push `AppRoute.budgetDetail(budget)` onto the navigation path. The carry-over chip and the per-row Add Expense button SHALL NOT be part of this tap target.

#### Scenario: Drill-in pushes Budget detail

- **WHEN** the user taps the row's primary content area (name / amount / period / bar)
- **THEN** `AppRoute.budgetDetail(budget)` is appended to the navigation path

#### Scenario: Tapping the chip does not drill in

- **WHEN** the user taps the carry-over chip
- **THEN** no navigation occurs (the chip is a static, informational element)

### Requirement: Row provides a single composed VoiceOver label that states budget name, remaining, and period

The row's drill-in button SHALL provide a single composed VoiceOver label that includes the budget's name, the remaining amount, and a period descriptor. The label SHALL use distinct localization keys for the on-budget and over-budget cases:

- `budget.row.accessibilityLabel` when `remaining >= 0`, including the budget name, formatted remaining amount, and inline period descriptor.
- `budget.row.accessibilityLabel.overBudget` when `remaining < 0`, including the budget name, the **positive** overage amount (i.e. `-remaining`), and the inline period descriptor.

The row SHALL also provide an accessibility hint describing the action (key `budget.row.accessibilityHint`, "Opens budget details").

The inline period descriptor SHALL be sourced from `Budget.periodInlineLabel`, which returns dedicated per-locale strings: `period.daily.inline`, `period.weekly.inline`, `period.biweekly.inline`, `period.monthly.inline` for recurring periods, and `period.specificDates.inline.budgetRow` (English source: "in this window") for `.specificDates`. This ensures the VoiceOver sentence reads naturally for each period type (e.g. "Coffee, $12.50 remaining this daily period" vs "Italy Trip, €941.00 remaining in this window").

#### Scenario: On-budget recurring row label

- **WHEN** VoiceOver focuses a recurring-period row whose `remaining >= 0`
- **THEN** the announced label uses key `budget.row.accessibilityLabel` and includes the budget name, the formatted positive remaining amount, and the inline period descriptor (e.g. "Coffee, $12.50 remaining this daily period")

#### Scenario: On-budget Specific Dates row label

- **WHEN** VoiceOver focuses a `.specificDates` row whose `remaining >= 0`
- **THEN** the announced label includes the budget name, the formatted positive remaining amount, and the Specific Dates inline descriptor (e.g. "Italy Trip, €941.00 remaining in this window")

#### Scenario: Over-budget row label uses positive overage amount

- **WHEN** VoiceOver focuses a row whose `remaining < 0`
- **THEN** the announced label uses key `budget.row.accessibilityLabel.overBudget` and includes the budget name, the **positive** overage amount (i.e. `|remaining|`), and the inline period descriptor; the negative sign is not announced literally

### Requirement: Row layout adapts at large Dynamic Type sizes

The row SHALL render the amount and period label using `ViewThatFits(in: .horizontal)` so the layout responds to the available width rather than a fixed `dynamicTypeSize` threshold. The first (preferred) child SHALL be a horizontal `HStack(alignment: .firstTextBaseline, spacing: amountSpacing)` containing the amount text and the period label, both with `.lineLimit(1)` so `ViewThatFits` correctly detects overflow. The fallback child SHALL be a vertical `VStack(alignment: .leading, spacing: amountSpacing)` containing the same two texts; in this fallback the period label SHALL omit `.lineLimit(1)` so it can wrap naturally on its own line. Row spacing and vertical padding SHALL scale with Dynamic Type via `@ScaledMetric`.

This requirement explicitly replaces the prior fixed-threshold behaviour (HStack below `.xxxLarge`, VStack at `.xxxLarge` and above). Switching to `ViewThatFits` ensures that long period labels (notably the date range produced for `.specificDates` budgets) wrap to the VStack at moderate Dynamic Type sizes where the HStack would have wrapped or truncated, while short labels ("Daily") stay inline even at larger sizes.

#### Scenario: Horizontal layout when content fits

- **WHEN** the amount and period label together fit within the available row width at their ideal one-line size
- **THEN** the layout uses the HStack child with both texts side-by-side aligned to the first text baseline

#### Scenario: Vertical layout when content does not fit

- **WHEN** the amount and period label together exceed the available row width (e.g. at larger Dynamic Type sizes, or for a long `.specificDates` date-range label)
- **THEN** `ViewThatFits` selects the VStack child, rendering the amount above the period label aligned to the leading edge

#### Scenario: Short period label stays inline at moderate sizes

- **WHEN** a recurring budget with period label "Daily" is rendered at `.xLarge` or `.xxLarge`
- **THEN** the layout remains horizontal (HStack child fits)

#### Scenario: Date-range label wraps to vertical at moderate sizes

- **WHEN** a `.specificDates` budget with period label "May 8 – May 25" is rendered at `.xxLarge` where the HStack would not fit
- **THEN** the layout switches to the VStack child, with the date range on its own line below the amount

### Requirement: Row renders paused presentation when budget lifecycle state is paused

When `BudgetLifecycleResult.lifecycleState == .paused` for the budget rendered by a row, the row SHALL apply a paused visual treatment to the lifecycle-driven values:

- The `remaining` amount label SHALL render with `.foregroundStyle(.secondary)` (the greyed value treatment) regardless of sign, overriding the default surplus / deficit color rules.
- The `RemainingBar` SHALL render with `.foregroundStyle(.secondary)` (overriding accent / `Color.moneyDeficit` tints).
- When `Budget.isCarryOverEnabled == true` (so the `CarryOverChip` is rendered per the existing carry-over-chip requirement), the chip's value foreground style SHALL be overridden to `.secondary`; its background capsule tint SHALL remain its existing surplus / deficit color (so the chip stays visually identifiable as a carry-over chip).
- Below the row's primary content area (name / amount / period / bar), the row SHALL render a single line of `.caption`/`.secondary` text containing the localized caption `chip.paused.caption.format` (en-US "Paused since %@") using `BudgetLifecycleResult.pausedSince` formatted via `Date.formatted(date: .abbreviated, time: .omitted)`. When `pausedSince` is `nil` (defensive — should not happen when `lifecycleState == .paused`), the caption SHALL be omitted.
- The row's composed VoiceOver label SHALL use a paused-state key (`budget.row.accessibilityLabel.paused`) that includes the budget's name, the formatted remaining amount, the inline period name, and the formatted `pausedSince` date. This is a distinct key from the existing on-budget / over-budget keys.

When `BudgetLifecycleResult.lifecycleState != .paused`, none of the paused-state treatments above SHALL apply; the row renders per the original requirements.

The paused presentation SHALL NOT affect the row's drill-in tap target, the per-row Add Expense button, or the swipe / reorder affordances. The user can still drill into a paused budget's detail screen, add an expense to it from the row's `plus.circle.fill` button (which presents `SheetRoute.addExpense(budget)` regardless of pause state — the date-bounds constraint lives in the Add/Edit Expense screen), and reorder the row.

#### Scenario: Paused row renders greyed value, greyed bar, and "Paused since" caption

- **WHEN** the lifecycle service returns `lifecycleState == .paused`, `remaining = 7.50`, and `pausedSince = 2026-05-01` for the budget rendered by a row
- **THEN** the row's `remaining` label and `RemainingBar` render with `.foregroundStyle(.secondary)`, and a `.caption`/`.secondary` line below the primary content reads "Paused since May 1, 2026"

#### Scenario: Paused carry-over chip stays visible with greyed value but tinted capsule

- **WHEN** `lifecycleState == .paused` and `Budget.isCarryOverEnabled == true`
- **THEN** the row's `CarryOverChip` continues to render with its formatted carry-over amount and its surplus / deficit background capsule color, but its value foreground style is overridden to `.secondary`

#### Scenario: Paused row VoiceOver label

- **WHEN** VoiceOver focuses a row whose budget is paused with `pausedSince = 2026-05-01`
- **THEN** the announced label uses key `budget.row.accessibilityLabel.paused` and includes the budget name, the formatted remaining amount, the inline period name, and "May 1, 2026"

#### Scenario: Paused row still supports row-level Add Expense

- **WHEN** the user taps the per-row `plus.circle.fill` button on a paused budget's row
- **THEN** `router.sheet = .addExpense(budget)` is set as it would be for an active budget (the Add/Edit Expense screen's date-bounds rules — see `add-edit-expense-screen` — handle the paused-state date constraint)

#### Scenario: Active row is unaffected by paused-state styling

- **WHEN** the lifecycle service returns `lifecycleState == .active` for the budget rendered by a row
- **THEN** the row renders per the original surplus / deficit color rules with no "Paused since" caption and no `.secondary` overrides

### Requirement: Row eagerly refreshes carry-over and remaining via the lifecycle service

Each row SHALL invoke `BudgetLifecycleService.result(for:)` for its budget:

- On task initialization keyed by the budget's `persistentModelID` (so the call is re-issued when the row's identity changes, e.g. row recycling).
- On `scenePhase` becoming `.active` while the row is on screen (so any period or reset boundaries crossed while the app was inactive are applied before the next render).

The row SHALL bind the returned `BudgetLifecycleResult.remaining` and `BudgetLifecycleResult.carryOverAmount` for display. When the lifecycle result is unavailable (initial state before the first call returns), the row MAY fall back to the budget's persisted `carryOverAmount`. The row SHALL NOT call `BudgetCalculator.rollCarryOver` or `checkScheduledReset` directly — `BudgetLifecycleService` is the sole entry point for the eager sequence.

#### Scenario: Refresh on row appearance

- **WHEN** the Budgets screen renders a row for a budget
- **THEN** `BudgetLifecycleService.result(for:)` is called for that budget within the row's `.task(id: budget.persistentModelID)`, and the returned `remaining` and `carryOverAmount` are bound to the row's display

#### Scenario: Refresh on scene activation

- **WHEN** the app transitions from `.inactive` or `.background` to `.active` while the Budgets screen is visible
- **THEN** each visible row re-invokes `BudgetLifecycleService.result(for:)` and re-binds the returned values

### Requirement: All user-visible strings are registered for localization

Every user-visible string introduced by the Budgets screen, the carry-over chip, and the period display extension SHALL use `String(localized:defaultValue:comment:)` with a stable kebab/dot-cased key, a default value (en-US source), and a `comment:` providing translator context. Strings SHALL be present in `Resources/Localizable.xcstrings`.

Per-locale forms SHALL be used for both display ("Daily") and inline ("daily") period names. Inline forms SHALL NOT be derived from display forms via `.lowercased()`.

#### Scenario: Period inline label uses dedicated localization key

- **WHEN** the row composes its accessibility label (which contains the inline period name)
- **THEN** the inline period name is sourced from a dedicated localization key (`period.daily.inline`, `period.weekly.inline`, `period.biweekly.inline`, or `period.monthly.inline`), not from `.lowercased()` of the list-label key

#### Scenario: All Budgets-screen strings are present in the catalog

- **WHEN** the app is built
- **THEN** `Resources/Localizable.xcstrings` contains entries for every key referenced by `BudgetsView`, `CarryOverChip`, and `BudgetPeriod+Display`, each with a `comment:` providing translator context

### Requirement: Money colors are exposed as semantic aliases for surplus and deficit

The system SHALL expose `Color.moneySurplus` and `Color.moneyDeficit` as `Color` extensions used by the Budgets screen and the carry-over chip for surplus/positive and deficit/negative money signals. The colors SHALL adapt automatically to light and dark mode.

High-contrast variants of these colors are intentionally not provided in this capability and may be introduced by a separate change (tracked under T-4 theming work in `docs/product-features-planning.md`).

#### Scenario: Surplus and deficit colors adapt to dark mode

- **WHEN** the user switches between light and dark appearance while the Budgets screen is visible
- **THEN** `Color.moneySurplus` and `Color.moneyDeficit` re-render in their dark-appropriate variants without requiring code changes
