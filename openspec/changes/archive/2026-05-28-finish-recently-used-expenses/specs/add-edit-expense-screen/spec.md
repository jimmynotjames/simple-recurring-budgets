## ADDED Requirements

### Requirement: Add Expense surfaces a Recents section above the Amount card (F-7.04)

In Add mode, the Add/Edit Expense screen SHALL render a "Recents" section above the Amount card when the bound budget has at least one prior expense item eligible to surface as a suggestion. In Edit mode, the section SHALL NOT render. When the bound budget has zero eligible candidates, the section SHALL NOT render at sheet-open and SHALL NOT later appear during the sheet's lifetime.

#### Scenario: Add mode with prior expenses shows the Recents section

- **WHEN** the user opens the Add Expense sheet for a budget that has at least one prior named, non-Add-Funds expense item
- **THEN** the screen renders a card titled "Recents" above the Amount card
- **AND** the card contains a horizontal scroll row of tappable tiles, one per candidate

#### Scenario: Add mode with no prior expenses hides the section

- **WHEN** the user opens the Add Expense sheet for a budget with no prior expense items (a brand-new budget)
- **THEN** the screen does not render the Recents card
- **AND** the form opens with the Amount card at the top of the scroll view

#### Scenario: Edit mode never shows the Recents section

- **WHEN** the user opens the Edit Expense sheet for an existing expense
- **THEN** the screen does not render the Recents card

### Requirement: Recents algorithm sorts by recency and dedupes by description

The candidate set surfaced in the Recents section SHALL be derived from `Budget.expenseItems` by:

1. Excluding Add Funds entries (`ExpenseItem.isAddFunds == true`) — they are not reusable as expense suggestions.
2. Excluding entries with no description (nil or whitespace-only `name`) — they are not actionable as suggestions.
3. Collapsing duplicates by description (case- AND diacritic-insensitive comparison after trimming whitespace, so "Café" / "cafe" / "CAFÉ" all collapse to one entry) — keeping only the most recent occurrence per unique description, with that occurrence's amount riding along.
4. Sorting the deduplicated set by date descending (most recent first).
5. Capping the result at an implementation-defined number.

The candidate set SHALL be computed at sheet-open and reused across keystrokes during typing; recomputing per-keystroke is forbidden because for budgets with many expenses, the sort would dominate the per-keystroke cost.

#### Scenario: Most recent occurrence per unique description wins

