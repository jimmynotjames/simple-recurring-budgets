## MODIFIED Requirements

### Requirement: Add Expense surfaces a Recents section below the Description card (F-7.04)

In Add mode, the Add/Edit Expense screen SHALL render a "Recents" section **directly below the Description card** (card order: Amount, Description, Recents, When, Add Funds) when the bound budget has at least one prior expense item eligible to surface as a suggestion. The placement is deliberate: the Description field doubles as the Recents filter query, so the suggestions sit directly beneath their input (input-above/suggestions-below autocomplete idiom), while the Amount card keeps the top slot for the amount-first quick-log flow.

In Edit/View mode, the section SHALL render only after a **reveal latch** has been set, and once set it SHALL remain rendered for the rest of the sheet's lifetime. The latch SHALL be set when the trimmed Description is empty, evaluated:

- at sheet-open (`init(editing:)` for an `ExpenseItem` whose name is `nil` or whitespace-only), and
- whenever the Description draft transitions to empty (trimmed) during the sheet's lifetime.

The latch SHALL be one-way: once set it SHALL NOT clear when the Description later becomes non-empty (e.g., after a tile tap fills it, or after the user re-types). All other Recents behavior in Edit mode — the candidate corpus, the typed-query filter against the Description, the display cap, the tap and double-tap semantics, and the accessibility affordances — SHALL be identical to Add mode once the section is revealed.

When the bound budget has zero eligible candidates, the section SHALL NOT render at sheet-open and SHALL NOT later appear during the sheet's lifetime, in either mode.

#### Scenario: Add mode with prior expenses shows the Recents section below Description

- **WHEN** the user opens the Add Expense sheet for a budget that has at least one prior named, non-Add-Funds expense item
- **THEN** the screen renders a card titled "Recents" directly below the Description card and above the When card
- **AND** the card contains a horizontal scroll row of tappable tiles, one per candidate
- **AND** the Amount card is the topmost card in the scroll view

#### Scenario: Add mode with no prior expenses hides the section

- **WHEN** the user opens the Add Expense sheet for a budget with no prior expense items (a brand-new budget)
- **THEN** the screen does not render the Recents card
- **AND** the form opens with the Amount card at the top of the scroll view

#### Scenario: Edit mode with a blank Description on open shows the Recents section

- **WHEN** the user opens the Edit Expense sheet for an existing expense whose stored description is `nil` or whitespace-only, on a budget that has at least one eligible candidate
- **THEN** the Recents section is rendered directly below the Description card from sheet appearance

#### Scenario: Edit mode with a non-blank Description on open hides the Recents section initially

- **WHEN** the user opens the Edit Expense sheet for an existing expense whose stored description is non-empty
- **THEN** the Recents section is not rendered at sheet-open

#### Scenario: Clearing the Description in Edit mode reveals the section, which then persists

- **WHEN** the user opens the Edit Expense sheet with a non-empty Description (Recents hidden) and then clears the Description to empty (via delete-all or the trailing clear button)
- **THEN** the Recents section appears
- **AND** the section remains rendered for the rest of the sheet's lifetime even after the Description becomes non-empty again (e.g., after the user re-types or taps a tile)

#### Scenario: Edit mode with no eligible candidates never shows the section

- **WHEN** the user opens the Edit Expense sheet for an expense on a budget with no eligible Recents candidates and clears the Description
- **THEN** the Recents section does not appear

### Requirement: Tapping a Recents tile applies the amount-provenance smart-apply rule

The draft's amount SHALL carry a provenance classification: **empty** (no amount; initial state or after the user clears/deletes it), **user-typed** (the user entered or edited the current amount this session), or **tile-seeded** (a Recents apply wrote the current amount). Echo writes — the amount field re-parsing the text it re-seeded after an external write — SHALL NOT change provenance.

In Edit/View mode, the amount seeded from the existing `ExpenseItem` at sheet-open SHALL be classified **user-typed** for the purposes of this rule. This protects the existing amount: a single tile tap fills the Description only and SHALL NOT overwrite the stored amount, while the double-tap full replace (or clearing the amount first, then tapping) remains the explicit path to take the tile's amount.

A single tap on a Recents tile SHALL always write the suggestion's `name` to the draft and SHALL reset the Add Funds toggle (`isAddFunds`) to off (a Recents tile represents a prior *expense*). The tap SHALL write the suggestion's `amount` **only when the draft amount's provenance is empty or tile-seeded**; a user-typed amount SHALL survive the tap, and SHALL keep surviving across subsequent single taps (suggestion-switching never clobbers typed input). An amount written by a tap is classified tile-seeded, so a later single tap on a different tile replaces it. The tap SHALL NOT persist the expense — the user remains on the sheet to review and confirm via Save — and SHALL NOT alter the `date` field or other draft state.

