## MODIFIED Requirements

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

- **WHEN** a recurring budget has `isCarryOverEnabled == true` and `carryOverAmount > 0`
- **THEN** the chip displays `arrow.up`, the formatted amount, the localized "carry-over" label, and uses `Color.moneySurplus` for foreground and tinted background

#### Scenario: Deficit chip renders with down arrow and deficit color

- **WHEN** a recurring budget has `isCarryOverEnabled == true` and `carryOverAmount < 0`
- **THEN** the chip displays `arrow.down`, the formatted amount, the localized "carry-over" label, and uses `Color.moneyDeficit` for foreground and tinted background

#### Scenario: Zero-amount chip renders without an arrow

- **WHEN** a recurring budget has `isCarryOverEnabled == true` and `carryOverAmount == 0`
- **THEN** the chip displays the formatted amount and the localized "carry-over" label, without any directional arrow, using surplus colors

#### Scenario: Increased-contrast tunes background opacity

- **WHEN** `colorSchemeContrast == .increased`
- **THEN** the chip's capsule background opacity is `0.05` (instead of `0.15` in default contrast) and the trailing label foreground opacity is `1.0` (instead of `0.8`)

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