- **WHEN** the user opens Add Expense for a budget that has logged "Coffee" at $5.50 last week and "Coffee" at $6.00 yesterday
- **THEN** the Recents section shows one "Coffee" tile, showing $6.00 (the most recent occurrence's amount)

#### Scenario: Add Funds entries are excluded from the candidate set

- **WHEN** the user opens Add Expense for a budget whose history includes both expense entries and Add Funds entries
- **THEN** the Recents section only surfaces the expense entries

#### Scenario: Unnamed entries are excluded from the candidate set

- **WHEN** the user opens Add Expense for a budget whose history includes some expenses with no description
- **THEN** the Recents section only surfaces the named expenses

#### Scenario: Candidate set is capped at the implementation-defined limit

- **WHEN** the user opens Add Expense for a budget with more unique-named expenses than the implementation-defined cap
- **THEN** the Recents section surfaces no more than the cap, ordered most-recent-first

### Requirement: Tapping a Recents tile fills name + amount and resets Add Funds

A tap on a Recents tile SHALL write both `name` and `amount` to the draft (the in-memory `AddEditExpenseViewModel`) from the chosen suggestion AND SHALL reset the Add Funds toggle (`isAddFunds`) to off. A Recents tile represents a prior *expense*, so the toggle is reset to match that semantic; otherwise a user who toggled Add Funds on (and abandoned the action) would silently log the recent's positive amount as an add-funds adjustment. The tap SHALL NOT persist the expense — the user remains on the sheet to review and confirm via Save. The tap SHALL NOT alter the `date` field or other draft state.

#### Scenario: Tap fills name and amount but does not save

- **WHEN** the user taps a Recents tile labeled "Coffee · $5.50"
- **THEN** the Description field shows "Coffee"
- **AND** the Amount field shows $5.50
- **AND** the user remains on the Add Expense sheet
- **AND** no `ExpenseItem` is persisted

#### Scenario: Tap resets the Add Funds toggle to off

- **WHEN** the user has the Add Funds toggle on, then taps a Recents tile
- **THEN** the Add Funds toggle becomes off
- **AND** the draft's `name` and `amount` are set from the tapped suggestion

### Requirement: Recents section filters as the user types into Description

The Recents candidate set SHALL filter in place as the user types into the Description field, using a case-insensitive substring match against each candidate's name. The section SHALL stay on the same surface as the form — no separate picker view, sheet, or screen is presented. The candidate set displayed SHALL be the cached candidate set filtered by the current query; the cache SHALL NOT be recomputed.

#### Scenario: Typing into Description narrows the Recents row

- **WHEN** the user opens Add Expense and the Recents section shows tiles for "Coffee", "Lunch", and "Groceries"
- **AND** the user types "co" into the Description field
- **THEN** the Recents row shows only the "Coffee" tile (substring match)

#### Scenario: Filter is case-insensitive

- **WHEN** the Recents section contains a "Coffee" tile
- **AND** the user types "COFFEE" into the Description field
- **THEN** the "Coffee" tile remains visible

#### Scenario: Filter is diacritic-insensitive

- **WHEN** the Recents section contains a "Café" tile
- **AND** the user types "cafe" into the Description field
- **THEN** the "Café" tile remains visible
- **AND** the same equivalence is used to dedup the candidate set, so the user never sees both "Café" and "cafe" as separate tiles

### Requirement: Filter-empty Recents preserves layout via a "No matches" placeholder

When the user types into Description and the resulting filter yields zero matches, the Recents card SHALL remain mounted with a placeholder labeled with the localized equivalent of "No matches". The placeholder SHALL occupy the same vertical space as a populated tile row, so the form below does not shift while the user types. This SHALL apply only when the bound budget has candidate expenses; if the candidate set is empty (true-empty), the section is absent (per the section-visibility requirement above).

#### Scenario: Filter yields no matches but the card stays mounted

- **WHEN** the user opens Add Expense on a budget with prior expenses
- **AND** the user types text that matches no candidate (e.g., "xyz")
- **THEN** the Recents card stays mounted at the same height
- **AND** displays the localized "No matches" placeholder
- **AND** the Amount card directly below does not shift vertically

### Requirement: Recents surface is accessible to VoiceOver and Dynamic Type users

Each tappable Recents tile SHALL expose a composed `accessibilityLabel` that announces both the description and the formatted amount, and an `accessibilityHint` that explains the tap action ("Fills the amount and description for review."). The trailing swipe-affordance icon (when shown) SHALL be hidden from VoiceOver (`accessibilityHidden(true)`) because its meaning is reproduced by VoiceOver's natural scroll-container behavior. The "No matches" placeholder SHALL expose an `accessibilityLabel` distinct from the visible glyph (e.g., "No matching recent expenses"). The phantom-content sizing anchor used by the placeholder SHALL be hidden from VoiceOver.

Tile geometry — the maximum tile width and the inner padding values — SHALL scale with Dynamic Type via `@ScaledMetric(relativeTo: .subheadline)` so the section remains legible at larger type sizes.

#### Scenario: VoiceOver reads a Recents tile as one combined element

- **WHEN** a VoiceOver user focuses a Recents tile labeled visually as "Coffee · $5.50"
- **THEN** VoiceOver announces a single combined label including both the name and the formatted amount
- **AND** announces the hint that explains the tap fills the draft for review

#### Scenario: Decorative swipe icon is silent to VoiceOver

- **WHEN** the Recents row contains the trailing swipe-affordance icon
- **THEN** VoiceOver does not announce the icon as a separate element

#### Scenario: Tile geometry scales with larger Dynamic Type sizes

- **WHEN** the user has set Dynamic Type to a larger size (e.g., `xxxLarge`)
- **THEN** the Recents tile maximum width and padding grow proportionally relative to the subheadline text style

### Requirement: Recents UI strings are keyed in Localizable.xcstrings

All user-facing strings introduced by the Recents surface SHALL be registered in `Localizable.xcstrings` under the `addEditExpense.recents.*` namespace, with translator-friendly `comment:` text describing the surface, context, and any interpolated arguments. The keys SHALL be translated to all 38 App Store storefront locales via the `translate-new-strings` skill before the change ships.

The keys SHALL include at minimum: the section title, the "No matches" placeholder copy, each accessibility label and hint introduced by the accessibility requirement, and any future-tense strings the implementation surfaces.

#### Scenario: All visible Recents strings have localization keys

- **WHEN** an auditor inspects the Recents surface source
- **THEN** no bare-literal `Text("…")` calls appear on user-visible strings under the `addEditExpense.recents.*` surface
- **AND** every string is a `String(localized:defaultValue:comment:)` call (or equivalent) under the `addEditExpense.recents.*` namespace

#### Scenario: Translations exist for all 38 storefront locales

- **WHEN** `python scripts/translate_catalog/check_translations.py` runs after the Recents work lands
- **THEN** the check passes with no missing or stale translations for any `addEditExpense.recents.*` key

### Requirement: Recents tile tap emits a Mixpanel `expense_recent_reused` event (F-8.02)

When the user taps a Recents tile, the app SHALL emit an `expense_recent_reused` analytics event via the injected `AnalyticsClient`. The event SHALL contain only categorical, non-PII properties per the analytics-spec.md §2.1 no-PII rule. The event SHALL include at minimum:

- The bound budget's period (`period`).
- A bucketed count of the number of Recents tiles visible when the tap happened (`recents_visible_count`).
- A bucketed position of the tapped tile in the visible row (`recents_tap_position`).
- A bucketed length of the typed Description query at tap time (`name_query_length`).

The event SHALL NOT include the description string, the amount value, or any user-identifying signal. Emission SHALL be subject to the user's consent state per analytics-spec.md §2.1 (same gating as `expense_logged` and `expense_edited`).

#### Scenario: Tap emits the analytics event with categorical properties

- **WHEN** the user taps a Recents tile in Add Expense on a daily budget
- **AND** the user has consented to analytics
- **THEN** the app emits an `expense_recent_reused` event
- **AND** the event includes `period: "daily"` (or its analytics-mapped equivalent)
- **AND** the event includes bucketed values for `recents_visible_count`, `recents_tap_position`, and `name_query_length`
- **AND** the event does not include the description string, the amount value, or any user identifier

#### Scenario: Tap does not emit when analytics consent is withheld

- **WHEN** the user has withheld analytics consent (or is in a consent-required jurisdiction without granting consent)
- **AND** the user taps a Recents tile
- **THEN** the app does not emit the `expense_recent_reused` event
- **AND** the draft fields are still populated (the analytics gate does not block the feature)