Rationale: a user-typed amount is fresher intent than the tile's historical amount, and the silent-overwrite failure (a wrong amount saved unnoticed) is costlier than the visible not-applied failure (fixable in place). The escape hatches for explicitly wanting the tile's amount over a typed one are the amount clear button followed by a re-tap, or the double-tap full replace.

#### Scenario: Tap with an empty amount fills name and amount but does not save

- **WHEN** the draft amount is empty and the user taps a Recents tile labeled "Coffee · $5.50"
- **THEN** the Description field shows "Coffee"
- **AND** the Amount field shows $5.50
- **AND** the user remains on the Add Expense sheet
- **AND** no `ExpenseItem` is persisted

#### Scenario: Tap preserves a user-typed amount

- **WHEN** the user has typed $12.80 into the Amount field, then taps a Recents tile labeled "Coffee · $5.50"
- **THEN** the Description field shows "Coffee"
- **AND** the Amount field still shows $12.80

#### Scenario: A second tap replaces a tile-seeded amount

- **WHEN** the draft amount was filled by a prior Recents tap and the user taps a different tile
- **THEN** both the name and the amount update to the newly tapped suggestion

#### Scenario: Clearing the amount re-arms filling

- **WHEN** the user typed an amount, then cleared it (✕ or delete-all), then taps a Recents tile
- **THEN** the tile's amount fills the Amount field

#### Scenario: Tap resets the Add Funds toggle to off

- **WHEN** the user has the Add Funds toggle on, then taps a Recents tile
- **THEN** the Add Funds toggle becomes off
- **AND** the draft's `name` is set from the tapped suggestion (and `amount` per the provenance rule)

#### Scenario: Edit-mode single tap fills the Description without overwriting the existing amount

- **WHEN** the user opens the Edit Expense sheet for an existing expense with amount $9.00, reveals Recents (by clearing the Description), and single-taps a tile labeled "Coffee · $5.50"
- **THEN** the Description field shows "Coffee"
- **AND** the Amount field still shows $9.00 (the existing amount is protected because the edit-seeded amount is classified user-typed)

#### Scenario: Edit-mode double-tap overwrites both Description and amount

- **WHEN** the user opens the Edit Expense sheet for an existing expense with amount $9.00, reveals Recents, and double-taps a tile labeled "Coffee · $5.50"
- **THEN** the Description field shows "Coffee" and the Amount field shows $5.50

### Requirement: Recents tile tap emits a Mixpanel `expense_recent_reused` event (F-8.02)

When the user taps a Recents tile, the app SHALL emit an `expense_recent_reused` analytics event via the injected `AnalyticsClient`, in both Add and Edit/View mode. The event SHALL contain only categorical, non-PII properties per the analytics-spec.md §2.1 no-PII rule. The event SHALL include at minimum:

- The bound budget's period (`period`).
- A bucketed count of the number of Recents tiles visible when the tap happened (`recents_visible_count`); the top bucket is `8+` (open-ended, since the display cap exceeds 15).
- A bucketed position of the tapped tile in the visible row (`recents_tap_position`).
- A bucketed length of the typed Description query at tap time (`name_query_length`).
- The originating surface (`from_screen`): `add_sheet` in Add mode, `budget_detail` in Edit/View mode, matching the convention used by `expense_logged` / `expense_edited`.

The event SHALL NOT include the description string, the amount value, or any user-identifying signal. Emission SHALL be subject to the user's consent state per analytics-spec.md §2.1 (same gating as `expense_logged` and `expense_edited`). Exactly one event SHALL fire per physical interaction: the double-tap full replace does not emit a second event (its first tap already emitted one), and the event fires regardless of whether the amount was filled or preserved by the provenance rule.

#### Scenario: Tap emits the analytics event with categorical properties

- **WHEN** the user taps a Recents tile in Add Expense on a daily budget
- **AND** the user has consented to analytics
- **THEN** the app emits an `expense_recent_reused` event
- **AND** the event includes `period: "daily"` (or its analytics-mapped equivalent)
- **AND** the event includes bucketed values for `recents_visible_count`, `recents_tap_position`, and `name_query_length`
- **AND** the event includes `from_screen: "add_sheet"`
- **AND** the event does not include the description string, the amount value, or any user identifier

#### Scenario: Edit-mode tap emits the event with the budget_detail surface

- **WHEN** the user taps a Recents tile in Edit/View mode with analytics consent granted
- **THEN** the app emits an `expense_recent_reused` event with `from_screen: "budget_detail"`

#### Scenario: Tap does not emit when analytics consent is withheld

- **WHEN** the user has withheld analytics consent (or is in a consent-required jurisdiction without granting consent)
- **AND** the user taps a Recents tile
- **THEN** the app does not emit the `expense_recent_reused` event
- **AND** the draft fields are still populated (the analytics gate does not block the feature)

#### Scenario: Double-tap emits exactly one event

- **WHEN** the user double-taps a Recents tile with analytics consent granted
- **THEN** exactly one `expense_recent_reused` event is emitted (from the pair's first tap)
